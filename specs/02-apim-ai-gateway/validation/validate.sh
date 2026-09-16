#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
MODE="${1:-all}"
OFFLINE_ONLY="${OFFLINE_ONLY:-false}"
RUN_WHAT_IF="${RUN_WHAT_IF:-true}"
VALIDATION_PHASE="${VALIDATION_PHASE:-all}"

FOUNDATION_TEMPLATE="infra/envs/poc/apim.bicep"
FOUNDATION_PARAMETERS="infra/envs/poc/apim.bicepparam"
INTEGRATION_TEMPLATE="infra/envs/poc/apim-foundry-integration.bicep"
INTEGRATION_PARAMETERS="infra/envs/poc/apim-foundry-integration.bicepparam"

case "$MODE" in
  foundation|integration|all) ;;
  *)
    echo "Usage: $0 {foundation|integration|all}" >&2
    exit 2
    ;;
esac

case "$VALIDATION_PHASE" in
  preview|runtime|all) ;;
  *)
    echo "VALIDATION_PHASE must be preview, runtime, or all." >&2
    exit 2
    ;;
esac

blocked=false

block() {
  echo "BLOCKED [$1]: $2"
  blocked=true
}

require_file() {
  [[ -f "$REPO_ROOT/$1" ]] || {
    echo "ERROR: missing required file: $1" >&2
    exit 1
  }
}

validate_parameter_conventions() {
  local file violation
  while IFS= read -r file; do
    while IFS= read -r violation; do
      [[ -z "$violation" ]] && continue
      if [[ "$violation" != *readEnvironmentVariable* ]]; then
        echo "ERROR: $file has a parameter assignment that is not environment-backed: $violation" >&2
        exit 1
      fi
    done < <(grep -En '^[[:space:]]*param[[:space:]]+[[:alnum:]_]+[[:space:]]*=' "$file" || true)
  done < <(find "$REPO_ROOT/infra" -type f -name '*.bicepparam' | sort)
}

compile_bicep() {
  local file="$1"
  echo "Compiling $file"
  az bicep build --file "$REPO_ROOT/$file" --stdout >/dev/null
}

compile_params() {
  local file="$1"
  echo "Compiling $file"
  az bicep build-params --file "$REPO_ROOT/$file" --stdout >/dev/null
}

compile_to() {
  local file="$1"
  local outfile="$2"
  az bicep build --file "$REPO_ROOT/$file" --outfile "$outfile" >/dev/null
}

assert_absent() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -Eq "$pattern" "$file"; then
    echo "ERROR: $message" >&2
    exit 1
  fi
}

assert_present() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    echo "ERROR: $message" >&2
    exit 1
  fi
}

azure_session_available() {
  command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1
}

is_private_ipv4() {
  [[ "$1" =~ ^10\. ]] ||
    [[ "$1" =~ ^192\.168\. ]] ||
    [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
}

require_env_value() {
  local name="$1"
  local stage="$2"
  if [[ -z "${!name:-}" ]]; then
    block "$stage" "Set $name to run live validation and what-if."
    return 1
  fi
}

validate_static_ownership() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  compile_to "$FOUNDATION_TEMPLATE" "$temp_dir/foundation.json"
  compile_to "$INTEGRATION_TEMPLATE" "$temp_dir/integration.json"

  assert_absent 'Microsoft\.CognitiveServices|foundry-openai-backend|approved-models|enterprise-llm-api' \
    "$temp_dir/foundation.json" \
    "foundation compiled template contains an integration-owned reference"
  assert_present '"type": "Microsoft\.ApiManagement/service"' \
    "$temp_dir/foundation.json" \
    "foundation compiled template does not deploy APIM"
  assert_present 'Microsoft\.Network/privateDnsZones' \
    "$temp_dir/foundation.json" \
    "foundation compiled template does not deploy private DNS"
  assert_present 'Microsoft\.Insights/metricAlerts' \
    "$temp_dir/foundation.json" \
    "foundation compiled template does not deploy the capacity alert"

  assert_absent '"type": "Microsoft\.ApiManagement/service"|Microsoft\.Network/privateDnsZones|Microsoft\.Insights/components|Microsoft\.OperationalInsights/workspaces|Microsoft\.Insights/metricAlerts' \
    "$temp_dir/integration.json" \
    "integration compiled template declares a foundation-owned resource"
  assert_present 'Microsoft\.Authorization/roleAssignments' \
    "$temp_dir/integration.json" \
    "integration compiled template lacks the Foundry role assignment"
  assert_present 'Microsoft\.ApiManagement/service/backends' \
    "$temp_dir/integration.json" \
    "integration compiled template lacks the APIM backend"
  assert_present 'Microsoft\.ApiManagement/service/apis' \
    "$temp_dir/integration.json" \
    "integration compiled template lacks the governed API"

  printf '%s\n' 'Microsoft.CognitiveServices/accounts' >"$temp_dir/seed-foundation"
  if ! grep -Eq 'Microsoft\.CognitiveServices|foundry-openai-backend|approved-models|enterprise-llm-api' "$temp_dir/seed-foundation"; then
    echo "ERROR: foundation ownership regression self-test did not detect a seeded reference" >&2
    exit 1
  fi
  printf '%s\n' '"type": "Microsoft.ApiManagement/service"' >"$temp_dir/seed-integration"
  if ! grep -Eq '"type": "Microsoft\.ApiManagement/service"|Microsoft\.Network/privateDnsZones|Microsoft\.Insights/components|Microsoft\.OperationalInsights/workspaces|Microsoft\.Insights/metricAlerts' "$temp_dir/seed-integration"; then
    echo "ERROR: integration ownership regression self-test did not detect a seeded resource" >&2
    exit 1
  fi
}

validate_foundation_offline() {
  echo "== Foundation offline validation =="
  local files=(
    "infra/modules/apim/main.bicep"
    "infra/modules/apim/private-dns.bicep"
    "infra/modules/apim/observability.bicep"
    "$FOUNDATION_TEMPLATE"
    "$FOUNDATION_PARAMETERS"
    "infra/envs/poc/apim.customer.example.bicepparam"
  )
  for file in "${files[@]}"; do require_file "$file"; done

  compile_bicep "infra/modules/apim/main.bicep"
  compile_bicep "infra/modules/apim/private-dns.bicep"
  compile_bicep "infra/modules/apim/observability.bicep"
  compile_bicep "$FOUNDATION_TEMPLATE"
  compile_params "$FOUNDATION_PARAMETERS"
  compile_params "infra/envs/poc/apim.customer.example.bicepparam"

  local observability_template
  observability_template="$(mktemp)"
  trap 'rm -f "$observability_template"' RETURN
  compile_to "infra/modules/apim/observability.bicep" "$observability_template"
  jq -e '
    [.resources[]
      | select(
          .type == "Microsoft.ApiManagement/service/loggers"
          or .type == "Microsoft.ApiManagement/service/diagnostics"
        )
    ]
    | length == 2 and all(has("location") and .location != null)
  ' "$observability_template" >/dev/null || {
    echo "ERROR: APIM logger and diagnostic deployment requests must carry policy-compatible location metadata." >&2
    exit 1
  }

  assert_present "virtualNetworkType: 'Internal'" "$REPO_ROOT/infra/modules/apim/main.bicep" "APIM is not internal"
  assert_present "'Developer'" "$REPO_ROOT/infra/modules/apim/main.bicep" "Developer smoke-test SKU is not allowed"
  assert_present "Developer APIM requires apimSkuCapacity to be 1" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "Developer capacity guard is missing"
  assert_present "'Microsoft.Network/publicIPAddresses@2023-11-01'" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "foundation does not create the APIM platform public IP"
  assert_present "publicIPAllocationMethod: 'Static'" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "APIM public IP is not static"
  assert_present 'APIM_PUBLIC_IP_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "APIM public IP customer tag input is missing"
  assert_present 'publicIpAddressId:' "$REPO_ROOT/infra/modules/apim/main.bicep" "classic APIM public IP is not associated"
  assert_present 'Gateway.Security.Protocols.Tls10' "$REPO_ROOT/infra/modules/apim/main.bicep" "TLS 1.0 disablement is missing"
  assert_present 'Gateway.Security.Protocols.Tls11' "$REPO_ROOT/infra/modules/apim/main.bicep" "TLS 1.1 disablement is missing"
  assert_present "categoryGroup: 'AllLogs'" "$REPO_ROOT/infra/modules/apim/observability.bicep" "AllLogs diagnostics are missing"
  assert_present "category: 'AllMetrics'" "$REPO_ROOT/infra/modules/apim/observability.bicep" "AllMetrics diagnostics are missing"
  assert_present "metricName: 'Capacity'" "$REPO_ROOT/infra/modules/apim/observability.bicep" "capacity alert is missing"
  assert_present 'threshold: capacityAlertThreshold' "$REPO_ROOT/infra/modules/apim/observability.bicep" "capacity threshold is missing"
  assert_absent 'foundry|approvedModels|backendName|apiName|productName|tokenLimit' \
    "$REPO_ROOT/$FOUNDATION_TEMPLATE" \
    "foundation source contains integration inputs"
  assert_absent 'foundry|approvedModels|backendName|apiName|productName|tokenLimit' \
    "$REPO_ROOT/$FOUNDATION_PARAMETERS" \
    "foundation parameters contain integration inputs"
  echo "Foundation offline validation passed."
}

validate_integration_offline() {
  echo "== Integration offline validation =="
  local files=(
    "infra/modules/apim/foundry-role-assignment.bicep"
    "infra/modules/apim/backend.bicep"
    "infra/modules/apim/api.bicep"
    "$INTEGRATION_TEMPLATE"
    "$INTEGRATION_PARAMETERS"
  )
  for file in "${files[@]}"; do require_file "$file"; done

  compile_bicep "infra/modules/apim/foundry-role-assignment.bicep"
  compile_bicep "infra/modules/apim/backend.bicep"
  compile_bicep "infra/modules/apim/api.bicep"
  compile_bicep "$INTEGRATION_TEMPLATE"
  compile_params "$INTEGRATION_PARAMETERS"

  assert_present 'authentication-managed-identity' "$REPO_ROOT/infra/modules/apim/backend.bicep" "managed-identity backend policy is missing"
  assert_present 'https://cognitiveservices.azure.com' "$REPO_ROOT/infra/modules/apim/backend.bicep" "Cognitive Services audience is missing"
  assert_present 'subscriptionRequired: true' "$REPO_ROOT/infra/modules/apim/api.bicep" "subscription enforcement is missing"
  assert_present 'set-header name="Ocp-Apim-Subscription-Key" exists-action="delete"' \
    "$REPO_ROOT/infra/modules/apim/api.bicep" \
    "subscription key is not removed before backend forwarding"
  assert_present 'unsupported_model' "$REPO_ROOT/infra/modules/apim/api.bicep" "model allowlist rejection is missing"
  assert_absent 'api[-_]?key|connectionString|accountKey' \
    "$REPO_ROOT/infra/modules/apim/backend.bicep" \
    "integration backend appears to contain key-based authentication"
  echo "Integration offline validation passed."
}

validate_foundation_live() {
  echo "== Foundation live read-only validation =="
  if [[ "$OFFLINE_ONLY" == "true" ]]; then
    echo "Foundation live checks skipped by OFFLINE_ONLY=true."
    return
  fi
  if ! azure_session_available; then
    block foundation "An authenticated Azure CLI session is required."
    return
  fi

  local missing=false
  for name in APIM_RESOURCE_GROUP APIM_NETWORK_RESOURCE_GROUP APIM_VNET_NAME APIM_SUBNET_NAME APIM_APPROVED_NSG_RESOURCE_ID APIM_PUBLISHER_EMAIL; do
    require_env_value "$name" foundation || missing=true
  done
  if [[ -z "${APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID:-}" && -z "${APIM_ROUTE_TABLE_EXCEPTION_REFERENCE:-}" ]]; then
    block foundation "Set APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID or APIM_ROUTE_TABLE_EXCEPTION_REFERENCE."
    missing=true
  fi
  if [[ "$missing" == true ]]; then
    return 0
  fi

  local subnet_json subnet_nsg subnet_route subnet_name
  subnet_json="$(az network vnet subnet show \
    --resource-group "$APIM_NETWORK_RESOURCE_GROUP" \
    --vnet-name "$APIM_VNET_NAME" \
    --name "$APIM_SUBNET_NAME" -o json)"
  subnet_name="$(jq -r '.name' <<<"$subnet_json")"
  subnet_nsg="$(jq -r '.networkSecurityGroup.id // ""' <<<"$subnet_json")"
  subnet_route="$(jq -r '.routeTable.id // ""' <<<"$subnet_json")"

  if [[ "$subnet_name" != apimsubnet-* && -z "${APIM_SUBNET_NAMING_EXCEPTION_REFERENCE:-}" ]]; then
    echo "ERROR [foundation]: APIM subnet naming is unapproved and no exception reference was supplied." >&2
    exit 1
  fi
  [[ "${subnet_nsg,,}" == "${APIM_APPROVED_NSG_RESOURCE_ID,,}" ]] || {
    echo "ERROR [foundation]: APIM subnet NSG does not match the approved NSG." >&2
    exit 1
  }
  if [[ -n "${APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID:-}" ]]; then
    [[ "${subnet_route,,}" == "${APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID,,}" ]] || {
      echo "ERROR [foundation]: APIM subnet route table does not match approval." >&2
      exit 1
    }
  elif [[ -n "$subnet_route" ]]; then
    echo "ERROR [foundation]: route-table exception was supplied but the subnet has a route table." >&2
    exit 1
  fi
  jq -e '(.delegations // [] | length) == 0' <<<"$subnet_json" >/dev/null
  for endpoint in Microsoft.AzureActiveDirectory Microsoft.KeyVault Microsoft.Sql Microsoft.Storage; do
    jq -e --arg endpoint "$endpoint" '[.serviceEndpoints[]?.service] | index($endpoint) != null' <<<"$subnet_json" >/dev/null
  done

  if [[ "$APIM_PUBLISHER_EMAIL" == *@example.com || "$APIM_PUBLISHER_EMAIL" == *@contoso.com ]]; then
    echo "ERROR [foundation]: APIM_PUBLISHER_EMAIL must be a corporate address." >&2
    exit 1
  fi

  if [[ "$RUN_WHAT_IF" == "true" && "$VALIDATION_PHASE" != "runtime" ]]; then
    az deployment group what-if \
      --resource-group "$APIM_RESOURCE_GROUP" \
      --name apim-foundation-preview \
      --template-file "$REPO_ROOT/$FOUNDATION_TEMPLATE" \
      --parameters "$REPO_ROOT/$FOUNDATION_PARAMETERS" \
      --result-format ResourceIdOnly
  fi

  if [[ "$VALIDATION_PHASE" == "preview" ]]; then
    echo "Foundation preview validation passed."
    return
  fi

  if az apim show --resource-group "$APIM_RESOURCE_GROUP" --name "${APIM_SERVICE_NAME:-apim-agent-factory-private-poc}" >/dev/null 2>&1; then
    local apim_json apim_id workspace_id apim_name expected_sku expected_capacity
    apim_name="${APIM_SERVICE_NAME:-apim-agent-factory-private-poc}"
    expected_sku="${APIM_SKU_NAME:-Premium}"
    expected_capacity="${APIM_SKU_CAPACITY:-1}"
    apim_json="$(az apim show --resource-group "$APIM_RESOURCE_GROUP" --name "${APIM_SERVICE_NAME:-apim-agent-factory-private-poc}" -o json)"
    jq -e --arg sku "$expected_sku" --argjson capacity "$expected_capacity" '
      .sku.name == $sku and
      .sku.capacity == $capacity and
      .virtualNetworkType == "Internal" and
      .identity.type == "SystemAssigned" and
      (.identity.principalId | length > 0)
    ' <<<"$apim_json" >/dev/null
    jq -e '(.privateIpAddresses // [] | length) > 0' <<<"$apim_json" >/dev/null
    jq -e '
      .customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10"] == "false" and
      .customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11"] == "false" and
      .customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10"] == "false" and
      .customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11"] == "false" and
      .customProperties["Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168"] == "false"
    ' <<<"$apim_json" >/dev/null
    apim_id="$(jq -r '.id' <<<"$apim_json")"
    local apim_public_ip_id
    apim_public_ip_id="$(jq -r '.publicIpAddressId // ""' <<<"$apim_json")"
    [[ -n "$apim_public_ip_id" ]] || {
      echo "ERROR [foundation]: APIM has no associated platform public IP resource ID." >&2
      exit 1
    }
    az resource show --ids "$apim_public_ip_id" --api-version 2023-11-01 \
      --query "sku.name=='Standard' && properties.publicIPAllocationMethod=='Static'" -o tsv | grep -qx true

    if [[ "${APIM_PRIVATE_DNS_MODE:-blueprint}" == "blueprint" ]]; then
      for record in "$apim_name" "$apim_name.developer" "$apim_name.portal" "$apim_name.management" "$apim_name.scm"; do
        az network private-dns record-set a show \
          --resource-group "$APIM_RESOURCE_GROUP" \
          --zone-name "${APIM_PRIVATE_DNS_ZONE_NAME:-azure-api.net}" \
          --name "$record" \
          --query "aRecords | length(@)" -o tsv | grep -Eq '^[1-9][0-9]*$'
      done
    else
      block foundation "External DNS mode requires customer confirmation that the APIM hostnames resolve to the reported private IP."
    fi

    if [[ "${APIM_VALIDATE_ENDPOINT_REACHABILITY:-false}" == "true" ]]; then
      local endpoint ip
      for endpoint in \
        "$apim_name.azure-api.net" \
        "$apim_name.developer.azure-api.net" \
        "$apim_name.portal.azure-api.net" \
        "$apim_name.management.azure-api.net" \
        "$apim_name.scm.azure-api.net"; do
        ip="$(getent ahostsv4 "$endpoint" | awk 'NR == 1 { print $1 }')"
        [[ -n "$ip" ]] && is_private_ipv4 "$ip" || {
          echo "ERROR [foundation]: $endpoint did not resolve to a private IPv4 address." >&2
          exit 1
        }
        if ! curl --silent --show-error --connect-timeout 5 --max-time 10 "https://$endpoint" -o /dev/null; then
          echo "ERROR [foundation]: $endpoint was not reachable from the approved validation network." >&2
          exit 1
        fi
      done
    else
      block foundation "Set APIM_VALIDATE_ENDPOINT_REACHABILITY=true from an authorized network to verify internal gateway, portal, management, and SCM reachability."
    fi

    local diagnostic_settings_json
    diagnostic_settings_json="$(az monitor diagnostic-settings list --resource "$apim_id" -o json)"
    jq -e '[.value[] | select((([.logs[]? | select(.enabled == true and (.categoryGroup == "AllLogs" or .category != null))] | length) > 0) and (([.metrics[]? | select(.enabled == true and .category == "AllMetrics")] | length) > 0))] | length > 0' \
      <<<"$diagnostic_settings_json" >/dev/null
    if [[ "${APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP:-policy}" == "blueprint" ]]; then
      jq -e --arg name "${APIM_DIAGNOSTIC_SETTING_NAME:-diag-apim-gateway}" \
        '[.value[] | select(.name == $name)] | length == 1' <<<"$diagnostic_settings_json" >/dev/null
    fi

    az monitor metrics alert show \
      --resource-group "$APIM_RESOURCE_GROUP" \
      --name "${APIM_CAPACITY_ALERT_NAME:-alert-apim-capacity-over-60}" \
      --query "criteria.allOf[?metricName=='Capacity' && timeAggregation=='Average' && threshold>=\`60\`] | length(@)" -o tsv | grep -qx 1

    workspace_id="${APIM_LOG_ANALYTICS_WORKSPACE_ID:-}"
    if [[ -n "$workspace_id" && "${APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP:-policy}" == "policy" ]]; then
      jq -e --arg workspace_id "${workspace_id,,}" \
        '[.value[] | select(((.workspaceId // "") | ascii_downcase) == $workspace_id)] | length > 0' \
        <<<"$diagnostic_settings_json" >/dev/null
    fi
  else
    block foundation "APIM is not deployed; runtime identity, DNS, diagnostics, alert, and internal endpoint checks remain pending."
  fi
}

validate_integration_live() {
  echo "== Integration live read-only validation =="
  if [[ "$OFFLINE_ONLY" == "true" ]]; then
    echo "Integration live checks skipped by OFFLINE_ONLY=true."
    return
  fi
  if ! azure_session_available; then
    block integration "An authenticated Azure CLI session is required."
    return
  fi

  local missing=false
  for name in APIM_RESOURCE_GROUP APIM_SERVICE_NAME FOUNDRY_RESOURCE_GROUP FOUNDRY_ACCOUNT_NAME FOUNDRY_ACCOUNT_ID FOUNDRY_APPROVED_MODELS GENAI_APPROVAL_REFERENCE FOUNDRY_ENABLEMENT_REFERENCE FOUNDRY_CUSTOMER_POLICY_SOURCE; do
    require_env_value "$name" integration || missing=true
  done
  if [[ "$missing" == true ]]; then
    return 0
  fi

  local apim_json foundry_json apim_principal foundry_id foundry_location approved_regions_json approved_models_json model_deployment
  approved_regions_json="${FOUNDRY_APPROVED_REGIONS:-[\"eastus\",\"eastus2\",\"westeurope\"]}"
  approved_models_json="$FOUNDRY_APPROVED_MODELS"
  jq -e 'type == "array" and length > 0 and all(.[];
    (.publicName | type == "string" and length > 0) and
    (.deploymentName | type == "string" and length > 0) and
    (.enabled | type == "boolean")
  )' <<<"$approved_models_json" >/dev/null || {
    echo "ERROR [integration]: FOUNDRY_APPROVED_MODELS must be a non-empty JSON array with publicName, deploymentName, and enabled values." >&2
    exit 1
  }
  jq -e '[.[] | select(.enabled == true)] | length > 0' <<<"$approved_models_json" >/dev/null || {
    echo "ERROR [integration]: FOUNDRY_APPROVED_MODELS must enable at least one model." >&2
    exit 1
  }

  apim_json="$(az apim show --resource-group "$APIM_RESOURCE_GROUP" --name "$APIM_SERVICE_NAME" -o json)"
  apim_principal="$(jq -r '.identity.principalId // ""' <<<"$apim_json")"
  [[ -n "$apim_principal" ]] || {
    echo "ERROR [integration]: existing APIM has no system-assigned principal." >&2
    exit 1
  }

  foundry_json="$(az cognitiveservices account show --resource-group "$FOUNDRY_RESOURCE_GROUP" --name "$FOUNDRY_ACCOUNT_NAME" -o json)"
  foundry_id="$(jq -r '.id' <<<"$foundry_json")"
  foundry_location="$(jq -r '.location | ascii_downcase' <<<"$foundry_json")"
  [[ "${foundry_id,,}" == "${FOUNDRY_ACCOUNT_ID,,}" ]] || {
    echo "ERROR [integration]: FOUNDRY_ACCOUNT_ID does not match the selected account." >&2
    exit 1
  }
  [[ "$(jq -r '.properties.publicNetworkAccess // .publicNetworkAccess // ""' <<<"$foundry_json")" == "Disabled" ]] || {
    echo "ERROR [integration]: Foundry public network access must be Disabled." >&2
    exit 1
  }
  jq -e --arg location "$foundry_location" 'index($location) != null' <<<"$approved_regions_json" >/dev/null || {
    echo "ERROR [integration]: Foundry region is not in FOUNDRY_APPROVED_REGIONS." >&2
    exit 1
  }

  az network private-endpoint-connection list --id "$foundry_id" \
    --query "[?privateLinkServiceConnectionState.status=='Approved'] | length(@)" -o tsv | grep -Eq '^[1-9][0-9]*$'

  while IFS= read -r model_deployment; do
    az cognitiveservices account deployment show \
      --resource-group "$FOUNDRY_RESOURCE_GROUP" \
      --name "$FOUNDRY_ACCOUNT_NAME" \
      --deployment-name "$model_deployment" >/dev/null
  done < <(jq -r '.[] | select(.enabled == true) | .deploymentName' <<<"$approved_models_json")

  if [[ "$RUN_WHAT_IF" == "true" && "$VALIDATION_PHASE" != "runtime" ]]; then
    az deployment group what-if \
      --resource-group "$APIM_RESOURCE_GROUP" \
      --name apim-foundry-integration-preview \
      --template-file "$REPO_ROOT/$INTEGRATION_TEMPLATE" \
      --parameters "$REPO_ROOT/$INTEGRATION_PARAMETERS" \
      --result-format ResourceIdOnly
  fi

  if [[ "$VALIDATION_PHASE" == "preview" ]]; then
    echo "Integration preview validation passed."
    return
  fi

  if az apim backend show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --backend-id "${APIM_BACKEND_NAME:-foundry-openai-backend}" >/dev/null 2>&1; then
    az role assignment list --assignee "$apim_principal" --scope "$foundry_id" \
      --query "[?roleDefinitionName=='Cognitive Services OpenAI User'] | length(@)" -o tsv | grep -qx 1
    az apim backend show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --backend-id "${APIM_BACKEND_NAME:-foundry-openai-backend}" \
      --query "starts_with(url, 'https://')" -o tsv | grep -qx true
    az apim api show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --api-id "${APIM_API_NAME:-enterprise-llm-api}" \
      --query "subscriptionRequired" -o tsv | grep -qx true
    az apim nv show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --named-value-id approved-models \
      --query "secret==\`false\`" -o tsv | grep -qx true
    local api_policy
    api_policy="$(az apim api policy show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --api-id "${APIM_API_NAME:-enterprise-llm-api}" --query value -o tsv)"
    grep -q 'authentication-managed-identity' <<<"$api_policy"
    grep -q 'llm-token-limit' <<<"$api_policy"
    grep -q 'unsupported_model' <<<"$api_policy"
    grep -q 'Ocp-Apim-Subscription-Key' <<<"$api_policy"
    grep -q 'set-header name="Ocp-Apim-Subscription-Key" exists-action="delete"' <<<"$api_policy"

    if [[ "${APIM_VALIDATE_INTEGRATION_REQUESTS:-false}" != "true" ]]; then
      block integration "Set APIM_VALIDATE_INTEGRATION_REQUESTS=true with authorized client inputs to verify allowed, unsupported, unauthenticated, and secret-safe telemetry behavior."
    fi
  else
    block integration "Integration resources are not deployed; role, backend, API, request, and telemetry checks remain pending."
  fi
}

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI with Bicep support is required for offline compilation." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for validation." >&2
  exit 1
fi

validate_parameter_conventions

case "$MODE" in
  foundation)
    validate_foundation_offline
    validate_static_ownership
    validate_foundation_live
    ;;
  integration)
    validate_integration_offline
    validate_static_ownership
    validate_integration_live
    ;;
  all)
    validate_foundation_offline
    validate_integration_offline
    validate_static_ownership
    validate_foundation_live
    validate_integration_live
    ;;
esac

if [[ "$blocked" == true ]]; then
  echo "Offline validation passed; one or more live stage gates are BLOCKED."
  exit 3
fi

echo "Validation passed for mode: $MODE"
