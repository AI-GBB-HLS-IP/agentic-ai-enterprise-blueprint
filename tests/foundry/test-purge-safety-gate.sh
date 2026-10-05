#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PURGE_SCRIPT="$REPO_ROOT/scripts/foundry/purge.sh"

command -v az >/dev/null 2>&1 || { echo "SKIP: az CLI not available."; exit 0; }

# Stub out az so the test never touches a live subscription; it only exercises the script's
# required-env-var checks and its default (no --execute) dry-run gate.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cat >"$workdir/az" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "list-deleted" ]; then
  echo "[]"
  exit 0
fi
if [ "$1" = "keyvault" ] && [ "$2" = "list-deleted" ]; then
  echo "[]"
  exit 0
fi
echo "Unexpected az invocation (purge must not be called without --execute): $*" >&2
exit 1
STUB
chmod +x "$workdir/az"

# Missing required env vars must fail fast.
if (unset LOCATION RG_NAME FOUNDRY_ACCOUNT_NAME; PATH="$workdir:$PATH" "$PURGE_SCRIPT" >/dev/null 2>&1); then
  echo "FAIL: purge.sh should require LOCATION/RG_NAME/FOUNDRY_ACCOUNT_NAME" >&2
  exit 1
fi

# Default (no --execute) run must only list, never purge.
output="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc PATH="$workdir:$PATH" "$PURGE_SCRIPT")"
echo "$output" | grep -q "Dry run complete. No resources were purged." || {
  echo "FAIL: purge.sh default run did not report a dry run" >&2
  exit 1
}

echo "purge.sh safety gate behaves as expected."
