#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/network/scan-confidentiality.sh"

assert_fails() {
  local description="$1"
  local path="$2"

  if "$VALIDATOR" "$path" >"$workdir/network-confidentiality.out" 2>&1; then
    echo "FAIL: expected confidentiality check to reject ${description}" >&2
    cat "$workdir/network-confidentiality.out" >&2
    exit 1
  fi
}

assert_passes() {
  local description="$1"
  local path="$2"

  if ! "$VALIDATOR" "$path" >"$workdir/network-confidentiality.out" 2>&1; then
    echo "FAIL: expected confidentiality check to allow ${description}" >&2
    cat "$workdir/network-confidentiality.out" >&2
    exit 1
  fi
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/allowed.txt" <<'EOF'
Generic example policy handoff:
policyInputs:
  publicNetworkAccessDisabled: true
  localAuthDisabled: true
  allowedModelSkus:
    - generic-model-sku-a
    - generic-model-sku-b
EOF
assert_passes "generic placeholders" "$workdir/allowed.txt"

cat >"$workdir/rejected.txt" <<'EOF'
Customer: Contoso
Email: jane.doe@contoso.com
Subscription: 11111111-2222-3333-4444-555555666666
Path: /home/tenant/network-discovery.json
CIDR: 10.10.0.0/24
EOF
assert_fails "live discovery output" "$workdir/rejected.txt"

echo "Confidentiality validation tests passed."
