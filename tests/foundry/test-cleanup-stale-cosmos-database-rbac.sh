#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/foundry/cleanup-stale-cosmos-database-rbac.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/az" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$AZ_CALL_LOG"

if [ "$1" = "cosmosdb" ] && [ "$5" = "list" ]; then
  case "$*" in
    *"ends_with(roleDefinitionId, '00000000-0000-0000-0000-000000000002')"*) ;;
    *) echo "missing built-in Data Contributor role filter" >&2; exit 1 ;;
  esac
  case "$*" in
    *"--subscription 11111111-2222-3333-4444-555555555555"*) ;;
    *) echo "missing explicit subscription" >&2; exit 1 ;;
  esac
  echo '[{"id":"obsolete-assignment","principalId":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","scope":"/dbs/enterprise_memory","roleDefinitionId":"/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"}]'
elif [ "$1" = "cosmosdb" ] && [ "$5" = "delete" ]; then
  case "$*" in
    *"--subscription 11111111-2222-3333-4444-555555555555"*) ;;
    *) echo "missing explicit subscription on delete" >&2; exit 1 ;;
  esac
  case "$*" in
    *"--role-assignment-id obsolete-assignment"*) ;;
    *) echo "unexpected assignment deleted" >&2; exit 1 ;;
  esac
fi
STUB
chmod +x "$workdir/az"

export AZ_CALL_LOG="$workdir/az-calls.log"
export PATH="$workdir:$PATH"
output="$(COSMOS_ACCOUNT_ID=/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/cosmos-rg/providers/Microsoft.DocumentDB/databaseAccounts/shared-cosmos \
  bash "$SCRIPT" --execute)"

grep -q "Cosmos account: /subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/cosmos-rg/providers/Microsoft.DocumentDB/databaseAccounts/shared-cosmos" <<< "$output"
grep -q "az cosmosdb sql role assignment list" <<< "$output"
grep -q -- "--subscription '11111111-2222-3333-4444-555555555555'" <<< "$output"
grep -q -- "--subscription 11111111-2222-3333-4444-555555555555" "$AZ_CALL_LOG"
grep -q -- "--account-name shared-cosmos --resource-group cosmos-rg" "$AZ_CALL_LOG"
grep -q "Deleting obsolete-assignment" <<< "$output"

if COSMOS_ACCOUNT_ID=shared-cosmos bash "$SCRIPT" >/dev/null 2>&1; then
  echo "expected malformed account resource ID to be rejected" >&2
  exit 1
fi

echo "Stale Cosmos database RBAC cleanup tests passed."
