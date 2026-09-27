#!/usr/bin/env bash
set -euo pipefail

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required Foundry tool input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input TOOL_API_TENANT_ID "${TOOL_API_TENANT_ID:-}"
check_required_input TOOL_API_AUDIENCE "${TOOL_API_AUDIENCE:-}"
check_required_input BACKEND_API_AUDIENCE "${BACKEND_API_AUDIENCE:-}"
check_required_input TOOL_API_TOKEN_VERSION "${TOOL_API_TOKEN_VERSION:-}"
check_required_input TOOL_API_ISSUER "${TOOL_API_ISSUER:-}"
check_required_input TOOL_API_ALLOWED_PRINCIPAL_IDS "${TOOL_API_ALLOWED_PRINCIPAL_IDS:-}"
check_required_input APIM_MANAGED_IDENTITY_PRINCIPAL_ID "${APIM_MANAGED_IDENTITY_PRINCIPAL_ID:-}"
check_required_input FOUNDRY_OPENAPI_INTEGRATION "${FOUNDRY_OPENAPI_INTEGRATION:-}"
check_required_input FOUNDRY_OPENAPI_API_VERSION "${FOUNDRY_OPENAPI_API_VERSION:-}"
check_required_input FOUNDRY_CALLER_PRINCIPAL_ID "${FOUNDRY_CALLER_PRINCIPAL_ID:-}"
check_required_input FOUNDRY_CALLER_EVIDENCE_FILE "${FOUNDRY_CALLER_EVIDENCE_FILE:-}"
check_required_input TOOL_API_APPROVAL_REFERENCE "${TOOL_API_APPROVAL_REFERENCE:-}"
check_required_input BACKEND_API_APPROVAL_REFERENCE "${BACKEND_API_APPROVAL_REFERENCE:-}"

if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

if [[ ! -f "$FOUNDRY_CALLER_EVIDENCE_FILE" ]]; then
  printf 'BLOCKED: redacted Foundry caller evidence file is unavailable.\n' >&2
  exit 2
fi

python3 - "$FOUNDRY_CALLER_EVIDENCE_FILE" <<'PY'
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    evidence = json.loads(path.read_text())
except (OSError, json.JSONDecodeError):
    print("BLOCKED: redacted Foundry caller evidence is unreadable or invalid.", file=sys.stderr)
    sys.exit(2)

if not isinstance(evidence, dict):
    print("BLOCKED: redacted Foundry caller evidence must be a JSON object.", file=sys.stderr)
    sys.exit(2)

for forbidden in ("access_token", "authorization", "token"):
    if forbidden in {key.lower() for key in evidence}:
        print("BLOCKED: caller evidence must not contain a token or authorization field.", file=sys.stderr)
        sys.exit(2)

expected = {
    "tenant_id": os.environ["TOOL_API_TENANT_ID"],
    "issuer": os.environ["TOOL_API_ISSUER"],
    "audience": os.environ["TOOL_API_AUDIENCE"],
    "token_version": os.environ["TOOL_API_TOKEN_VERSION"],
    "principal_id": os.environ["FOUNDRY_CALLER_PRINCIPAL_ID"],
    "token_type": "app",
}
missing_claims = [claim for claim in expected if not isinstance(evidence.get(claim), str) or not evidence[claim].strip()]
if missing_claims:
    print(
        "BLOCKED: redacted Foundry caller evidence is missing required claim(s): "
        + ", ".join(missing_claims)
        + ".",
        file=sys.stderr,
    )
    sys.exit(2)

allowed_principals = {
    principal.strip().lower()
    for principal in os.environ["TOOL_API_ALLOWED_PRINCIPAL_IDS"].split(",")
    if principal.strip()
}
if not allowed_principals:
    print("BLOCKED: the approved tool API principal allowlist is empty.", file=sys.stderr)
    sys.exit(2)
if os.environ["FOUNDRY_CALLER_PRINCIPAL_ID"].strip().lower() not in allowed_principals:
    print("BLOCKED: the selected Foundry caller is not in the approved tool API principal allowlist.", file=sys.stderr)
    sys.exit(2)

mismatches = []
for claim, expected_value in expected.items():
    observed_value = evidence[claim].strip()
    if claim in ("tenant_id", "principal_id"):
        matches = observed_value.lower() == expected_value.strip().lower()
    else:
        matches = observed_value == expected_value
    if not matches:
        mismatches.append(claim)
if mismatches:
    print(
        "BLOCKED: redacted Foundry caller evidence does not match approved input(s): "
        + ", ".join(mismatches)
        + ".",
        file=sys.stderr,
    )
    sys.exit(2)

print(
    "PENDING: redacted Foundry caller claims match the explicit contract; "
    "live tool authorization and network reachability are not verified."
)
PY
