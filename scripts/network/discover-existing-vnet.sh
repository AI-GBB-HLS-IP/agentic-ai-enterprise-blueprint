#!/usr/bin/env bash
set -euo pipefail

# Read-only discovery of an existing (admin-provided) VNet for brownfield deployments.
# Emits a single JSON document consumed by scripts/network/generate-brownfield-params.sh.
#
# This script only issues `az ... show/list` calls. It creates, modifies, and deletes nothing.
# Its output contains subscription-specific values: keep it untracked. The default output path
# matches the `**/network-discovery-*.json` .gitignore rule.

usage() {
  cat >&2 <<'EOF'
Usage: discover-existing-vnet.sh --resource-group <rg> --vnet <name> [options]

Options:
  --resource-group, -g <rg>   Resource group holding the existing VNet (required)
  --vnet, -n <name>           Existing VNet name (required)
  --subscription <id>         Subscription to query (defaults to the current az context)
  --dns-resource-group <rg>   Also inventory private DNS zones in this resource group
  --output, -o <path>         Output file (default: ./network-discovery-<vnet>.json)
  --stdout                    Write JSON to stdout instead of a file
  -h, --help                  Show this help

All operations are read-only. Never commit the output.
EOF
}

resource_group=""
vnet_name=""
subscription=""
dns_resource_group=""
output_path=""
to_stdout="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group|-g)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      resource_group="$2"; shift 2 ;;
    --vnet|-n)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      vnet_name="$2"; shift 2 ;;
    --subscription)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      subscription="$2"; shift 2 ;;
    --dns-resource-group)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      dns_resource_group="$2"; shift 2 ;;
    --output|-o)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      output_path="$2"; shift 2 ;;
    --stdout)
      to_stdout="true"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$resource_group" || -z "$vnet_name" ]]; then
  echo "Both --resource-group and --vnet are required." >&2
  usage
  exit 1
fi

for tool in az python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Required tool not found: $tool" >&2; exit 1; }
done

az_args=(--only-show-errors -o json)
if [[ -n "$subscription" ]]; then
  az_args+=(--subscription "$subscription")
fi

echo "Discovering ${vnet_name} in resource group ${resource_group} (read-only)..." >&2

vnet_json="$(az network vnet show -g "$resource_group" -n "$vnet_name" "${az_args[@]}")"
subnets_json="$(az network vnet subnet list -g "$resource_group" --vnet-name "$vnet_name" "${az_args[@]}")"
peerings_json="$(az network vnet peering list -g "$resource_group" --vnet-name "$vnet_name" "${az_args[@]}")"

dns_json="[]"
if [[ -n "$dns_resource_group" ]]; then
  dns_json="$(az network private-dns zone list -g "$dns_resource_group" "${az_args[@]}")"
fi

# Pass large `az` JSON payloads via temp files instead of argv: real-world VNets with many
# subnets/NSGs/peerings can produce output that exceeds the OS ARG_MAX limit when passed
# directly as command-line arguments (causing "Argument list too long").
work_dir="$(mktemp -d 2>/dev/null || mktemp -d -t discover-existing-vnet)"
[[ -n "$work_dir" ]] || { echo "Failed to create temp directory" >&2; exit 1; }
trap 'rm -rf "$work_dir"' EXIT
printf '%s' "$vnet_json" > "$work_dir/vnet.json"
printf '%s' "$subnets_json" > "$work_dir/subnets.json"
printf '%s' "$peerings_json" > "$work_dir/peerings.json"
printf '%s' "$dns_json" > "$work_dir/dns.json"

document="$(python3 - "$work_dir/vnet.json" "$work_dir/subnets.json" "$work_dir/peerings.json" "$work_dir/dns.json" "$dns_resource_group" <<'PY'
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


vnet = load(sys.argv[1])
subnets = load(sys.argv[2])
peerings = load(sys.argv[3])
zones = load(sys.argv[4])
dns_rg = sys.argv[5]


def resource_group_of(resource_id):
    if not resource_id:
        return None
    parts = resource_id.split("/")
    for index, part in enumerate(parts):
        if part.lower() == "resourcegroups" and index + 1 < len(parts):
            return parts[index + 1]
    return None


document = {
    "schemaVersion": "1.0",
    "vnet": {
        "id": vnet.get("id"),
        "name": vnet.get("name"),
        "resourceGroup": vnet.get("resourceGroup") or resource_group_of(vnet.get("id")),
        "location": vnet.get("location"),
        "addressPrefixes": (vnet.get("addressSpace") or {}).get("addressPrefixes") or [],
        "dnsServers": (vnet.get("dhcpOptions") or {}).get("dnsServers") or [],
        "ddosProtectionEnabled": bool(vnet.get("enableDdosProtection")),
    },
    "subnets": [
        {
            "name": subnet.get("name"),
            "addressPrefix": subnet.get("addressPrefix"),
            "addressPrefixes": subnet.get("addressPrefixes") or [],
            "networkSecurityGroupId": (subnet.get("networkSecurityGroup") or {}).get("id"),
            "routeTableId": (subnet.get("routeTable") or {}).get("id"),
            "natGatewayId": (subnet.get("natGateway") or {}).get("id"),
            "delegations": [
                (delegation.get("serviceName") or "")
                for delegation in (subnet.get("delegations") or [])
            ],
            "serviceEndpoints": [
                (endpoint.get("service") or "")
                for endpoint in (subnet.get("serviceEndpoints") or [])
            ],
            "privateEndpointNetworkPolicies": subnet.get("privateEndpointNetworkPolicies"),
        }
        for subnet in subnets
    ],
    "peerings": [
        {
            "name": peering.get("name"),
            "peeringState": peering.get("peeringState"),
            "allowForwardedTraffic": peering.get("allowForwardedTraffic"),
            "useRemoteGateways": peering.get("useRemoteGateways"),
        }
        for peering in peerings
    ],
    "privateDnsZones": [
        {
            "name": zone.get("name"),
            "resourceGroup": dns_rg or zone.get("resourceGroup"),
            "virtualNetworkLinks": zone.get("numberOfVirtualNetworkLinks"),
        }
        for zone in zones
    ],
}

print(json.dumps(document, indent=2))
PY
)"

if [[ "$to_stdout" == "true" ]]; then
  printf '%s\n' "$document"
  exit 0
fi

if [[ -z "$output_path" ]]; then
  output_path="./network-discovery-${vnet_name}.json"
fi

printf '%s\n' "$document" > "$output_path"
chmod 600 "$output_path" 2>/dev/null || true

echo "Discovery written to ${output_path} (untracked — do not commit)." >&2
echo "Next: ./scripts/network/generate-brownfield-params.sh --discovery ${output_path}" >&2
