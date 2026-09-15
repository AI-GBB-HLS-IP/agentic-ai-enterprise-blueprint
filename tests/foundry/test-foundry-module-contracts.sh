#!/usr/bin/env bash
set -euo pipefail

# Contract tests for the Foundry private-endpoint / DNS-zone-group split:
#
#   1. infra/modules/foundry/private-endpoint.bicep creates only bare private endpoints — no
#      privateDnsZoneGroups child resources — and exposes each endpoint's name as an output.
#   2. infra/modules/foundry/private-endpoint-dns.bicep creates the privateDnsZoneGroups child
#      resource for every dependency by referencing each private endpoint as `existing` (by
#      name), and skips the optional ones (storage/cosmos/aiSearch) when their name is empty.
#   3. infra/modules/foundry/main.bicep no longer accepts a privateDnsZoneIds parameter and
#      passes through the private-endpoint-name outputs.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

PRIVATE_ENDPOINT_MODULE="${REPO_ROOT}/infra/modules/foundry/private-endpoint.bicep"
PRIVATE_ENDPOINT_DNS_MODULE="${REPO_ROOT}/infra/modules/foundry/private-endpoint-dns.bicep"
MAIN_MODULE="${REPO_ROOT}/infra/modules/foundry/main.bicep"

command -v az >/dev/null 2>&1 || {
  echo "SKIP: az CLI not available; cannot run bicep build checks." >&2
  exit 0
}
command -v python3 >/dev/null 2>&1 || {
  echo "SKIP: python3 not available; cannot run compiled-template assertions." >&2
  exit 0
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "==> az bicep build: modules/foundry/private-endpoint.bicep"
az bicep build --file "$PRIVATE_ENDPOINT_MODULE" --stdout >"$workdir/pe.json" 2>"$workdir/pe.err" \
  || { cat "$workdir/pe.err" >&2; fail "az bicep build failed for private-endpoint.bicep"; }

echo "==> private-endpoint.bicep declares no privateDnsZoneGroups resources"
python3 - "$workdir/pe.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
zone_groups = [
    r for r in arm["resources"]
    if r.get("type") == "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"
]
if zone_groups:
    names = [r.get("name") for r in zone_groups]
    sys.exit(f"private-endpoint.bicep must not declare privateDnsZoneGroups resources, found: {names}")

for key in (
    "foundryPrivateEndpointName",
    "storagePrivateEndpointName",
    "keyVaultPrivateEndpointName",
    "cosmosDBPrivateEndpointName",
    "aiSearchPrivateEndpointName",
):
    if key not in arm.get("outputs", {}):
        sys.exit(f"private-endpoint.bicep is missing expected output: {key}")
PY

echo "==> private-endpoint.bicep no longer accepts DNS-zone-ID parameters"
for removed_param in cognitiveServicesDnsZoneId openAiDnsZoneId servicesAiDnsZoneId blobDnsZoneId keyVaultDnsZoneId cosmosDBDnsZoneId aiSearchDnsZoneId; do
  if grep -q "param ${removed_param} " "$PRIVATE_ENDPOINT_MODULE"; then
    fail "private-endpoint.bicep still declares removed DNS-zone-ID parameter: ${removed_param}"
  fi
done

echo "==> az bicep build: modules/foundry/private-endpoint-dns.bicep"
az bicep build --file "$PRIVATE_ENDPOINT_DNS_MODULE" --stdout >"$workdir/pedns.json" 2>"$workdir/pedns.err" \
  || { cat "$workdir/pedns.err" >&2; fail "az bicep build failed for private-endpoint-dns.bicep"; }

echo "==> private-endpoint-dns.bicep creates every expected DNS zone group against an existing PE"
python3 - "$workdir/pedns.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
resources = arm["resources"]

# `existing` resources never appear in the compiled ARM "resources" array — only the resources
# actually being created do. So the absence of any Microsoft.Network/privateEndpoints creation
# resource here (only privateDnsZoneGroups) is itself proof every PE is referenced as `existing`.
pe_creations = [r for r in resources if r.get("type") == "Microsoft.Network/privateEndpoints"]
if pe_creations:
    sys.exit(f"private-endpoint-dns.bicep must reference private endpoints as 'existing', not create them: {[r['name'] for r in pe_creations]}")

zone_groups = [
    r for r in resources
    if r.get("type") == "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"
]
if len(zone_groups) != 5:
    sys.exit(f"expected 5 privateDnsZoneGroups resources, found {len(zone_groups)}")

expected_pe_params = {
    "foundryPrivateEndpointName",
    "storagePrivateEndpointName",
    "keyVaultPrivateEndpointName",
    "cosmosDBPrivateEndpointName",
    "aiSearchPrivateEndpointName",
}
expected_group_suffixes = {"foundry-dns", "storage-dns", "keyvault-dns", "cosmosdb-dns", "aisearch-dns"}
found_pe_params = set()
found_group_suffixes = set()
for r in zone_groups:
    # Each zone group's compiled name is a format() expression like:
    #   format('{0}/{1}', parameters('fooPrivateEndpointName'), 'foo-dns')
    # which proves the zone group is parented to the PE by name (i.e. the PE is `existing`).
    name_expr = r["name"]
    matched_param = next((p for p in expected_pe_params if f"parameters('{p}')" in name_expr), None)
    matched_suffix = next((s for s in expected_group_suffixes if f"'{s}'" in name_expr), None)
    if not matched_param or not matched_suffix:
        sys.exit(f"unexpected privateDnsZoneGroups name expression: {name_expr}")
    found_pe_params.add(matched_param)
    found_group_suffixes.add(matched_suffix)

missing_params = expected_pe_params - found_pe_params
missing_suffixes = expected_group_suffixes - found_group_suffixes
if missing_params or missing_suffixes:
    sys.exit(f"private-endpoint-dns.bicep is missing expected DNS zone groups: params={missing_params} suffixes={missing_suffixes}")
PY

echo "==> private-endpoint-dns.bicep skips optional DNS groups when the PE name is empty"
grep -q "createStorageDnsGroup = !empty(storagePrivateEndpointName)" "$PRIVATE_ENDPOINT_DNS_MODULE" \
  || fail "private-endpoint-dns.bicep must gate the storage DNS group on storagePrivateEndpointName"
grep -q "createCosmosDBDnsGroup = !empty(cosmosDBPrivateEndpointName)" "$PRIVATE_ENDPOINT_DNS_MODULE" \
  || fail "private-endpoint-dns.bicep must gate the Cosmos DB DNS group on cosmosDBPrivateEndpointName"
grep -q "createAISearchDnsGroup = !empty(aiSearchPrivateEndpointName)" "$PRIVATE_ENDPOINT_DNS_MODULE" \
  || fail "private-endpoint-dns.bicep must gate the AI Search DNS group on aiSearchPrivateEndpointName"

echo "==> az bicep build: modules/foundry/main.bicep"
az bicep build --file "$MAIN_MODULE" --stdout >"$workdir/main.json" 2>"$workdir/main.err" \
  || { cat "$workdir/main.err" >&2; fail "az bicep build failed for main.bicep"; }

echo "==> main.bicep no longer declares a privateDnsZoneIds parameter"
python3 - "$workdir/main.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
if "privateDnsZoneIds" in arm.get("parameters", {}):
    sys.exit("main.bicep must not declare a privateDnsZoneIds parameter")

for key in (
    "foundryPrivateEndpointName",
    "storagePrivateEndpointName",
    "keyVaultPrivateEndpointName",
    "cosmosDBPrivateEndpointName",
    "aiSearchPrivateEndpointName",
):
    if key not in arm.get("outputs", {}):
        sys.exit(f"main.bicep is missing expected pass-through output: {key}")
PY

echo "Foundry module contract tests passed."
