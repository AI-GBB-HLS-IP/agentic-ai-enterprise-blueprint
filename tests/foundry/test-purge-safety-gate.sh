#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PURGE_SCRIPT="$REPO_ROOT/scripts/foundry/purge.sh"

# Stub out az so the test never touches a live subscription; it only exercises the script's
# required-env-var checks and safety gates.
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

# Lookup failures other than an explicit not-found response must fail closed.
workdir4="$(mktemp -d)"
trap 'rm -rf "$workdir" "$workdir2" "$workdir3" "$workdir4"' EXIT
cat >"$workdir4/az" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "show" ]; then
  echo "ERROR: (AuthorizationFailed) The client is not authorized." >&2
  exit 1
fi
echo "Unexpected az invocation after lookup failure: $*" >&2
exit 1
STUB
chmod +x "$workdir4/az"

if failure_output="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc PATH="$workdir4:$PATH" "$PURGE_SCRIPT" 2>&1)"; then
  echo "FAIL: purge.sh should fail when account lookup is unauthorized" >&2
  exit 1
fi
echo "$failure_output" | grep -q "Failed to look up live Cognitive Services account" || {
  echo "FAIL: purge.sh did not report the account lookup failure" >&2
  exit 1
}

# Execute mode may delete only an explicitly allowed terminal failure state, and the command
# must retain the exact resource-group/name arguments.
workdir5="$(mktemp -d)"
trap 'rm -rf "$workdir" "$workdir2" "$workdir3" "$workdir4" "$workdir5"' EXIT
cat >"$workdir5/az" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "show" ]; then
  printf '%s\n' "$LIVE_STATE"
  exit 0
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "delete" ]; then
  printf '%s\n' "$*" >>"$CALL_LOG"
  exit 0
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "purge" ]; then
  printf '%s\n' "$*" >>"$CALL_LOG"
  exit 0
fi
if [ "$1" = "cognitiveservices" ] && [ "$2" = "account" ] && [ "$3" = "list-deleted" ]; then
  case "$*" in
    *length*) printf '%s\n' "$DELETED_COUNT" ;;
    *) printf '[{"name":"foundry-agent-factory-poc"}]\n' ;;
  esac
  exit 0
fi
if [ "$1" = "keyvault" ] && [ "$2" = "list-deleted" ]; then
  case "$*" in
    *length*) printf '%s\n' "$DELETED_COUNT" ;;
    *) printf '[{"name":"kv-agent-factory-poc"}]\n' ;;
  esac
  exit 0
fi
if [ "$1" = "keyvault" ] && [ "$2" = "purge" ]; then
  printf '%s\n' "$*" >>"$CALL_LOG"
  exit 0
fi
echo "Unexpected az invocation: $*" >&2
exit 1
STUB
chmod +x "$workdir5/az"

for state in Failed Succeeded Creating Updating Deleting Unknown; do
  call_log="$workdir5/calls-$state"
  : >"$call_log"
  deleted_count=0
  vault_name=""
  if [ "$state" = "Failed" ]; then
    deleted_count=1
    vault_name=kv-agent-factory-poc
  fi
  output5="$(LOCATION=eastus2 RG_NAME=rg-agent-factory-poc FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc FOUNDRY_KEY_VAULT_NAME="$vault_name" LIVE_STATE="$state" DELETED_COUNT="$deleted_count" CALL_LOG="$call_log" PATH="$workdir5:$PATH" "$PURGE_SCRIPT" --execute)"
  if [ "$state" = "Failed" ]; then
    expected_call="$(printf '%s\n' \
      'cognitiveservices account delete --resource-group rg-agent-factory-poc --name foundry-agent-factory-poc' \
      'cognitiveservices account purge --resource-group rg-agent-factory-poc --location eastus2 --name foundry-agent-factory-poc' \
      'keyvault purge --name kv-agent-factory-poc --location eastus2')"
    if [ "$(cat "$call_log")" != "$expected_call" ]; then
      echo "FAIL: Failed-state delete/purge calls did not match exactly" >&2
      exit 1
    fi
  else
    if [ -s "$call_log" ]; then
      echo "FAIL: purge.sh deleted a live account in '$state' state" >&2
      exit 1
    fi
    if [ "$state" = "Succeeded" ]; then
      expected_message="provisioningState: Succeeded"
    else
      expected_message="leaving it in place"
    fi
    echo "$output5" | grep -q "$expected_message" || {
      echo "FAIL: purge.sh did not report that '$state' state was left in place" >&2
      exit 1
    }
  fi
done

echo "purge.sh safety gate behaves as expected."
