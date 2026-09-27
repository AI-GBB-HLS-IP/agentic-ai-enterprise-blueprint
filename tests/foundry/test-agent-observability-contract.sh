#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/infra/envs/poc/agent-observability.bicep"

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

az bicep build --file "$TEMPLATE" --stdout >"$workdir/agent-observability.json"

python3 - "$workdir/agent-observability.json" <<'PY'
import json
import sys

template = json.load(open(sys.argv[1]))
parameters = template.get("parameters", {})
for name in (
    "approvedLogAnalyticsWorkspaceId",
    "monitoringOwnerApprovalReference",
    "apimApplicationInsightsResourceId",
):
    if "defaultValue" in parameters.get(name, {}):
        sys.exit(f"{name} must be required; no workspace or approval fallback is allowed")

deployments = [
    resource
    for resource in template.get("resources", [])
    if resource.get("type") == "Microsoft.Resources/deployments"
]
if len(deployments) != 1:
    sys.exit(f"expected one observability module deployment, found {len(deployments)}")

nested = deployments[0].get("properties", {}).get("template", {})
resources = nested.get("resources", [])
components = [
    resource
    for resource in resources
    if resource.get("type") == "Microsoft.Insights/components"
]
if len(components) != 1:
    sys.exit(f"agent observability must create exactly one Application Insights component, found {len(components)}")
if any(
    resource.get("type") == "Microsoft.OperationalInsights/workspaces"
    for resource in resources
):
    sys.exit("agent observability must not create a Log Analytics workspace")
if any(
    resource.get("type", "").startswith("Microsoft.ApiManagement/")
    for resource in resources
):
    sys.exit("agent observability must not modify APIM or its telemetry logger")

properties = components[0].get("properties", {})
if properties.get("WorkspaceResourceId") != "[reference(resourceId('Microsoft.OperationalInsights/workspaces', variables('workspaceParts')[8]), '2023-09-01').id]":
    serialized = json.dumps(properties.get("WorkspaceResourceId", ""))
    if "Microsoft.OperationalInsights/workspaces" not in serialized:
        sys.exit("agent Application Insights must bind to the supplied existing workspace")

outputs = template.get("outputs", {})
for name in ("agentApplicationInsightsId", "agentWorkspaceResourceId", "apimApplicationInsightsId"):
    if name not in outputs:
        sys.exit(f"agent observability is missing telemetry-boundary output {name}")

print("Agent observability workspace and APIM separation contracts passed.")
PY
