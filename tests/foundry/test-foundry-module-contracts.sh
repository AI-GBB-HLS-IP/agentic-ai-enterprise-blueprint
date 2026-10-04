#!/usr/bin/env bash
set -euo pipefail

# Contract tests for the staged Foundry private-endpoint deployment:
#
#   1. private-endpoint.bicep creates bare private endpoints and exposes IDs and names.
#   2. private-endpoint-dns.bicep is a generic one-endpoint/one-zone-group module.
#   3. foundry-dns.bicep validates full endpoint ARM IDs, scopes each association to the
#      endpoint's subscription/resource group, and gates optional endpoint associations.
#   4. main.bicep and envs/poc/foundry.bicep expose endpoint IDs for the DNS stage.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

PRIVATE_ENDPOINT_MODULE="${REPO_ROOT}/infra/modules/foundry/private-endpoint.bicep"
PRIVATE_ENDPOINT_DNS_MODULE="${REPO_ROOT}/infra/modules/foundry/private-endpoint-dns.bicep"
FOUNDRY_DNS_ENV="${REPO_ROOT}/infra/envs/poc/foundry-dns.bicep"
MAIN_MODULE="${REPO_ROOT}/infra/modules/foundry/main.bicep"
FOUNDRY_ENV="${REPO_ROOT}/infra/envs/poc/foundry.bicep"
STORAGE_RBAC_MODULE="${REPO_ROOT}/infra/modules/foundry/storage-rbac.bicep"

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

build_bicep() {
  local source_file="$1"
  local output_file="$2"
  local display_path="${source_file#"${REPO_ROOT}/"}"

  echo "==> az bicep build: ${display_path}"
  az bicep build --file "$source_file" --stdout >"$output_file" 2>"${output_file}.err" \
    || { cat "${output_file}.err" >&2; fail "az bicep build failed for ${display_path}"; }
}

build_bicep "$PRIVATE_ENDPOINT_MODULE" "$workdir/private-endpoint.json"
build_bicep "$PRIVATE_ENDPOINT_DNS_MODULE" "$workdir/private-endpoint-dns.json"
build_bicep "$FOUNDRY_DNS_ENV" "$workdir/foundry-dns.json"
build_bicep "$MAIN_MODULE" "$workdir/main.json"
build_bicep "$FOUNDRY_ENV" "$workdir/foundry-env.json"
build_bicep "$STORAGE_RBAC_MODULE" "$workdir/storage-rbac.json"

echo "==> private-endpoint.bicep creates bare endpoints and exposes IDs and names"
python3 - "$workdir/private-endpoint.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
resources = arm.get("resources", [])

zone_groups = [
    resource
    for resource in resources
    if resource.get("type") == "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"
]
if zone_groups:
    sys.exit("private-endpoint.bicep must not create privateDnsZoneGroups resources")

private_endpoints = [
    resource
    for resource in resources
    if resource.get("type") == "Microsoft.Network/privateEndpoints"
]
if len(private_endpoints) != 5:
    sys.exit(f"private-endpoint.bicep must declare five private endpoints, found {len(private_endpoints)}")

outputs = arm.get("outputs", {})
services = ("foundry", "storage", "keyVault", "cosmosDB", "aiSearch")
for service in services:
    for suffix in ("PrivateEndpointId", "PrivateEndpointName"):
        key = f"{service}{suffix}"
        if key not in outputs:
            sys.exit(f"private-endpoint.bicep is missing expected output: {key}")
PY

echo "==> private-endpoint-dns.bicep creates one zone group for one existing endpoint"
python3 - "$workdir/private-endpoint-dns.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
resources = arm.get("resources", [])
parameters = arm.get("parameters", {})

if any(resource.get("type") == "Microsoft.Network/privateEndpoints" for resource in resources):
    sys.exit("private-endpoint-dns.bicep must reference an existing private endpoint")

zone_groups = [
    resource
    for resource in resources
    if resource.get("type") == "Microsoft.Network/privateEndpoints/privateDnsZoneGroups"
]
if len(zone_groups) != 1:
    sys.exit(f"private-endpoint-dns.bicep must create exactly one privateDnsZoneGroups resource, found {len(zone_groups)}")

for parameter in ("privateEndpointName", "dnsGroupName", "privateDnsZoneConfigs"):
    if parameter not in parameters or "defaultValue" in parameters[parameter]:
        sys.exit(f"private-endpoint-dns.bicep must require parameter: {parameter}")

zone_group = zone_groups[0]
name_expression = zone_group.get("name", "")
if "parameters('privateEndpointName')" not in name_expression or "parameters('dnsGroupName')" not in name_expression:
    sys.exit("privateDnsZoneGroups name must be derived from privateEndpointName and dnsGroupName")

configs_expression = zone_group.get("properties", {}).get("privateDnsZoneConfigs", "")
if "parameters('privateDnsZoneConfigs')" not in str(configs_expression):
    sys.exit("privateDnsZoneGroups properties must use privateDnsZoneConfigs")

compiled = json.dumps(arm)
messages = (
    "privateEndpointName must not be empty.",
    "dnsGroupName must not be empty.",
    "privateDnsZoneConfigs must contain at least one private DNS zone configuration.",
)
for message in messages:
    if message not in compiled:
        sys.exit(f"private-endpoint-dns.bicep is missing validation message: {message}")
PY

echo "==> foundry-dns.bicep validates endpoint IDs, scopes modules, and gates optional associations"
python3 - "$workdir/foundry-dns.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
parameters = arm.get("parameters", {})
resources = arm.get("resources", [])

optional = (
    "foundryPrivateEndpointId",
    "storagePrivateEndpointId",
    "keyVaultPrivateEndpointId",
    "cosmosDBPrivateEndpointId",
    "aiSearchPrivateEndpointId",
)
for parameter in optional:
    if parameters.get(parameter, {}).get("defaultValue") != "":
        sys.exit(f"foundry-dns.bicep must make {parameter} optional with an empty default")

compiled = json.dumps(arm)
expected_messages = {
    "foundryPrivateEndpointId": "must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.",
    "keyVaultPrivateEndpointId": "must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.",
    "storagePrivateEndpointId": "must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.",
    "cosmosDBPrivateEndpointId": "must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.",
    "aiSearchPrivateEndpointId": "must be empty or a full ARM resource ID for Microsoft.Network/privateEndpoints.",
}
for parameter, message_suffix in expected_messages.items():
    message = f"{parameter} {message_suffix}"
    if message not in compiled:
        sys.exit(f"foundry-dns.bicep is missing clear validation failure: {message}")

deployments = {
    resource.get("name"): resource
    for resource in resources
    if resource.get("type") == "Microsoft.Resources/deployments"
}
expected = {
    "foundry-private-endpoint-dns": ("foundry", "createFoundryDnsGroup"),
    "storage-private-endpoint-dns": ("storage", "createStorageDnsGroup"),
    "keyvault-private-endpoint-dns": ("keyVault", "createKeyVaultDnsGroup"),
    "cosmosdb-private-endpoint-dns": ("cosmosDB", "createCosmosDBDnsGroup"),
    "aisearch-private-endpoint-dns": ("aiSearch", "createAISearchDnsGroup"),
}
for deployment_name, (prefix, gate_variable) in expected.items():
    deployment = deployments.get(deployment_name)
    if deployment is None:
        sys.exit(f"foundry-dns.bicep is missing module deployment: {deployment_name}")

    expected_subscription = f"[variables('{prefix}PrivateEndpointSubscriptionId')]"
    expected_resource_group = f"[variables('{prefix}PrivateEndpointResourceGroupName')]"
    if deployment.get("subscriptionId") != expected_subscription:
        sys.exit(f"{deployment_name} must use the subscription parsed from its endpoint ID")
    if deployment.get("resourceGroup") != expected_resource_group:
        sys.exit(f"{deployment_name} must use the resource group parsed from its endpoint ID")

    module_parameters = deployment.get("properties", {}).get("parameters", {})
    endpoint_name = str(module_parameters.get("privateEndpointName", {}))
    if f"variables('{prefix}PrivateEndpointName')" not in endpoint_name:
        sys.exit(f"{deployment_name} must use the endpoint name parsed from its endpoint ID")

    condition = str(deployment.get("condition", ""))
    if f"variables('{gate_variable}')" not in condition:
        sys.exit(f"{deployment_name} must be gated when its optional endpoint ID is empty")
PY

echo "==> main.bicep and envs/poc/foundry.bicep expose endpoint IDs"
python3 - "$workdir/main.json" "$workdir/foundry-env.json" <<'PY'
import json
import sys

expected_outputs = (
    "foundryPrivateEndpointId",
    "storagePrivateEndpointId",
    "keyVaultPrivateEndpointId",
    "cosmosDBPrivateEndpointId",
    "aiSearchPrivateEndpointId",
)
for path, display_name in zip(sys.argv[1:], ("main.bicep", "envs/poc/foundry.bicep")):
    arm = json.load(open(path))
    outputs = arm.get("outputs", {})
    for output in expected_outputs:
        if output not in outputs:
            sys.exit(f"{display_name} is missing expected endpoint ID output: {output}")
PY

echo "==> private-endpoint.bicep guards Key Vault private-endpoint creation like Storage/Cosmos/AISearch"
python3 - "$workdir/private-endpoint.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
parameters = arm.get("parameters", {})
resources = arm.get("resources", [])
outputs = arm.get("outputs", {})

if parameters.get("createKeyVaultPrivateEndpoint", {}).get("defaultValue") is not True:
    sys.exit("private-endpoint.bicep: createKeyVaultPrivateEndpoint must default to true (unconditional creation unless the caller opts out)")

key_vault_pe = next(
    (
        r for r in resources
        if r.get("type") == "Microsoft.Network/privateEndpoints"
        and "keyvault" in str(r.get("name", "")).lower()
    ),
    None,
)
if key_vault_pe is None:
    sys.exit("private-endpoint.bicep is missing the Key Vault private endpoint resource")
condition = str(key_vault_pe.get("condition", ""))
if "parameters('createKeyVaultPrivateEndpoint')" not in condition:
    sys.exit("the Key Vault private endpoint resource must be conditional on createKeyVaultPrivateEndpoint, like Storage/Cosmos/AISearch")

for output_name in ("keyVaultPrivateEndpointId", "keyVaultPrivateEndpointName"):
    output_value = str(outputs.get(output_name, {}).get("value", ""))
    if "parameters('createKeyVaultPrivateEndpoint')" not in output_value:
        sys.exit(f"{output_name} must be conditional on createKeyVaultPrivateEndpoint so it is safe to read when the resource is skipped")
PY

echo "==> main.bicep forwards the Key Vault reuse decision and rejects an invalid flag/resource-ID combination"
python3 - "$workdir/main.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
parameters = arm.get("parameters", {})

if "existingKeyVaultPrivateEndpoint" not in parameters:
    sys.exit("main.bicep is missing the existingKeyVaultPrivateEndpoint parameter")
if parameters["existingKeyVaultPrivateEndpoint"].get("defaultValue") is not False:
    sys.exit("main.bicep: existingKeyVaultPrivateEndpoint must default to false")

compiled = json.dumps(arm)
if "existingKeyVaultPrivateEndpoint can only be true when existingKeyVaultResourceId is set." not in compiled:
    sys.exit("main.bicep must reject existingKeyVaultPrivateEndpoint=true without existingKeyVaultResourceId")

private_endpoints_module = next(
    (
        r for r in arm.get("resources", [])
        if r.get("type") == "Microsoft.Resources/deployments" and "private-endpoint" in str(r.get("name", "")).lower()
    ),
    None,
)
if private_endpoints_module is None:
    sys.exit("main.bicep is missing the private-endpoints module deployment")
module_params = json.dumps(private_endpoints_module.get("properties", {}).get("parameters", {}))
if "createKeyVaultPrivateEndpoint" not in module_params:
    sys.exit("main.bicep must forward a createKeyVaultPrivateEndpoint decision to the private-endpoints module")
PY

echo "==> envs/poc/foundry.bicep forwards existingKeyVaultPrivateEndpoint to the foundry module"
python3 - "$workdir/foundry-env.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
parameters = arm.get("parameters", {})
if "existingKeyVaultPrivateEndpoint" not in parameters:
    sys.exit("envs/poc/foundry.bicep is missing the existingKeyVaultPrivateEndpoint parameter")

foundry_module = next(
    (
        r for r in arm.get("resources", [])
        if r.get("type") == "Microsoft.Resources/deployments"
    ),
    None,
)
if foundry_module is None:
    sys.exit("envs/poc/foundry.bicep is missing the inner foundry module deployment")
module_params = json.dumps(foundry_module.get("properties", {}).get("parameters", {}))
if "existingKeyVaultPrivateEndpoint" not in module_params:
    sys.exit("envs/poc/foundry.bicep must forward existingKeyVaultPrivateEndpoint to the foundry module")
PY

echo "==> storage RBAC assigns Contributor account-wide and Owner with workspace-container ABAC"
python3 - "$workdir/storage-rbac.json" <<'PY'
import json
import sys

arm = json.load(open(sys.argv[1]))
variables = arm.get("variables", {})
resources = [
    resource for resource in arm.get("resources", [])
    if resource.get("type") == "Microsoft.Authorization/roleAssignments"
]
if len(resources) != 2:
    sys.exit(f"storage-rbac.bicep must declare exactly two role assignments, found {len(resources)}")

def assignment_for(role_id):
    matches = [
        resource for resource in resources
        if role_id in str(resource.get("properties", {}).get("roleDefinitionId", ""))
    ]
    if len(matches) != 1:
        sys.exit(f"expected exactly one assignment for built-in role {role_id}")
    return matches[0]

contributor_role_id = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
owner_role_id = "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
if contributor_role_id not in str(variables):
    sys.exit("storage Blob Data Contributor built-in role ID is incorrect")
if owner_role_id not in str(variables):
    sys.exit("storage Blob Data Owner built-in role ID is incorrect")

contributor = assignment_for("storageBlobDataContributorRoleId")
if "condition" in contributor.get("properties", {}) or "conditionVersion" in contributor.get("properties", {}):
    sys.exit("Storage Blob Data Contributor must be unconditional at the storage-account scope")

owner = assignment_for("storageBlobDataOwnerRoleId")
owner_properties = owner.get("properties", {})
if owner_properties.get("conditionVersion") != "2.0":
    sys.exit("Storage Blob Data Owner must use ABAC condition version 2.0")
condition = str(owner_properties.get("condition", ""))
for required in (
    "projectWorkspaceIdGuid",
    "StringStartsWithIgnoreCase",
    "*-azureml-agent",
):
    if required not in condition:
        sys.exit(f"Storage Blob Data Owner condition is missing {required}")
PY

echo "Foundry module contract tests passed."
