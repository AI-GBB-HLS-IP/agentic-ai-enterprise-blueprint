#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

command -v az >/dev/null 2>&1 || { echo "SKIP: az CLI not available."; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available."; exit 0; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

build() {
  az bicep build --file "$1" --stdout >"$2"
}

build "$REPO_ROOT/infra/envs/poc/main.bicep" "$workdir/main.json"
build "$REPO_ROOT/infra/envs/poc/brownfield-network.bicep" "$workdir/brownfield-network.json"
build "$REPO_ROOT/infra/envs/poc/brownfield-dns.bicep" "$workdir/brownfield-dns.json"
build "$REPO_ROOT/infra/modules/network/private-dns.bicep" "$workdir/private-dns.json"

python3 - "$workdir/main.json" "$workdir/brownfield-network.json" "$workdir/brownfield-dns.json" "$workdir/private-dns.json" <<'PY'
import json
import sys

main, brownfield_network, brownfield_dns, private_dns = [json.load(open(path)) for path in sys.argv[1:]]

for name in ("virtualNetworkTags", "apimNsgTags", "computeNsgTags", "privateDnsZoneTags", "privateDnsVnetLinkTags"):
    if main["parameters"][name]["defaultValue"] != {}:
        raise SystemExit(f"greenfield default for {name} must be {{}}")

network_module = next(
    resource for resource in main["resources"]
    if resource.get("name") == "network-foundation"
)
network_params = network_module["properties"]["parameters"]
for name in ("virtualNetworkTags", "apimNsgTags", "computeNsgTags", "privateDnsZoneTags", "privateDnsVnetLinkTags"):
    if name not in network_params:
        raise SystemExit(f"greenfield network module is missing {name}")

def assert_vnet_tag_mapping(params):
    if params["virtualNetworkTags"]["value"] != "[parameters('virtualNetworkTags')]":
        raise AssertionError("greenfield VNet tags are mapped to the wrong parameter")

assert_vnet_tag_mapping(network_params)
miswired = dict(network_params)
miswired["virtualNetworkTags"] = {"value": "[parameters('apimNsgTags')]"}
try:
    assert_vnet_tag_mapping(miswired)
except AssertionError:
    pass
else:
    raise SystemExit("deliberately miswired VNet tag mapping was not rejected")

for name in ("apimNsgTags", "computeNsgTags"):
    if brownfield_network["parameters"][name]["defaultValue"] != {}:
        raise SystemExit(f"brownfield default for {name} must be {{}}")

nsg_module = next(
    resource for resource in brownfield_network["resources"]
    if resource.get("name") == "brownfield-nsg"
)
nsg_params = nsg_module["properties"]["parameters"]
for name in ("apimNsgTags", "computeNsgTags"):
    if name not in nsg_params:
        raise SystemExit(f"brownfield NSG module is missing {name}")

if brownfield_dns["parameters"]["privateDnsVnetLinkTags"]["defaultValue"] != {}:
    raise SystemExit("brownfield DNS tag map must default to {}")
for resource in brownfield_dns["resources"]:
    if resource.get("name", "").startswith("brownfield-link-"):
        params = resource.get("properties", {}).get("parameters", {})
        if "tags" not in params:
            raise SystemExit(f"{resource['name']} is missing its resource-specific tags")

resources = private_dns["resources"]
zones = [r for r in resources if r.get("type") == "Microsoft.Network/privateDnsZones"]
links = [r for r in resources if r.get("type") == "Microsoft.Network/privateDnsZones/virtualNetworkLinks"]
if len(zones) != 8 or len(links) != 8:
    raise SystemExit(f"expected 8 zones and 8 links, found {len(zones)} and {len(links)}")
for resource in zones + links:
    if "tags" not in resource:
        raise SystemExit(f"missing tags on {resource.get('name')}")

variables = private_dns.get("variables", {})
if "privateDnsTagsValidated" not in variables:
    raise SystemExit("private DNS unknown-key validation is not compiled")
if "unsupported logical resource key" not in json.dumps(variables):
    raise SystemExit("private DNS unknown-key error does not identify the rejected key")
PY

echo "Network resource tagging contract tests passed."
