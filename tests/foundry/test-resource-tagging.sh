#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

command -v az >/dev/null 2>&1 || { echo "SKIP: az CLI not available."; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available."; exit 0; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

az bicep build --file "$REPO_ROOT/infra/modules/foundry/main.bicep" --stdout >"$workdir/main.json"
az bicep build --file "$REPO_ROOT/infra/modules/foundry/private-endpoint.bicep" --stdout >"$workdir/private-endpoint.json"
az bicep build --file "$REPO_ROOT/infra/envs/poc/foundry-dns.bicep" --stdout >"$workdir/foundry-dns.json"

python3 - "$workdir/main.json" "$workdir/private-endpoint.json" "$workdir/foundry-dns.json" <<'PY'
import json
import sys

main, private_endpoint, foundry_dns = [json.load(open(path)) for path in sys.argv[1:]]

for name in (
    "foundryAccountTags",
    "foundryProjectTags",
    "keyVaultTags",
    "storageTags",
    "aiSearchTags",
    "cosmosDBTags",
    "privateEndpointTags",
):
    if main["parameters"][name]["defaultValue"] != {}:
        raise SystemExit(f"Foundry default for {name} must be {{}}")

for resource_type in (
    "Microsoft.CognitiveServices/accounts",
    "Microsoft.CognitiveServices/accounts/projects",
):
    resource = next(r for r in main["resources"] if r.get("type") == resource_type)
    tags = resource.get("tags", "")
    if "union(parameters('tags')" not in str(tags):
        raise SystemExit(f"{resource_type} does not preserve the shared tags base")

account = next(r for r in main["resources"] if r.get("type") == "Microsoft.CognitiveServices/accounts")

def assert_account_tag_mapping(resource):
    if "foundryAccountTags" not in str(resource.get("tags", "")):
        raise AssertionError("Foundry account tags are not layered over the shared base")

assert_account_tag_mapping(account)
if "union(parameters('tags'), parameters('foundryAccountTags'))" not in str(account.get("tags", "")):
    raise SystemExit("Foundry account payload does not preserve resource-specific precedence")
miswired_account = dict(account)
miswired_account["tags"] = str(account["tags"]).replace("foundryAccountTags", "foundryProjectTags")
try:
    assert_account_tag_mapping(miswired_account)
except AssertionError:
    pass
else:
    raise SystemExit("deliberately miswired Foundry account tag mapping was not rejected")

deployments = {
    resource.get("name"): resource
    for resource in main["resources"]
    if resource.get("type") == "Microsoft.Resources/deployments"
}
for deployment_name, tag_name in (
    ("foundry-keyvault", "keyVaultTags"),
    ("foundry-storage", "storageTags"),
    ("foundry-ai-search", "aiSearchTags"),
    ("foundry-cosmos-db", "cosmosDBTags"),
):
    params = deployments[deployment_name]["properties"]["parameters"]
    if "tags" not in params or tag_name not in str(params["tags"]):
        raise SystemExit(f"{deployment_name} does not receive {tag_name}")

pe_deployment = deployments["foundry-private-endpoints"]
pe_params = pe_deployment["properties"]["parameters"]
if "privateEndpointTags" not in pe_params:
    raise SystemExit("private endpoint deployment is missing the purpose-keyed tag map")

pe_resources = [
    resource for resource in private_endpoint["resources"]
    if resource.get("type") == "Microsoft.Network/privateEndpoints"
]
if len(pe_resources) != 5:
    raise SystemExit(f"expected five private endpoints, found {len(pe_resources)}")
for resource in pe_resources:
    if "tags" not in resource:
        raise SystemExit(f"private endpoint {resource.get('name')} is missing tags")

effective_private_endpoint_tags = variables = main.get("variables", {}).get("effectivePrivateEndpointTags", {})
for purpose in ("foundry", "storage", "keyVault", "cosmosDB", "aiSearch"):
    expected = f"tryGet(parameters('privateEndpointTags'), '{purpose}')"
    if expected not in str(effective_private_endpoint_tags.get(purpose, "")):
        raise SystemExit(f"private endpoint payload for {purpose} does not preserve tag precedence")

variables = main.get("variables", {})
if "privateEndpointTagsValidated" not in variables:
    raise SystemExit("Foundry private-endpoint unknown-key validation is not compiled")
if "unsupported logical resource key" not in json.dumps(variables):
    raise SystemExit("Foundry private-endpoint error does not identify the rejected key")

for name in ("servicesAiPrivateDnsZoneTags", "servicesAiPrivateDnsVnetLinkTags"):
    if foundry_dns["parameters"][name]["defaultValue"] != {}:
        raise SystemExit(f"Foundry DNS default for {name} must be {{}}")
services_module = next(
    resource for resource in foundry_dns["resources"]
    if resource.get("name") == "services-ai-private-dns"
)
services_params = services_module["properties"]["parameters"]
for name in ("zoneTags", "vnetLinkTags"):
    if name not in services_params:
        raise SystemExit(f"services.ai DNS module is missing {name}")
PY

echo "Foundry resource tagging contract tests passed."
