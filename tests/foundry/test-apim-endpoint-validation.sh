#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR_LIBRARY_ONLY=true source "$REPO_ROOT/specs/02-apim-ai-gateway/validation/validate.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

printf '%s\n' '{"resources":{"apim":{"type":"Microsoft.ApiManagement/service","existing":true}}}' >"$workdir/existing.json"
integration_resources_owned "$workdir/existing.json"
for resource_type in Microsoft.ApiManagement/service Microsoft.Network/privateDnsZones Microsoft.Insights/components Microsoft.OperationalInsights/workspaces Microsoft.Insights/metricAlerts; do
  jq -cn --arg type "$resource_type" '{resources:[{type:"Microsoft.Resources/deployments",properties:{template:{resources:[{type:$type}]}}}]}' >"$workdir/write.json"
  if integration_resources_owned "$workdir/write.json"; then
    echo "FAIL: Stage 2 ownership check accepted a foundation resource write" >&2
    exit 1
  fi
done

expect() {
  local expected="$1" actual=0
  shift
  "$@" >"$workdir/result" 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    cat "$workdir/result" >&2
    echo "FAIL: expected $expected, got $actual: $1" >&2
    exit 1
  fi
}

APIM_PRIVATE_DNS_MODE=external
APIM_ENDPOINT_MODE=custom
APIM_ENDPOINT_ACCESS_PATH=direct-private
APIM_CUSTOM_ENDPOINT_HOSTNAMES='{"gateway":"api.example.com","developerPortal":"developer.example.com","management":"management.example.com"}'
service_id='/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.ApiManagement/service/example'
apim_json="$(jq -cn --arg id "$service_id" '{
  id:$id, sku:{name:"Developer",capacity:1},virtualNetworkType:"Internal",privateIPAddresses:["10.0.0.4"],
  hostnameConfigurations:[
    {type:"Proxy",hostName:"API.Example.com"},
    {type:"DeveloperPortal",hostName:"developer.example.com"},
    {type:"Management",hostName:"management.example.com"}]
}')"
selected="$(select_apim_endpoints example)"
evidence="$(jq -cn --arg id "$service_id" --argjson hostnames "$APIM_CUSTOM_ENDPOINT_HOSTNAMES" '{
  validationType:"apim-endpoint-access",status:"pass",owner:"network-owner",
  scope:"apim-foundation",approvalReference:"approval-generic-001",
  evidenceSummary:"Selected endpoint checks retained.",timestampUtc:"2026-10-11T00:00:00Z",
  apimServiceId:$id,endpointMode:"custom",endpointAccessPath:"direct-private",
  selectedHostnames:$hostnames,validationReference:"validation-record-001"
}')"
APIM_ENDPOINT_VALIDATION_EVIDENCE="$evidence"
handoff="$(jq -cn --arg id "$service_id" --argjson selected "$selected" --argjson evidence "$evidence" '{
  apimServiceId:$id,endpointMode:"custom",endpointAccessPath:"direct-private",
  selectedHostnames:$evidence.selectedHostnames,endpoints:$selected,
  selectedGatewayHostname:$evidence.selectedHostnames.gateway,
  selectedGatewayUrl:("https://"+$evidence.selectedHostnames.gateway),
  excludedClientChecks:["legacyPortal","scm"],endpointValidationEvidence:$evidence
}')"

check_handoff_evidence() {
  local APIM_STAGE1_ENDPOINT_ACCESS
  APIM_STAGE1_ENDPOINT_ACCESS="$(jq --argjson evidence "$1" '.endpointValidationEvidence=$evidence' <<<"$handoff")"
  validate_endpoint_handoff "$apim_json" "$selected"
}

getent() {
  [[ "$*" != *azure-api.net* ]] || {
    echo "FAIL: custom mode probed a built-in hostname" >&2
    return 1
  }
  printf '%s\n' "$2" >>"$workdir/dns"
  printf '%s STREAM %s\n' "${mock_ip:-10.0.0.4}" "$2"
  if [[ -n "${mock_additional_ip:-}" ]]; then
    printf '%s STREAM %s\n' "$mock_additional_ip" "$2"
  fi
}
curl() {
  [[ "$*" != *azure-api.net* && "$*" != *--insecure* && "$*" != *"-k "* ]] || return 1
  printf '%s\n' "$*" >>"$workdir/tls"
  return "${mock_tls_result:-0}"
}

expect 0 validate_apim_endpoint_reachability example "$apim_json"
[[ "$(wc -l <"$workdir/dns")" -eq 3 && "$(wc -l <"$workdir/tls")" -eq 3 ]] || {
  echo "FAIL: custom mode must measure all three endpoints" >&2
  exit 1
}
for role in Proxy DeveloperPortal Management; do
  expect 1 validate_apim_endpoint_reachability example "$(jq --arg role "$role" '.hostnameConfigurations |= map(select(.type != $role))' <<<"$apim_json")"
done
expect 1 validate_apim_endpoint_reachability example "$(jq '.hostnameConfigurations[2].type="Proxy"' <<<"$apim_json")"
expect 1 validate_apim_endpoint_reachability example "$(jq '.virtualNetworkType="External"' <<<"$apim_json")"
expect 1 validate_apim_endpoint_reachability example "$(jq '.sku.name="StandardV2"' <<<"$apim_json")"
mock_tls_result=60
expect 1 validate_apim_endpoint_reachability example "$apim_json"
unset mock_tls_result
mock_additional_ip=203.0.113.4
expect 1 validate_apim_endpoint_reachability example "$apim_json"
mock_additional_ip=10.0.0.5
expect 0 validate_apim_endpoint_reachability example "$(jq '.privateIPAddresses += ["10.0.0.5"]' <<<"$apim_json")"
unset mock_additional_ip
mock_ip=203.0.113.4
expect 1 validate_apim_endpoint_reachability example "$apim_json"
APIM_ENDPOINT_ACCESS_PATH=corporate-routed
corporate_evidence="$(jq '.endpointAccessPath="corporate-routed" | .routingApprovalReference="route-approval-001"' <<<"$evidence")"
APIM_ENDPOINT_VALIDATION_EVIDENCE="$corporate_evidence"
expect 0 validate_apim_endpoint_reachability example "$apim_json"
APIM_ENDPOINT_VALIDATION_EVIDENCE='{}'
expect 3 validate_apim_endpoint_reachability example "$apim_json"
expect 1 validate_endpoint_evidence "$evidence" "$service_id" "$selected"
expect 1 validate_endpoint_evidence "$(jq '.owner="dns-owner"' <<<"$corporate_evidence")" "$service_id" "$selected"
for bad in 'null' '""' '" "' '1' 'true' '{}' '[]'; do
  expect 1 validate_endpoint_evidence "$(jq --argjson bad "$bad" '.routingApprovalReference=$bad' <<<"$corporate_evidence")" "$service_id" "$selected"
done
expect 1 validate_endpoint_evidence "$(jq 'del(.routingApprovalReference)' <<<"$corporate_evidence")" "$service_id" "$selected"

APIM_ENDPOINT_ACCESS_PATH=direct-private
APIM_ENDPOINT_VALIDATION_EVIDENCE="$evidence"
unset mock_ip
expect 0 validate_endpoint_evidence "$evidence" "$service_id" "$selected"
expect 0 validate_endpoint_evidence "$(jq '.timestampUtc="2026-10-11T00:00:00.123Z"' <<<"$evidence")" "$service_id" "$selected"
for field in validationType status owner scope approvalReference evidenceSummary timestampUtc apimServiceId endpointMode endpointAccessPath selectedHostnames validationReference; do
  expect 1 validate_endpoint_evidence "$(jq --arg field "$field" 'del(.[$field])' <<<"$evidence")" "$service_id" "$selected"
  expect 1 check_handoff_evidence "$(jq --arg field "$field" 'del(.[$field])' <<<"$evidence")"
  for bad in 'null' '""' '" "' '1' 'true' '{}' '[]'; do
    expect 1 validate_endpoint_evidence "$(jq --arg field "$field" --argjson bad "$bad" '.[$field]=$bad' <<<"$evidence")" "$service_id" "$selected"
    expect 1 check_handoff_evidence "$(jq --arg field "$field" --argjson bad "$bad" '.[$field]=$bad' <<<"$evidence")"
  done
done
for role in gateway developerPortal management; do
  expect 1 validate_endpoint_evidence "$(jq --arg role "$role" 'del(.selectedHostnames[$role])' <<<"$evidence")" "$service_id" "$selected"
  for bad in 'null' '""' '1' 'true' '{}' '[]'; do
    expect 1 validate_endpoint_evidence "$(jq --arg role "$role" --argjson bad "$bad" '.selectedHostnames[$role]=$bad' <<<"$evidence")" "$service_id" "$selected"
  done
done
for timestamp in '2026-02-30T00:00:00Z' '2026-10-11T00:00:00+00:00' '2026-10-11' 'not-a-timestamp' '2026-10-11T25:00:00Z'; do
  expect 1 validate_endpoint_evidence "$(jq --arg timestamp "$timestamp" '.timestampUtc=$timestamp' <<<"$evidence")" "$service_id" "$selected"
  expect 1 check_handoff_evidence "$(jq --arg timestamp "$timestamp" '.timestampUtc=$timestamp' <<<"$evidence")"
done
for alias in timestamp validationTimestamp; do
  expect 1 validate_endpoint_evidence "$(jq --arg alias "$alias" '.[$alias]=.timestampUtc | del(.timestampUtc)' <<<"$evidence")" "$service_id" "$selected"
  expect 1 check_handoff_evidence "$(jq --arg alias "$alias" '.[$alias]=.timestampUtc | del(.timestampUtc)' <<<"$evidence")"
done
expect 1 validate_endpoint_evidence "$(jq '.validationType="dns"' <<<"$evidence")" "$service_id" "$selected"
expect 1 validate_endpoint_evidence "$(jq '.status="invalid"' <<<"$evidence")" "$service_id" "$selected"
expect 1 validate_endpoint_evidence "$(jq '.status="fail"' <<<"$evidence")" "$service_id" "$selected"
expect 3 validate_endpoint_evidence "$(jq '.status="blocked"' <<<"$evidence")" "$service_id" "$selected"
expect 1 validate_endpoint_evidence "$evidence" "$service_id-other" "$selected"
expect 1 validate_endpoint_evidence "$(jq '.selectedHostnames.gateway="other.example.com"' <<<"$evidence")" "$service_id" "$selected"

for host in 'https://api.example.com' 'api.example.com:443' 'api.example.com/path' '*.example.com' 'a..example.com' '127.0.0.1' 'example.azure-api.net'; do
  APIM_CUSTOM_ENDPOINT_HOSTNAMES="$(jq --arg host "$host" '.gateway=$host' <<<"$(jq -c '.selectedHostnames' <<<"$evidence")")"
  expect 1 select_apim_endpoints example
done
APIM_CUSTOM_ENDPOINT_HOSTNAMES="$(jq -c '.selectedHostnames' <<<"$evidence")"
APIM_STAGE1_ENDPOINT_ACCESS="$handoff"
expect 0 validate_endpoint_handoff "$apim_json" "$selected"
for status in fail blocked invalid; do
  expect 1 check_handoff_evidence "$(jq --arg status "$status" '.status=$status' <<<"$evidence")"
done
expect 1 check_handoff_evidence "$(jq '.validationType="dns"' <<<"$evidence")"
for field in apimServiceId endpointMode endpointAccessPath selectedHostnames endpoints selectedGatewayHostname selectedGatewayUrl excludedClientChecks; do
  APIM_STAGE1_ENDPOINT_ACCESS="$(jq --arg field "$field" 'del(.[$field])' <<<"$handoff")"
  expect 1 validate_endpoint_handoff "$apim_json" "$selected"
done
APIM_STAGE1_ENDPOINT_ACCESS="$handoff"
expect 1 validate_endpoint_handoff "$(jq --arg id "$service_id-other" '.id=$id' <<<"$apim_json")" "$selected"
expect 1 validate_endpoint_handoff "$(jq '.hostnameConfigurations[0].hostName="other.example.com"' <<<"$apim_json")" "$selected"

expect 0 selected_integration_request_url api.example.com llm/v1
expect 0 selected_integration_request_url api.example.com llm/v1 https://api.example.com/llm/v1/chat/completions
expect 0 selected_integration_request_url api.example.com llm/v1 https://api.example.com:443/llm/v1/chat/completions
expect 0 selected_integration_request_url api.example.com llm/v1 HTTPS://API.EXAMPLE.COM:443/llm/v1/chat/completions
run_integration_preflight() (
  fixture_apim_json="$apim_json"
  azure_session_available() { return 0; }
  load_selected_parameter_values() { :; }
  az() {
    if [[ "$*" == "apim show "* ]]; then
      jq '.identity={principalId:"fixture-principal"}' <<<"$fixture_apim_json"
    else
      echo "FAIL: invalid request URL reached downstream validation" >>"$workdir/downstream"
      return 1
    fi
  }
  curl() {
    echo "FAIL: invalid request URL sent a request" >>"$workdir/downstream"
    return 1
  }
  OFFLINE_ONLY=false RUN_WHAT_IF=false VALIDATION_PHASE=runtime
  APIM_RESOURCE_GROUP=example APIM_SERVICE_NAME=example
  APIM_STAGE1_SERVICE_ID="$service_id"
  APIM_STAGE1_FOUNDATION_READINESS='{"network":"validated","apim":"deployed","identity":"deployed","dns":"deployed","observability":"deployed","status":"deployed"}'
  FOUNDRY_RESOURCE_GROUP=example FOUNDRY_ACCOUNT_NAME=example FOUNDRY_ACCOUNT_ID=example
  FOUNDRY_APPROVED_REGIONS='["eastus"]'
  FOUNDRY_APPROVED_MODELS='[{"publicName":"fixture","deploymentName":"fixture","enabled":true}]'
  GENAI_APPROVAL_REFERENCE=approval-001 FOUNDRY_ENABLEMENT_REFERENCE=enablement-001 FOUNDRY_CUSTOMER_POLICY_SOURCE=policy-001
  APIM_INTEGRATION_REQUEST_URL="$1"
  APIM_VALIDATE_INTEGRATION_REQUESTS=true APIM_INTEGRATION_SUBSCRIPTION_KEY=fixture-not-a-secret
  validate_integration_live
)
for url in \
  http://api.example.com/llm/v1/chat/completions \
  https://other.example.com/llm/v1/chat/completions \
  https://user@api.example.com/llm/v1/chat/completions \
  https://api.example.com/wrong/chat/completions \
  https://api.example.com:8443/llm/v1/chat/completions \
  https://api.example.com:80/llm/v1/chat/completions \
  'https://api.example.com/llm/v1/chat/completions?key=fixture' \
  'https://api.example.com/llm/v1/chat/completions#fragment'; do
  expect 1 selected_integration_request_url api.example.com llm/v1 "$url"
  expect 1 run_integration_preflight "$url"
  [[ ! -e "$workdir/downstream" ]] || {
    cat "$workdir/downstream" >&2
    exit 1
  }
done
APIM_PRIVATE_DNS_MODE=blueprint
expect 1 select_apim_endpoints example
APIM_ENDPOINT_MODE=built-in
APIM_ENDPOINT_ACCESS_PATH=corporate-routed
expect 1 select_apim_endpoints example
APIM_ENDPOINT_ACCESS_PATH=direct-private
expect 0 select_apim_endpoints example
[[ "$(select_apim_endpoints example | jq 'length')" -eq 5 ]] || exit 1
APIM_STAGE1_ENDPOINT_ACCESS='{}'
expect 0 validate_endpoint_handoff "$apim_json" "$(select_apim_endpoints example)"
unset -f getent curl
echo "PASS: mocked custom binding, DNS/TLS, evidence schema/outcomes, and no built-in probes"
