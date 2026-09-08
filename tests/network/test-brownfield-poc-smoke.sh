#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

NETWORK_ENTRY="${REPO_ROOT}/infra/envs/poc/brownfield-network.bicep"
DNS_ENTRY="${REPO_ROOT}/infra/envs/poc/brownfield-dns.bicep"
SUBNETS_MODULE="${REPO_ROOT}/infra/modules/network/subnets.bicep"
DNS_LINK_MODULE="${REPO_ROOT}/infra/modules/network/private-dns-link.bicep"
NETWORK_PARAM_EXAMPLE="${REPO_ROOT}/infra/envs/poc/brownfield-network.bicepparam.example"
DNS_PARAM_EXAMPLE="${REPO_ROOT}/infra/envs/poc/brownfield-dns.bicepparam.example"

command -v az >/dev/null 2>&1 || {
  echo "SKIP: az CLI not available; cannot run bicep build checks." >&2
  exit 0
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> az bicep build: brownfield-network.bicep"
az bicep build --file "$NETWORK_ENTRY" --stdout >"$workdir/network.json" 2>"$workdir/network.err"
if [[ ! -s "$workdir/network.json" ]]; then
  echo "FAIL: brownfield-network.bicep produced no compiled output" >&2
  cat "$workdir/network.err" >&2
  exit 1
fi

echo "==> az bicep build: brownfield-dns.bicep"
az bicep build --file "$DNS_ENTRY" --stdout >"$workdir/dns.json" 2>"$workdir/dns.err"
if [[ ! -s "$workdir/dns.json" ]]; then
  echo "FAIL: brownfield-dns.bicep produced no compiled output" >&2
  cat "$workdir/dns.err" >&2
  exit 1
fi

echo "==> subnets.bicep: serialized writes, no VNet mutation"
if ! grep -q '@batchSize(1)' "$SUBNETS_MODULE"; then
  echo "FAIL: subnets.bicep must serialize subnet writes with @batchSize(1)" >&2
  exit 1
fi
if grep -q 'addressSpace' "$SUBNETS_MODULE"; then
  echo "FAIL: subnets.bicep must not declare or write the existing VNet's addressSpace" >&2
  exit 1
fi
if ! grep -Eq "resource vnet 'Microsoft.Network/virtualNetworks@[^']+' existing" "$SUBNETS_MODULE"; then
  echo "FAIL: subnets.bicep must reference the VNet as 'existing' only" >&2
  exit 1
fi

echo "==> private-dns-link.bicep: link-only, registration disabled"
if ! grep -q 'registrationEnabled: false' "$DNS_LINK_MODULE"; then
  echo "FAIL: private-dns-link.bicep must fix registrationEnabled to false" >&2
  exit 1
fi
if ! grep -Eq "resource zone 'Microsoft.Network/privateDnsZones@[^']+' existing" "$DNS_LINK_MODULE"; then
  echo "FAIL: private-dns-link.bicep must reference the DNS zone as 'existing' only" >&2
  exit 1
fi

echo "==> .bicepparam.example files contain placeholders only"
placeholder_pattern="^param [A-Za-z][A-Za-z0-9]* = ('<[^']*>'|''|true|false)\$"
for example in "$NETWORK_PARAM_EXAMPLE" "$DNS_PARAM_EXAMPLE"; do
  while IFS= read -r line; do
    if [[ "$line" =~ ^param\  ]] && ! [[ "$line" =~ $placeholder_pattern ]]; then
      echo "FAIL: $(basename "$example") contains a non-placeholder param value: $line" >&2
      exit 1
    fi
  done <"$example"
done

echo "==> .bicepparam.example files compile once placeholders are filled"
network_tmp_param="${REPO_ROOT}/infra/envs/poc/.tmp-brownfield-network-smoketest.bicepparam"
dns_tmp_param="${REPO_ROOT}/infra/envs/poc/.tmp-brownfield-dns-smoketest.bicepparam"
cleanup_tmp_params() {
  rm -f "$network_tmp_param" "$dns_tmp_param"
}
trap 'cleanup_tmp_params; rm -rf "$workdir"' EXIT

sed \
  -e "s/<existing-vnet-name>/vnet-example/" \
  -e "s/<existing-vnet-resource-group>/rg-example-network/" \
  -e "s/<region>/eastus2/" \
  -e "s/<admin-approved-cidr>/10.0.0.0\/28/" \
  "$NETWORK_PARAM_EXAMPLE" >"$network_tmp_param"
az bicep build-params --file "$network_tmp_param" --stdout >/dev/null 2>"$workdir/network-params.err"
if [[ -s "$workdir/network-params.err" ]] && grep -qi error "$workdir/network-params.err"; then
  echo "FAIL: filled-in brownfield-network.bicepparam.example does not compile" >&2
  cat "$workdir/network-params.err" >&2
  exit 1
fi

sed \
  -e "s#<dns-zone-resource-group>#rg-example-dns#" \
  -e "s#<full-arm-resource-id-of-existing-vnet>#/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example-network/providers/Microsoft.Network/virtualNetworks/vnet-example#" \
  -e "s#<existing-vnet-name>#vnet-example#" \
  "$DNS_PARAM_EXAMPLE" >"$dns_tmp_param"
az bicep build-params --file "$dns_tmp_param" --stdout >/dev/null 2>"$workdir/dns-params.err"
if [[ -s "$workdir/dns-params.err" ]] && grep -qi error "$workdir/dns-params.err"; then
  echo "FAIL: filled-in brownfield-dns.bicepparam.example does not compile" >&2
  cat "$workdir/dns-params.err" >&2
  exit 1
fi

cleanup_tmp_params

echo "Brownfield network foundation POC smoke tests passed."
