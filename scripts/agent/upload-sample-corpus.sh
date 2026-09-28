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
    printf 'BLOCKED: required corpus upload input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input UPLOAD_IDENTITY_CLIENT_ID "${UPLOAD_IDENTITY_CLIENT_ID:-}"
check_required_input UPLOAD_IDENTITY_APPROVAL_REFERENCE "${UPLOAD_IDENTITY_APPROVAL_REFERENCE:-}"
check_required_input STORAGE_ACCOUNT_NAME "${STORAGE_ACCOUNT_NAME:-}"
check_required_input STORAGE_CONTAINER_NAME "${STORAGE_CONTAINER_NAME:-}"
if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

if ! command -v az >/dev/null 2>&1; then
  printf 'BLOCKED: Azure CLI is required for corpus upload.\n' >&2
  exit 2
fi

if ! identity_type="$(az account show --query user.type -o tsv)"; then
  printf 'BLOCKED: Azure CLI is not authenticated; sign in with the approved identity first.\n' >&2
  exit 2
fi
if [[ "$identity_type" != "servicePrincipal" ]]; then
  printf 'BLOCKED: corpus upload requires a managed or federated service-principal identity.\n' >&2
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
        sys.exit(f"invalid corpus document path: {document['path']}")
    print(source)
PY

az storage container create \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --name "$STORAGE_CONTAINER_NAME" \
  --public-access off \
  --auth-mode login \
  --only-show-errors >/dev/null

while IFS= read -r source_file; do
  blob_name="$(basename "$source_file")"
  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STORAGE_CONTAINER_NAME" \
    --file "$source_file" \
    --name "$blob_name" \
    --overwrite true \
    --auth-mode login \
    --only-show-errors >/dev/null
done <"$workdir/expected-blobs.txt"

az storage blob list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$STORAGE_CONTAINER_NAME" \
  --auth-mode login \
  --query '[].name' \
  --output tsv >"$workdir/actual-blobs.txt"

if ! python3 - "$workdir/expected-blobs.txt" "$workdir/actual-blobs.txt" <<'PY'
import pathlib
import sys

expected = {
    pathlib.Path(line.strip()).name
    for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
    if line.strip()
}
actual = {
    line.strip()
    for line in pathlib.Path(sys.argv[2]).read_text().splitlines()
    if line.strip()
}
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

printf 'PENDING: corpus documents match the manifest; private Storage reachability and Foundry ingestion are not verified.\n'
