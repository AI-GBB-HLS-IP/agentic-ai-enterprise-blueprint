#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/agents/knowledge/sample-corpus/v1"
MANIFEST="$CORPUS_DIR/manifest.json"

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required Storage validation input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input STORAGE_ACCOUNT_NAME "${STORAGE_ACCOUNT_NAME:-}"
check_required_input STORAGE_CONTAINER_NAME "${STORAGE_CONTAINER_NAME:-}"
check_required_input STORAGE_BLOB_ENDPOINT "${STORAGE_BLOB_ENDPOINT:-}"
check_required_input UPLOAD_IDENTITY_CLIENT_ID "${UPLOAD_IDENTITY_CLIENT_ID:-}"
if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

for command_name in az getent python3 cmp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'BLOCKED: required command %s is unavailable.\n' "$command_name" >&2
    exit 2
  fi
done

if ! identity_type="$(az account show --query user.type -o tsv)"; then
  printf 'BLOCKED: Azure CLI is not authenticated with the approved upload identity.\n' >&2
  exit 2
fi
if [[ "$identity_type" != "servicePrincipal" ]]; then
  printf 'BLOCKED: Storage validation requires the approved managed or federated service-principal identity.\n' >&2
  exit 2
fi

if ! identity_client_id="$(az account show --query user.name -o tsv)"; then
  printf 'BLOCKED: Azure CLI could not resolve the active service-principal client ID.\n' >&2
  exit 2
fi
identity_client_id_lower="$(printf '%s' "$identity_client_id" | tr '[:upper:]' '[:lower:]')"
upload_identity_client_id_lower="$(printf '%s' "$UPLOAD_IDENTITY_CLIENT_ID" | tr '[:upper:]' '[:lower:]')"
if [[ "$identity_client_id_lower" != "$upload_identity_client_id_lower" ]]; then
  printf 'BLOCKED: active Azure CLI identity does not match UPLOAD_IDENTITY_CLIENT_ID.\n' >&2
  exit 2
fi

endpoint_host="$(python3 - "$STORAGE_BLOB_ENDPOINT" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
if parsed.scheme != "https" or not parsed.hostname:
    sys.exit("BLOCKED: STORAGE_BLOB_ENDPOINT must be a valid HTTPS endpoint.")
print(parsed.hostname)
PY
)" || exit 2

if ! storage_endpoint_suffix="$(az cloud show --query suffixes.storage -o tsv)"; then
  printf 'BLOCKED: Azure CLI could not resolve the active cloud storage endpoint suffix.\n' >&2
  exit 2
fi
expected_endpoint_host="${STORAGE_ACCOUNT_NAME}.blob.${storage_endpoint_suffix%.}"
endpoint_host_lower="$(printf '%s' "$endpoint_host" | tr '[:upper:]' '[:lower:]')"
expected_endpoint_host_lower="$(printf '%s' "$expected_endpoint_host" | tr '[:upper:]' '[:lower:]')"
if [[ "$endpoint_host_lower" != "$expected_endpoint_host_lower" ]]; then
  printf 'BLOCKED: STORAGE_BLOB_ENDPOINT does not match the active Azure cloud endpoint used by Azure CLI.\n' >&2
  exit 2
fi

if ! resolved_addresses="$(getent ahosts "$endpoint_host")"; then
  printf 'BLOCKED: Storage blob endpoint does not resolve through the configured private DNS path.\n' >&2
  exit 2
fi
if ! python3 - "$resolved_addresses" <<'PY'
import ipaddress
import sys

addresses = []
for line in sys.argv[1].splitlines():
    fields = line.split()
    if fields:
        addresses.append(fields[0])
if not addresses:
    print("BLOCKED: Storage blob endpoint has no DNS addresses.", file=sys.stderr)
    sys.exit(2)
if any(not ipaddress.ip_address(address).is_private for address in addresses):
    print("BLOCKED: Storage blob endpoint resolves to a non-private address; public fallback is not allowed.", file=sys.stderr)
    sys.exit(2)
PY
then
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

python3 - "$MANIFEST" "$CORPUS_DIR" >"$workdir/expected-blobs.txt" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
corpus_dir = pathlib.Path(sys.argv[2]).resolve()
for document in manifest["documents"]:
    source = (corpus_dir / document["path"]).resolve()
    if corpus_dir not in source.parents or not source.is_file():
        sys.exit(f"BLOCKED: invalid corpus document path: {document['path']}")
    print(source)
PY

az storage blob list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$STORAGE_CONTAINER_NAME" \
  --auth-mode login \
  --query '[].name' \
  --output tsv >"$workdir/actual-blobs.txt"

if ! python3 - "$workdir/expected-blobs.txt" "$workdir/actual-blobs.txt" <<'PY'
import pathlib
import sys

expected = {pathlib.Path(line.strip()).name for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.strip()}
actual = {line.strip() for line in pathlib.Path(sys.argv[2]).read_text().splitlines() if line.strip()}
if expected != actual:
    missing = sorted(expected - actual)
    unexpected = sorted(actual - expected)
    if missing:
        print("BLOCKED: expected corpus document(s) are missing: " + ", ".join(missing), file=sys.stderr)
    if unexpected:
        print("BLOCKED: unexpected blob(s) exist in the dedicated corpus container: " + ", ".join(unexpected), file=sys.stderr)
    sys.exit(2)
PY
then
  exit 2
fi

while IFS= read -r source_file; do
  blob_name="$(basename "$source_file")"
  downloaded_file="$workdir/$blob_name"
  az storage blob download \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STORAGE_CONTAINER_NAME" \
    --name "$blob_name" \
    --file "$downloaded_file" \
    --auth-mode login \
    --only-show-errors >/dev/null
  if ! cmp -s "$source_file" "$downloaded_file"; then
    printf 'BLOCKED: Storage content does not match the committed corpus file %s.\n' "$blob_name" >&2
    exit 2
  fi
done <"$workdir/expected-blobs.txt"

printf 'PASSED: Storage resolves privately, the approved identity can list/read the complete sample corpus, and all document contents match.\n'
