#!/usr/bin/env bash
set -euo pipefail

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required AKS deployment input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input AKS_CLUSTER_RESOURCE_ID "${AKS_CLUSTER_RESOURCE_ID:-}"
check_required_input AKS_NAMESPACE "${AKS_NAMESPACE:-}"
check_required_input AKS_INGRESS_PATTERN "${AKS_INGRESS_PATTERN:-}"
check_required_input AKS_WORKLOAD_IDENTITY_ISSUER "${AKS_WORKLOAD_IDENTITY_ISSUER:-}"
check_required_input AKS_CONTAINER_REGISTRY "${AKS_CONTAINER_REGISTRY:-}"

if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

if [[ ! "$AKS_CLUSTER_RESOURCE_ID" =~ ^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerService/managedClusters/[^/]+$ ]]; then
  printf 'BLOCKED: AKS_CLUSTER_RESOURCE_ID must be a full AKS cluster resource ID.\n' >&2
  exit 2
fi

if [[ ! "$AKS_WORKLOAD_IDENTITY_ISSUER" =~ ^https://[^/]+(/.*)?$ ]]; then
  printf 'BLOCKED: AKS_WORKLOAD_IDENTITY_ISSUER must be an HTTPS URL.\n' >&2
  exit 2
fi

printf 'PENDING: required AKS deployment inputs are present; approval and live readiness are not verified.\n'
