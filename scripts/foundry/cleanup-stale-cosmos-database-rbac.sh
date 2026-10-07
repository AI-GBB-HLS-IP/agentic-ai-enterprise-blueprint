#!/usr/bin/env bash
set -euo pipefail

# Removes the obsolete database-scoped Cosmos DB Built-in Data Contributor role assignment left
# behind by an earlier revision of cosmos-data-rbac.bicep. That revision assigned the role at
# `/dbs/enterprise_memory` (covering every container, and therefore every project's memory, in a
# shared/BYO Cosmos account). The current revision instead assigns the role per-project to only
# the three workspace-prefixed containers (`*-thread-message-store`, `*-system-thread-message-store`,
# `*-agent-entity-store`). Because ARM Incremental mode does not delete resources that are removed
# from a template, any deployment that ran the earlier revision still has the broader,
# database-scoped assignment in place even after redeploying the current Bicep -- this script finds
# and removes it.
#
# Scope/role filtering: it only ever matches assignments whose `scope` ends in exactly
# `/dbs/enterprise_memory` (no `/colls/<container>` suffix) and whose `roleDefinitionId` is the
# Cosmos DB Built-in Data Contributor role. Container-scoped assignments created by the current
# Bicep, and assignments using any other role, are never touched. This filtering alone is NOT
# sufficient to prove a matching assignment is the stale one: because this blueprint supports
# shared/BYO Cosmos accounts, a database-scoped Built-in Data Contributor grant can also be a
# legitimate assignment owned by a different workload on the same account. To avoid deleting the
# wrong principal's access, --execute additionally REQUIRES the caller to explicitly identify
# which assignment(s) to remove, either by PRINCIPAL_ID (the stale project's managed identity) or
# by an explicit ASSIGNMENT_IDS list (e.g. copied from a prior dry-run review).
#
# Usage:
#   # Dry-run / discovery: lists every matching assignment, no principal required.
#   COSMOS_ACCOUNT_ID=<full-account-resource-id> ./cleanup-stale-cosmos-database-rbac.sh
#
#   # Execute: requires PRINCIPAL_ID ...
#   COSMOS_ACCOUNT_ID=<full-account-resource-id> PRINCIPAL_ID=<project-identity-guid> \
#     ./cleanup-stale-cosmos-database-rbac.sh --execute
#
#   # ... or an explicit assignment-id list (from --assignment-ids or ASSIGNMENT_IDS env var).
#   COSMOS_ACCOUNT_ID=<full-account-resource-id> \
#     ./cleanup-stale-cosmos-database-rbac.sh --execute --assignment-ids=<id1>,<id2>
#
# PRINCIPAL_ID and ASSIGNMENT_IDS are mutually exclusive ways of scoping a deletion; at least one
# is required whenever --execute is passed. Neither is required for a dry-run: dry-run listing
# remains unrestricted for discovery/visibility purposes.

: "${COSMOS_ACCOUNT_ID:?COSMOS_ACCOUNT_ID must be the full Cosmos DB account resource ID}"
if [[ ! "$COSMOS_ACCOUNT_ID" =~ ^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.DocumentDB/databaseAccounts/([^/]+)$ ]]; then
  echo "COSMOS_ACCOUNT_ID must be a full /subscriptions/.../resourceGroups/.../providers/Microsoft.DocumentDB/databaseAccounts/... resource ID." >&2
  exit 1
fi
COSMOS_SUBSCRIPTION_ID="${BASH_REMATCH[1]}"
RG_NAME="${BASH_REMATCH[2]}"
COSMOS_ACCOUNT_NAME="${BASH_REMATCH[3]}"
PRINCIPAL_ID="${PRINCIPAL_ID:-}"
ASSIGNMENT_IDS="${ASSIGNMENT_IDS:-}"
EXECUTE=false

for arg in "$@"; do
  case "$arg" in
    --execute)
      EXECUTE=true
      ;;
    --principal-id=*)
      PRINCIPAL_ID="${arg#--principal-id=}"
      ;;
    --assignment-ids=*)
      ASSIGNMENT_IDS="${arg#--assignment-ids=}"
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--execute] [--principal-id=<guid>] [--assignment-ids=<id1,id2,...>]" >&2
      exit 1
      ;;
  esac
done

if [ "$EXECUTE" = true ] && [ -z "$PRINCIPAL_ID" ] && [ -z "$ASSIGNMENT_IDS" ]; then
  echo "ERROR: --execute requires either PRINCIPAL_ID (env var or --principal-id=<guid>) or" >&2
  echo "       ASSIGNMENT_IDS (env var or --assignment-ids=<id1,id2,...>) to scope the deletion" >&2
  echo "       to a specific principal or explicit set of assignments. This blueprint supports" >&2
  echo "       shared/BYO Cosmos accounts, so an unscoped --execute could delete a legitimate" >&2
  echo "       database-scoped grant owned by another workload. Re-run without --execute first" >&2
  echo "       to review matching assignments, then target the specific principal/assignment(s)." >&2
  exit 1
fi

if [ -n "$PRINCIPAL_ID" ] && [[ ! "$PRINCIPAL_ID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
  echo "ERROR: PRINCIPAL_ID must be a GUID." >&2
  exit 1
fi

echo "=== Stale Cosmos database-scope RBAC cleanup (dry-run=$([ "$EXECUTE" = true ] && echo false || echo true)) ==="
echo "Cosmos account: $COSMOS_ACCOUNT_ID"
echo "Resource group: $RG_NAME"
[ -n "$PRINCIPAL_ID" ] && echo "Principal filter: $PRINCIPAL_ID"
[ -n "$ASSIGNMENT_IDS" ] && echo "Assignment-id filter: $ASSIGNMENT_IDS"
echo

QUERY="[?(scope=='/dbs/enterprise_memory' || ends_with(scope, '/dbs/enterprise_memory')) && ends_with(roleDefinitionId, '00000000-0000-0000-0000-000000000002')]"
if [ -n "$PRINCIPAL_ID" ]; then
  QUERY="[?(scope=='/dbs/enterprise_memory' || ends_with(scope, '/dbs/enterprise_memory')) && ends_with(roleDefinitionId, '00000000-0000-0000-0000-000000000002') && principalId=='${PRINCIPAL_ID}']"
fi

STALE_JSON=$(az cosmosdb sql role assignment list \
  --account-name "$COSMOS_ACCOUNT_NAME" \
  --resource-group "$RG_NAME" \
  --subscription "$COSMOS_SUBSCRIPTION_ID" \
  --query "$QUERY" -o json)

if [ -n "$ASSIGNMENT_IDS" ]; then
  STALE_JSON=$(echo "$STALE_JSON" | jq --arg ids "$ASSIGNMENT_IDS" '
    ($ids | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $wanted
    | map(select(.id as $id | $wanted | index($id) != null))')
fi

STALE_COUNT=$(echo "$STALE_JSON" | jq 'length')
if [ "$STALE_COUNT" -eq 0 ]; then
  echo "No stale database-scoped assignments found. Nothing to do."
  exit 0
fi

echo "Found $STALE_COUNT stale database-scoped assignment(s):"
echo "$STALE_JSON" | jq -r '.[] | "  id=\(.id)\n    principalId=\(.principalId)  scope=\(.scope)  roleDefinitionId=\(.roleDefinitionId)"'
echo

echo "$STALE_JSON" | jq -r '.[].id' | while IFS= read -r ASSIGNMENT_ID; do
  if [ "$EXECUTE" = true ]; then
    echo "Deleting $ASSIGNMENT_ID ..."
    az cosmosdb sql role assignment delete \
      --account-name "$COSMOS_ACCOUNT_NAME" \
      --resource-group "$RG_NAME" \
      --subscription "$COSMOS_SUBSCRIPTION_ID" \
      --role-assignment-id "$ASSIGNMENT_ID" \
      --yes
  else
    echo "[DRY-RUN] Would delete: $ASSIGNMENT_ID"
  fi
done

echo
if [ "$EXECUTE" = true ]; then
  echo "Done. Verify with:"
else
  echo "Dry-run complete. Re-run with --execute (and --principal-id=<guid> or"
  echo "--assignment-ids=<id1,id2,...>) to apply. Verify afterwards with:"
fi
echo "  az cosmosdb sql role assignment list --account-name '$COSMOS_ACCOUNT_NAME' --resource-group '$RG_NAME' --subscription '$COSMOS_SUBSCRIPTION_ID' --query \"$QUERY\" -o table"
