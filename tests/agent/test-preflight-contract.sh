#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/agent/preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

set +e
output="$(env -i PATH="$PATH" "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "missing inputs must return exit code 2"
for input_name in \
  AKS_CLUSTER_RESOURCE_ID \
  AKS_NAMESPACE \
  AKS_INGRESS_PATTERN \
  AKS_WORKLOAD_IDENTITY_ISSUER \
  AKS_CONTAINER_REGISTRY; do
  grep -Fq "BLOCKED: required AKS deployment input $input_name is not set." <<<"$output" ||
    fail "missing input $input_name was not reported as BLOCKED"
done
if grep -Fq 'PENDING:' <<<"$output"; then
  fail "missing inputs must not produce a PENDING result"
fi

output="$(
  AKS_CLUSTER_RESOURCE_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-phase1/providers/Microsoft.ContainerService/managedClusters/aks-phase1 \
  AKS_NAMESPACE=phase1-agent \
  AKS_INGRESS_PATTERN=private-internal \
  AKS_WORKLOAD_IDENTITY_ISSUER=https://oidc.example.invalid/issuer \
  AKS_CONTAINER_REGISTRY=registry.example.invalid \
  "$PREFLIGHT"
)"
grep -Fq 'PENDING: required AKS deployment inputs are present; approval and live readiness are not verified.' <<<"$output" ||
  fail "populated inputs must remain explicitly pending live verification"

set +e
output="$(
  AKS_CLUSTER_RESOURCE_ID=not-a-resource-id \
  AKS_NAMESPACE=phase1-agent \
  AKS_INGRESS_PATTERN=private-internal \
  AKS_WORKLOAD_IDENTITY_ISSUER=https://oidc.example.invalid/issuer \
  AKS_CONTAINER_REGISTRY=registry.example.invalid \
  "$PREFLIGHT" 2>&1
)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "an invalid cluster resource ID must be blocked"
grep -Fq 'BLOCKED: AKS_CLUSTER_RESOURCE_ID must be a full AKS cluster resource ID.' <<<"$output" ||
  fail "an invalid cluster resource ID must have a named BLOCKED result"

printf 'AKS deployment input contract tests passed.\n'
