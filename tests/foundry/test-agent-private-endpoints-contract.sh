#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/infra/envs/poc/agent-private-endpoints.bicep"

command -v az >/dev/null 2>&1 || {
  echo "SKIP: az CLI not available; cannot run Bicep build checks." >&2
  exit 0
}
command -v python3 >/dev/null 2>&1 || {
  echo "SKIP: python3 not available; cannot run compiled-template assertions." >&2
  exit 0
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

az bicep build --file "$TEMPLATE" --stdout >"$workdir/agent-private-endpoints.json"

python3 - "$workdir/agent-private-endpoints.json" <<'PY'
import json
import sys

template = json.load(open(sys.argv[1]))
parameters = template.get("parameters", {})
required_flags = (
    "createStoragePrivateEndpoint",
    "createKeyVaultPrivateEndpoint",
    "createCosmosDBPrivateEndpoint",
    "createAISearchPrivateEndpoint",
)
for name in required_flags:
    if "defaultValue" in parameters.get(name, {}):
        sys.exit(f"{name} must require an explicit create-or-reuse decision")
for name in ("approvedAmplsPrivateEndpointId", "approvedAmplsResourceId"):
    if name in parameters:
        sys.exit(f"{name} must not gate the four service endpoints")

deployments = [
    resource
    for resource in template.get("resources", [])
    if resource.get("type") == "Microsoft.Resources/deployments"
]
if len(deployments) != 1:
    sys.exit(f"expected one private-endpoint module deployment, found {len(deployments)}")
nested = deployments[0].get("properties", {}).get("template", {})
if any(name in nested.get("parameters", {}) for name in ("approvedAmplsPrivateEndpointId", "approvedAmplsResourceId")):
    sys.exit("the service endpoint module must not require AMPLS inputs")
resources = nested.get("resources", [])
endpoints = [
    resource for resource in resources
    if resource.get("type") == "Microsoft.Network/privateEndpoints"
]
if len(endpoints) != 4:
    sys.exit(f"expected exactly four shared-service endpoint create branches, found {len(endpoints)}")
if any(
    resource.get("type") == "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"
    for resource in resources
):
    sys.exit("shared private endpoints must remain bare; DNS associations are a later stage")
if any(resource.get("type", "").startswith("Microsoft.CognitiveServices/") for resource in resources):
    sys.exit("the pre-approval endpoint stage must not create Foundry account or project endpoints")
if any(resource.get("type") == "Microsoft.Insights/privateLinkScopes" for resource in resources):
    sys.exit("the private-endpoint stage must not create an AMPLS")

expected = {
    "phase1-agent-storage-connection": ("storageAccountId", ["blob"], "createStoragePrivateEndpoint"),
    "phase1-agent-keyvault-connection": ("keyVaultId", ["vault"], "createKeyVaultPrivateEndpoint"),
    "phase1-agent-cosmos-connection": ("cosmosDBAccountId", ["Sql"], "createCosmosDBPrivateEndpoint"),
    "phase1-agent-search-connection": ("aiSearchServiceId", ["searchService"], "createAISearchPrivateEndpoint"),
}
for resource in endpoints:
    connections = resource.get("properties", {}).get("privateLinkServiceConnections", [])
    if len(connections) != 1:
        sys.exit(f"{resource.get('name')} must have exactly one private-link connection")
    connection = connections[0]
    name = connection.get("name")
    if name not in expected:
        sys.exit(f"unexpected private-link connection: {name}")
    target, groups, create_flag = expected[name]
    properties = connection.get("properties", {})
    if properties.get("privateLinkServiceId") != f"[parameters('{target}')]":
        sys.exit(f"{name} must target the shared handoff parameter {target}")
    if properties.get("groupIds") != groups:
        sys.exit(f"{name} has an unexpected private-link subresource")
    if create_flag not in str(resource.get("condition", "")):
        sys.exit(f"{name} must be gated by an explicit create decision")

outputs = template.get("outputs", {})
for name in (
    "storagePrivateEndpointId",
    "keyVaultPrivateEndpointId",
    "cosmosDBPrivateEndpointId",
    "aiSearchPrivateEndpointId",
):
    if name not in outputs:
        sys.exit(f"private endpoint handoff is missing output {name}")
if "amplsPrivateEndpointId" in outputs or "amplsPrivateEndpointId" in nested.get("outputs", {}):
    sys.exit("the service endpoint handoff must not claim an AMPLS endpoint")

print("Shared service private endpoint create/reuse contracts passed.")
PY
