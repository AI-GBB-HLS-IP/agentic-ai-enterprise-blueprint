#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
MODE="${1:-all}"
OFFLINE_ONLY="${OFFLINE_ONLY:-false}"
RUN_WHAT_IF="${RUN_WHAT_IF:-true}"
VALIDATION_PHASE="${VALIDATION_PHASE:-all}"

FOUNDATION_TEMPLATE="infra/envs/poc/apim.bicep"
FOUNDATION_PARAMETERS="${APIM_FOUNDATION_PARAMETERS_FILE:-${FOUNDATION_PARAMETERS:-infra/envs/poc/apim.bicepparam}}"
INTEGRATION_TEMPLATE="infra/envs/poc/apim-foundry-integration.bicep"
INTEGRATION_PARAMETERS="${APIM_INTEGRATION_PARAMETERS_FILE:-${INTEGRATION_PARAMETERS:-infra/envs/poc/apim-foundry-integration.bicepparam}}"

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
  local path
  path="$(parameter_file_path "$1")"
  [[ -f "$path" ]] || {
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
  local compile_stage1_readiness="${APIM_STAGE1_FOUNDATION_READINESS:-{\"network\":\"validated\",\"apim\":\"deployed\",\"identity\":\"deployed\",\"dns\":\"deployed\",\"observability\":\"deployed\",\"status\":\"deployed\"}}"
  local compile_approved_regions="${FOUNDRY_APPROVED_REGIONS:-[\"compile-only-region\"]}"
  echo "Compiling $file"
  APIM_STAGE1_FOUNDATION_READINESS="$compile_stage1_readiness" \
    FOUNDRY_APPROVED_REGIONS="$compile_approved_regions" \
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

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_placeholder() {
  local value normalized
  value="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  normalized="$(lowercase "$value")"
  [[ -z "$value" ]] ||
    [[ "$value" == \<*\> ]] ||
    [[ "$normalized" == *placeholder* ]] ||
    [[ "$normalized" == *replace-me* ]] ||
    [[ "$normalized" == "todo" ]] ||
    [[ "$normalized" == "tbd" ]]
}

parameter_file_path() {
  local file="$1"
  if [[ "$file" = /* ]]; then
    printf '%s\n' "$file"
  else
    printf '%s/%s\n' "$REPO_ROOT" "$file"
  fi
}

load_selected_parameter_values() {
  local file="$1" parameter_path env_name default_value
  parameter_path="$(parameter_file_path "$file")"
  [[ -f "$parameter_path" ]] || {
    echo "ERROR: missing required file: $file" >&2
    exit 1
  }
  while IFS=$'\t' read -r env_name default_value; do
    [[ -n "$env_name" ]] || continue
    if [[ -z "${!env_name+x}" ]]; then
      printf -v "$env_name" '%s' "$default_value"
      export "$env_name"
    fi
  done < <(
    sed -nE \
      "s/^[[:space:]]*param[[:space:]]+[[:alnum:]_]+[[:space:]]*=[^#]*readEnvironmentVariable\\('([^']*)'([[:space:]]*,[[:space:]]*'([^']*)')?.*$/\1\\t\3/p" \
      "$parameter_path"
  )
}

validate_optional_evidence_reference() {
  local name="$1" stage="$2" value="${!1:-}"
  if [[ -n "$value" ]] && is_placeholder "$value"; then
    echo "ERROR [$stage]: $name must not contain placeholder evidence." >&2
    exit 1
  fi
}

validate_non_placeholder_value() {
  local name="$1" stage="$2" value="${!1:-}"
  if [[ -n "$value" ]] && is_placeholder "$value"; then
    echo "ERROR [$stage]: $name must not use a placeholder value." >&2
    exit 1
  fi
}

require_governance_reference() {
  local name="$1"
  local stage="$2"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    block "$stage" "Set $name to an approved governance evidence reference."
    return 1
  fi
  if is_placeholder "$value"; then
    echo "ERROR [$stage]: $name must not contain placeholder governance evidence." >&2
    exit 1
  fi
}

require_evidence_reference() {
  local name="$1"
  local stage="$2"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    block "$stage" "Set $name to an approved validation evidence reference."
    return 1
  fi
  if is_placeholder "$value"; then
    echo "ERROR [$stage]: $name must not contain placeholder validation evidence." >&2
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

validate_foundation_workspace_selection() {
  local workspace_name="${APIM_LOG_ANALYTICS_WORKSPACE_NAME:-}"
  if [[ -n "${APIM_LOG_ANALYTICS_WORKSPACE_ID:-}" ]]; then
    return
  fi
  if [[ -z "$workspace_name" ]]; then
    block foundation "Set APIM_LOG_ANALYTICS_WORKSPACE_ID for an existing workspace or APIM_LOG_ANALYTICS_WORKSPACE_NAME to create one."
    return 1
  fi
  if is_placeholder "$workspace_name" ||
    [[ ${#workspace_name} -lt 4 || ${#workspace_name} -gt 63 ]] ||
    [[ ! "$workspace_name" =~ ^[[:alnum:]][[:alnum:]-]*[[:alnum:]]$ ]]; then
    echo "ERROR [foundation]: APIM_LOG_ANALYTICS_WORKSPACE_NAME must be a valid 4-63 character Azure workspace name using letters, numbers, and hyphens." >&2
    exit 1
  fi
}

resolve_foundation_workspace_id() {
  if [[ -n "${APIM_LOG_ANALYTICS_WORKSPACE_ID:-}" ]]; then
    printf '%s\n' "$APIM_LOG_ANALYTICS_WORKSPACE_ID"
    return
  fi
  [[ -n "${APIM_LOG_ANALYTICS_WORKSPACE_NAME:-}" ]] || return 1
  az monitor log-analytics workspace show \
    --resource-group "$APIM_RESOURCE_GROUP" \
    --workspace-name "$APIM_LOG_ANALYTICS_WORKSPACE_NAME" \
    --query id -o tsv
}

diagnostics_match_expected_workspace() {
  local diagnostic_settings_json="$1"
  local expected_workspace_id="$2"
  local diagnostics_owner="$3"
  local diagnostic_setting_name="$4"
  jq -e \
    --arg owner "$diagnostics_owner" \
    --arg name "$diagnostic_setting_name" \
    --arg workspace_id "$(lowercase "$expected_workspace_id")" '
      [.value[]
        | select(
            ((.properties.workspaceId // "") | ascii_downcase) == $workspace_id
            and ([.properties.logs[]? | select(.enabled == true and .categoryGroup == "AllLogs")] | length) > 0
            and ([.properties.metrics[]? | select(.enabled == true and .category == "AllMetrics")] | length) > 0
            and ($owner != "blueprint" or .name == $name or .properties.name == $name)
          )
      ]
      | length == 1
    ' <<<"$diagnostic_settings_json" >/dev/null
}

apim_classic_sku_supported() {
  jq -e '
    ((.sku.name | ascii_downcase) == "developer" and .sku.capacity == 1)
    or ((.sku.name | ascii_downcase) == "premium")
  ' <<<"$1" >/dev/null
}

select_apim_endpoints() {
  local apim_name="$1" stage="${2:-foundation}"
  local mode="${APIM_ENDPOINT_MODE:-built-in}" path="${APIM_ENDPOINT_ACCESS_PATH:-direct-private}"
  local dns_owner="${APIM_PRIVATE_DNS_MODE:-external}" hostnames="${APIM_CUSTOM_ENDPOINT_HOSTNAMES:-}"
  [[ -n "$hostnames" ]] || hostnames='{}'
  if [[ "$mode" == "built-in" && "$path" == "direct-private" && ( "$dns_owner" == "blueprint" || "$dns_owner" == "external" ) ]]; then
    jq -cn --arg name "$(lowercase "$apim_name")" '[
      {role:"gateway",type:"Proxy",hostname:($name+".azure-api.net")},
      {role:"developerPortal",type:"DeveloperPortal",hostname:($name+".developer.azure-api.net")},
      {role:"legacyPortal",type:"Portal",hostname:($name+".portal.azure-api.net")},
      {role:"management",type:"Management",hostname:($name+".management.azure-api.net")},
      {role:"scm",type:"Scm",hostname:($name+".scm.azure-api.net")}
    ]'
    return
  fi
  if [[ "$mode" != "custom" || "$dns_owner" != "external" || ( "$path" != "direct-private" && "$path" != "corporate-routed" ) ]]; then
    echo "ERROR [$stage]: unsupported endpoint mode/access path/DNS owner; custom requires external DNS and corporate routing requires custom." >&2
    return 1
  fi
  jq -ce '
    def hostname:
      type == "string" and
      (ascii_downcase | gsub("^\\s+|\\s+$"; "") |
        length <= 253 and test("[a-z]") and
        test("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$") and
        (split(".") | all(.[]; length <= 63)) and
        (endswith(".azure-api.net") | not));
    if type == "object" and keys == ["developerPortal","gateway","management"]
      and all(.[]; hostname) then
      with_entries(.value |= (ascii_downcase | gsub("^\\s+|\\s+$"; ""))) |
      [{role:"gateway",type:"Proxy",hostname:.gateway},
       {role:"developerPortal",type:"DeveloperPortal",hostname:.developerPortal},
       {role:"management",type:"Management",hostname:.management}]
    else error("invalid custom endpoint hostnames") end
  ' <<<"$hostnames" || {
    echo "ERROR [$stage]: require exactly three DNS hostname strings: gateway, developerPortal, management; URLs, ports, paths, wildcards, and built-in names are invalid." >&2
    return 1
  }
}

validate_endpoint_bindings() {
  local apim_json="$1" endpoints="$2" stage="${3:-foundation}"
  jq -e --argjson selected "$endpoints" '
    .hostnameConfigurations as $bindings |
    all($selected[]; . as $endpoint |
      any($bindings[]?; (.type | ascii_downcase) == ($endpoint.type | ascii_downcase)
        and (.hostName | ascii_downcase) == $endpoint.hostname))
  ' <<<"$apim_json" >/dev/null || {
    echo "ERROR [$stage]: selected custom endpoints do not match the intended live APIM role bindings." >&2
    return 1
  }
}

validate_endpoint_evidence() {
  local evidence="$1" service_id="$2" endpoints="$3" stage="${4:-foundation}"
  local path="${APIM_ENDPOINT_ACCESS_PATH:-direct-private}" status
  if [[ -z "$evidence" ]] || jq -e 'type == "object" and length == 0' <<<"$evidence" >/dev/null 2>&1; then
    block "$stage" "Custom endpoint validation evidence is required; retain measured checks and approved routing context."
    return 3
  fi
  jq -e --arg id "$service_id" --arg path "$path" --argjson selected "$endpoints" '
    def nonempty: type == "string" and (gsub("^\\s+|\\s+$"; "") | length > 0);
    def reference:
      nonempty and (ascii_downcase | test("[<>]|placeholder|replace-me|^\\s*(todo|tbd)\\s*$") | not);
    def utc:
      nonempty and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$") and
      (sub("\\.[0-9]+Z$"; "Z") as $canonical |
        try (($canonical | fromdateiso8601 | strftime("%Y-%m-%dT%H:%M:%SZ")) == $canonical) catch false);
    . as $e |
    type == "object" and
    all(["validationType","status","owner","scope","approvalReference","evidenceSummary","timestampUtc",
         "apimServiceId","endpointMode","endpointAccessPath","validationReference"][]; $e[.] | nonempty) and
    .validationType == "apim-endpoint-access" and
    (.status == "pass" or .status == "fail" or .status == "blocked") and
    (.timestampUtc | utc) and
    (.apimServiceId | ascii_downcase) == ($id | ascii_downcase) and
    .endpointMode == "custom" and .endpointAccessPath == $path and
    .selectedHostnames == ($selected | map({key:.role,value:.hostname}) | from_entries) and
    (.validationReference | reference) and
    ($path != "corporate-routed" or
      (.owner == "network-owner" and (.routingApprovalReference | reference)))
  ' <<<"$evidence" >/dev/null || {
    echo "ERROR [$stage]: invalid endpoint evidence; require exact base/extension fields, valid UTC timestampUtc, gate/owner, and matching service/mode/path/hostnames." >&2
    return 1
  }
  status="$(jq -r '.status' <<<"$evidence")"
  case "$status" in
    pass) ;;
    blocked)
      block "$stage" "Endpoint evidence status is blocked; custom readiness cannot advance."
      return 3
      ;;
    fail)
      echo "ERROR [$stage]: endpoint evidence status is fail; custom readiness cannot advance." >&2
      return 1
      ;;
  esac
}

validate_apim_endpoint_reachability() {
  local apim_name="$1"
  local apim_json="$2"
  local endpoint ip endpoints ips service_id
  local curl_args=(--silent --show-error --connect-timeout 5 --max-time 10)
  if [[ "${APIM_ENDPOINT_ACCESS_PATH:-direct-private}" == "direct-private" ]]; then
    curl_args+=(--noproxy '*')
  fi
  endpoints="$(select_apim_endpoints "$apim_name")" || return 1
  if [[ "${APIM_ENDPOINT_MODE:-built-in}" == "custom" ]]; then
    apim_classic_sku_supported "$apim_json" &&
      [[ "$(lowercase "$(jq -r '.virtualNetworkType // ""' <<<"$apim_json")")" == "internal" ]] || {
      echo "ERROR [foundation]: custom endpoint checks require classic Developer capacity 1 or Premium in Internal mode." >&2
      return 1
    }
    validate_endpoint_bindings "$apim_json" "$endpoints" || return 1
  fi
  while IFS= read -r endpoint; do
    if ! ips="$(getent ahostsv4 "$endpoint" | awk '{print $1}' | sort -u)" || [[ -z "$ips" ]]; then
      echo "ERROR [foundation]: a selected endpoint did not resolve to IPv4 from the validation network." >&2
      return 1
    fi
    if [[ "${APIM_ENDPOINT_ACCESS_PATH:-direct-private}" == "direct-private" ]]; then
      while IFS= read -r ip; do
        if ! is_private_ipv4 "$ip" || ! jq -e --arg ip "$ip" '(.privateIPAddresses // []) | index($ip) != null' <<<"$apim_json" >/dev/null; then
          echo "ERROR [foundation]: a selected endpoint resolved outside the APIM-reported private IPs." >&2
          return 1
        fi
      done <<<"$ips"
    fi
    if ! curl "${curl_args[@]}" "https://$endpoint" -o /dev/null; then
      echo "ERROR [foundation]: selected endpoint TLS/reachability failed; certificate bypass is not permitted." >&2
      return 1
    fi
  done < <(jq -r '.[].hostname' <<<"$endpoints")
  if [[ "${APIM_ENDPOINT_MODE:-built-in}" == "custom" ]]; then
    service_id="$(jq -r '.id // ""' <<<"$apim_json")"
    [[ -n "$service_id" ]] || {
      block foundation "Live APIM service ID is unavailable; selected upstream context cannot be verified."
      return 3
    }
    validate_endpoint_evidence "${APIM_ENDPOINT_VALIDATION_EVIDENCE:-}" "$service_id" "$endpoints" || return $?
    echo "PASS [foundation]: selected live bindings and DNS/TLS measured; endpoint evidence retained separately from measurements."
  fi
}

validate_endpoint_handoff() {
  local apim_json="$1" endpoints="$2" handoff="${APIM_STAGE1_ENDPOINT_ACCESS:-}" service_id selected_hostnames
  [[ -n "$handoff" ]] || handoff='{}'
  service_id="$(jq -r '.id' <<<"$apim_json")"
  if jq -e 'type == "object" and length == 0' <<<"$handoff" >/dev/null 2>&1; then
    if [[ "${APIM_ENDPOINT_MODE:-built-in}" != "built-in" || "${APIM_ENDPOINT_ACCESS_PATH:-direct-private}" != "direct-private" ]]; then
      echo "ERROR [integration]: custom selection requires a matching Stage 1 endpointAccess handoff; legacy permits only built-in/direct-private." >&2
      return 1
    fi
    return
  fi
  selected_hostnames="$(jq -c 'map(select(.role == "gateway" or .role == "developerPortal" or .role == "management") | {key:.role,value:.hostname}) | from_entries' <<<"$endpoints")"
  jq -e --arg id "$service_id" --arg mode "${APIM_ENDPOINT_MODE:-built-in}" \
    --arg path "${APIM_ENDPOINT_ACCESS_PATH:-direct-private}" \
    --argjson endpoints "$endpoints" --argjson hostnames "$selected_hostnames" '
      type == "object" and (.apimServiceId | ascii_downcase) == ($id | ascii_downcase)
      and .endpointMode == $mode and .endpointAccessPath == $path
      and .selectedHostnames == $hostnames and .endpoints == $endpoints
      and .selectedGatewayHostname == $endpoints[0].hostname
      and .selectedGatewayUrl == ("https://"+$endpoints[0].hostname)
      and .excludedClientChecks == (if $mode == "custom" then ["legacyPortal","scm"] else [] end)
    ' <<<"$handoff" >/dev/null || {
    echo "ERROR [integration]: Stage 1 endpointAccess does not match selected service/mode/path/hostnames." >&2
    return 1
  }
  if [[ "${APIM_ENDPOINT_MODE:-built-in}" == "custom" ]]; then
    local result=0
    validate_endpoint_evidence "$(jq -c '.endpointValidationEvidence // {}' <<<"$handoff")" "$service_id" "$endpoints" integration || result=$?
    if [[ "$result" != 0 ]]; then
      echo "ERROR [integration]: custom Stage 1 handoff lacks complete valid pass endpoint evidence; overall readiness cannot override it." >&2
      return 1
    fi
    validate_endpoint_bindings "$apim_json" "$(jq -c '.[0:1]' <<<"$endpoints")" integration || return 1
  fi
}

selected_integration_request_url() {
  local selected_gateway="$1" api_path="$2" override="${3:-}" request_url
  request_url="${override:-https://$selected_gateway/$api_path/chat/completions}"
  jq -en --arg url "$request_url" --arg host "$selected_gateway" --arg path "/$api_path/chat/completions" '
    ($url | capture("^(?i:https)://(?<host>[a-zA-Z0-9.-]+)(?<port>:[0-9]+)?(?<path>/[^?#]*)$")) as $parsed |
    ($parsed.host | ascii_downcase) == $host and
    ($parsed.port == null or $parsed.port == ":443") and
    $parsed.path == $path
  ' >/dev/null || {
    echo "ERROR [integration]: request URL must use HTTPS, selected gateway, configured API path, no userinfo/query/fragment, and implicit or explicit port 443." >&2
    return 1
  }
  printf '%s\n' "$request_url"
}

validate_static_ownership() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN

  if [[ "$MODE" == "foundation" || "$MODE" == "all" ]]; then
    compile_to "$FOUNDATION_TEMPLATE" "$temp_dir/foundation.json"
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

    printf '%s\n' 'Microsoft.CognitiveServices/accounts' >"$temp_dir/seed-foundation"
    if (assert_absent 'Microsoft\.CognitiveServices|foundry-openai-backend|approved-models|enterprise-llm-api' \
      "$temp_dir/seed-foundation" "seeded foundation ownership violation") >/dev/null 2>&1; then
      echo "ERROR: foundation ownership regression self-test did not exercise assert_absent" >&2
      exit 1
    fi
  fi

  if [[ "$MODE" == "integration" || "$MODE" == "all" ]]; then
    compile_to "$INTEGRATION_TEMPLATE" "$temp_dir/integration.json"
    integration_resources_owned "$temp_dir/integration.json" || {
      echo "ERROR: integration compiled template declares a foundation-owned resource" >&2
      exit 1
    }
    assert_present 'Microsoft\.Authorization/roleAssignments' \
      "$temp_dir/integration.json" \
      "integration compiled template lacks the Foundry role assignment"
    assert_present 'Microsoft\.ApiManagement/service/backends' \
      "$temp_dir/integration.json" \
      "integration compiled template lacks the APIM backend"
    assert_present 'Microsoft\.ApiManagement/service/apis' \
      "$temp_dir/integration.json" \
      "integration compiled template lacks the governed API"

    printf '%s\n' '{"resources":[{"type":"Microsoft.ApiManagement/service"}]}' >"$temp_dir/seed-integration"
    if integration_resources_owned "$temp_dir/seed-integration" >/dev/null 2>&1; then
      echo "ERROR: integration ownership regression self-test did not exercise assert_absent" >&2
      exit 1
    fi
  fi
}

integration_resources_owned() {
  jq -e '
    [.. | objects | select(has("resources")) | .resources[] |
      select(.existing != true) |
      select(.type == "Microsoft.ApiManagement/service"
        or (.type | startswith("Microsoft.Network/privateDnsZones"))
        or .type == "Microsoft.Insights/components"
        or .type == "Microsoft.OperationalInsights/workspaces"
        or .type == "Microsoft.Insights/metricAlerts")]
    | length == 0
  ' "$1" >/dev/null
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
  if [[ "$FOUNDATION_PARAMETERS" != "infra/envs/poc/apim.customer.example.bicepparam" ]]; then
    compile_params "infra/envs/poc/apim.customer.example.bicepparam"
  fi

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
  assert_present "legacyPortalStatus: 'Disabled'" "$REPO_ROOT/infra/modules/apim/main.bicep" "legacy APIM portal is not explicitly disabled"
  assert_present "Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'False'" "$REPO_ROOT/infra/modules/apim/main.bicep" "APIM HTTP/2 is not explicitly disabled"
  assert_present "'Developer'" "$REPO_ROOT/infra/modules/apim/main.bicep" "Developer smoke-test SKU is not allowed"
  assert_present "Developer APIM requires apimSkuCapacity to be 1" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "Developer capacity guard is missing"
  assert_present "'Microsoft.Network/publicIPAddresses@2023-11-01'" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "foundation does not create the APIM platform public IP"
  assert_present "publicIPAllocationMethod: 'Static'" "$REPO_ROOT/$FOUNDATION_TEMPLATE" "APIM public IP is not static"
  assert_present 'apimPublicIpDdosProtectionMode' "$REPO_ROOT/$FOUNDATION_TEMPLATE" "APIM public IP DDoS mode is not preserved"
  assert_present 'APIM_PUBLIC_IP_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "APIM public IP customer tag input is missing"
  assert_present 'APIM_SERVICE_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "APIM service tag input is missing"
  assert_present 'APIM_LOG_ANALYTICS_WORKSPACE_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "Log Analytics workspace tag input is missing"
  assert_present 'APIM_APP_INSIGHTS_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "Application Insights tag input is missing"
  assert_present 'APIM_CAPACITY_ALERT_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "capacity alert tag input is missing"
  assert_present 'APIM_PRIVATE_DNS_ZONE_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "private DNS zone tag input is missing"
  assert_present 'APIM_PRIVATE_DNS_VNET_LINK_TAGS' "$REPO_ROOT/$FOUNDATION_PARAMETERS" "private DNS VNet link tag input is missing"
  assert_present 'publicIpAddressId:' "$REPO_ROOT/infra/modules/apim/main.bicep" "classic APIM public IP is not associated"
  assert_present 'Gateway.Security.Protocols.Tls10' "$REPO_ROOT/infra/modules/apim/main.bicep" "TLS 1.0 disablement is missing"
  assert_present 'Gateway.Security.Protocols.Tls11' "$REPO_ROOT/infra/modules/apim/main.bicep" "TLS 1.1 disablement is missing"
  assert_present "categoryGroup: 'AllLogs'" "$REPO_ROOT/infra/modules/apim/observability.bicep" "AllLogs diagnostics are missing"
  assert_present "category: 'AllMetrics'" "$REPO_ROOT/infra/modules/apim/observability.bicep" "AllMetrics diagnostics are missing"
  assert_present 'retentionInDays: logAnalyticsRetentionInDays' "$REPO_ROOT/infra/modules/apim/observability.bicep" "Log Analytics retention is not parameterized"
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
    "infra/envs/poc/apim-foundry-integration.customer.example.bicepparam"
  )
  for file in "${files[@]}"; do require_file "$file"; done

  compile_bicep "infra/modules/apim/foundry-role-assignment.bicep"
  compile_bicep "infra/modules/apim/backend.bicep"
  compile_bicep "infra/modules/apim/api.bicep"
  compile_bicep "$INTEGRATION_TEMPLATE"
  compile_params "$INTEGRATION_PARAMETERS"
  if [[ "$INTEGRATION_PARAMETERS" != "infra/envs/poc/apim-foundry-integration.customer.example.bicepparam" ]]; then
    compile_params "infra/envs/poc/apim-foundry-integration.customer.example.bicepparam"
  fi

  assert_present 'authentication-managed-identity' "$REPO_ROOT/infra/modules/apim/backend.bicep" "managed-identity backend policy is missing"
  assert_present 'https://cognitiveservices.azure.com' "$REPO_ROOT/infra/modules/apim/backend.bicep" "Cognitive Services audience is missing"
  assert_present 'subscriptionRequired: true' "$REPO_ROOT/infra/modules/apim/api.bicep" "subscription enforcement is missing"
  assert_present 'set-header name="Ocp-Apim-Subscription-Key" exists-action="delete"' \
    "$REPO_ROOT/infra/modules/apim/api.bicep" \
    "subscription key is not removed before backend forwarding"
  assert_present 'set-query-parameter name="subscription-key" exists-action="delete"' \
    "$REPO_ROOT/infra/modules/apim/api.bicep" \
    "subscription key query parameter is not removed before backend forwarding"
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
  load_selected_parameter_values "$FOUNDATION_PARAMETERS"
  select_apim_endpoints "$APIM_SERVICE_NAME" >/dev/null || exit 1

  local missing=false
  for name in APIM_RESOURCE_GROUP APIM_NETWORK_RESOURCE_GROUP APIM_VNET_NAME APIM_SUBNET_NAME APIM_APPROVED_NSG_RESOURCE_ID APIM_PUBLISHER_EMAIL; do
    require_env_value "$name" foundation || missing=true
  done
  for name in APIM_RESOURCE_GROUP APIM_NETWORK_RESOURCE_GROUP APIM_VNET_NAME APIM_SUBNET_NAME APIM_APPROVED_NSG_RESOURCE_ID APIM_PUBLIC_IP_NAME APIM_PUBLISHER_EMAIL; do
    validate_non_placeholder_value "$name" foundation
  done
  validate_foundation_workspace_selection || missing=true
  validate_optional_evidence_reference APIM_SUBNET_NAMING_EXCEPTION_REFERENCE foundation
  validate_optional_evidence_reference APIM_ROUTE_TABLE_EXCEPTION_REFERENCE foundation
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

  if [[ "$(lowercase "$subnet_name")" != apimsubnet-* && -z "${APIM_SUBNET_NAMING_EXCEPTION_REFERENCE:-}" ]]; then
    echo "ERROR [foundation]: APIM subnet naming is unapproved and no exception reference was supplied." >&2
    exit 1
  fi
  [[ "$(lowercase "$subnet_nsg")" == "$(lowercase "$APIM_APPROVED_NSG_RESOURCE_ID")" ]] || {
    echo "ERROR [foundation]: APIM subnet NSG does not match the approved NSG." >&2
    exit 1
  }
  if [[ -n "${APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID:-}" ]]; then
    [[ "$(lowercase "$subnet_route")" == "$(lowercase "$APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID")" ]] || {
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

  local publisher_email_normalized
  publisher_email_normalized="$(lowercase "$APIM_PUBLISHER_EMAIL")"
  if [[ "$publisher_email_normalized" == *@example.com || "$publisher_email_normalized" == *@contoso.com ]]; then
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

  local apim_json
  if apim_json="$(az apim show --resource-group "$APIM_RESOURCE_GROUP" --name "$APIM_SERVICE_NAME" -o json)"; then
    local apim_json apim_id apim_name expected_sku expected_capacity expected_public_ip_id
    apim_name="$APIM_SERVICE_NAME"
    expected_sku="${APIM_SKU_NAME:-Premium}"
    expected_capacity="${APIM_SKU_CAPACITY:-1}"
    jq -e --arg sku "$expected_sku" --argjson capacity "$expected_capacity" '
      .sku.name == $sku and
      .sku.capacity == $capacity and
      .virtualNetworkType == "Internal" and
      .identity.type == "SystemAssigned" and
      (.identity.principalId | length > 0)
    ' <<<"$apim_json" >/dev/null
    jq -e '(.privateIPAddresses // [] | length) > 0' <<<"$apim_json" >/dev/null
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
    expected_public_ip_id="$(az network public-ip show \
      --resource-group "$APIM_RESOURCE_GROUP" \
      --name "$APIM_PUBLIC_IP_NAME" \
      --query id -o tsv)" || {
      echo "ERROR [foundation]: selected APIM public IP $APIM_PUBLIC_IP_NAME could not be resolved." >&2
      exit 1
    }
    [[ "$(lowercase "$apim_public_ip_id")" == "$(lowercase "$expected_public_ip_id")" ]] || {
      echo "ERROR [foundation]: APIM publicIpAddressId does not match the selected APIM_PUBLIC_IP_NAME resource." >&2
      exit 1
    }
    az resource show --ids "$expected_public_ip_id" --api-version 2023-11-01 -o json |
      jq -e '.sku.name == "Standard" and .properties.publicIPAllocationMethod == "Static"' >/dev/null || {
      echo "ERROR [foundation]: selected APIM public IP must use Standard SKU and Static allocation." >&2
      exit 1
    }

    if [[ "${APIM_PRIVATE_DNS_MODE:-external}" == "blueprint" ]]; then
      for record in "$apim_name" "$apim_name.developer" "$apim_name.portal" "$apim_name.management" "$apim_name.scm"; do
        az network private-dns record-set a show \
          --resource-group "$APIM_RESOURCE_GROUP" \
          --zone-name "${APIM_PRIVATE_DNS_ZONE_NAME:-azure-api.net}" \
          --name "$record" \
          --query "aRecords | length(@)" -o tsv | grep -Eq '^[1-9][0-9]*$'
      done
    fi

    if [[ "${APIM_VALIDATE_ENDPOINT_REACHABILITY:-false}" == "true" ]]; then
      local endpoint_result=0
      validate_apim_endpoint_reachability "$apim_name" "$apim_json" || endpoint_result=$?
      if [[ "$endpoint_result" == 1 ]]; then exit 1; fi
      if [[ "${APIM_ENDPOINT_MODE:-built-in}" == "built-in" && "${APIM_PRIVATE_DNS_MODE:-external}" == "external" ]]; then
        require_evidence_reference APIM_EXTERNAL_DNS_VALIDATION_REFERENCE foundation || true
      fi
    elif [[ "${APIM_PRIVATE_DNS_MODE:-external}" == "external" ]]; then
      block foundation "External DNS requires APIM_VALIDATE_ENDPOINT_REACHABILITY=true from an authorized network to validate customer-managed resolution and reachability."
    else
      block foundation "Set APIM_VALIDATE_ENDPOINT_REACHABILITY=true from an authorized network to verify internal gateway, portal, management, and SCM reachability."
    fi

    local diagnostic_settings_json expected_workspace_id expected_workspace_label diagnostics_owner
    diagnostic_settings_json="$(az monitor diagnostic-settings list --resource "$apim_id" -o json)"
    if ! expected_workspace_id="$(resolve_foundation_workspace_id)" || [[ -z "$expected_workspace_id" ]]; then
      if [[ -n "${APIM_LOG_ANALYTICS_WORKSPACE_NAME:-}" ]]; then
        block foundation "Log Analytics workspace $APIM_LOG_ANALYTICS_WORKSPACE_NAME was not found in resource group $APIM_RESOURCE_GROUP; runtime diagnostics validation cannot resolve its resource ID."
      else
        block foundation "Runtime diagnostics validation could not resolve an expected Log Analytics workspace ID."
      fi
      return 0
    fi
    if [[ -n "${APIM_LOG_ANALYTICS_WORKSPACE_ID:-}" ]]; then
      expected_workspace_label="$APIM_LOG_ANALYTICS_WORKSPACE_ID"
    else
      expected_workspace_label="$APIM_LOG_ANALYTICS_WORKSPACE_NAME ($expected_workspace_id)"
    fi
    diagnostics_owner="${APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP:-policy}"
    case "$diagnostics_owner" in
      blueprint|policy) ;;
      *)
        echo "ERROR [foundation]: APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP must be blueprint or policy." >&2
        exit 1
        ;;
    esac
    diagnostics_match_expected_workspace \
      "$diagnostic_settings_json" \
      "$expected_workspace_id" \
      "$diagnostics_owner" \
      "${APIM_DIAGNOSTIC_SETTING_NAME:-diag-apim-gateway}" || {
      echo "ERROR [foundation]: $diagnostics_owner diagnostics must send AllLogs and AllMetrics to the resolved Log Analytics workspace." >&2
      exit 1
    }
    if [[ "$diagnostics_owner" == "policy" ]]; then
      require_governance_reference APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE foundation || return 0
    fi
    echo "Validated $diagnostics_owner APIM diagnostics to workspace $expected_workspace_label."

    az monitor metrics alert show \
      --resource-group "$APIM_RESOURCE_GROUP" \
      --name "${APIM_CAPACITY_ALERT_NAME:-alert-apim-capacity-over-60}" \
      --query "criteria.allOf[?metricName=='Capacity' && operator=='GreaterThan' && timeAggregation=='Average' && threshold>=\`${APIM_CAPACITY_ALERT_THRESHOLD:-60}\`] | length(@)" -o tsv | grep -qx 1

  else
    block foundation "APIM runtime read is unavailable (missing deployment or access); identity, DNS, diagnostics, alert, and selected endpoint checks remain pending."
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
  load_selected_parameter_values "$INTEGRATION_PARAMETERS"

  local missing=false
  for name in APIM_RESOURCE_GROUP APIM_SERVICE_NAME APIM_STAGE1_SERVICE_ID APIM_STAGE1_FOUNDATION_READINESS FOUNDRY_RESOURCE_GROUP FOUNDRY_ACCOUNT_NAME FOUNDRY_ACCOUNT_ID FOUNDRY_APPROVED_REGIONS FOUNDRY_APPROVED_MODELS; do
    require_env_value "$name" integration || missing=true
  done
  for name in GENAI_APPROVAL_REFERENCE FOUNDRY_ENABLEMENT_REFERENCE FOUNDRY_CUSTOMER_POLICY_SOURCE; do
    require_governance_reference "$name" integration || missing=true
  done
  if [[ "$missing" == true ]]; then
    return 0
  fi

  local apim_json apim_id foundry_json apim_principal foundry_id foundry_location approved_regions_json approved_models_json model_deployment
  approved_regions_json="$FOUNDRY_APPROVED_REGIONS"
  approved_models_json="$FOUNDRY_APPROVED_MODELS"
  jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' \
    <<<"$approved_regions_json" >/dev/null || {
    echo "ERROR [integration]: FOUNDRY_APPROVED_REGIONS must be a non-empty JSON array of region names." >&2
    exit 1
  }
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
  jq -e '
    [.[]
      | select(.enabled == true)
      | .publicName
      | ascii_downcase
    ] as $aliases
    | ($aliases | length) == ($aliases | unique | length)
  ' <<<"$approved_models_json" >/dev/null || {
    echo "ERROR [integration]: FOUNDRY_APPROVED_MODELS must not contain duplicate enabled model aliases." >&2
    exit 1
  }
  jq -e '
    .network == "validated" and
    .apim == "deployed" and
    .identity == "deployed" and
    .dns == "deployed" and
    .observability == "deployed" and
    .status == "deployed"
  ' <<<"$APIM_STAGE1_FOUNDATION_READINESS" >/dev/null || {
    echo "ERROR [integration]: APIM_STAGE1_FOUNDATION_READINESS must be the deployed Stage 1 foundationReadiness output." >&2
    exit 1
  }

  if ! apim_json="$(az apim show --resource-group "$APIM_RESOURCE_GROUP" --name "$APIM_SERVICE_NAME" -o json)"; then
    block integration "Live APIM read is unavailable; service identity and selected gateway binding cannot be verified."
    return 0
  fi
  apim_id="$(jq -r '.id' <<<"$apim_json")"
  [[ "$(lowercase "$apim_id")" == "$(lowercase "$APIM_STAGE1_SERVICE_ID")" ]] || {
    echo "ERROR [integration]: APIM_STAGE1_SERVICE_ID does not match the selected Stage 1 APIM service." >&2
    exit 1
  }
  apim_classic_sku_supported "$apim_json" || {
    echo "ERROR [integration]: Stage 2 requires a validated internal APIM Stage 1 foundation using Developer capacity 1 or Premium." >&2
    exit 1
  }
  [[ "$(lowercase "$(jq -r '.virtualNetworkType // ""' <<<"$apim_json")")" == "internal" ]] || {
    echo "ERROR [integration]: Stage 2 requires a validated internal APIM Stage 1 foundation using Developer capacity 1 or Premium." >&2
    exit 1
  }
  apim_principal="$(jq -r '.identity.principalId // ""' <<<"$apim_json")"
  [[ -n "$apim_principal" ]] || {
    echo "ERROR [integration]: existing APIM has no system-assigned principal." >&2
    exit 1
  }
  local selected_endpoints selected_gateway request_base_url
  selected_endpoints="$(select_apim_endpoints "$APIM_SERVICE_NAME" integration)" || exit 1
  validate_endpoint_handoff "$apim_json" "$selected_endpoints" || exit 1
  selected_gateway="$(jq -r '.[0].hostname' <<<"$selected_endpoints")"
  request_base_url="$(selected_integration_request_url "$selected_gateway" "${APIM_GOVERNED_API_PATH:-llm/v1}" "${APIM_INTEGRATION_REQUEST_URL:-}")" || exit 1

  foundry_json="$(az cognitiveservices account show --resource-group "$FOUNDRY_RESOURCE_GROUP" --name "$FOUNDRY_ACCOUNT_NAME" -o json)"
  foundry_id="$(jq -r '.id' <<<"$foundry_json")"
  foundry_location="$(jq -r '.location | ascii_downcase' <<<"$foundry_json")"
  [[ "$(lowercase "$foundry_id")" == "$(lowercase "$FOUNDRY_ACCOUNT_ID")" ]] || {
    echo "ERROR [integration]: FOUNDRY_ACCOUNT_ID does not match the selected account." >&2
    exit 1
  }
  [[ "$(jq -r '.properties.publicNetworkAccess // .publicNetworkAccess // ""' <<<"$foundry_json")" == "Disabled" ]] || {
    echo "ERROR [integration]: Foundry public network access must be Disabled." >&2
    exit 1
  }
  jq -e --arg location "$foundry_location" 'map(ascii_downcase) | index($location) != null' <<<"$approved_regions_json" >/dev/null || {
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

  if az apim backend show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --backend-id "${APIM_FOUNDRY_BACKEND_NAME:-foundry-openai-backend}" >/dev/null 2>&1; then
    local role_assignments_json normalized_foundry_id
    normalized_foundry_id="$(lowercase "$foundry_id")"
    role_assignments_json="$(az role assignment list \
      --assignee "$apim_principal" \
      --scope "$foundry_id" \
      --include-inherited \
      --all \
      -o json)"
    jq -e --arg scope "$normalized_foundry_id" '
      def is_openai_user:
        (.roleDefinitionName == "Cognitive Services OpenAI User")
        or ((.roleDefinitionId // "") | ascii_downcase | endswith("/5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"));
      ([.[] | select(is_openai_user and ((.scope // "") | ascii_downcase) == $scope)] | length) == 1
      and ([.[] | select(((.scope // "") | ascii_downcase) != $scope)] | length) == 0
    ' <<<"$role_assignments_json" >/dev/null || {
      echo "ERROR [integration]: APIM must have exactly one Cognitive Services OpenAI User assignment at the Foundry account and no inherited broader-scope assignments." >&2
      exit 1
    }
    az apim backend show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --backend-id "${APIM_FOUNDRY_BACKEND_NAME:-foundry-openai-backend}" \
      --query "starts_with(url, 'https://')" -o tsv | grep -qx true
    local governed_api_name="${APIM_GOVERNED_API_NAME:-enterprise-llm-api}"
    az apim api show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --api-id "$governed_api_name" \
      --query "subscriptionRequired" -o tsv | grep -qx true
    az apim nv show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --named-value-id approved-models \
      --query "secret==\`false\`" -o tsv | grep -qx true
    local api_policy
    api_policy="$(az apim api policy show --resource-group "$APIM_RESOURCE_GROUP" --service-name "$APIM_SERVICE_NAME" --api-id "$governed_api_name" --query value -o tsv)"
    grep -q 'authentication-managed-identity' <<<"$api_policy"
    grep -q 'llm-token-limit' <<<"$api_policy"
    grep -q 'unsupported_model' <<<"$api_policy"
    grep -q 'Ocp-Apim-Subscription-Key' <<<"$api_policy"
    grep -q 'set-header name="Ocp-Apim-Subscription-Key" exists-action="delete"' <<<"$api_policy"
    grep -q 'set-query-parameter name="subscription-key" exists-action="delete"' <<<"$api_policy"

    if [[ "${APIM_VALIDATE_INTEGRATION_REQUESTS:-false}" == "true" ]]; then
      local subscription_key approved_model unsupported_model request_body
      local response_file status_code success_count telemetry_workspace_id
      for name in APIM_INTEGRATION_SUBSCRIPTION_KEY APIM_INTEGRATION_TELEMETRY_WORKSPACE_ID APIM_ALLOWED_REQUEST_TELEMETRY_QUERY APIM_REJECTED_REQUEST_BACKEND_QUERY APIM_UNSAFE_TELEMETRY_QUERY; do
        require_env_value "$name" integration || missing=true
      done
      if [[ "$missing" == true ]]; then
        block integration "Authorized request validation requires a subscription key, telemetry workspace, and allowed/rejected/unsafe telemetry queries."
        return 0
      fi

      subscription_key="$APIM_INTEGRATION_SUBSCRIPTION_KEY"
      approved_model="$(jq -r '.[] | select(.enabled == true) | .publicName' <<<"$approved_models_json" | head -n 1)"
      unsupported_model="validator-unapproved-model"
      if jq -e --arg model "$unsupported_model" '[.[].publicName] | index($model) != null' <<<"$approved_models_json" >/dev/null; then
        unsupported_model="validator-unapproved-model-2"
      fi
      response_file="$(mktemp)"
      trap 'rm -f "$response_file"' RETURN
      success_count=0
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        request_body="$(jq -cn --arg model "$approved_model" \
          '{model:$model,messages:[{role:"user",content:"validation probe"}],stream:false}')"
        status_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
          --connect-timeout 10 --max-time 120 \
          --header 'Content-Type: application/json' \
          --header "Ocp-Apim-Subscription-Key: $subscription_key" \
          --data "$request_body" \
          "$request_base_url")"
        if [[ "$status_code" == 2* ]] && jq -e '
          .object == "chat.completion" and (.model | type == "string" and length > 0)
          and (.choices | type == "array" and length > 0)
          and .choices[0].message.role == "assistant"
          and (.choices[0].message.content | type == "string" and length > 0)
        ' "$response_file" >/dev/null; then
          success_count=$((success_count + 1))
        fi
      done
      [[ "$success_count" -ge 9 ]] || {
        echo "ERROR [integration]: approved request reliability was $success_count/10; at least 9/10 must succeed." >&2
        exit 1
      }

      request_body="$(jq -cn --arg model "$approved_model" \
        '{model:$model,messages:[{role:"user",content:"validation unauthenticated probe"}],stream:false}')"
      status_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
        --connect-timeout 10 --max-time 120 \
        --header 'Content-Type: application/json' \
        --data "$request_body" \
        "$request_base_url")"
      [[ "$status_code" == "401" || "$status_code" == "403" ]] || {
        echo "ERROR [integration]: unauthenticated request returned HTTP $status_code instead of 401/403." >&2
        exit 1
      }

      request_body="$(jq -cn --arg model "$unsupported_model" \
        '{model:$model,messages:[{role:"user",content:"validation unsupported-model probe"}],stream:false}')"
      status_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
        --connect-timeout 10 --max-time 120 \
        --header 'Content-Type: application/json' \
        --header "Ocp-Apim-Subscription-Key: $subscription_key" \
        --data "$request_body" \
        "$request_base_url")"
      if [[ "$status_code" != "400" ]] || ! jq -e '.error.code == "unsupported_model"' "$response_file" >/dev/null; then
        echo "ERROR [integration]: unsupported model request was not rejected with HTTP 400 and unsupported_model." >&2
        exit 1
      fi

      telemetry_workspace_id="$APIM_INTEGRATION_TELEMETRY_WORKSPACE_ID"
      az monitor log-analytics query --workspace "$telemetry_workspace_id" \
        --analytics-query "$APIM_ALLOWED_REQUEST_TELEMETRY_QUERY" \
        --query 'tables[0].rows[0][0]' -o tsv | grep -Eq '^[1-9][0-9]*$'
      az monitor log-analytics query --workspace "$telemetry_workspace_id" \
        --analytics-query "$APIM_REJECTED_REQUEST_BACKEND_QUERY" \
        --query 'tables[0].rows[0][0]' -o tsv | grep -qx 0
      az monitor log-analytics query --workspace "$telemetry_workspace_id" \
        --analytics-query "$APIM_UNSAFE_TELEMETRY_QUERY" \
        --query 'tables[0].rows[0][0]' -o tsv | grep -qx 0
      echo "Integration request and telemetry validation passed."
    else
      block integration "Set APIM_VALIDATE_INTEGRATION_REQUESTS=true with authorized client inputs to verify allowed, unsupported, unauthenticated, and secret-safe telemetry behavior."
    fi
  else
    block integration "Integration resources are not deployed; role, backend, API, request, and telemetry checks remain pending."
  fi
}

if [[ "${VALIDATOR_LIBRARY_ONLY:-false}" != "true" ]]; then
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
fi
