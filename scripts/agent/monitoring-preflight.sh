#!/usr/bin/env bash
set -euo pipefail

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required monitoring input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input MONITORING_WORKSPACE_RESOURCE_ID "${MONITORING_WORKSPACE_RESOURCE_ID:-}"
check_required_input MONITORING_AMPLS_RESOURCE_ID "${MONITORING_AMPLS_RESOURCE_ID:-}"
check_required_input MONITORING_AMPLS_PRIVATE_ENDPOINT_ID "${MONITORING_AMPLS_PRIVATE_ENDPOINT_ID:-}"
check_required_input MONITORING_PRIVATE_DNS_OWNER_REFERENCE "${MONITORING_PRIVATE_DNS_OWNER_REFERENCE:-}"
check_required_input MONITORING_OWNER_APPROVAL_REFERENCE "${MONITORING_OWNER_APPROVAL_REFERENCE:-}"
check_required_input MONITORING_WORKSPACE_ASSOCIATION_EVIDENCE "${MONITORING_WORKSPACE_ASSOCIATION_EVIDENCE:-}"
check_required_input AGENT_APPINSIGHTS_ASSOCIATION_EVIDENCE "${AGENT_APPINSIGHTS_ASSOCIATION_EVIDENCE:-}"
check_required_input APIM_APPINSIGHTS_ASSOCIATION_EVIDENCE "${APIM_APPINSIGHTS_ASSOCIATION_EVIDENCE:-}"
check_required_input AKS_TELEMETRY_AUTH_MODE "${AKS_TELEMETRY_AUTH_MODE:-}"
check_required_input AKS_TELEMETRY_PRIVATE_ROUTE_EVIDENCE "${AKS_TELEMETRY_PRIVATE_ROUTE_EVIDENCE:-}"
check_required_input FOUNDRY_TELEMETRY_AUTH_MODE "${FOUNDRY_TELEMETRY_AUTH_MODE:-}"
check_required_input FOUNDRY_TELEMETRY_PRIVATE_ROUTE_EVIDENCE "${FOUNDRY_TELEMETRY_PRIVATE_ROUTE_EVIDENCE:-}"
check_required_input APIM_TELEMETRY_AUTH_MODE "${APIM_TELEMETRY_AUTH_MODE:-}"
check_required_input APIM_TELEMETRY_PRIVATE_ROUTE_EVIDENCE "${APIM_TELEMETRY_PRIVATE_ROUTE_EVIDENCE:-}"

if [[ "${APIM_TELEMETRY_AUTH_MODE:-}" != "instrumentation-key" ]]; then
  printf 'BLOCKED: APIM telemetry must retain its existing instrumentation-key logger authentication for this POC.\n' >&2
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  printf 'BLOCKED: APIM telemetry readiness requires monitoring-owner acceptance and an approved private ingestion route; no authentication migration or public fallback is allowed.\n' >&2
  exit 2
fi

printf 'PENDING: monitoring approvals and sender evidence are supplied; private routes and telemetry arrival are not verified.\n'
