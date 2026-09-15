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
    if gate_variable:
        if f"variables('{gate_variable}')" not in condition:
            sys.exit(f"{deployment_name} must be gated when its optional endpoint ID is empty")
    elif deployment.get("condition") is not None:
        sys.exit(f"{deployment_name} must always deploy for its required endpoint ID")
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

echo "Foundry module contract tests passed."
