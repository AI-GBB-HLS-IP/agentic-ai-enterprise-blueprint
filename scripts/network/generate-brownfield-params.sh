#!/usr/bin/env bash
set -euo pipefail

# Generates reviewable brownfield .bicepparam files from read-only VNet discovery output.
#
# Input : the JSON produced by scripts/network/discover-existing-vnet.sh
# Output: infra/envs/poc/brownfield-network.bicepparam, brownfield-dns.bicepparam, and
#         brownfield-foundry.bicepparam (all git-ignored), plus a human-readable allocation
#         report on stdout.
#
# The generated files are a PROPOSAL. Review them, get IPAM approval for the CIDRs, and run
# `az deployment group what-if` before deploying. This script deploys nothing.

usage() {
  cat >&2 <<'EOF'
Usage: generate-brownfield-params.sh --discovery <discovery.json> [options]

Address plan:
  --block <cidr>                 Use this exact free block instead of auto-selecting one
  --block-size <n>               Prefix length of the block to auto-select (default: 25).
                                 Minimum viable is /25: foundry /27 + APIM /27 +
                                 private endpoints /28 + merged compute/CI/CD /28,
                                 leaving one /27 spare.
  --name-prefix <prefix>         Subnet name prefix (default: hybridsubnet)
  --location <region>            Override the location from discovery

NSG mode (choose one; default is blueprint-owned):
  --shared-hybrid-nsg-id <id>    Mode 1: associate one existing NSG with all four subnets
  --reuse-existing-nsgs          Mode 2: reuse per-purpose NSGs (requires the two IDs below)
  --existing-apim-nsg-id <id>
  --existing-compute-nsg-id <id>

Other:
  --dns-integration-mode <mode>  Required: vnet-link | zone-group
  --dns-subscription-id <id>     Subscription holding the private DNS zones; required for
                                 zone-group mode
  --private-endpoints-network-policies <value>
                                 Disabled (default) | Enabled | NetworkSecurityGroupEnabled |
                                 RouteTableEnabled
  --dns-resource-group <rg>      Resource group holding the private DNS zones
  --out-dir <dir>                Output directory (default: infra/envs/poc)
  --allow-name-collision         Downgrade existing-subnet-name collisions to warnings
  --force                        Overwrite existing generated parameter files
  --dry-run                      Print the proposal without writing files
  -h, --help                     Show this help

The generated .bicepparam files contain subscription-specific values and are git-ignored.
EOF
}

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

discovery=""
block=""
block_size="25"
name_prefix="hybridsubnet"
location=""
shared_nsg_id=""
reuse_existing_nsgs="false"
existing_apim_nsg_id=""
existing_compute_nsg_id=""
pe_policies="Disabled"
dns_resource_group=""
dns_integration_mode=""
dns_subscription_id=""
out_dir="${REPO_ROOT}/infra/envs/poc"
allow_name_collision="false"
force="false"
dry_run="false"

require_value() {
  [[ $2 -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --discovery) require_value "$1" $#; discovery="$2"; shift 2 ;;
    --block) require_value "$1" $#; block="$2"; shift 2 ;;
    --block-size) require_value "$1" $#; block_size="$2"; shift 2 ;;
    --name-prefix) require_value "$1" $#; name_prefix="$2"; shift 2 ;;
    --location) require_value "$1" $#; location="$2"; shift 2 ;;
    --shared-hybrid-nsg-id) require_value "$1" $#; shared_nsg_id="$2"; shift 2 ;;
    --reuse-existing-nsgs) reuse_existing_nsgs="true"; shift ;;
    --existing-apim-nsg-id) require_value "$1" $#; existing_apim_nsg_id="$2"; shift 2 ;;
    --existing-compute-nsg-id) require_value "$1" $#; existing_compute_nsg_id="$2"; shift 2 ;;
    --private-endpoints-network-policies) require_value "$1" $#; pe_policies="$2"; shift 2 ;;
    --dns-integration-mode) require_value "$1" $#; dns_integration_mode="$2"; shift 2 ;;
    --dns-subscription-id) require_value "$1" $#; dns_subscription_id="$2"; shift 2 ;;
    --dns-resource-group) require_value "$1" $#; dns_resource_group="$2"; shift 2 ;;
    --out-dir) require_value "$1" $#; out_dir="$2"; shift 2 ;;
    --allow-name-collision) allow_name_collision="true"; shift ;;
    --force) force="true"; shift ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$discovery" ]]; then
  echo "--discovery is required." >&2
  usage
  exit 1
fi

if [[ ! -f "$discovery" ]]; then
  echo "Discovery file not found: $discovery" >&2
  exit 1
fi

if [[ -z "$dns_integration_mode" ]]; then
  echo "--dns-integration-mode is required and must be one of: vnet-link, zone-group." >&2
  exit 1
fi

if [[ "$dns_integration_mode" != "vnet-link" && "$dns_integration_mode" != "zone-group" ]]; then
  echo "--dns-integration-mode must be one of: vnet-link, zone-group." >&2
  exit 1
fi

if [[ "$dns_integration_mode" == "zone-group" ]]; then
  if [[ -z "$dns_subscription_id" || -z "$dns_resource_group" ]]; then
    echo "--dns-integration-mode zone-group requires both --dns-subscription-id and --dns-resource-group." >&2
    exit 1
  fi
fi

command -v python3 >/dev/null 2>&1 || { echo "Required tool not found: python3" >&2; exit 1; }

CONFIG="$(python3 - "$block" "$block_size" "$name_prefix" "$location" "$shared_nsg_id" \
  "$reuse_existing_nsgs" "$existing_apim_nsg_id" "$existing_compute_nsg_id" "$pe_policies" \
  "$dns_integration_mode" "$dns_subscription_id" "$dns_resource_group" "$out_dir" \
  "$allow_name_collision" "$force" "$dry_run" <<'PY'
import json
import sys

keys = [
    "block", "blockSize", "namePrefix", "location", "sharedHybridNsgId",
    "reuseExistingNsgs", "existingApimNsgId", "existingComputeNsgId",
    "privateEndpointsNetworkPolicies", "dnsIntegrationMode", "dnsSubscriptionId",
    "dnsResourceGroup", "outDir",
    "allowNameCollision", "force", "dryRun",
]
print(json.dumps(dict(zip(keys, sys.argv[1:]))))
PY
)"

python3 - "$discovery" "$CONFIG" "$REPO_ROOT" <<'PY'
import ipaddress
import json
import os
import sys

discovery_path = sys.argv[1]
config = json.loads(sys.argv[2])
repo_root = sys.argv[3]


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    with open(discovery_path, encoding="utf-8") as handle:
        discovery = json.load(handle)
except json.JSONDecodeError as exc:
    fail(f"discovery file is not valid JSON: {exc}")

if not isinstance(discovery, dict):
    fail("discovery file must contain a JSON object.")

vnet = discovery.get("vnet")
if not isinstance(vnet, dict):
    fail("discovery file is missing the 'vnet' object.")

vnet_name = vnet.get("name")
vnet_rg = vnet.get("resourceGroup")
vnet_id = vnet.get("id")
location = config["location"] or vnet.get("location")

if not vnet_name:
    fail("discovery file is missing vnet.name.")
if not vnet_rg:
    fail("discovery file is missing vnet.resourceGroup.")
if not location:
    fail("discovery file is missing vnet.location; pass --location.")

if config["dnsIntegrationMode"] == "vnet-link":
    if config["dnsSubscriptionId"]:
        fail("--dns-subscription-id is not supported in vnet-link mode; use zone-group for cross-subscription DNS.")
    if config["dnsResourceGroup"] and config["dnsResourceGroup"].lower() != vnet_rg.lower():
        fail("--dns-resource-group must match the VNet resource group in vnet-link mode; use zone-group for a separate DNS scope.")

address_prefixes = vnet.get("addressPrefixes") or []
if not address_prefixes:
    fail("discovery file lists no VNet address prefixes.")

try:
    vnet_networks = [ipaddress.ip_network(prefix, strict=False) for prefix in address_prefixes]
except ValueError as exc:
    fail(f"invalid VNet address prefix in discovery file: {exc}")

vnet_networks = [network for network in vnet_networks if network.version == 4]
if not vnet_networks:
    fail("no IPv4 address prefix found on the VNet; this blueprint requires IPv4 space.")

subnets = discovery.get("subnets") or []
used_networks = []
for subnet in subnets:
    prefixes = [subnet.get("addressPrefix")] + list(subnet.get("addressPrefixes") or [])
    for prefix in prefixes:
        if not prefix:
            continue
        try:
            network = ipaddress.ip_network(prefix, strict=False)
        except ValueError as exc:
            name = subnet.get("name") or "<unknown>"
            fail(f"invalid subnet address prefix in discovery file for subnet '{name}': {prefix} ({exc})")
        if network.version == 4:
            used_networks.append((subnet.get("name"), network))

# ---------------------------------------------------------------------------------------------
# Address plan. A /25 supplies fixed POC minimums: foundry /27, APIM stv2 /27, private
# endpoints /28, and one merged compute/CI/CD agents /28. The final /27 remains spare.
#
# RECOMMENDED_BLOCK_PREFIX is the default and the size to prefer whenever the VNet has the room.
# MIN_VIABLE_BLOCK_PREFIX is the hard floor because Foundry and APIM each require a /27, while
# private endpoints and the merged compute/CI/CD workload each require a /28.
# ---------------------------------------------------------------------------------------------
RECOMMENDED_BLOCK_PREFIX = 25
MIN_VIABLE_BLOCK_PREFIX = 25
MAX_BLOCK_PREFIX = MIN_VIABLE_BLOCK_PREFIX

def free_blocks(networks, used_list):
    """Address space in `networks` not covered by `used_list`, largest first."""
    remaining = list(networks)
    for used in used_list:
        next_remaining = []
        for net in remaining:
            if not net.overlaps(used):
                next_remaining.append(net)
                continue
            if net.subnet_of(used):
                continue
            if used.subnet_of(net):
                next_remaining.extend(net.address_exclude(used))
            elif net.prefixlen < 32:
                next_remaining.extend(net.subnets())
        remaining = next_remaining
    collapsed = list(ipaddress.collapse_addresses(remaining))
    return sorted(collapsed, key=lambda net: (net.prefixlen, int(net.network_address)))


if config["block"]:
    try:
        chosen = ipaddress.ip_network(config["block"], strict=True)
    except ValueError as exc:
        fail(f"--block is not a valid, correctly aligned CIDR: {exc}")
    if chosen.version != 4:
        fail("--block must be an IPv4 CIDR.")
    if chosen.prefixlen > MAX_BLOCK_PREFIX:
        fail(
            f"--block {chosen} is too small: /{MIN_VIABLE_BLOCK_PREFIX} or larger is required so "
            "the foundry and APIM stv2 subnets each meet their /27 platform minimum, with /28 "
            "subnets for private endpoints and merged compute/CI/CD agents."
        )
    if not any(chosen.subnet_of(network) for network in vnet_networks):
        fail(f"--block {chosen} is not contained in any VNet address prefix {address_prefixes}.")
    overlaps = [name for name, network in used_networks if chosen.overlaps(network)]
    if overlaps:
        fail(f"--block {chosen} overlaps existing subnet(s): {', '.join(sorted(set(overlaps)))}.")
    auto_selected = False
else:
    try:
        block_size = int(config["blockSize"])
    except ValueError:
        fail("--block-size must be an integer.")
    if not 8 <= block_size <= MAX_BLOCK_PREFIX:
        fail(
            f"--block-size must be between 8 and {MAX_BLOCK_PREFIX} (the minimum viable block; "
            f"{RECOMMENDED_BLOCK_PREFIX} is recommended whenever the VNet has the room)."
        )

    chosen = None
    for network in sorted(vnet_networks, key=lambda item: int(item.network_address)):
        if network.prefixlen > block_size:
            continue
        for candidate in network.subnets(new_prefix=block_size):
            if any(candidate.overlaps(used) for _, used in used_networks):
                continue
            chosen = candidate
            break
        if chosen is not None:
            break
    if chosen is None:
        available = free_blocks(vnet_networks, [network for _, network in used_networks])
        if available:
            largest = ", ".join(str(net) for net in available[:5])
            hint = (
                f"Largest free ranges in this VNet: {largest}. If one of them is at least a "
                f"/{MIN_VIABLE_BLOCK_PREFIX}, pass it with --block-size {MIN_VIABLE_BLOCK_PREFIX} "
                "or --block (this yields /27 foundry + /27 APIM + /28 private endpoints + "
                "/28 merged compute/CI/CD agents); "
                "otherwise ask the network admin to extend the VNet address space or hand you a "
                "larger allocation."
            )
        else:
            hint = (
                "The VNet address space is fully allocated — ask the network admin to extend it "
                "or hand you an allocation."
            )
        fail(f"no free /{block_size} block found in {address_prefixes}. {hint}")
    auto_selected = True

minimum_blocks = chosen.subnets(new_prefix=27)
foundry_net = next(minimum_blocks)
apim_net = next(minimum_blocks)
support_net = next(minimum_blocks)
support_subnets = support_net.subnets(new_prefix=28)
private_endpoints_net = next(support_subnets)
compute_net = next(support_subnets)

prefix = config["namePrefix"].rstrip("-")
plan = [
    ("foundry", f"{prefix}-foundry", foundry_net, "Delegated to Microsoft.App/environments; platform minimum /27"),
    ("apim", f"{prefix}-apim", apim_net, "APIM Premium SKU on confirmed stv2 platform; minimum /27"),
    ("privateendpoints", f"{prefix}-privateendpoints", private_endpoints_net, "Private endpoints; 5 Azure-reserved addresses"),
    ("compute", f"{prefix}-compute", compute_net, "Merged compute and CI/CD agents; 5 Azure-reserved addresses"),
]

MINIMUM_PREFIX = {"foundry": 27, "apim": 27}
for key, name, network, _ in plan:
    minimum = MINIMUM_PREFIX.get(key, 29)
    if network.prefixlen > minimum:
        fail(
            f"{name} would be {network} (/{network.prefixlen}), smaller than the platform "
            f"minimum /{minimum}. Use a larger --block or --block-size."
        )

# ---------------------------------------------------------------------------------------------
# Safety findings. A subnet PUT replaces the whole object, so writing into an existing subnet
# name silently removes its route table, service endpoints, and NAT gateway.
# ---------------------------------------------------------------------------------------------
existing_by_name = {subnet.get("name"): subnet for subnet in subnets if subnet.get("name")}
blocking = []
warnings = []

for _, name, network, _ in plan:
    existing = existing_by_name.get(name)
    if existing is None:
        continue
    lost = [
        label
        for label, value in (
            ("route table (UDR)", existing.get("routeTableId")),
            ("NAT gateway", existing.get("natGatewayId")),
            ("service endpoints", existing.get("serviceEndpoints")),
        )
        if value
    ]
    detail = f"subnet name '{name}' already exists in {vnet_name}"
    if lost:
        detail += f"; deploying would REMOVE its {', '.join(lost)}"
    (warnings if config["allowNameCollision"] == "true" else blocking).append(detail)

if blocking:
    for item in blocking:
        print(f"COLLISION: {item}", file=sys.stderr)
    fail(
        "requested subnet names collide with existing subnets. Rename with --name-prefix, or "
        "pass --allow-name-collision only if you own those subnets."
    )

# ---------------------------------------------------------------------------------------------
# NSG mode resolution.
# ---------------------------------------------------------------------------------------------
shared_nsg_id = config["sharedHybridNsgId"]
reuse = config["reuseExistingNsgs"] == "true"
apim_nsg_id = config["existingApimNsgId"]
compute_nsg_id = config["existingComputeNsgId"]

if shared_nsg_id:
    nsg_mode = "1 - shared hybrid NSG (associated with all four subnets; none created)"
    if reuse or apim_nsg_id or compute_nsg_id:
        warnings.append(
            "--shared-hybrid-nsg-id overrides --reuse-existing-nsgs and the per-purpose NSG IDs."
        )
        reuse = False
        apim_nsg_id = ""
        compute_nsg_id = ""
elif reuse:
    if not apim_nsg_id or not compute_nsg_id:
        fail(
            "--reuse-existing-nsgs requires both --existing-apim-nsg-id and "
            "--existing-compute-nsg-id."
        )
    nsg_mode = "2 - per-purpose existing NSGs on the APIM and compute subnets"
else:
    nsg_mode = "3 - blueprint-owned NSGs created for the APIM and compute subnets"

allowed_policies = {"Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"}
pe_policies = config["privateEndpointsNetworkPolicies"]
if pe_policies not in allowed_policies:
    fail(
        "--private-endpoints-network-policies must be one of: "
        + ", ".join(sorted(allowed_policies))
    )

for name, network in used_networks:
    if any(network.overlaps(item[2]) for item in plan):
        fail(f"internal error: proposed allocation overlaps existing subnet '{name}' ({network}).")

if not vnet_id:
    warnings.append("discovery file has no vnet.id; the generated DNS parameter file keeps a placeholder.")

dns_mode = config["dnsIntegrationMode"]
requested_dns_subscription_id = config["dnsSubscriptionId"]
dns_subscription_id = requested_dns_subscription_id
dns_rg = config["dnsResourceGroup"]
if not dns_subscription_id and vnet_id:
    vnet_id_parts = vnet_id.strip("/").split("/")
    if len(vnet_id_parts) >= 2 and vnet_id_parts[0].lower() == "subscriptions":
        dns_subscription_id = vnet_id_parts[1]
if not dns_rg:
    warnings.append(
        "no --dns-resource-group given; fill in dnsResourceGroupName in the DNS parameter file."
    )


def bicep_string(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


out_dir = config["outDir"]
templates_dir = os.path.join(repo_root, "infra", "envs", "poc")
rel_templates_dir = os.path.relpath(templates_dir, out_dir)


def template_using_path(filename):
    rel_path = os.path.join(rel_templates_dir, filename).replace(os.sep, "/")
    if not rel_path.startswith(("./", "../")):
        rel_path = "./" + rel_path
    return rel_path


network_bicep_path = template_using_path("brownfield-network.bicep")
dns_bicep_path = template_using_path("brownfield-dns.bicep")
foundry_bicep_path = template_using_path("foundry.bicep")

header = f"""using '{network_bicep_path}'

// GENERATED by scripts/network/generate-brownfield-params.sh from read-only VNet discovery.
// This is a PROPOSAL for human review, not an approved allocation.
//
//   VNet            : {vnet_name} (resource group {vnet_rg})
//   VNet space      : {', '.join(address_prefixes)}
//   Allocated block : {chosen} ({'auto-selected first free block' if auto_selected else 'operator supplied'})
//   NSG mode        : {nsg_mode}
//
// Before deploying: confirm the block with IPAM, confirm no subnet name collides, and review
// `az deployment group what-if` output line by line. See docs/deploy-00-network.md section 5.
//
// This file contains environment-specific values and is git-ignored. Never commit it.
"""

lines = [header]
lines.append(f"param existingVnetName = {bicep_string(vnet_name)}")
lines.append(f"param existingVnetResourceGroupName = {bicep_string(vnet_rg)}")
lines.append(f"param location = {bicep_string(location)}")
lines.append("")
lines.append("// Subnet names and admin-approved CIDRs.")
for key, name, network, rationale in plan:
    camel = {"privateendpoints": "privateEndpoints", "cicdagents": "cicdAgents"}.get(key, key)
    usable = network.num_addresses - 5
    lines.append(f"// {name}: {network} - {usable} usable addresses. {rationale}")
    lines.append(f"param {camel}SubnetName = {bicep_string(name)}")
    lines.append(f"param {camel}SubnetPrefix = {bicep_string(str(network))}")
lines.append("")
lines.append(f"// NSG mode {nsg_mode}")
lines.append(f"param sharedHybridNsgId = {bicep_string(shared_nsg_id)}")
lines.append(f"param reuseExistingNsgs = {'true' if reuse else 'false'}")
lines.append(f"param existingApimNsgId = {bicep_string(apim_nsg_id)}")
lines.append(f"param existingComputeNsgId = {bicep_string(compute_nsg_id)}")
lines.append("")
lines.append(f"param privateEndpointsNetworkPolicies = {bicep_string(pe_policies)}")
network_param_text = "\n".join(lines) + "\n"

dns_param_text = f"""using '{dns_bicep_path}'

// GENERATED by scripts/network/generate-brownfield-params.sh. Review before deploying.
// Deploy once per DNS-owner resource group scope. This file is git-ignored; never commit it.

param dnsIntegrationMode = {bicep_string(dns_mode)}
param dnsSubscriptionId = {bicep_string(dns_subscription_id) if dns_subscription_id else "'<dns-zone-subscription-id>'"}
param dnsResourceGroupName = {bicep_string(dns_rg) if dns_rg else "'<dns-zone-resource-group>'"}
param vnetId = {bicep_string(vnet_id) if vnet_id else "'<full-arm-resource-id-of-existing-vnet>'"}
param vnetName = {bicep_string(vnet_name)}
param privateDnsZoneNames = {{
  cognitiveServices: 'privatelink.cognitiveservices.azure.com'
  azureOpenAI: 'privatelink.openai.azure.com'
  keyVault: 'privatelink.vaultcore.azure.net'
  storageBlob: 'privatelink.blob.core.windows.net'
  cosmosDB: 'privatelink.documents.azure.com'
  aiSearch: 'privatelink.search.windows.net'
}}
"""

foundry_param_text = f"""using '{foundry_bicep_path}'

// GENERATED by scripts/network/generate-brownfield-params.sh for a brownfield deployment.
// This file is git-ignored; never commit it.

param location = {bicep_string(location)}
param networkResourceGroupName = {bicep_string(vnet_rg)}
param dnsIntegrationMode = {bicep_string(dns_mode)}
param dnsSubscriptionId = {bicep_string(requested_dns_subscription_id) if requested_dns_subscription_id else "''"}
param dnsResourceGroupName = {bicep_string(dns_rg) if dns_rg else "''"}
param vnetName = {bicep_string(vnet_name)}
param foundrySubnetName = {bicep_string(plan[0][1])}
param privateEndpointSubnetName = {bicep_string(plan[2][1])}
"""

network_path = os.path.join(out_dir, "brownfield-network.bicepparam")
dns_path = os.path.join(out_dir, "brownfield-dns.bicepparam")
foundry_path = os.path.join(out_dir, "brownfield-foundry.bicepparam")

print("Proposed brownfield allocation")
print(f"  VNet             : {vnet_name} (resource group {vnet_rg})")
print(f"  Location         : {location}")
print(f"  VNet space       : {', '.join(address_prefixes)}")
print(f"  Existing subnets : {len(subnets)}")
print(f"  Allocated block  : {chosen} ({'auto-selected' if auto_selected else 'operator supplied'})")
print(f"  NSG mode         : {nsg_mode}")
print(f"  DNS mode         : {dns_mode}")
print()
print(f"  {'SUBNET':<40} {'CIDR':<20} USABLE")
for _, name, network, _ in plan:
    print(f"  {name:<40} {str(network):<20} {network.num_addresses - 5}")
print()

for warning in warnings:
    print(f"WARNING: {warning}", file=sys.stderr)

if config["dryRun"] == "true":
    print("--- brownfield-network.bicepparam (dry run) ---")
    print(network_param_text)
    print("--- brownfield-dns.bicepparam (dry run) ---")
    print(dns_param_text)
    print("--- brownfield-foundry.bicepparam (dry run) ---")
    print(foundry_param_text)
    raise SystemExit(0)

if not os.path.isdir(out_dir):
    fail(f"output directory does not exist: {out_dir}")

for path in (network_path, dns_path, foundry_path):
    if os.path.exists(path) and config["force"] != "true":
        fail(f"{path} already exists. Re-run with --force to overwrite.")

with open(network_path, "w", encoding="utf-8") as handle:
    handle.write(network_param_text)
with open(dns_path, "w", encoding="utf-8") as handle:
    handle.write(dns_param_text)
with open(foundry_path, "w", encoding="utf-8") as handle:
    handle.write(foundry_param_text)

print(f"Wrote {network_path}")
print(f"Wrote {dns_path}")
print(f"Wrote {foundry_path}")
print()
print("Review all three files, obtain IPAM approval for the CIDRs, then run `az deployment group")
print("what-if` as described in docs/deploy-00-network.md sections 5.4 and 5.5.")
PY
