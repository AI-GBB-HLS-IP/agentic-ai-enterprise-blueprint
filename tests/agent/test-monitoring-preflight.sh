#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/agent/monitoring-preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

set +e
output="$(env -i PATH="$PATH" "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "missing monitoring approvals and routes must fail closed"
grep -Fq 'BLOCKED: required monitoring input MONITORING_OWNER_APPROVAL_REFERENCE is not set.' <<<"$output" ||
  fail "missing monitoring-owner approval must be named"
grep -Fq 'BLOCKED: required monitoring input APIM_TELEMETRY_PRIVATE_ROUTE_EVIDENCE is not set.' <<<"$output" ||
  fail "missing APIM private-route evidence must be named"
grep -Fq 'BLOCKED: APIM telemetry readiness requires monitoring-owner acceptance and an approved private ingestion route;' <<<"$output" ||
  fail "APIM telemetry must remain explicitly blocked without owner acceptance and private route evidence"

monitoring_inputs=(
  MONITORING_WORKSPACE_RESOURCE_ID=/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example
  MONITORING_AMPLS_RESOURCE_ID=/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-example/providers/Microsoft.Insights/privateLinkScopes/ampls-example
  MONITORING_AMPLS_PRIVATE_ENDPOINT_ID=/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-example/providers/Microsoft.Network/privateEndpoints/pe-ampls-example
  MONITORING_PRIVATE_DNS_OWNER_REFERENCE=approval-example
  MONITORING_OWNER_APPROVAL_REFERENCE=approval-example
  MONITORING_WORKSPACE_ASSOCIATION_EVIDENCE=association-example
  AGENT_APPINSIGHTS_ASSOCIATION_EVIDENCE=association-example
  APIM_APPINSIGHTS_ASSOCIATION_EVIDENCE=association-example
  AKS_TELEMETRY_AUTH_MODE=managed-identity
  AKS_TELEMETRY_PRIVATE_ROUTE_EVIDENCE=route-example
  FOUNDRY_TELEMETRY_AUTH_MODE=managed-identity
  FOUNDRY_TELEMETRY_PRIVATE_ROUTE_EVIDENCE=route-example
  APIM_TELEMETRY_AUTH_MODE=instrumentation-key
  APIM_TELEMETRY_PRIVATE_ROUTE_EVIDENCE=route-example
)

output="$(env "${monitoring_inputs[@]}" "$PREFLIGHT")"
grep -Fq 'PENDING: monitoring approvals and sender evidence are supplied; private routes and telemetry arrival are not verified.' <<<"$output" ||
  fail "supplied references must remain pending live validation"

set +e
output="$(env "${monitoring_inputs[@]}" APIM_TELEMETRY_AUTH_MODE=managed-identity "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "an APIM authentication migration must be blocked"
grep -Fq 'BLOCKED: APIM telemetry must retain its existing instrumentation-key logger authentication for this POC.' <<<"$output" ||
  fail "an APIM authentication migration must be named as blocked"

printf 'Monitoring preflight contract tests passed.\n'
