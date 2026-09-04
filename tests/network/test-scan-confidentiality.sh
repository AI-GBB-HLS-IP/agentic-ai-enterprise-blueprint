#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/network/scan-confidentiality.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
counter=0
subscription_guid='7f3a91c2-4b8e-4d15-''9a67-2c5e8b0d4f1a'
tenant_guid='4d2c8a17-9e30-41b6-''8f52-0ab7c9d13e64'
owner_email='network.owner''@northwind-industries.io'
tenant_email='testuser.sample''@MngEnvSample123456.onmicrosoft.com'
home_path='/home/''engineer1/vnet-discovery.json'
windows_path='C:\Users\''engineer1\discovery'
hub_cidr='172.21.''48.0/20'
outside_cidr='10.240.''12.0/22'

assert_fails() {
  local description="$1"
  local body="$2"
  counter=$((counter + 1))
  local path="${workdir}/reject-${counter}.txt"

  printf '%s\n' "$body" >"$path"
  if "$VALIDATOR" "$path" >"${workdir}/out" 2>&1; then
    echo "FAIL: expected rejection of ${description}" >&2
    cat "${workdir}/out" >&2
    exit 1
  fi
}

assert_passes() {
  local description="$1"
  local body="$2"
  counter=$((counter + 1))
  local path="${workdir}/allow-${counter}.txt"

  printf '%s\n' "$body" >"$path"
  if ! "$VALIDATOR" "$path" >"${workdir}/out" 2>&1; then
    echo "FAIL: expected ${description} to be allowed" >&2
    cat "${workdir}/out" >&2
    exit 1
  fi
}

# --- Prohibited disclosure ---------------------------------------------------

assert_fails "subscription GUID" \
  "subscriptionId: ${subscription_guid}"

assert_fails "tenant GUID" \
  "tenantId = ${tenant_guid}"

assert_fails "resolved ARM resource ID" \
  "id: /subscriptions/${subscription_guid}/resourceGroups/rg-shared-network"

assert_fails "real email address" \
  "approver: ${owner_email}"

assert_fails "onmicrosoft tenant identity" \
  "signed in as ${tenant_email}"

assert_fails "absolute home path" \
  "discovery written to ${home_path}"

assert_fails "Windows user path" \
  "source: ${windows_path}"

assert_fails "peered hub address range" \
  "existing hub prefix: ${hub_cidr}"

assert_fails "address range outside the blueprint plan" \
  "peer subnet: ${outside_cidr}"

# --- Permitted placeholders, constants, and public identifiers ---------------

assert_passes "placeholder GUID" \
  'subscriptionId: 00000000-0000-0000-0000-000000000000'

assert_passes "placeholder resource ID" \
  'id: /subscriptions/<subscription-id>/resourceGroups/<blueprint-resource-group>'

assert_passes "example.com address" \
  'contact: platform-owner@example.com'

assert_passes "fictional sample domain" \
  'contact: ai-platform@contoso.com'

assert_passes "approved greenfield address plan" \
  'vnet 10.0.0.0/16 with subnets 10.0.1.0/24 and 10.0.6.0/26'

assert_passes "RFC 1918 block reference" \
  'private space is 10.0.0.0/8, 172.16.0.0/12, and 192.168.0.0/16'

assert_passes "public built-in role definition ID" \
  "roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'"

assert_passes "first-party application ID" \
  'Microsoft Graph app: 00000003-0000-0000-c000-000000000000'

assert_passes "generic policy inputs" \
  'policyInputs: publicNetworkAccessDisabled=true localAuthDisabled=true allowedModelSkus=[generic-model-sku-a]'

# Vocabulary is not disclosure: prose must never be flagged (regression guard).
assert_passes "ordinary prose vocabulary" \
  'The customer organization supplies tenant-managed DNS zones; name and id fields stay generic.'

# --- Repository-wide gate must be usable (T070) ------------------------------

if ! "$VALIDATOR" >"${workdir}/repo-out" 2>&1; then
  echo "FAIL: repository-wide confidentiality gate must pass on tracked artifacts" >&2
  cat "${workdir}/repo-out" >&2
  exit 1
fi

echo "Confidentiality validation tests passed."
