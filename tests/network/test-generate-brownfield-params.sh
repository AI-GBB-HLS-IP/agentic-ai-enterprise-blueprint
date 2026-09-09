#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
GENERATOR="${REPO_ROOT}/scripts/network/generate-brownfield-params.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

outdir="$workdir/out"
mkdir -p "$outdir"

fail() {
  echo "FAIL: $1" >&2
  [[ -f "$workdir/run.out" ]] && cat "$workdir/run.out" >&2
  exit 1
}

run_generator() {
  "$GENERATOR" "$@" >"$workdir/run.out" 2>&1
}

assert_contains() {
  grep -qF "$2" "$1" || fail "$3"
}

# Placeholder-only fixture: address space inside the blueprint's own 10.0.0.0/16 plan and the
# all-zero subscription GUID, so the confidentiality gate stays green on this tracked file.
cat >"$workdir/discovery.json" <<'JSON'
{
  "schemaVersion": "1.0",
  "vnet": {
    "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-placeholder/providers/Microsoft.Network/virtualNetworks/vnet-placeholder",
    "name": "vnet-placeholder",
    "resourceGroup": "rg-placeholder",
    "location": "placeholderregion",
    "addressPrefixes": ["10.0.0.0/20"],
    "dnsServers": [],
    "ddosProtectionEnabled": false
  },
  "subnets": [
    {
      "name": "existing-workload",
      "addressPrefix": "10.0.0.0/24",
      "addressPrefixes": [],
      "networkSecurityGroupId": null,
      "routeTableId": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-placeholder/providers/Microsoft.Network/routeTables/rt-placeholder",
      "natGatewayId": null,
      "delegations": [],
      "serviceEndpoints": ["Microsoft.Storage"],
      "privateEndpointNetworkPolicies": "Enabled"
    }
  ],
  "peerings": [],
  "privateDnsZones": []
}
JSON

# --- happy path: auto-selected block ----------------------------------------------------------
run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" \
  --dns-resource-group "rg-dns-placeholder" \
  || fail "generator should succeed on a clean discovery document"

network_param="$outdir/brownfield-network.bicepparam"
dns_param="$outdir/brownfield-dns.bicepparam"

[[ -f "$network_param" ]] || fail "network parameter file was not written"
[[ -f "$dns_param" ]] || fail "dns parameter file was not written"

expected_using_prefix="$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" \
  "${REPO_ROOT}/infra/envs/poc" "$outdir")"
assert_contains "$network_param" "using '${expected_using_prefix}/brownfield-network.bicep'" \
  "missing using statement pointing at the templates directory relative to --out-dir"
assert_contains "$network_param" "param existingVnetName = 'vnet-placeholder'" "wrong vnet name"
assert_contains "$network_param" "param existingVnetResourceGroupName = 'rg-placeholder'" "wrong rg"
assert_contains "$network_param" "param location = 'placeholderregion'" "wrong location"
assert_contains "$network_param" "param foundrySubnetPrefix = '10.0.1.0/26'" "wrong foundry CIDR"
assert_contains "$network_param" "param apimSubnetPrefix = '10.0.1.64/28'" "wrong apim CIDR"
assert_contains "$network_param" "param privateEndpointsSubnetPrefix = '10.0.1.80/28'" "wrong pe CIDR"
assert_contains "$network_param" "param computeSubnetPrefix = '10.0.1.96/28'" "wrong compute CIDR"
assert_contains "$network_param" "param cicdAgentsSubnetPrefix = '10.0.1.112/28'" "wrong cicd CIDR"
assert_contains "$network_param" "param reuseExistingNsgs = false" "default NSG mode should be 3"
assert_contains "$network_param" "param privateEndpointsNetworkPolicies = 'Disabled'" "wrong PE policy"
assert_contains "$dns_param" "param dnsResourceGroupName = 'rg-dns-placeholder'" "wrong dns rg"
assert_contains "$dns_param" "param vnetName = 'vnet-placeholder'" "wrong dns vnet name"

# --- overwrite protection ---------------------------------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir"; then
  fail "generator should refuse to overwrite existing parameter files without --force"
fi

run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  || fail "--force should allow overwriting"

# --- explicit block ---------------------------------------------------------------------------
run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block "10.0.8.0/25" || fail "explicit in-range block should be accepted"
assert_contains "$network_param" "param foundrySubnetPrefix = '10.0.8.0/26'" "explicit block ignored"

# --- explicit block that overlaps an existing subnet -------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block "10.0.0.0/25"; then
  fail "overlapping block should be rejected"
fi
assert_contains "$workdir/run.out" "overlaps existing subnet" "missing overlap diagnostic"

# --- explicit block outside the VNet address space ---------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block "10.0.32.0/25"; then
  fail "block outside the VNet address space should be rejected"
fi
assert_contains "$workdir/run.out" "not contained in any VNet address prefix" "missing containment diagnostic"

# --- block too small ---------------------------------------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block "10.0.8.0/27"; then
  fail "undersized block should be rejected"
fi

# --- /26 minimum-viable block is accepted (foundry /27 + four /29s) ----------------------------
run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block-size 26 || fail "minimum-viable /26 block-size should be accepted"
assert_contains "$network_param" "param foundrySubnetPrefix = '10.0.1.0/27'" "wrong /26-split foundry CIDR"
assert_contains "$network_param" "param apimSubnetPrefix = '10.0.1.32/29'" "wrong /26-split apim CIDR"

# --- block-size below the /26 floor is rejected -------------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --block-size 27; then
  fail "--block-size below the /26 floor should be rejected"
fi
assert_contains "$workdir/run.out" "must be between 8 and 26" "missing block-size floor diagnostic"

# --- subnet name collision is fail-closed -------------------------------------------------------
python3 - "$workdir/discovery.json" "$workdir/collision.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    document = json.load(handle)

collision = dict(document["subnets"][0])
collision["name"] = "hybridsubnet-apim"
document["subnets"].append(collision)

with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY

if run_generator --discovery "$workdir/collision.json" --out-dir "$outdir" --force; then
  fail "existing subnet name collision should be rejected"
fi
assert_contains "$workdir/run.out" "COLLISION: subnet name 'hybridsubnet-apim' already exists" \
  "missing collision diagnostic"
assert_contains "$workdir/run.out" "route table (UDR)" "collision should name the properties at risk"

run_generator --discovery "$workdir/collision.json" --out-dir "$outdir" --force \
  --allow-name-collision || fail "--allow-name-collision should downgrade the collision"

run_generator --discovery "$workdir/collision.json" --out-dir "$outdir" --force \
  --name-prefix "othersubnet" || fail "--name-prefix should resolve the collision"
assert_contains "$network_param" "param apimSubnetName = 'othersubnet-apim'" "name prefix ignored"

# --- NSG modes -----------------------------------------------------------------------------------
placeholder_nsg="/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-placeholder/providers/Microsoft.Network/networkSecurityGroups/nsg-placeholder"

run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --shared-hybrid-nsg-id "$placeholder_nsg" || fail "shared hybrid NSG mode should be accepted"
assert_contains "$network_param" "param sharedHybridNsgId = '${placeholder_nsg}'" "shared NSG not written"

if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --reuse-existing-nsgs; then
  fail "--reuse-existing-nsgs without both NSG IDs should be rejected"
fi

run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --reuse-existing-nsgs \
  --existing-apim-nsg-id "$placeholder_nsg" \
  --existing-compute-nsg-id "$placeholder_nsg" || fail "mode 2 should be accepted with both IDs"
assert_contains "$network_param" "param reuseExistingNsgs = true" "mode 2 not written"

# --- invalid private endpoint policy --------------------------------------------------------------
if run_generator --discovery "$workdir/discovery.json" --out-dir "$outdir" --force \
  --private-endpoints-network-policies "Sometimes"; then
  fail "invalid privateEndpointsNetworkPolicies value should be rejected"
fi

# --- dry run writes nothing -----------------------------------------------------------------------
emptydir="$workdir/empty"
mkdir -p "$emptydir"
run_generator --discovery "$workdir/discovery.json" --out-dir "$emptydir" --dry-run \
  || fail "--dry-run should succeed"
[[ -z "$(ls -A "$emptydir")" ]] || fail "--dry-run must not write files"

# --- malformed and missing input --------------------------------------------------------------------
echo "not json" >"$workdir/bad.json"
if run_generator --discovery "$workdir/bad.json" --out-dir "$outdir" --force; then
  fail "malformed discovery JSON should be rejected"
fi

if run_generator --discovery "$workdir/does-not-exist.json" --out-dir "$outdir"; then
  fail "missing discovery file should be rejected"
fi

# --- fragmented VNet: the first free aligned block is selected, occupied space skipped ----------
python3 - "$workdir/fragmented.json" <<'PY'
import json
import sys

document = {
    "vnet": {
        "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-placeholder/providers/Microsoft.Network/virtualNetworks/vnet-placeholder",
        "name": "vnet-placeholder",
        "resourceGroup": "rg-placeholder",
        "location": "placeholderregion",
        "addressPrefixes": ["10.0.0.0/22"],
    },
    "subnets": [
        {"name": "existing-a", "addressPrefix": "10.0.0.0/24"},
        {"name": "existing-b", "addressPrefix": "10.0.1.0/25"},
        {"name": "existing-c", "addressPrefix": "10.0.1.192/26"},
        {"name": "existing-d", "addressPrefix": "10.0.2.0/27"},
        {"name": "existing-e", "addressPrefix": "10.0.3.0/24"},
    ],
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY

run_generator --discovery "$workdir/fragmented.json" --out-dir "$outdir" --force \
  || fail "generator should find a free block in a partially allocated VNet"
assert_contains "$network_param" "param foundrySubnetPrefix = '10.0.2.128/26'" \
  "generator should skip the occupied 10.0.2.0/25 and land on 10.0.2.128/25"

# --- no free block of the requested size ---------------------------------------------------------
python3 - "$workdir/tight.json" <<'PY'
import json
import sys

with open(sys.argv[1].replace("tight", "fragmented"), encoding="utf-8") as handle:
    document = json.load(handle)

document["subnets"].append({"name": "existing-f", "addressPrefix": "10.0.2.128/26"})
document["subnets"].append({"name": "existing-g", "addressPrefix": "10.0.2.224/27"})

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY

if run_generator --discovery "$workdir/tight.json" --out-dir "$outdir" --force; then
  fail "a VNet with no free /25 should be rejected"
fi
assert_contains "$workdir/run.out" "no free /25 block found" "missing exhaustion diagnostic"
assert_contains "$workdir/run.out" "Largest free ranges in this VNet" \
  "exhaustion diagnostic should list the remaining free ranges"
assert_contains "$workdir/run.out" "10.0.1.128/26" "exhaustion diagnostic should compute free space"

python3 - "$workdir/full.json" <<'PY'
import json
import sys

document = {
    "vnet": {
        "id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-placeholder/providers/Microsoft.Network/virtualNetworks/vnet-placeholder",
        "name": "vnet-placeholder",
        "resourceGroup": "rg-placeholder",
        "location": "placeholderregion",
        "addressPrefixes": ["10.0.0.0/24"],
    },
    "subnets": [{"name": "existing-full", "addressPrefix": "10.0.0.0/24"}],
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(document, handle)
PY

if run_generator --discovery "$workdir/full.json" --out-dir "$outdir" --force; then
  fail "a fully allocated VNet should be rejected"
fi
assert_contains "$workdir/run.out" "no free /25 block found" "missing exhaustion diagnostic"
assert_contains "$workdir/run.out" "fully allocated" \
  "a fully allocated VNet should say so rather than list free ranges"

echo "Brownfield parameter generator tests passed."
