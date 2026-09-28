#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/agent/foundry-tool-preflight.sh"
EVIDENCE="$SCRIPT_DIR/fixtures/foundry-caller-claims.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

set +e
output="$(env -i PATH="$PATH" "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "missing tenant approvals and caller evidence must fail closed"
for input_name in \
  TOOL_API_TENANT_ID TOOL_API_AUDIENCE BACKEND_API_AUDIENCE TOOL_API_TOKEN_VERSION \
  TOOL_API_ISSUER TOOL_API_ALLOWED_PRINCIPAL_IDS APIM_MANAGED_IDENTITY_PRINCIPAL_ID \
  FOUNDRY_OPENAPI_INTEGRATION FOUNDRY_OPENAPI_API_VERSION FOUNDRY_CALLER_PRINCIPAL_ID \
  FOUNDRY_CALLER_EVIDENCE_FILE TOOL_API_APPROVAL_REFERENCE BACKEND_API_APPROVAL_REFERENCE; do
  grep -Fq "BLOCKED: required Foundry tool input $input_name is not set." <<<"$output" ||
    fail "missing input $input_name was not reported as BLOCKED"
done

tool_inputs=(
  TOOL_API_TENANT_ID=00000000-0000-0000-0000-000000000000
  TOOL_API_AUDIENCE=api://phase1-tool-example
  BACKEND_API_AUDIENCE=api://phase1-backend-example
  TOOL_API_TOKEN_VERSION=2.0
  TOOL_API_ISSUER=https://login.example.invalid/00000000-0000-0000-0000-000000000000/v2.0
  TOOL_API_ALLOWED_PRINCIPAL_IDS=00000000-0000-0000-0000-000000000002
  APIM_MANAGED_IDENTITY_PRINCIPAL_ID=00000000-0000-0000-0000-000000000003
  FOUNDRY_OPENAPI_INTEGRATION=managed-identity
  FOUNDRY_OPENAPI_API_VERSION=2025-01-01-preview
  FOUNDRY_CALLER_PRINCIPAL_ID=00000000-0000-0000-0000-000000000002
  FOUNDRY_CALLER_EVIDENCE_FILE="$EVIDENCE"
  TOOL_API_APPROVAL_REFERENCE=approval-example
  BACKEND_API_APPROVAL_REFERENCE=approval-example
)

output="$(env "${tool_inputs[@]}" "$PREFLIGHT")"
grep -Fq 'PENDING: redacted Foundry caller claims match the explicit contract;' <<<"$output" ||
  fail "matching redacted evidence must remain pending live verification"

set +e
output="$(env "${tool_inputs[@]}" TOOL_API_AUDIENCE=api://wrong-example "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "an audience mismatch must fail closed"
grep -Fq 'BLOCKED: redacted Foundry caller evidence does not match approved input(s): audience.' <<<"$output" ||
  fail "an audience mismatch must be named without printing claim values"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
python3 - "$EVIDENCE" "$workdir" <<'PY'
import json
import pathlib
import sys

evidence = json.loads(pathlib.Path(sys.argv[1]).read_text())
for filename, extra in (
    ("extra.json", {"unapproved_claim": "extra"}),
    ("nested.json", {"metadata": {"authorization": "redacted"}}),
):
    pathlib.Path(sys.argv[2], filename).write_text(json.dumps({**evidence, **extra}))
PY
for filename in extra.json nested.json; do
  set +e
  output="$(env "${tool_inputs[@]}" FOUNDRY_CALLER_EVIDENCE_FILE="$workdir/$filename" "$PREFLIGHT" 2>&1)"
  status=$?
  set -e
  [[ "$status" -eq 2 ]] || fail "$filename must fail closed on unapproved claims"
  grep -Fq 'BLOCKED: redacted Foundry caller evidence must contain only the six approved claims.' <<<"$output" ||
    fail "$filename must report the approved-claims boundary"
done

printf 'Foundry tool identity preflight contract tests passed.\n'
