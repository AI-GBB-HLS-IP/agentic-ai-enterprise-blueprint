#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
UPLOAD="$REPO_ROOT/scripts/agent/upload-sample-corpus.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/bin"
cat >"$workdir/bin/az" <<'MOCK_AZ'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AZ_MOCK_LOG"
if [[ "$1" == "account" && "$2" == "show" ]]; then
  if [[ "$*" == *"user.type"* ]]; then
    printf 'servicePrincipal\n'
  else
    printf '%s\n' "$AZ_MOCK_CLIENT_ID"
  fi
elif [[ "$1" == "storage" && "$2" == "blob" && "$3" == "list" ]]; then
  printf 'maintenance-window.md\nservice-status.md\n'
  if [[ -n "${AZ_MOCK_EXTRA_BLOB:-}" ]]; then
    printf '%s\n' "$AZ_MOCK_EXTRA_BLOB"
  fi
fi
MOCK_AZ
chmod +x "$workdir/bin/az"

export PATH="$workdir/bin:$PATH"
export AZ_MOCK_LOG="$workdir/az.log"
export AZ_MOCK_CLIENT_ID=00000000-0000-0000-0000-000000000002
export UPLOAD_IDENTITY_CLIENT_ID="$AZ_MOCK_CLIENT_ID"
export UPLOAD_IDENTITY_APPROVAL_REFERENCE=approval-example
export STORAGE_ACCOUNT_NAME=sampleaccount
export STORAGE_CONTAINER_NAME=phase1-samples

output="$("$UPLOAD")"
grep -Fq 'PENDING: corpus documents match the manifest;' <<<"$output" ||
  fail "matching corpus upload must remain pending private-route and ingestion verification"
grep -Fq -- '--auth-mode login' "$AZ_MOCK_LOG" ||
  fail "Storage operations must use login-based authentication"
grep -Fq -- '--overwrite true' "$AZ_MOCK_LOG" ||
  fail "document uploads must be idempotent"
if grep -Eqi 'account.key|account-key|storage.key' "$AZ_MOCK_LOG"; then
  fail "Storage operations must not use account keys"
fi
[[ "$(grep -c 'storage blob upload' "$AZ_MOCK_LOG")" -eq 2 ]] ||
  fail "only the two manifest-declared documents should be uploaded"

output="$("$UPLOAD")"
grep -Fq 'PENDING: corpus documents match the manifest;' <<<"$output" ||
  fail "repeated upload must preserve the exact declared corpus"
[[ "$(grep -c 'storage blob upload' "$AZ_MOCK_LOG")" -eq 4 ]] ||
  fail "repeated upload must overwrite only the two manifest-declared documents"

set +e
output="$(AZ_MOCK_EXTRA_BLOB=unexpected.md "$UPLOAD" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "unexpected blobs must block corpus readiness"
grep -Fq 'BLOCKED: unexpected blob(s) exist in the dedicated corpus container: unexpected.md' <<<"$output" ||
  fail "unexpected blobs must be reported without deleting them"

printf 'Sample corpus upload contract tests passed.\n'
