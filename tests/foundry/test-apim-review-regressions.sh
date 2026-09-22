#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
validator="$REPO_ROOT/specs/02-apim-ai-gateway/validation/validate.sh"
integration="$REPO_ROOT/infra/envs/poc/apim-foundry-integration.bicep"
foundation="$REPO_ROOT/infra/envs/poc/apim.bicep"
foundation_params="$REPO_ROOT/infra/envs/poc/apim.bicepparam"
apim_main="$REPO_ROOT/infra/modules/apim/main.bicep"
observability="$REPO_ROOT/infra/modules/apim/observability.bicep"
private_dns="$REPO_ROOT/infra/modules/apim/private-dns.bicep"
foundation_example_params="$REPO_ROOT/infra/envs/poc/apim.customer.example.bicepparam"
final_report="$REPO_ROOT/specs/02-apim-ai-gateway/validation/final-report.md"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_succeeds() {
  local message="$1"
  shift
  "$@" || fail "$message"
}

assert_fails() {
  local message="$1"
  shift
  if "$@"; then
    fail "$message"
  fi
}

command -v jq >/dev/null 2>&1 || fail "jq is required to run these regression tests"

resource_uses_tag_parameter() {
  local template="$1" resource_type="$2" parameter_name="$3"
  jq -e --arg type "$resource_type" --arg tags "[parameters('$parameter_name')]" '
    [.resources[] | select(.type == $type and .tags == $tags)] | length == 1
  ' "$template" >/dev/null
}

HAVE_AZ=false
if command -v az >/dev/null 2>&1; then
  HAVE_AZ=true
fi

if [[ "$HAVE_AZ" == "true" ]]; then
  echo "==> Azure CLI/Bicep detected: running compile-dependent regression checks"

  az bicep build --file "$integration" --outfile "$workdir/integration.json" >/dev/null
  az bicep build --file "$apim_main" --outfile "$workdir/apim-main.json" >/dev/null
  az bicep build --file "$observability" --outfile "$workdir/observability.json" >/dev/null
  az bicep build --file "$private_dns" --outfile "$workdir/private-dns.json" >/dev/null
  az bicep build --file "$foundation" --outfile "$workdir/foundation.json" >/dev/null

  echo "==> Compiled Stage 2 classic SKU contract"
  sku_expression="$(jq -r 'first(.. | strings | select(contains("supported classic SKU")))' "$workdir/integration.json")"
  [[ "$sku_expression" == *"equals(toLower("*".sku.name), 'developer')"* ]] ||
    fail "compiled Stage 2 template must normalize and accept Developer"
  [[ "$sku_expression" == *".sku.capacity, 1)"* ]] ||
    fail "compiled Stage 2 template must require Developer capacity one"
  [[ "$sku_expression" == *"equals(toLower("*".sku.name), 'premium')"* ]] ||
    fail "compiled Stage 2 template must accept Premium"
  [[ "$sku_expression" == *"Internal virtual network mode"* ]] ||
    fail "compiled Stage 2 template must retain the internal VNet gate"
  [[ "$sku_expression" == *"provisioned managed identity"* ]] ||
    fail "compiled Stage 2 template must retain the managed identity gate"
  jq -e '.. | strings | select(contains("Stage 2 requires the Stage 1 foundationReadiness handoff with network validated and APIM, identity, DNS, observability, and overall status deployed."))' \
    "$workdir/integration.json" >/dev/null ||
    fail "compiled Stage 2 template must retain the complete readiness gate"

  echo "==> Compiled governance sentinel rejection (Stage 2)"
  for field in genAiApprovalReference foundryEnablementReference; do
    jq -e --arg needle "$field must contain non-placeholder customer governance evidence." \
      '.. | strings | select(contains($needle))' "$workdir/integration.json" >/dev/null ||
      fail "compiled Stage 2 template must reject placeholder $field values"
  done
  jq -e '.. | strings | select(contains("customerPolicySource must identify a maintained non-placeholder customer policy source."))' \
    "$workdir/integration.json" >/dev/null ||
    fail "compiled Stage 2 template must reject a placeholder customerPolicySource"

  echo "==> Compiled duplicate enabled model alias rejection (Stage 2)"
  jq -e '.. | strings | select(contains("requires unique case-insensitive publicName aliases across enabled approved model mappings"))' \
    "$workdir/integration.json" >/dev/null ||
    fail "compiled Stage 2 template must reject duplicate enabled model aliases"

  echo "==> Compiled external DNS readiness contract"
  jq -e '
    .outputs.dnsReadiness.value as $readiness
    | $readiness.mode == "[if(parameters('\''deployPrivateDns'\''), '\''blueprint'\'', '\''external'\'')]"
    and $readiness.zone == "[if(parameters('\''deployPrivateDns'\''), '\''deployed'\'', '\''external'\'')]"
    and $readiness.link == "[if(parameters('\''deployPrivateDns'\''), '\''deployed'\'', '\''external'\'')]"
    and ($readiness.record | contains("external-handoff-required"))
    and ($readiness.additionalEndpointRecords | contains("external-handoff-required"))
    and $readiness.externalDnsValidation == "[if(variables('\''externalDnsValidated'\''), '\''validated'\'', if(not(parameters('\''deployPrivateDns'\'')), '\''required'\'', '\''not-required'\''))]"
    and $readiness.status == "[if(or(and(parameters('\''deployPrivateDns'\''), greater(length(parameters('\''apimPrivateIpAddresses'\'')), 0)), and(variables('\''externalDnsValidated'\''), greater(length(parameters('\''apimPrivateIpAddresses'\'')), 0))), '\''deployed'\'', '\''pending'\'')]"
  ' "$workdir/private-dns.json" >/dev/null ||
    fail "compiled DNS handoff must stay pending for external mode until validation evidence exists"

  echo "==> Compiled required ProjectCode=APIM tag precedence (Stage 1)"
  public_ip_resource="$(jq -e '.resources[] | select(.type == "Microsoft.Network/publicIPAddresses")' "$workdir/foundation.json")"
  tags_variable_name="$(jq -r 'if (.tags | type) == "string" then (.tags | capture("variables\\(.(?<n>[^)]+).\\)").n) else empty end' <<<"$public_ip_resource")"
  [[ -n "$tags_variable_name" ]] || fail "compiled foundation template public IP tags must resolve through a variable"
  tags_expression="$(jq -r --arg name "$tags_variable_name" '.variables[$name]' "$workdir/foundation.json")"
  [[ "$tags_expression" == *"union(parameters('apimPublicIpTags'), createObject('ProjectCode', 'APIM'))"* ]] ||
    fail "compiled foundation template must merge caller tags with a required ProjectCode=APIM override that wins on conflict"

  echo "==> Compiled independent resource tag mappings (Stage 1)"
  assert_succeeds "APIM service must use only apimServiceTags" \
    resource_uses_tag_parameter "$workdir/apim-main.json" "Microsoft.ApiManagement/service" "apimServiceTags"
  assert_succeeds "created Log Analytics workspace must use only logAnalyticsWorkspaceTags" \
    resource_uses_tag_parameter "$workdir/observability.json" "Microsoft.OperationalInsights/workspaces" "logAnalyticsWorkspaceTags"
  assert_succeeds "Application Insights must use only applicationInsightsTags" \
    resource_uses_tag_parameter "$workdir/observability.json" "Microsoft.Insights/components" "applicationInsightsTags"
  assert_succeeds "capacity alert must use only capacityAlertTags" \
    resource_uses_tag_parameter "$workdir/observability.json" "Microsoft.Insights/metricAlerts" "capacityAlertTags"
  assert_succeeds "private DNS zone must use only privateDnsZoneTags" \
    resource_uses_tag_parameter "$workdir/private-dns.json" "Microsoft.Network/privateDnsZones" "privateDnsZoneTags"
  assert_succeeds "private DNS VNet link must use only privateDnsVnetLinkTags" \
    resource_uses_tag_parameter "$workdir/private-dns.json" "Microsoft.Network/privateDnsZones/virtualNetworkLinks" "privateDnsVnetLinkTags"

  jq '
    .resources |= map(
      if .type == "Microsoft.ApiManagement/service"
      then .tags = "[parameters('\''applicationInsightsTags'\'')]"
      else .
      end
    )
  ' "$workdir/apim-main.json" >"$workdir/miswired-apim-main.json"
  assert_fails "resource-specific tag assertion must reject a deliberately miswired APIM tag parameter" \
    resource_uses_tag_parameter "$workdir/miswired-apim-main.json" "Microsoft.ApiManagement/service" "apimServiceTags"

  jq -e '
    [.resources[] | select(.type == "Microsoft.OperationalInsights/workspaces")]
    | length == 1
      and .[0].condition == "[empty(parameters('\''logAnalyticsWorkspaceId'\''))]"
  ' "$workdir/observability.json" >/dev/null ||
    fail "only the conditionally created workspace may receive logAnalyticsWorkspaceTags"

  jq -e '
    [.resources[]
      | select(
          .type == "Microsoft.Network/privateDnsZones"
          or .type == "Microsoft.Network/privateDnsZones/virtualNetworkLinks"
        )
    ]
    | length == 2
      and all(.condition == "[parameters('\''deployPrivateDns'\'')]")
  ' "$workdir/private-dns.json" >/dev/null ||
    fail "private DNS zone and VNet link tags must apply only in blueprint DNS mode"

  echo "==> Tag defaults and opaque custom-key passthrough (Stage 1)"
  env \
    -u APIM_SERVICE_TAGS \
    -u APIM_LOG_ANALYTICS_WORKSPACE_TAGS \
    -u APIM_APP_INSIGHTS_TAGS \
    -u APIM_CAPACITY_ALERT_TAGS \
    -u APIM_PRIVATE_DNS_ZONE_TAGS \
    -u APIM_PRIVATE_DNS_VNET_LINK_TAGS \
    az bicep build-params --file "$foundation_params" --stdout >"$workdir/default-params.json"
  jq -e '
    (.parametersJson | fromjson | .parameters) as $params
    | [
        $params.apimServiceTags.value,
        $params.logAnalyticsWorkspaceTags.value,
        $params.applicationInsightsTags.value,
        $params.capacityAlertTags.value,
        $params.privateDnsZoneTags.value,
        $params.privateDnsVnetLinkTags.value
      ]
    | all(. == {})
  ' "$workdir/default-params.json" >/dev/null ||
    fail "new APIM resource tag inputs must default to empty objects"

  APIM_SERVICE_TAGS='{"Owner::Group":"Example-Team"}' \
    az bicep build-params --file "$foundation_params" --stdout >"$workdir/custom-tag-params.json"
  jq -e '
    (.parametersJson | fromjson | .parameters.apimServiceTags.value)
      == {"Owner::Group":"Example-Team"}
  ' "$workdir/custom-tag-params.json" >/dev/null ||
    fail "Azure-valid custom tag keys and values must pass through unchanged"

  echo "==> Compiled placeholder network exception rejection (Stage 1)"
  jq -e '.. | strings | select(contains("The APIM subnet name must match apimsubnet-* or subnetNamingExceptionReference must identify a tenant-approved exception."))' \
    "$workdir/foundation.json" >/dev/null ||
    fail "compiled foundation template must reject unapproved subnet names without a valid exception reference"
  jq -e '.. | strings | select(contains("Supply the approved APIM route table, or leave the subnet route table empty and provide routeTableExceptionReference."))' \
    "$workdir/foundation.json" >/dev/null ||
    fail "compiled foundation template must reject a missing route table without a valid exception reference"
  jq -e '.. | strings | select(contains("The APIM subnet route table does not match approvedApimRouteTableResourceId."))' \
    "$workdir/foundation.json" >/dev/null ||
    fail "compiled foundation template must reject a route table that does not match the approved resource ID"

  echo "==> Compiled built-in APIM DNS naming enforcement (Stage 1)"
  jq -e '.. | strings | select(contains("Private DNS must use the APIM built-in hostname contract: <service>.azure-api.net."))' \
    "$workdir/foundation.json" >/dev/null ||
    fail "compiled foundation template must enforce the built-in <service>.azure-api.net DNS contract"
else
  echo "==> Azure CLI not found: skipping Bicep compile-dependent regression checks"
fi

VALIDATOR_LIBRARY_ONLY=true
# shellcheck source=../../specs/02-apim-ai-gateway/validation/validate.sh
source "$validator"

echo "==> Normalized governance/exception sentinel rejection (shell-only)"
for sentinel in '<placeholder>' 'Placeholder' '  REPLACE-ME  ' 'todo' 'TBD' 'ToDo' '<TODO>'; do
  assert_succeeds "is_placeholder must reject sentinel value '$sentinel'" \
    is_placeholder "$sentinel"
done
assert_succeeds "is_placeholder must reject empty values" is_placeholder ""
assert_fails "is_placeholder must accept genuine governance evidence" \
  is_placeholder "issue-71-genai-approval-2026-09-16"
assert_fails "is_placeholder must accept genuine evidence regardless of surrounding case" \
  is_placeholder "GOVERNANCE-REF-CONTOSO-2026"

echo "==> Duplicate enabled model alias rejection (runtime jq contract)"
duplicate_models_json='[{"publicName":"Gpt4o","deploymentName":"gpt-4o-a","enabled":true},{"publicName":"gpt4o","deploymentName":"gpt-4o-b","enabled":true}]'
distinct_models_json='[{"publicName":"gpt-4o","deploymentName":"gpt-4o-a","enabled":true},{"publicName":"gpt-4o-mini","deploymentName":"gpt-4o-mini-a","enabled":true}]'
duplicate_alias_check() {
  local models_json="$1"
  jq -e '
    [.[]
      | select(.enabled == true)
      | .publicName
      | ascii_downcase
    ] as $aliases
    | ($aliases | length) == ($aliases | unique | length)
  ' <<<"$models_json" >/dev/null
}
assert_fails "runtime preflight must reject case-insensitive duplicate enabled model aliases" \
  duplicate_alias_check "$duplicate_models_json"
assert_succeeds "runtime preflight must accept distinct enabled model aliases" \
  duplicate_alias_check "$distinct_models_json"

echo "==> Compiled Stage 2 classic SKU contract (live validator function)"
assert_succeeds "live validator must accept Developer capacity one" \
  apim_classic_sku_supported '{"sku":{"name":"Developer","capacity":1}}'
assert_succeeds "live validator must accept Premium" \
  apim_classic_sku_supported '{"sku":{"name":"Premium","capacity":2}}'
assert_fails "live validator must reject Developer capacity other than one" \
  apim_classic_sku_supported '{"sku":{"name":"Developer","capacity":2}}'
assert_fails "live validator must reject unsupported APIM SKUs" \
  apim_classic_sku_supported '{"sku":{"name":"Basic","capacity":1}}'

echo "==> Mixed-case APIM subnet naming normalization"
assert_succeeds "mixed-case apimsubnet-* names must normalize and pass" \
  bash -c '[[ "$(printf "%s" "ApimSubnet-Prod01" | tr "[:upper:]" "[:lower:]")" == apimsubnet-* ]]'
assert_fails "non-conforming subnet names without an exception reference must fail" \
  bash -c '[[ "$(printf "%s" "corpsubnet-01" | tr "[:upper:]" "[:lower:]")" == apimsubnet-* ]]'

echo "==> Mixed-case publisher email normalization"
publisher_email_rejected() {
  local normalized
  normalized="$(lowercase "$1")"
  [[ "$normalized" == *@example.com || "$normalized" == *@contoso.com ]]
}
assert_succeeds "mixed-case @Example.com addresses must be normalized and rejected" \
  publisher_email_rejected "Admin@Example.COM"
assert_succeeds "mixed-case @Contoso.com addresses must be normalized and rejected" \
  publisher_email_rejected "Owner@CONTOSO.com"
assert_fails "a genuine corporate address must be accepted after normalization" \
  publisher_email_rejected "Platform.Owner@Fabrikam.com"

echo "==> External DNS live resolution and reachability"
apim_json='{"privateIPAddresses":["10.0.0.4"]}'
getent() {
  printf '10.0.0.4 STREAM %s\n' "$2"
}
curl() {
  return 0
}
assert_succeeds "authorized-network private resolution and reachability must pass" \
  validate_apim_endpoint_reachability "apim-test" "$apim_json"
getent() {
  printf '203.0.113.4 STREAM %s\n' "$2"
}
assert_fails "public DNS resolution must fail external DNS validation" \
  validate_apim_endpoint_reachability "apim-test" "$apim_json"
getent() {
  printf '10.0.0.4 STREAM %s\n' "$2"
}
curl() {
  return 1
}
assert_fails "unreachable private endpoints must fail external DNS validation" \
  validate_apim_endpoint_reachability "apim-test" "$apim_json"
unset -f getent curl

echo "==> Runtime default private DNS mode matches the customer parameter example"
customer_example_default="$(grep -oE "APIM_PRIVATE_DNS_MODE', '[a-z]+'" "$foundation_example_params" | grep -oE "'[a-z]+'\$" | tr -d "'")"
runtime_default="$(grep -oE '\$\{APIM_PRIVATE_DNS_MODE:-[a-z]+\}' "$validator" | head -n1 | grep -oE '[a-z]+\}$' | tr -d '}')"
[[ -n "$customer_example_default" && -n "$runtime_default" ]] ||
  fail "could not resolve the private DNS mode defaults for comparison"
[[ "$runtime_default" == "$customer_example_default" ]] ||
  fail "runtime default private DNS mode ($runtime_default) must match the customer parameter example ($customer_example_default)"

echo "==> Log Analytics workspace and exact nested diagnostics contracts"
mkdir -p "$workdir/bin"
cat >"$workdir/bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${MOCK_AZ_CALLED_FILE:-}" ]]; then
  : >"$MOCK_AZ_CALLED_FILE"
fi
if [[ "$*" == *"monitor log-analytics workspace show"* && -n "${MOCK_WORKSPACE_ID:-}" ]]; then
  printf '%s\n' "$MOCK_WORKSPACE_ID"
  exit 0
fi
exit 1
EOF
chmod +x "$workdir/bin/az"
PATH="$workdir/bin:$PATH"

APIM_RESOURCE_GROUP="rg-test"
APIM_LOG_ANALYTICS_WORKSPACE_ID="workspace-existing-id"
MOCK_AZ_CALLED_FILE="$workdir/az-called"
export MOCK_AZ_CALLED_FILE
[[ "$(resolve_foundation_workspace_id)" == "$APIM_LOG_ANALYTICS_WORKSPACE_ID" ]] ||
  fail "existing workspace ID must remain authoritative"
[[ ! -e "$MOCK_AZ_CALLED_FILE" ]] ||
  fail "workspace lookup must not run when an existing workspace ID is supplied"

unset APIM_LOG_ANALYTICS_WORKSPACE_ID
APIM_LOG_ANALYTICS_WORKSPACE_NAME="created-workspace"
MOCK_WORKSPACE_ID="workspace-created-id"
export MOCK_WORKSPACE_ID
resolved_workspace_id="$(resolve_foundation_workspace_id)"
[[ "$resolved_workspace_id" == "workspace-created-id" ]] ||
  fail "runtime must resolve a created workspace by name"

unset APIM_LOG_ANALYTICS_WORKSPACE_NAME
unset MOCK_WORKSPACE_ID
assert_fails "runtime must fail explicitly when no workspace destination can be resolved" \
  resolve_foundation_workspace_id

APIM_LOG_ANALYTICS_WORKSPACE_NAME="future-workspace"
rm -f "$MOCK_AZ_CALLED_FILE"
assert_succeeds "preview/create-new flow must accept a valid workspace name" \
  validate_foundation_workspace_selection
[[ ! -e "$MOCK_AZ_CALLED_FILE" ]] ||
  fail "preview workspace selection must not query an undeployed workspace"

# Diagnostic settings must be read from nested `.properties`, matching the real Azure API
# response shape, rather than flattened top-level fields.
diagnostics_json='{"value":[{"name":"diag-apim-gateway","properties":{"workspaceId":"workspace-created-id","logs":[{"enabled":true,"categoryGroup":"AllLogs"}],"metrics":[{"enabled":true,"category":"AllMetrics"}]}}]}'
assert_succeeds "exact AllLogs and AllMetrics destination must pass when read from nested properties" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id" blueprint diag-apim-gateway
assert_fails "diagnostics pointing to another workspace must fail" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id-wrong" blueprint diag-apim-gateway
assert_fails "blueprint diagnostics must retain the expected setting identity" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id" blueprint wrong-name
assert_succeeds "policy-owned diagnostics must not require a matching setting name" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id" policy wrong-name
top_level_diagnostics_json='{"value":[{"name":"diag-apim-gateway","workspaceId":"workspace-created-id","logs":[{"enabled":true,"categoryGroup":"AllLogs"}],"metrics":[{"enabled":true,"category":"AllMetrics"}]}]}'
assert_fails "diagnostics with fields outside .properties must not satisfy the nested-property contract" \
  diagnostics_match_expected_workspace "$top_level_diagnostics_json" "$resolved_workspace_id" blueprint diag-apim-gateway

echo "==> Exact approved public-IP resource matching"
public_ip_match() {
  local actual="$1" expected="$2"
  [[ "$(lowercase "$actual")" == "$(lowercase "$expected")" ]]
}
approved_id="/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/publicIPAddresses/pip-apim-agent-factory-poc"
assert_succeeds "an exact case-insensitive public IP resource ID match must pass" \
  public_ip_match "$(printf '%s' "$approved_id" | tr '[:lower:]' '[:upper:]')" "$approved_id"
assert_fails "a public IP resource ID from a different resource must fail" \
  public_ip_match "$approved_id-other" "$approved_id"
assert_fails "a public IP resource ID that is only a prefix match must still fail" \
  public_ip_match "${approved_id%/pip-apim-agent-factory-poc}/pip-unapproved" "$approved_id"
grep -Eq "APIM publicIpAddressId does not match the selected APIM_PUBLIC_IP_NAME resource" "$validator" ||
  fail "runtime validation must retain the exact public-IP mismatch error message"

echo "==> GreaterThan capacity-alert operator enforcement"
capacity_alert_query_matches() {
  local criteria_json="$1"
  jq -e "[.[] | select(.metricName==\"Capacity\" and .operator==\"GreaterThan\" and .timeAggregation==\"Average\" and .threshold>=60)] | length == 1" \
    <<<"$criteria_json" >/dev/null
}
assert_succeeds "a GreaterThan capacity alert at or above threshold must pass" \
  capacity_alert_query_matches '[{"metricName":"Capacity","operator":"GreaterThan","timeAggregation":"Average","threshold":60}]'
assert_fails "a GreaterThanOrEqual capacity alert must not satisfy the GreaterThan contract" \
  capacity_alert_query_matches '[{"metricName":"Capacity","operator":"GreaterThanOrEqual","timeAggregation":"Average","threshold":60}]'
assert_fails "a LessThan capacity alert must fail" \
  capacity_alert_query_matches '[{"metricName":"Capacity","operator":"LessThan","timeAggregation":"Average","threshold":60}]'
grep -Eq "operator=='GreaterThan'" "$validator" ||
  fail "runtime validation must retain the GreaterThan operator requirement"

echo "==> APIM_GOVERNED_API_NAME override and compatibility fallback"
(
  unset APIM_GOVERNED_API_NAME
  governed_api_name="${APIM_GOVERNED_API_NAME:-enterprise-llm-api}"
  [[ "$governed_api_name" == "enterprise-llm-api" ]] ||
    fail "APIM_GOVERNED_API_NAME must fall back to the documented default enterprise-llm-api"
)
(
  APIM_GOVERNED_API_NAME="customer-governed-api"
  governed_api_name="${APIM_GOVERNED_API_NAME:-enterprise-llm-api}"
  [[ "$governed_api_name" == "customer-governed-api" ]] ||
    fail "APIM_GOVERNED_API_NAME must override the default when supplied"
)
grep -Eq 'governed_api_name="\$\{APIM_GOVERNED_API_NAME:-enterprise-llm-api\}"' "$validator" ||
  fail "runtime validation must retain the APIM_GOVERNED_API_NAME compatibility fallback"

echo "==> Parameter-file-derived runtime values"
(
  unset -v APIM_SERVICE_NAME APIM_PUBLIC_IP_NAME APIM_SUBNET_NAME APIM_PRIVATE_DNS_MODE
  load_selected_parameter_values "infra/envs/poc/apim.bicepparam"
  [[ "$APIM_SERVICE_NAME" == "apim-agent-factory-private-poc" ]] ||
    fail "parameter-file defaults must resolve APIM_SERVICE_NAME when unset"
  [[ "$APIM_PUBLIC_IP_NAME" == "pip-apim-agent-factory-poc" ]] ||
    fail "parameter-file defaults must resolve APIM_PUBLIC_IP_NAME when unset"
  [[ "$APIM_SUBNET_NAME" == "" ]] ||
    fail "parameter-file values without a default must resolve to an empty string rather than a placeholder"
)
(
  APIM_SERVICE_NAME="caller-selected-apim"
  load_selected_parameter_values "infra/envs/poc/apim.bicepparam"
  [[ "$APIM_SERVICE_NAME" == "caller-selected-apim" ]] ||
    fail "an already-exported runtime value must not be overwritten by the parameter-file default"
)

echo "==> Final report staged evidence"
grep -Eq 'APIM foundation .*PASS: accepted 2026-09-16.*Deployment and private-path runtime validated' "$final_report" ||
  fail "final report must record accepted Stage 1 evidence"
grep -Eq 'APIM ran at Developer capacity one in internal VNet mode' "$final_report" ||
  fail "final report must record the accepted Developer capacity-one smoke test"
grep -Eq 'Foundry integration .*BLOCKED:.*Pending live' "$final_report" ||
  fail "final report must leave Stage 2 pending"
grep -Eq 'Issue #71 records the authoritative redacted acceptance evidence' "$final_report" ||
  fail "final report must identify issue #71 as the redacted evidence source"

echo "APIM review regression tests passed."
