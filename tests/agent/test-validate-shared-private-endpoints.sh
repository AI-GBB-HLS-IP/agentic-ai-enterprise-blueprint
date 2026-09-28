#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/agent/validate-shared-private-endpoints.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/bin"
cat >"$workdir/bin/az" <<'MOCK_AZ'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "network" && "$2" == "private-endpoint" && "$3" == "show" ]]; then
  endpoint_id="$5"
  case "$endpoint_id" in
    *pe-storage) label=storage; target="$STORAGE_ACCOUNT_ID"; group=blob ;;
    *pe-keyvault) label=keyvault; target="$KEY_VAULT_ID"; group=vault ;;
    *pe-cosmos) label=cosmos; target="$COSMOS_DB_ACCOUNT_ID"; group=Sql ;;
    *pe-search) label=search; target="$AI_SEARCH_SERVICE_ID"; group=searchService ;;
    *) exit 2 ;;
  esac
  status=Approved
  if [[ "${MOCK_REJECTED_ENDPOINT:-}" == "$label" ]]; then
    status=Rejected
  fi
  python3 - "$endpoint_id" "$target" "$group" "$status" "$label" <<'PY'
import json
import sys

endpoint_id, target, group, status, label = sys.argv[1:]
json.dump({
    "id": endpoint_id,
    "privateLinkServiceConnections": [{
        "properties": {
            "privateLinkServiceId": target,
            "groupIds": [group],
            "privateLinkServiceConnectionState": {"status": status}
        }
    }],
    "networkInterfaces": [{
        "id": f"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/networkInterfaces/nic-{label}"
    }]
}, sys.stdout)
PY
elif [[ "$1" == "network" && "$2" == "nic" && "$3" == "show" ]]; then
  python3 - "$MOCK_NIC_IP" <<'PY'
import json
import sys
json.dump({"ipConfigurations": [{"properties": {"privateIPAddress": sys.argv[1]}}]}, sys.stdout)
PY
fi
MOCK_AZ
chmod +x "$workdir/bin/az"
export PATH="$workdir/bin:$PATH"

export STORAGE_ACCOUNT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/storageexample
export STORAGE_PRIVATE_ENDPOINT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/privateEndpoints/pe-storage
export KEY_VAULT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.KeyVault/vaults/kv-example
export KEY_VAULT_PRIVATE_ENDPOINT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/privateEndpoints/pe-keyvault
export COSMOS_DB_ACCOUNT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-example
export COSMOS_DB_PRIVATE_ENDPOINT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/privateEndpoints/pe-cosmos
export AI_SEARCH_SERVICE_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Search/searchServices/search-example
export AI_SEARCH_PRIVATE_ENDPOINT_ID=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/privateEndpoints/pe-search
export MOCK_NIC_IP=10.0.1.4

output="$(env -u AMPLS_RESOURCE_ID -u AMPLS_PRIVATE_ENDPOINT_ID "$VALIDATE")"
grep -Fq 'PASSED: supplied service endpoints target the expected resources/subresources and have approved connections and private IPs.' <<<"$output" ||
  fail "approved service endpoints must validate without AMPLS inputs"

set +e
output="$(env -u AI_SEARCH_PRIVATE_ENDPOINT_ID "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "missing service endpoint ID must block validation"
grep -Fq 'BLOCKED: required private endpoint input AI_SEARCH_PRIVATE_ENDPOINT_ID is not set.' <<<"$output" ||
  fail "missing service endpoint ID must be named"

set +e
output="$(MOCK_REJECTED_ENDPOINT=storage "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "a rejected endpoint connection must block readiness"
grep -Fq 'BLOCKED: Storage endpoint must have exactly one approved connection to its expected target and subresource.' <<<"$output" ||
  fail "rejected endpoint connection must be named"

set +e
output="$(MOCK_NIC_IP=8.8.8.8 "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "a non-private endpoint IP must block readiness"
grep -Fq 'BLOCKED: Storage endpoint does not have an assigned private IP address.' <<<"$output" ||
  fail "non-private endpoint IP must be named"

set +e
output="$(KEY_VAULT_PRIVATE_ENDPOINT_ID="$STORAGE_PRIVATE_ENDPOINT_ID" "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "duplicate endpoint IDs must block readiness"
grep -Fq 'BLOCKED: supplied private endpoint IDs must identify distinct service endpoints.' <<<"$output" ||
  fail "duplicate endpoint IDs must be named"

printf 'Shared private endpoint validation contract tests passed.\n'
