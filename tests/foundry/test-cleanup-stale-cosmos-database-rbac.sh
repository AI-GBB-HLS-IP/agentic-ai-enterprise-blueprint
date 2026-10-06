#!/usr/bin/env bash
set -euo pipefail

# Exercises scripts/foundry/cleanup-stale-cosmos-database-rbac.sh against a mocked `az` CLI so the
# tests run without any real Azure subscription or Cosmos account. Covers the PR #94 review
# finding that --execute must require explicit principal/assignment scoping before it can delete
# anything, since this blueprint supports shared/BYO Cosmos accounts where an unscoped deletion
# could remove a legitimate grant owned by a different workload.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/foundry/cleanup-stale-cosmos-database-rbac.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available."; exit 0; }

# Keep all scratch artifacts inside the repo tree (never /tmp).
workdir="$(mktemp -d "${REPO_ROOT}/tests/foundry/.cleanup-cosmos-test.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

ACCOUNT_ID="/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/cosmos-rg/providers/Microsoft.DocumentDB/databaseAccounts/shared-cosmos"
PRINCIPAL_STALE="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
PRINCIPAL_OTHER="99999999-8888-7777-6666-555555555555"

fixture="$workdir/fixture.json"
cat >"$fixture" <<JSON
[
  {
    "id": "obsolete-assignment-stale",
    "principalId": "${PRINCIPAL_STALE}",
    "scope": "/dbs/enterprise_memory",
    "roleDefinitionId": "/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  },
  {
    "id": "legit-assignment-other-workload",
    "principalId": "${PRINCIPAL_OTHER}",
    "scope": "/dbs/enterprise_memory",
    "roleDefinitionId": "/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  },
  {
    "id": "container-scoped-assignment",
    "principalId": "${PRINCIPAL_STALE}",
    "scope": "/dbs/enterprise_memory/colls/foo-thread-message-store",
    "roleDefinitionId": "/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  }
]
JSON

delete_log="$workdir/deleted.log"
: >"$delete_log"

cat >"$workdir/az" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$AZ_CALL_LOG"

if [ "$1" = "cosmosdb" ] && [ "$2" = "sql" ] && [ "$3" = "role" ] && [ "$4" = "assignment" ] && [ "$5" = "list" ]; then
  shift 5
  query=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --query) query="$2"; shift 2 ;;
      --subscription)
        [ "$2" = "00000000-0000-0000-0000-000000000000" ] || { echo "missing explicit subscription" >&2; exit 1; }
        shift 2 ;;
      *) shift ;;
    esac
  done
  case "$query" in
    *"ends_with(roleDefinitionId, '00000000-0000-0000-0000-000000000002')"*) ;;
    *) echo "missing built-in Data Contributor role filter" >&2; exit 1 ;;
  esac
  principal=""
  if [[ "$query" == *"principalId=="* ]]; then
    principal=$(printf '%s' "$query" | grep -oP "principalId=='\K[^']+")
  fi
  jq --arg p "$principal" '
    [.[] | select(.scope == "/dbs/enterprise_memory")
         | select(.roleDefinitionId | endswith("00000000-0000-0000-0000-000000000002"))
         | select(($p == "") or (.principalId == $p))]
  ' "$AZ_FIXTURE"
  exit 0
fi

if [ "$1" = "cosmosdb" ] && [ "$2" = "sql" ] && [ "$3" = "role" ] && [ "$4" = "assignment" ] && [ "$5" = "delete" ]; then
  shift 5
  id=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --role-assignment-id) id="$2"; shift 2 ;;
      --subscription)
        [ "$2" = "00000000-0000-0000-0000-000000000000" ] || { echo "missing explicit subscription on delete" >&2; exit 1; }
        shift 2 ;;
      *) shift ;;
    esac
  done
  echo "$id" >>"$AZ_DELETE_LOG"
  exit 0
fi

echo "mock az: unsupported invocation: $*" >&2
exit 1
STUB
chmod +x "$workdir/az"

export AZ_CALL_LOG="$workdir/az-calls.log"
export AZ_FIXTURE="$fixture"
export AZ_DELETE_LOG="$delete_log"
: >"$AZ_CALL_LOG"
export PATH="$workdir:$PATH"

run_cleanup() {
  COSMOS_ACCOUNT_ID="$ACCOUNT_ID" bash "$SCRIPT" "$@"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 1. Dry-run without a principal filter must still work (discovery is unrestricted) and must
#    list both database-scoped assignments but never the container-scoped one.
: >"$delete_log"
output="$(run_cleanup || true)"
echo "$output" | grep -q "obsolete-assignment-stale" || fail "dry-run without principal did not list the stale assignment"
echo "$output" | grep -q "legit-assignment-other-workload" || fail "dry-run without principal did not list the other workload's assignment"
echo "$output" | grep -q "container-scoped-assignment" && fail "dry-run incorrectly listed the container-scoped assignment"
[ -s "$delete_log" ] && fail "dry-run must never delete anything"
echo "PASS: dry-run without principal lists all matching assignments and deletes nothing"

# 2. --execute without PRINCIPAL_ID or ASSIGNMENT_IDS must be refused with a non-zero exit, and
#    must not delete anything.
: >"$delete_log"
if COSMOS_ACCOUNT_ID="$ACCOUNT_ID" bash "$SCRIPT" --execute >/dev/null 2>"$workdir/stderr.txt"; then
  fail "--execute without principal/assignment-ids unexpectedly succeeded"
fi
grep -qi "requires either" "$workdir/stderr.txt" || fail "refusal error message missing expected guidance"
[ -s "$delete_log" ] && fail "refused --execute must not delete anything"
echo "PASS: --execute without principal/assignment-ids is refused"

# 3. --execute with PRINCIPAL_ID must delete only that principal's assignment(s), not the other
#    workload's assignment matching the same role+scope.
: >"$delete_log"
run_cleanup --execute "--principal-id=${PRINCIPAL_STALE}" >/dev/null
grep -q "obsolete-assignment-stale" "$delete_log" || fail "expected deletion of the stale principal's assignment did not happen"
grep -q "legit-assignment-other-workload" "$delete_log" && fail "deletion must not touch a different principal's grant"
echo "PASS: --execute with PRINCIPAL_ID deletes only the targeted principal's assignment(s)"

# 4. --execute with --assignment-ids must delete only the listed id(s).
: >"$delete_log"
run_cleanup --execute "--assignment-ids=legit-assignment-other-workload" >/dev/null
grep -q "legit-assignment-other-workload" "$delete_log" || fail "expected deletion via --assignment-ids did not happen"
grep -q "obsolete-assignment-stale" "$delete_log" && fail "deletion must not touch an assignment not listed via --assignment-ids"
echo "PASS: --execute with --assignment-ids deletes only the listed assignment(s)"

# 5. A malformed COSMOS_ACCOUNT_ID must still be rejected (regression guard for existing check).
if COSMOS_ACCOUNT_ID=shared-cosmos bash "$SCRIPT" >/dev/null 2>&1; then
  fail "expected malformed account resource ID to be rejected"
fi
echo "PASS: malformed COSMOS_ACCOUNT_ID is rejected"

echo "Stale Cosmos database RBAC cleanup tests passed."
