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
# Safe by construction: it only ever matches assignments whose `scope` ends in exactly
# `/dbs/enterprise_memory` (no `/colls/<container>` suffix). Container-scoped assignments created
# by the current Bicep are never touched.
#
# Usage:
#   COSMOS_ACCOUNT_ID=<full-account-resource-id> ./cleanup-stale-cosmos-database-rbac.sh
#   COSMOS_ACCOUNT_ID=<full-account-resource-id> PRINCIPAL_ID=<project-identity-guid> ./cleanup-stale-cosmos-database-rbac.sh --execute
#
# PRINCIPAL_ID is optional; omit it to report/remove the stale grant for every principal still
# holding it (useful when multiple projects share the Cosmos account). Dry-run by default; pass
# --execute to actually delete.

: "${COSMOS_ACCOUNT_ID:?COSMOS_ACCOUNT_ID must be the full Cosmos DB account resource ID}"
if [[ ! "$COSMOS_ACCOUNT_ID" =~ ^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.DocumentDB/databaseAccounts/([^/]+)$ ]]; then
  echo "COSMOS_ACCOUNT_ID must be a full /subscriptions/.../resourceGroups/.../providers/Microsoft.DocumentDB/databaseAccounts/... resource ID." >&2
  exit 1
fi
COSMOS_SUBSCRIPTION_ID="${BASH_REMATCH[1]}"
RG_NAME="${BASH_REMATCH[2]}"
COSMOS_ACCOUNT_NAME="${BASH_REMATCH[3]}"
PRINCIPAL_ID="${PRINCIPAL_ID:-}"
EXECUTE=false
[ "${1:-}" = "--execute" ] && EXECUTE=true

echo "=== Stale Cosmos database-scope RBAC cleanup (dry-run=$([ "$EXECUTE" = true ] && echo false || echo true)) ==="
echo "Cosmos account: $COSMOS_ACCOUNT_ID"
echo "Resource group: $RG_NAME"
[ -n "$PRINCIPAL_ID" ] && echo "Principal filter: $PRINCIPAL_ID"
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
  echo "Dry-run complete. Re-run with --execute to apply. Verify afterwards with:"
fi
echo "  az cosmosdb sql role assignment list --account-name '$COSMOS_ACCOUNT_NAME' --resource-group '$RG_NAME' --subscription '$COSMOS_SUBSCRIPTION_ID' --query \"$QUERY\" -o table"
