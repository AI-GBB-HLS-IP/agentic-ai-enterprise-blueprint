#!/usr/bin/env bash
# Runs the Bicep test-framework assertions for the APIM custom-domain logic
# (infra/modules/apim/hostnames.bicep) and checks that the templates importing it still compile.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

bicep_bin=""
if command -v bicep >/dev/null 2>&1; then
  bicep_bin="$(command -v bicep)"
elif [[ -x "${HOME}/.azure/bin/bicep" ]]; then
  bicep_bin="${HOME}/.azure/bin/bicep"
fi

if [[ -z "$bicep_bin" ]]; then
  echo "SKIP: bicep CLI not available; cannot run APIM hostname tests." >&2
  exit 0
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "==> bicep test: tests/network/bicep/hostnames.tests.bicep"
output="$("$bicep_bin" test "${SCRIPT_DIR}/bicep/hostnames.tests.bicep" 2>&1)" || {
  echo "$output" >&2
  fail "APIM hostname assertions failed"
}
grep -q "All 1 evaluations passed" <<<"$output" || {
  echo "$output" >&2
  fail "APIM hostname assertions did not report a passing evaluation"
}

for template in infra/modules/apim/main.bicep infra/envs/poc/apim.bicep; do
  echo "==> bicep build: ${template}"
  "$bicep_bin" build "${REPO_ROOT}/${template}" --stdout >/dev/null 2>&1 || fail "${template} does not compile"
done

echo "PASS: APIM hostname tests"
