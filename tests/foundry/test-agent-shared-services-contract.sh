#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SHARED_TEMPLATE="$REPO_ROOT/infra/envs/poc/agent-shared-services.bicep"
FOUNDRY_TEMPLATE="$REPO_ROOT/infra/envs/poc/foundry.bicep"

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

az bicep build --file "$SHARED_TEMPLATE" --stdout >"$workdir/shared.json"
az bicep build --file "$FOUNDRY_TEMPLATE" --stdout >"$workdir/foundry.json"

python3 - "$workdir/shared.json" "$workdir/foundry.json" <<'PY'
import json
import sys

shared = json.load(open(sys.argv[1]))
foundry = json.load(open(sys.argv[2]))
deployments = {
    resource.get("name"): resource
    for resource in shared.get("resources", [])
    if resource.get("type") == "Microsoft.Resources/deployments"
}
expected_create_modules = {
    "phase1-agent-storage": "storagePassedIn",
    "phase1-agent-ai-search": "searchPassedIn",
    "phase1-agent-cosmos-db": "cosmosPassedIn",
}
for deployment_name, ownership_variable in expected_create_modules.items():
    deployment = deployments.get(deployment_name)
    if deployment is None:
        sys.exit(f"shared composition is missing create-or-reuse module {deployment_name}")
    if deployment.get("condition") != f"[not(variables('{ownership_variable}'))]":
        sys.exit(f"{deployment_name} must deploy only when the corresponding existing ID is empty")

key_vault_module = deployments.get("phase1-agent-key-vault")
if key_vault_module is None:
    sys.exit("shared composition is missing reusable Key Vault module")
key_vault_resources = key_vault_module.get("properties", {}).get("template", {}).get("resources", [])
new_key_vaults = [
    resource
    for resource in key_vault_resources
    if resource.get("type") == "Microsoft.KeyVault/vaults"
    and resource.get("condition") == "[not(variables('keyVaultPassedIn'))]"
]
if len(new_key_vaults) != 1:
    sys.exit("Key Vault creation must be disabled when an existing Key Vault ID is supplied")
if not all(
    new_key_vaults[0].get("properties", {}).get(key) == expected
    for key, expected in (
        ("enableSoftDelete", True),
        ("enablePurgeProtection", True),
        ("softDeleteRetentionInDays", 90),
    )
):
    sys.exit("New Key Vault must enable soft delete, purge protection, and 90-day retention")

def nested_resource_types(template):
    for resource in template.get("resources", []):
        yield resource.get("type")
        nested = resource.get("properties", {}).get("template")
        if isinstance(nested, dict):
            yield from nested_resource_types(nested)

for resource_type in nested_resource_types(shared):
    if resource_type in (
        "Microsoft.CognitiveServices/accounts",
        "Microsoft.CognitiveServices/accounts/projects",
        "Microsoft.CognitiveServices/accounts/projects/capabilityHosts",
    ):
        sys.exit(f"pre-approval shared composition must not deploy Foundry resources: {resource_type}")

parameters = foundry.get("parameters", {})
if parameters.get("existingKeyVaultResourceId", {}).get("defaultValue") != "":
    sys.exit("legacy Foundry deployment must preserve create-new Key Vault as the empty-ID default")
print("Shared-resource create/reuse and legacy Key Vault contracts passed.")
PY
