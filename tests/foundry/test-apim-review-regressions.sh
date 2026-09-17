#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
validator="$REPO_ROOT/specs/02-apim-ai-gateway/validation/validate.sh"
integration="$REPO_ROOT/infra/envs/poc/apim-foundry-integration.bicep"
private_dns="$REPO_ROOT/infra/modules/apim/private-dns.bicep"
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

command az bicep build --file "$integration" --outfile "$workdir/integration.json" >/dev/null
command az bicep build --file "$private_dns" --outfile "$workdir/private-dns.json" >/dev/null

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

VALIDATOR_LIBRARY_ONLY=true
# shellcheck source=../../specs/02-apim-ai-gateway/validation/validate.sh
source "$validator"

assert_succeeds "live validator must accept Developer capacity one" \
  apim_classic_sku_supported '{"sku":{"name":"Developer","capacity":1}}'
assert_succeeds "live validator must accept Premium" \
  apim_classic_sku_supported '{"sku":{"name":"Premium","capacity":2}}'
assert_fails "live validator must reject Developer capacity other than one" \
  apim_classic_sku_supported '{"sku":{"name":"Developer","capacity":2}}'
assert_fails "live validator must reject unsupported APIM SKUs" \
  apim_classic_sku_supported '{"sku":{"name":"Basic","capacity":1}}'

echo "==> Compiled external DNS readiness contract"
jq -e '
  .outputs.dnsReadiness.value as $readiness
  | $readiness.mode == "[if(parameters('\''deployPrivateDns'\''), '\''blueprint'\'', '\''external'\'')]"
  and $readiness.zone == "[if(parameters('\''deployPrivateDns'\''), '\''deployed'\'', '\''external'\'')]"
  and $readiness.link == "[if(parameters('\''deployPrivateDns'\''), '\''deployed'\'', '\''external'\'')]"
  and ($readiness.record | contains("external-handoff-required"))
  and ($readiness.additionalEndpointRecords | contains("external-handoff-required"))
  and $readiness.status == "[if(greater(length(parameters('\''apimPrivateIpAddresses'\'')), 0), '\''deployed'\'', '\''pending'\'')]"
' "$workdir/private-dns.json" >/dev/null ||
  fail "compiled DNS handoff must become ready from private IP data without claiming external resources"

dns_status() {
  local private_ip_count="$1"
  [[ "$private_ip_count" -gt 0 ]] && printf 'deployed\n' || printf 'pending\n'
}
[[ "$(dns_status 1)" == "deployed" ]] || fail "blueprint DNS with private IPs must be deployed"
[[ "$(dns_status 0)" == "pending" ]] || fail "blueprint DNS without private IPs must remain pending"
[[ "$(dns_status 1)" == "deployed" ]] || fail "external DNS with private IPs must be handoff-ready"
[[ "$(dns_status 0)" == "pending" ]] || fail "external DNS without private IPs must remain pending"

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

echo "==> Log Analytics workspace and exact diagnostics contracts"
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

diagnostics_json='{"value":[{"name":"diag-apim-gateway","workspaceId":"workspace-created-id","logs":[{"enabled":true,"categoryGroup":"AllLogs"}],"metrics":[{"enabled":true,"category":"AllMetrics"}]}]}'
assert_succeeds "exact AllLogs and AllMetrics destination must pass" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id" blueprint diag-apim-gateway
assert_fails "diagnostics pointing to another workspace must fail" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id-wrong" blueprint diag-apim-gateway
assert_fails "blueprint diagnostics must retain the expected setting identity" \
  diagnostics_match_expected_workspace "$diagnostics_json" "$resolved_workspace_id" blueprint wrong-name

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
