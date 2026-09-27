#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
VALIDATE="$REPO_ROOT/scripts/agent/validate-sample-storage.sh"

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
if [[ "$1" == "account" && "$2" == "show" ]]; then
  if [[ "$*" == *"user.type"* ]]; then
    printf 'servicePrincipal\n'
  else
    printf '%s\n' "$AZ_MOCK_CLIENT_ID"
  fi
elif [[ "$1" == "cloud" && "$2" == "show" ]]; then
  printf 'core.windows.net\n'
elif [[ "$1" == "storage" && "$2" == "blob" && "$3" == "list" ]]; then
  printf 'maintenance-window.md\nservice-status.md\n'
  if [[ -n "${AZ_MOCK_EXTRA_BLOB:-}" ]]; then
    printf '%s\n' "$AZ_MOCK_EXTRA_BLOB"
  fi
elif [[ "$1" == "storage" && "$2" == "blob" && "$3" == "download" ]]; then
  output_file=''
  blob_name=''
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --file) output_file="$2"; shift 2 ;;
      --name) blob_name="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  cp "$AZ_MOCK_CORPUS_DIR/$blob_name" "$output_file"
fi
MOCK_AZ
cat >"$workdir/bin/getent" <<'MOCK_GETENT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s STREAM sample\n' "$AZ_MOCK_DNS_IP"
MOCK_GETENT
chmod +x "$workdir/bin/az" "$workdir/bin/getent"

export PATH="$workdir/bin:$PATH"
export AZ_MOCK_CLIENT_ID=00000000-0000-0000-0000-000000000002
export AZ_MOCK_CORPUS_DIR="$REPO_ROOT/agents/knowledge/sample-corpus/v1"
export AZ_MOCK_DNS_IP=10.0.1.4
export STORAGE_ACCOUNT_NAME=sampleaccount
export STORAGE_CONTAINER_NAME=phase1-samples
export STORAGE_BLOB_ENDPOINT=https://sampleaccount.blob.core.windows.net/
export UPLOAD_IDENTITY_CLIENT_ID="$AZ_MOCK_CLIENT_ID"

output="$("$VALIDATE")"
grep -Fq 'PASSED: Storage resolves privately, the approved identity can list/read the complete sample corpus' <<<"$output" ||
  fail "valid private DNS and identity-based reads must pass the validation contract"

set +e
output="$(AZ_MOCK_DNS_IP=8.8.8.8 "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "a public DNS result must block Storage readiness"
grep -Fq 'BLOCKED: Storage blob endpoint resolves to a non-private address; public fallback is not allowed.' <<<"$output" ||
  fail "a public DNS result must be named as BLOCKED"

set +e
output="$(AZ_MOCK_EXTRA_BLOB=unexpected.md "$VALIDATE" 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 ]] || fail "an incomplete/non-canonical corpus must block readiness"
grep -Fq 'BLOCKED: unexpected blob(s) exist in the dedicated corpus container: unexpected.md' <<<"$output" ||
  fail "unexpected blobs must prevent corpus readiness"

printf 'Sample Storage validation contract tests passed.\n'
