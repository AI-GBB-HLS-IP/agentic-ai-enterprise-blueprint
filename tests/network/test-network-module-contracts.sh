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

echo "==> az bicep build: brownfield-network.bicep"
az bicep build --file "$BROWNFIELD_ENTRY" --stdout >"$workdir/brownfield.json" 2>"$workdir/brownfield.err" \
  || { cat "$workdir/brownfield.err" >&2; fail "az bicep build failed for brownfield-network.bicep"; }

echo "==> brownfield validates its BYO NSG resource IDs"
for param in sharedHybridNsgId existingApimNsgId existingComputeNsgId; do
  grep -q "_validate.*${param^}\|${param}" "$BROWNFIELD_ENTRY" \
    || fail "brownfield-network.bicep does not reference ${param} in a validation"
done

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
):
    if guard not in validated:
        sys.exit(f"nsgInputsValidated does not include {guard}")
PY

echo "Network module contract tests passed."
