#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
PREFLIGHT="$REPO_ROOT/scripts/agent/foundry-model-preflight.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

set +e
output="$(env -i PATH="$PATH" "$PREFLIGHT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "missing model approvals and capacity evidence must fail closed"
for input_name in \
  FOUNDRY_REGION \
  CHAT_MODEL_DEPLOYMENT CHAT_MODEL_VERSION CHAT_MODEL_APPROVAL_REFERENCE CHAT_MODEL_CAPACITY_EVIDENCE \
  EMBEDDING_MODEL_DEPLOYMENT EMBEDDING_MODEL_VERSION EMBEDDING_MODEL_APPROVAL_REFERENCE EMBEDDING_MODEL_CAPACITY_EVIDENCE \
  QUERY_MODEL_DEPLOYMENT QUERY_MODEL_VERSION QUERY_MODEL_APPROVAL_REFERENCE QUERY_MODEL_CAPACITY_EVIDENCE; do
  grep -Fq "BLOCKED: required Foundry model input $input_name is not set." <<<"$output" ||
    fail "missing input $input_name was not reported as BLOCKED"
done
if grep -Fq 'PENDING:' <<<"$output"; then
  fail "missing inputs must not produce a PENDING result"
fi

output="$(
  FOUNDRY_REGION=region-example \
  CHAT_MODEL_DEPLOYMENT=chat-example \
  CHAT_MODEL_VERSION=1 \
  CHAT_MODEL_APPROVAL_REFERENCE=approval-example \
  CHAT_MODEL_CAPACITY_EVIDENCE=capacity-example \
  EMBEDDING_MODEL_DEPLOYMENT=embedding-example \
  EMBEDDING_MODEL_VERSION=1 \
  EMBEDDING_MODEL_APPROVAL_REFERENCE=approval-example \
  EMBEDDING_MODEL_CAPACITY_EVIDENCE=capacity-example \
  QUERY_MODEL_DEPLOYMENT=query-example \
  QUERY_MODEL_VERSION=1 \
  QUERY_MODEL_APPROVAL_REFERENCE=approval-example \
  QUERY_MODEL_CAPACITY_EVIDENCE=capacity-example \
  "$PREFLIGHT"
)"
grep -Fq 'PENDING: Foundry model inputs and evidence references are present; approval and regional capacity are not verified.' <<<"$output" ||
  fail "populated references must not be reported as verified approval or capacity"

printf 'Foundry model preflight contract tests passed.\n'
