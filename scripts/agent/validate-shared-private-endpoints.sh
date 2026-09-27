#!/usr/bin/env bash
set -euo pipefail

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required private endpoint input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input STORAGE_ACCOUNT_ID "${STORAGE_ACCOUNT_ID:-}"
check_required_input STORAGE_PRIVATE_ENDPOINT_ID "${STORAGE_PRIVATE_ENDPOINT_ID:-}"
check_required_input KEY_VAULT_ID "${KEY_VAULT_ID:-}"
check_required_input KEY_VAULT_PRIVATE_ENDPOINT_ID "${KEY_VAULT_PRIVATE_ENDPOINT_ID:-}"
check_required_input COSMOS_DB_ACCOUNT_ID "${COSMOS_DB_ACCOUNT_ID:-}"
check_required_input COSMOS_DB_PRIVATE_ENDPOINT_ID "${COSMOS_DB_PRIVATE_ENDPOINT_ID:-}"
check_required_input AI_SEARCH_SERVICE_ID "${AI_SEARCH_SERVICE_ID:-}"
check_required_input AI_SEARCH_PRIVATE_ENDPOINT_ID "${AI_SEARCH_PRIVATE_ENDPOINT_ID:-}"
check_required_input AMPLS_RESOURCE_ID "${AMPLS_RESOURCE_ID:-}"
check_required_input AMPLS_PRIVATE_ENDPOINT_ID "${AMPLS_PRIVATE_ENDPOINT_ID:-}"
if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

if ! command -v az >/dev/null 2>&1; then
  printf 'BLOCKED: Azure CLI is required to validate private endpoint state.\n' >&2
  exit 2
fi

endpoint_ids=(
  "$STORAGE_PRIVATE_ENDPOINT_ID"
  "$KEY_VAULT_PRIVATE_ENDPOINT_ID"
  "$COSMOS_DB_PRIVATE_ENDPOINT_ID"
  "$AI_SEARCH_PRIVATE_ENDPOINT_ID"
  "$AMPLS_PRIVATE_ENDPOINT_ID"
)
for ((left = 0; left < ${#endpoint_ids[@]}; left++)); do
  left_id_lower="$(printf '%s' "${endpoint_ids[$left]}" | tr '[:upper:]' '[:lower:]')"
  for ((right = left + 1; right < ${#endpoint_ids[@]}; right++)); do
    right_id_lower="$(printf '%s' "${endpoint_ids[$right]}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$left_id_lower" == "$right_id_lower" ]]; then
      printf 'BLOCKED: supplied private endpoint IDs must identify distinct service endpoints.\n' >&2
      exit 2
    fi
  done
done

validate_endpoint() {
  local label="$1"
  local endpoint_id="$2"
  local target_id="$3"
  local subresource="$4"
  local endpoint_json
  local nic_ids
  local nic_id
  local nic_json

  if ! endpoint_json="$(az network private-endpoint show --ids "$endpoint_id" --output json)"; then
    printf 'BLOCKED: %s private endpoint could not be read.\n' "$label" >&2
    return 2
  fi
  if ! nic_ids="$(python3 - "$endpoint_json" "$endpoint_id" "$target_id" "$subresource" "$label" <<'PY'
import ipaddress
import json
import sys

try:
    endpoint = json.loads(sys.argv[1])
except json.JSONDecodeError:
    print(f"BLOCKED: {sys.argv[5]} private endpoint response is invalid.", file=sys.stderr)
    sys.exit(2)

endpoint_id, expected_target, expected_group, label = sys.argv[2:]
if endpoint.get("id", "").lower() != endpoint_id.lower():
    print(f"BLOCKED: {label} private endpoint ID does not match the supplied handoff.", file=sys.stderr)
    sys.exit(2)

connections = endpoint.get("privateLinkServiceConnections") or []
connections += endpoint.get("manualPrivateLinkServiceConnections") or []
matches = []
for connection in connections:
    properties = connection.get("properties") or {}
    target = connection.get("privateLinkServiceId") or properties.get("privateLinkServiceId")
    groups = connection.get("groupIds") or properties.get("groupIds") or []
    state = connection.get("privateLinkServiceConnectionState") or properties.get("privateLinkServiceConnectionState") or {}
    if (target or "").lower() == expected_target.lower() and any(
        group.lower() == expected_group.lower() for group in groups
    ):
        if (state.get("status") or "").lower() == "approved":
            matches.append(connection)

if len(matches) != 1:
    print(
        f"BLOCKED: {label} endpoint must have exactly one approved connection to its expected target and subresource.",
        file=sys.stderr,
    )
    sys.exit(2)

network_interfaces = endpoint.get("networkInterfaces") or (endpoint.get("properties") or {}).get("networkInterfaces") or []
nic_ids = [entry.get("id") for entry in network_interfaces if entry.get("id")]
if not nic_ids:
    print(f"BLOCKED: {label} endpoint has no network interface for a private route.", file=sys.stderr)
    sys.exit(2)
print("\n".join(nic_ids))
PY
)"; then
    return 2
  fi

  while IFS= read -r nic_id; do
    if ! nic_json="$(az network nic show --ids "$nic_id" --output json)"; then
      printf 'BLOCKED: %s endpoint network interface could not be read.\n' "$label" >&2
      return 2
    fi
    if ! python3 - "$nic_json" "$label" <<'PY'
import ipaddress
import json
import sys

try:
    nic = json.loads(sys.argv[1])
except json.JSONDecodeError:
    print(f"BLOCKED: {sys.argv[2]} endpoint network interface response is invalid.", file=sys.stderr)
    sys.exit(2)

addresses = []
for configuration in nic.get("ipConfigurations") or (nic.get("properties") or {}).get("ipConfigurations") or []:
    properties = configuration.get("properties") or {}
    address = configuration.get("privateIPAddress") or properties.get("privateIPAddress")
    if address:
        addresses.append(address)
if not addresses or any(not ipaddress.ip_address(address).is_private for address in addresses):
    print(f"BLOCKED: {sys.argv[2]} endpoint does not have an assigned private IP address.", file=sys.stderr)
    sys.exit(2)
PY
    then
      return 2
    fi
  done <<<"$nic_ids"
}

validate_endpoint "Storage" "$STORAGE_PRIVATE_ENDPOINT_ID" "$STORAGE_ACCOUNT_ID" "blob" ||
  exit 2
validate_endpoint "Key Vault" "$KEY_VAULT_PRIVATE_ENDPOINT_ID" "$KEY_VAULT_ID" "vault" ||
  exit 2
validate_endpoint "Cosmos DB" "$COSMOS_DB_PRIVATE_ENDPOINT_ID" "$COSMOS_DB_ACCOUNT_ID" "Sql" ||
  exit 2
validate_endpoint "Azure AI Search" "$AI_SEARCH_PRIVATE_ENDPOINT_ID" "$AI_SEARCH_SERVICE_ID" "searchService" ||
  exit 2
validate_endpoint "AMPLS" "$AMPLS_PRIVATE_ENDPOINT_ID" "$AMPLS_RESOURCE_ID" "azuremonitor" ||
  exit 2

printf 'PASSED: supplied service endpoints target the expected resources/subresources and have approved connections and private IPs. DNS association remains a separate stage.\n'
