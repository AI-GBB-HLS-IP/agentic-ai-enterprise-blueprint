#!/usr/bin/env bash
set -euo pipefail

# Contract tests for the two shared network module boundaries:
#
#   1. Greenfield and brownfield both build their subnets through modules/network/subnets.bicep,
#      so subnet shape (delegation, NSG association, private-endpoint policy) and the serialized
#      @batchSize(1) write behaviour have a single implementation.
#   2. The ownership boundary survives that sharing: the VNet is a managed resource ONLY in the
#      greenfield template, and is referenced as `existing` everywhere else.
#   3. Brownfield validates its BYO NSG resource IDs up front, mirroring the pattern in
#      infra/modules/foundry/main.bicep.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

GREENFIELD_MODULE="${REPO_ROOT}/infra/modules/network/main.bicep"
GREENFIELD_ENTRY="${REPO_ROOT}/infra/envs/poc/main.bicep"
BROWNFIELD_ENTRY="${REPO_ROOT}/infra/envs/poc/brownfield-network.bicep"
SUBNETS_MODULE="${REPO_ROOT}/infra/modules/network/subnets.bicep"

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

echo "==> az bicep build: modules/network/main.bicep"
az bicep build --file "$GREENFIELD_MODULE" --stdout >"$workdir/greenfield.json" 2>"$workdir/greenfield.err" \
  || { cat "$workdir/greenfield.err" >&2; fail "az bicep build failed for modules/network/main.bicep"; }
echo "==> az bicep build: envs/poc/main.bicep"
az bicep build --file "$GREENFIELD_ENTRY" --stdout >"$workdir/greenfield-entry.json" 2>"$workdir/greenfield-entry.err" \
  || { cat "$workdir/greenfield-entry.err" >&2; fail "az bicep build failed for envs/poc/main.bicep"; }

echo "==> greenfield builds subnets through the shared module, not inline resources"
grep -q "module subnets './subnets.bicep'" "$GREENFIELD_MODULE" \
  || fail "modules/network/main.bicep must delegate subnet creation to ./subnets.bicep"

if grep -Eq "^resource [A-Za-z]+ 'Microsoft\.Network/virtualNetworks/subnets@" "$GREENFIELD_MODULE"; then
  fail "modules/network/main.bicep must not declare subnet child resources inline; use ./subnets.bicep"
fi

echo "==> ownership boundary: the VNet is owned only by the greenfield template"
grep -Eq "^resource vnet 'Microsoft\.Network/virtualNetworks@[^']+' = \{" "$GREENFIELD_MODULE" \
  || fail "modules/network/main.bicep must declare the VNet as a managed resource"

grep -Eq "resource vnet 'Microsoft\.Network/virtualNetworks@[^']+' existing" "$SUBNETS_MODULE" \
  || fail "subnets.bicep must reference the VNet as 'existing' only"

if grep -Eq "^resource [A-Za-z]+ 'Microsoft\.Network/virtualNetworks@[^']+' = \{" "$BROWNFIELD_ENTRY"; then
  fail "brownfield-network.bicep must never declare the VNet as a managed resource"
fi

echo "==> greenfield subnet definitions are preserved through the shared module"
python3 - "$workdir/greenfield.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))

module = next(
    (r for r in arm["resources"]
     if r.get("type") == "Microsoft.Resources/deployments" and "-subnets" in str(r.get("name"))),
    None,
)
if module is None:
    sys.exit("no subnets module deployment found in the compiled greenfield template")

subnets = module["properties"]["parameters"]["subnets"]["value"]
by_name = {entry["name"]: entry for entry in subnets}

expected = [
    "hybridsubnet-apim",
    "hybridsubnet-foundry",
    "hybridsubnet-compute",
    "hybridsubnet-privateendpoints",
    "hybridsubnet-cicdagents",
    "AzureBastionSubnet",
]
missing = [name for name in expected if name not in by_name]
if missing:
    sys.exit(f"greenfield subnet definitions missing: {missing}")

if [entry["name"] for entry in subnets] != expected:
    sys.exit("subnet order changed; the subnetIds output indexes depend on it")

if by_name["hybridsubnet-foundry"].get("delegationServiceName") != "Microsoft.App/environments":
    sys.exit("foundry subnet lost its Microsoft.App/environments delegation")

foundry_service_endpoints = by_name["hybridsubnet-foundry"].get("serviceEndpoints")
if foundry_service_endpoints != "[parameters('foundryServiceEndpoints')]":
    sys.exit(
        "greenfield hybridsubnet-foundry must wire serviceEndpoints to the foundryServiceEndpoints "
        f"parameter, got: {foundry_service_endpoints}"
    )
if arm["parameters"]["foundryServiceEndpoints"]["defaultValue"] != []:
    sys.exit("greenfield foundryServiceEndpoints default value must be an empty array (FR-018a)")

if by_name["hybridsubnet-privateendpoints"].get("privateEndpointNetworkPolicies") != "Disabled":
    sys.exit("private endpoints subnet must keep privateEndpointNetworkPolicies = Disabled")

for name in ("hybridsubnet-apim", "hybridsubnet-compute"):
    if "nsgId" not in by_name[name]:
        sys.exit(f"{name} lost its NSG association")

for name in ("hybridsubnet-foundry", "hybridsubnet-privateendpoints", "AzureBastionSubnet"):
    if "nsgId" in by_name[name]:
        sys.exit(f"{name} must not receive an NSG in greenfield mode")

for key in ("vnetId", "subnetIds", "nsgIds", "privateDnsZoneIds"):
    if key not in arm.get("outputs", {}):
        sys.exit(f"greenfield output '{key}' was removed")
PY

echo "==> greenfield entry point forwards the opt-in Foundry endpoint parameter"
python3 - "$workdir/greenfield-entry.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
parameter = arm.get("parameters", {}).get("foundryServiceEndpoints", {})
if parameter.get("defaultValue") != []:
    sys.exit("greenfield entry point foundryServiceEndpoints default must remain empty (FR-018a)")

network_module = next(
    (
        r for r in arm.get("resources", [])
        if r.get("type") == "Microsoft.Resources/deployments"
        and "network-foundation" in str(r.get("name", ""))
    ),
    None,
)
if network_module is None:
    sys.exit("greenfield entry point is missing the network-foundation deployment")
module_params = network_module.get("properties", {}).get("parameters", {})
if module_params.get("foundryServiceEndpoints", {}).get("value") != "[parameters('foundryServiceEndpoints')]":
    sys.exit("greenfield entry point must forward foundryServiceEndpoints to the network module")
PY

echo "==> greenfield subnet writes are serialized"
grep -q '@batchSize(1)' "$SUBNETS_MODULE" \
  || fail "subnets.bicep must serialize subnet writes with @batchSize(1)"

python3 - "$workdir/greenfield.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
module = next(
    r for r in arm["resources"]
    if r.get("type") == "Microsoft.Resources/deployments" and "-subnets" in str(r.get("name"))
)
inner = module["properties"]["template"]["resources"]
subnet_res = next(r for r in inner if r["type"] == "Microsoft.Network/virtualNetworks/subnets")
copy = subnet_res.get("copy") or {}
if copy.get("mode") != "serial" or copy.get("batchSize") != 1:
    sys.exit(f"greenfield subnet writes are not serialized: {copy}")
PY

echo "==> subnets.bicep supports routeTableId and serviceEndpoints"
grep -q "routeTableId" "$SUBNETS_MODULE" \
  || fail "subnets.bicep must support an optional per-subnet routeTableId property"
grep -q "serviceEndpoints" "$SUBNETS_MODULE" \
  || fail "subnets.bicep must support an optional per-subnet serviceEndpoints property"

echo "==> az bicep build: brownfield-network.bicep"
az bicep build --file "$BROWNFIELD_ENTRY" --stdout >"$workdir/brownfield.json" 2>"$workdir/brownfield.err" \
  || { cat "$workdir/brownfield.err" >&2; fail "az bicep build failed for brownfield-network.bicep"; }

echo "==> brownfield validates its BYO NSG resource IDs"
for param in sharedHybridNsgId existingApimNsgId existingComputeNsgId; do
  grep -q "_validate.*${param^}\|${param}" "$BROWNFIELD_ENTRY" \
    || fail "brownfield-network.bicep does not reference ${param} in a validation"
done

echo "==> brownfield validates and wires apimRouteTableId/apimServiceEndpoints onto the APIM subnet only"
grep -q "apimRouteTableId" "$BROWNFIELD_ENTRY" \
  || fail "brownfield-network.bicep does not declare apimRouteTableId"
grep -q "apimServiceEndpoints" "$BROWNFIELD_ENTRY" \
  || fail "brownfield-network.bicep does not declare apimServiceEndpoints"
grep -q "_validateApimRouteTableId" "$BROWNFIELD_ENTRY" \
  || fail "brownfield-network.bicep does not validate apimRouteTableId's shape"

python3 - "$workdir/brownfield.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
variables = arm.get("variables", {})

# fail() compiles to the ARM `fail` function. Each guard must survive compilation.
serialized = json.dumps(variables)
for needle in (
    "sharedHybridNsgId must be a full ARM resource ID",
    "existingApimNsgId must be a full ARM resource ID",
    "existingComputeNsgId must be a full ARM resource ID",
    "both existingApimNsgId and existingComputeNsgId must be supplied",
    "apimRouteTableId must be empty or a full ARM resource ID",
):
    if needle not in serialized:
        sys.exit(f"missing NSG validation guard: {needle}")

# The guards must be reachable, otherwise their fail() never raises. They are threaded through
# nsgInputsValidated into useSharedHybridNsg, which every NSG decision depends on.
use_shared = variables.get("useSharedHybridNsg", "")
if "nsgInputsValidated" not in use_shared:
    sys.exit("useSharedHybridNsg does not depend on nsgInputsValidated; guards are dead code")

validated = variables.get("nsgInputsValidated", "")
for guard in (
    "_validateSharedHybridNsgId",
    "_validateReuseExistingNsgs",
    "_validateExistingApimNsgId",
    "_validateExistingComputeNsgId",
    "_validateApimRouteTableId",
):
    if guard not in validated:
        sys.exit(f"nsgInputsValidated does not include {guard}")
PY

echo "==> compiled brownfield template wires route table / service endpoints on APIM subnet only"
python3 - "$workdir/brownfield.json" <<'PY' || exit 1
import json
import sys

arm = json.load(open(sys.argv[1]))
module = next(
    r for r in arm["resources"]
    if r.get("type") == "Microsoft.Resources/deployments" and "-subnets" in str(r.get("name"))
)
subnets = module["properties"]["parameters"]["subnets"]["value"]

# Entries built with union() at authoring time compile to raw ARM expression strings rather than
# JSON objects (see foundry/private-endpoints subnets in brownfield-network.bicep); route-table /
# service-endpoint checks below only need name-keyed dict entries (currently just APIM/compute).
dict_entries = [e for e in subnets if isinstance(e, dict)]
by_name = {}
for entry in dict_entries:
    name = entry.get("name", "")
    # Names are ARM parameter-reference expressions like "[parameters('apimSubnetName')]"; map the
    # ones this test cares about back to their bicep parameter identity.
    if "apimSubnetName" in name:
        by_name["hybridsubnet-apim"] = entry
    elif "computeSubnetName" in name:
        by_name["hybridsubnet-compute"] = entry

apim = by_name.get("hybridsubnet-apim")
if apim is None:
    sys.exit("hybridsubnet-apim not found in compiled brownfield subnets parameter")

if "routeTableId" not in apim:
    sys.exit("APIM subnet definition is missing routeTableId")
if apim["routeTableId"] != "[parameters('apimRouteTableId')]":
    sys.exit(f"APIM subnet routeTableId must reference the apimRouteTableId parameter, got: {apim['routeTableId']}")
if "serviceEndpoints" not in apim:
    sys.exit("APIM subnet definition is missing serviceEndpoints")
if apim["serviceEndpoints"] != "[parameters('apimServiceEndpoints')]":
    sys.exit(f"APIM subnet serviceEndpoints must reference the apimServiceEndpoints parameter, got: {apim['serviceEndpoints']}")

# The compiled default for apimServiceEndpoints must be exactly the four endpoints required by
# common brownfield-deployment network policy (FR-018a); a regression to an empty or wrong list
# would still pass the presence-only checks above.
expected_default_endpoints = [
    "Microsoft.AzureActiveDirectory",
    "Microsoft.KeyVault",
    "Microsoft.Sql",
    "Microsoft.Storage",
]
actual_default_endpoints = arm["parameters"]["apimServiceEndpoints"]["defaultValue"]
if actual_default_endpoints != expected_default_endpoints:
    sys.exit(
        "apimServiceEndpoints default value does not match the required four endpoints: "
        f"expected {expected_default_endpoints}, got {actual_default_endpoints}"
    )
if arm["parameters"]["apimRouteTableId"]["defaultValue"] != "":
    sys.exit("apimRouteTableId default value must be an empty string (no association)")

compute = by_name.get("hybridsubnet-compute")
if compute is not None:
    if "routeTableId" in compute:
        sys.exit("hybridsubnet-compute must not receive routeTableId in brownfield mode; APIM-only")
    if "serviceEndpoints" in compute:
        sys.exit("hybridsubnet-compute must not receive serviceEndpoints in brownfield mode; APIM-only")

# Foundry/private-endpoints entries compile to union() expression strings. The foundry subnet
# must reference its own foundryServiceEndpoints parameter (so a regression that drops the
# wiring is caught) but never routeTableId; all other such expressions (e.g. private-endpoints
# subnet) must reference neither.
foundry_entry = next((e for e in subnets if isinstance(e, str) and "foundrySubnetName" in e), None)
if foundry_entry is None:
    sys.exit("could not find the foundry subnet's compiled union() expression")
if "parameters('foundryServiceEndpoints')" not in foundry_entry:
    sys.exit(f"the foundry subnet expression must wire serviceEndpoints to foundryServiceEndpoints, got: {foundry_entry}")

for entry in subnets:
    if not isinstance(entry, str):
        continue
    if "routeTableId" in entry:
        sys.exit(f"a non-APIM subnet expression unexpectedly references routeTableId: {entry}")
    if "serviceEndpoints" in entry and "foundrySubnetName" not in entry:
        sys.exit(f"a non-APIM, non-foundry subnet expression unexpectedly references serviceEndpoints: {entry}")

# The compiled default for foundryServiceEndpoints must be an empty array, matching FR-018a (no
# service endpoints except on the APIM-purpose subnet); callers opt in explicitly per deployment.
expected_foundry_default_endpoints = []
actual_foundry_default_endpoints = arm["parameters"]["foundryServiceEndpoints"]["defaultValue"]
if actual_foundry_default_endpoints != expected_foundry_default_endpoints:
    sys.exit(
        "foundryServiceEndpoints default value does not match FR-018a: "
        f"expected {expected_foundry_default_endpoints}, got {actual_foundry_default_endpoints}"
    )
PY

echo "Network module contract tests passed."
