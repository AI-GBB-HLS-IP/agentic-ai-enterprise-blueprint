#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/network/validate-policy-inputs.sh"

assert_passes() {
  local name="$1"
  local path="$2"

  if ! "$VALIDATOR" --input "$path" >/tmp/network-policy.out 2>&1; then
    echo "FAIL: $name should pass validation" >&2
    cat /tmp/network-policy.out >&2
    exit 1
  fi
}

assert_fails() {
  local name="$1"
  local path="$2"

  if "$VALIDATOR" --input "$path" >/tmp/network-policy.out 2>&1; then
    echo "FAIL: $name should fail validation" >&2
    exit 1
  fi
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/valid.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-a","generic-model-sku-b"]}}
JSON
assert_passes "valid policy input" "$workdir/valid.json"

for case_name in \
  missing-policy-object \
  missing-public-flag \
  false-public-flag \
  nonbool-public-flag \
  missing-local-flag \
  false-local-flag \
  nonbool-local-flag \
  missing-skus \
  empty-skus \
  duplicate-skus \
  whitespace-skus \
  wildcard-skus \
  pattern-skus
 do
  case "$case_name" in
    missing-policy-object)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":null}
JSON
      ;;
    missing-public-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    false-public-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":false,"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    nonbool-public-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":"true","localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    missing-local-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    false-local-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":false,"allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    nonbool-local-flag)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":"true","allowedModelSkus":["generic-model-sku-a"]}}
JSON
      ;;
    missing-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true}}
JSON
      ;;
    empty-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":[]}}
JSON
      ;;
    duplicate-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-a","generic-model-sku-a"]}}
JSON
      ;;
    whitespace-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":[" ","generic-model-sku-b"]}}
JSON
      ;;
    wildcard-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku-*","generic-model-sku-b"]}}
JSON
      ;;
    pattern-skus)
      cat >"$workdir/${case_name}.json" <<'JSON'
{"policyInputs":{"publicNetworkAccessDisabled":true,"localAuthDisabled":true,"allowedModelSkus":["generic-model-sku[0]","generic-model-sku-b"]}}
JSON
      ;;
  esac
  assert_fails "$case_name" "$workdir/${case_name}.json"
done

echo "Policy input validation tests passed."
