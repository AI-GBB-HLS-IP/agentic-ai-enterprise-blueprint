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
# Simulate Windows CRLF line endings in az's output to guard against the string-equality bug
# where "[]\r" (from a Windows-hosted az CLI) never matched a literal "[]" comparison.
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "show" ]; then
  echo "ResourceNotFound" >&2
  exit 3
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "list-deleted" ]; then
  printf '0\r\n'
  exit 0
fi
if [ "$1" = "keyvault" ] && [ "$2" = "list-deleted" ]; then
  printf '0\r\n'
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

# Default (no --execute) run must only list, never purge/delete.
output="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc PATH="$workdir:$PATH" "$PURGE_SCRIPT")"
echo "$output" | grep -q "Dry run complete. No resources were purged." || {
  echo "FAIL: purge.sh default run did not report a dry run" >&2
  exit 1
}

# When a soft-deleted match exists, the default run must report it and refuse to purge, never
# invoking the purge commands.
workdir2="$(mktemp -d)"
trap 'rm -rf "$workdir" "$workdir2"' EXIT
cat >"$workdir2/az" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "show" ]; then
  echo "ResourceNotFound" >&2
  exit 3
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "list-deleted" ]; then
  for arg in "$@"; do
    case "$arg" in
      *length*) printf '1\r\n'; exit 0 ;;
    esac
  done
  echo '[{"name":"foundry-agent-factory-poc"}]'
  exit 0
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "purge" ]; then
  echo "FAIL: purge must not run without --execute" >&2
  exit 1
fi
if [ "$1" = "keyvault" ] && [ "$2" = "list-deleted" ]; then
  printf '0\r\n'
  exit 0
fi
echo "Unexpected az invocation: $*" >&2
exit 1
STUB
chmod +x "$workdir2/az"

output2="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc PATH="$workdir2:$PATH" "$PURGE_SCRIPT")"
echo "$output2" | grep -q "Refusing to purge" || {
  echo "FAIL: purge.sh did not report a detected soft-deleted account" >&2
  exit 1
}

# When a live account exists in a non-Succeeded state, the default run must report it and
# refuse to delete it, never invoking the delete command.
workdir3="$(mktemp -d)"
trap 'rm -rf "$workdir" "$workdir2" "$workdir3"' EXIT
cat >"$workdir3/az" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "show" ]; then
  printf 'Failed\r\n'
  exit 0
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "delete" ]; then
  echo "FAIL: delete must not run without --execute" >&2
  exit 1
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "list-deleted" ]; then
  printf '0\r\n'
  exit 0
fi
if [ "$1" = "keyvault" ] && [ "$2" = "list-deleted" ]; then
  printf '0\r\n'
  exit 0
fi
echo "Unexpected az invocation: $*" >&2
exit 1
STUB
chmod +x "$workdir3/az"

output3="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc PATH="$workdir3:$PATH" "$PURGE_SCRIPT")"
echo "$output3" | grep -q "Refusing to delete" || {
  echo "FAIL: purge.sh did not report a detected live Failed-state account" >&2
  exit 1
}

echo "purge.sh safety gate behaves as expected."
