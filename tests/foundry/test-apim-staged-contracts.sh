#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_present() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  grep -Eq "$pattern" "$file" || fail "$message"
}

assert_absent() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if grep -Eq "$pattern" "$file"; then
    fail "$message"
  fi
}

foundation="${REPO_ROOT}/infra/envs/poc/apim.bicep"
foundation_params="${REPO_ROOT}/infra/envs/poc/apim.bicepparam"
customer_params="${REPO_ROOT}/infra/envs/poc/apim.customer.example.bicepparam"
integration="${REPO_ROOT}/infra/envs/poc/apim-foundry-integration.bicep"
integration_params="${REPO_ROOT}/infra/envs/poc/apim-foundry-integration.bicepparam"
api_module="${REPO_ROOT}/infra/modules/apim/api.bicep"
validator="${REPO_ROOT}/specs/02-apim-ai-gateway/validation/validate.sh"

echo "==> Stage 1 restricts public access and records policy validation"
if sed -n '/APIM public network access policy handoff/,/param publicNetworkAccess/p' "$foundation" |
  grep -q "'Disabled'"; then
  fail "Stage 1 publicNetworkAccess must allow only Enabled"
fi
assert_present 'policyOwnedDiagnosticSettingsValidationReference' "$foundation_params" \
  "default Stage 1 parameters must wire the policy validation reference"
assert_present 'policyOwnedDiagnosticSettingsValidationReference' "$customer_params" \
  "customer Stage 1 parameters must wire the policy validation reference"
assert_present "observabilityStatus = policyOwnedDiagnosticSettingsValidated" "$foundation" \
  "Stage 1 readiness must account for completed policy validation"
assert_present 'policyValidationReferenceIsPlaceholder' "$foundation" \
  "Stage 1 must reject placeholder policy diagnostic evidence"

echo "==> Stage 2 requires the validated Stage 1 handoff"
assert_present 'param stage1ApimServiceId' "$integration" \
  "Stage 2 template must require the Stage 1 APIM resource ID"
assert_present 'param stage1FoundationReadiness' "$integration" \
  "Stage 2 template must require Stage 1 readiness"
assert_present 'APIM_STAGE1_SERVICE_ID' "$integration_params" \
  "Stage 2 parameters must wire the Stage 1 APIM resource ID"
assert_present 'APIM_STAGE1_FOUNDATION_READINESS' "$integration_params" \
  "Stage 2 parameters must wire Stage 1 readiness"
assert_absent 'requirePrivateFoundryAccess|FOUNDRY_REQUIRE_PRIVATE_ACCESS' "$integration_params" \
  "Stage 2 parameters must not retain the removed private-access bypass"
assert_present "publicNetworkAccess.*== 'disabled'" "$integration" \
  "Stage 2 must unconditionally require private Foundry access"

echo "==> Customer policy values have no repository fallback"
assert_present "readEnvironmentVariable\\('FOUNDRY_APPROVED_REGIONS'\\)" "$integration_params" \
  "approved Foundry regions must be explicitly supplied"
assert_absent "FOUNDRY_APPROVED_REGIONS'.*eastus" "$integration_params" \
  "approved Foundry regions must not use a repository default"

echo "==> Validator follows the staged parameter and backend contracts"
assert_present 'APIM_FOUNDATION_PARAMETERS_FILE' "$validator" \
  "validator must support APIM_FOUNDATION_PARAMETERS_FILE"
assert_present 'FOUNDATION_PARAMETERS' "$validator" \
  "validator must preserve the FOUNDATION_PARAMETERS alias"
assert_present 'APIM_FOUNDRY_BACKEND_NAME' "$validator" \
  "validator must use the Stage 2 backend parameter environment name"
assert_present 'APIM_STAGE1_FOUNDATION_READINESS' "$validator" \
  "validator must verify the Stage 1 readiness handoff"
assert_present 'require_governance_reference APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE foundation' "$validator" \
  "validator must require real policy diagnostic evidence after live validation"
assert_present 'set-query-parameter name="subscription-key" exists-action="delete"' "$api_module" \
  "APIM policy must remove query-string subscription credentials"

echo "APIM staged contract tests passed."
