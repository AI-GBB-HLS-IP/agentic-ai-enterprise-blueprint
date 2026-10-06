#!/usr/bin/env bash
set -uo pipefail

# Read-only audit for an existing BYO-VNet Foundry deployment (Microsoft.CognitiveServices
# kind=AIServices, network-injected). It checks every account/project found against the
# approved reference pattern in infra/modules/foundry/*.bicep and prints a PASS/WARN/FAIL
# verdict per check, with a pointer to the bicep module that encodes the expected state.
#
# This does NOT apply to greenfield deployments created end-to-end by foundry.bicep in this
# repo (those already satisfy every check here by construction). It targets customer
# environments that were deployed by hand, by a different tool/template, or partially
# remediated out-of-band -- i.e. exactly the class of drift that caused the
# "customer-managed downstream dependency returned an error" Agents-tab failure this script
# was built to catch going forward.
#
# Usage:
#   SUBSCRIPTION_ID=<sub-id> ./audit-byo-deployment.sh
#   SUBSCRIPTION_ID=<sub-id> RG_FILTER=<resource-group-substring> ./audit-byo-deployment.sh
#
# Requires: az CLI (logged in), jq.

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID is required}"
RG_FILTER="${RG_FILTER:-}"
API_VERSION="2025-04-01-preview"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

verdict() {
  local status="$1" message="$2" hint="${3:-}"
  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)); echo "    [PASS] $message" ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)); echo "    [WARN] $message"; [ -n "$hint" ] && echo "           -> $hint" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); echo "    [FAIL] $message"; [ -n "$hint" ] && echo "           -> $hint" ;;
  esac
}

az account set --subscription "$SUBSCRIPTION_ID"
CURRENT_SUB="$(az account show --query id -o tsv)"
if [ "$CURRENT_SUB" != "$SUBSCRIPTION_ID" ]; then
  echo "ABORT: active subscription ($CURRENT_SUB) does not match requested ($SUBSCRIPTION_ID)." >&2
  exit 1
fi

echo "=== Subscription: $(az account show --query name -o tsv) ($SUBSCRIPTION_ID) ==="
[ -n "$RG_FILTER" ] && echo "=== Resource group filter: $RG_FILTER ==="
echo

if [ -n "$RG_FILTER" ]; then
  ACCOUNTS=$(az cognitiveservices account list --query "[?kind=='AIServices' && contains(resourceGroup, '${RG_FILTER}')].{name:name, rg:resourceGroup}" -o tsv)
else
  ACCOUNTS=$(az cognitiveservices account list --query "[?kind=='AIServices'].{name:name, rg:resourceGroup}" -o tsv)
fi

if [ -z "$ACCOUNTS" ]; then
  echo "No AIServices accounts found."
  exit 0
fi

# Finds a connection of the given category at project scope first, falling back to the
# account-level connection (inherited by every project). Echoes "name|scope|resourceId".
find_connection() {
  local category="$1" proj_json="$2" acct_json="$3"
  local row
  row=$(echo "$proj_json" | jq -r --arg c "$category" \
    '.value[]? | select(.properties.category==$c) | "\(.name)|project|\(.properties.metadata.ResourceId // "")"' | head -1)
  if [ -n "$row" ]; then echo "$row"; return; fi
  row=$(echo "$acct_json" | jq -r --arg c "$category" \
    '.value[]? | select(.properties.category==$c) | "\(.name)|account|\(.properties.metadata.ResourceId // "")"' | head -1)
  echo "$row"
}

# Checks whether PRINCIPAL_ID has ROLE_GUID assigned at SCOPE (management-plane RBAC).
has_role_assignment() {
  local scope="$1" principal_id="$2" role_guid="$3"
  local count
  count=$(az role assignment list --scope "$scope" \
    --query "[?principalId=='${principal_id}' && roleDefinitionId.ends_with(@, '${role_guid}')] | length(@)" \
    -o tsv 2>/dev/null || echo 0)
  [ "${count:-0}" -ge 1 ]
}

mapfile -t ACCOUNT_LINES <<< "$ACCOUNTS"
for LINE in "${ACCOUNT_LINES[@]}"; do
  IFS=$'\t' read -r NAME RG <<< "$LINE"
  echo "=============================================================="
  echo "ACCOUNT: $NAME   (RG: $RG)"
  echo "=============================================================="

  ACCT_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME?api-version=$API_VERSION"
  ACCT_JSON=$(az rest --method get --url "$ACCT_URL" -o json 2>/dev/null)

  echo "--- [1] Network injection / public network access ---"
  PNA=$(echo "$ACCT_JSON" | jq -r '.properties.publicNetworkAccess // "Unknown"')
  SUBNET=$(echo "$ACCT_JSON" | jq -r '.properties.networkInjections[0].subnetArnResourceId // empty')
  if [ -n "$SUBNET" ]; then
    verdict PASS "network-injected (subnet: $SUBNET)"
  else
    verdict WARN "no networkInjections found (publicNetworkAccess=$PNA)" \
      "expected for BYO-VNet accounts; see infra/modules/foundry/main.bicep account resource"
  fi

  echo "--- [2] Projects ---"
  PROJECTS_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects?api-version=$API_VERSION"
  PROJECTS=$(az rest --method get --url "$PROJECTS_URL" --query "value[].name" -o tsv 2>/dev/null)
  if [ -z "$PROJECTS" ]; then
    echo "  (no projects found)"
  fi

  ACCT_CONN_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/connections?api-version=$API_VERSION"
  ACCT_CONN_JSON=$(az rest --method get --url "$ACCT_CONN_URL" -o json 2>/dev/null)

  for PROJ in $PROJECTS; do
    echo "  --- Project: $PROJ ---"
    PROJ_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ?api-version=$API_VERSION"
    PRINCIPAL_ID=$(az rest --method get --url "$PROJ_URL" --query identity.principalId -o tsv 2>/dev/null)
    if [ -z "$PRINCIPAL_ID" ]; then
      verdict FAIL "could not resolve project managed identity principalId"
      continue
    fi

    PROJ_CONN_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ/connections?api-version=$API_VERSION"
    PROJ_CONN_JSON=$(az rest --method get --url "$PROJ_CONN_URL" -o json 2>/dev/null)

    COSMOS_ROW=$(find_connection "CosmosDB" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    STORAGE_ROW=$(find_connection "AzureStorageAccount" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    SEARCH_ROW=$(find_connection "CognitiveSearch" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    COSMOS_RESID="${COSMOS_ROW##*|}"; STORAGE_RESID="${STORAGE_ROW##*|}"; SEARCH_RESID="${SEARCH_ROW##*|}"

    echo "  [1] Required connections (Cosmos DB / Storage / AI Search):"
    [ -n "$COSMOS_ROW" ] && verdict PASS "CosmosDB connection: ${COSMOS_ROW%%|*} (${COSMOS_ROW#*|})" || verdict FAIL "no CosmosDB connection" "infra/modules/foundry/project-connections.bicep"
    [ -n "$STORAGE_ROW" ] && verdict PASS "AzureStorageAccount connection: ${STORAGE_ROW%%|*} (${STORAGE_ROW#*|})" || verdict FAIL "no AzureStorageAccount connection" "infra/modules/foundry/project-connections.bicep"
    [ -n "$SEARCH_ROW" ] && verdict PASS "CognitiveSearch connection: ${SEARCH_ROW%%|*} (${SEARCH_ROW#*|})" || verdict FAIL "no CognitiveSearch connection" "infra/modules/foundry/project-connections.bicep"

    echo "  [2] Capability Host:"
    CAP_HOSTS_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ/capabilityHosts?api-version=$API_VERSION"
    CAP_HOSTS_JSON=$(az rest --method get --url "$CAP_HOSTS_URL" -o json 2>/dev/null)
    CAP_HOST_NAME=$(echo "$CAP_HOSTS_JSON" | jq -r '.value[0].name // empty')
    CAP_HOST_STATE=""
    if [ -n "$CAP_HOST_NAME" ]; then
      CAP_HOST_STATE=$(echo "$CAP_HOSTS_JSON" | jq -r '.value[0].properties.provisioningState // "Unknown"')
      if [ "$CAP_HOST_STATE" = "Succeeded" ]; then
        verdict PASS "Capability Host '$CAP_HOST_NAME' provisioningState=Succeeded"
      else
        verdict WARN "Capability Host '$CAP_HOST_NAME' provisioningState=$CAP_HOST_STATE" \
          "infra/modules/foundry/capability-host.bicep"
      fi
    else
      verdict FAIL "no Capability Host found" "infra/modules/foundry/capability-host.bicep (depends on cosmosDBRbac, storageRbac, aiSearchRbac)"
    fi

    echo "  [3] RBAC on project managed identity ($PRINCIPAL_ID):"
    if [ -n "$COSMOS_RESID" ]; then
      if has_role_assignment "$COSMOS_RESID" "$PRINCIPAL_ID" "230815da-be43-4aae-9cb4-875f7bd000aa"; then
        verdict PASS "Cosmos DB Operator (mgmt-plane) on Cosmos account"
      else
        verdict FAIL "missing Cosmos DB Operator role on Cosmos account" "infra/modules/foundry/cosmos-rbac.bicep"
      fi
      COSMOS_ACCT_NAME=$(basename "$COSMOS_RESID")
      COSMOS_RG=$(echo "$COSMOS_RESID" | sed -n 's#.*/resourceGroups/\([^/]*\)/.*#\1#p')
      if [ "$CAP_HOST_STATE" = "Succeeded" ]; then
        DATA_ROLE_COUNT=$(az cosmosdb sql role assignment list --account-name "$COSMOS_ACCT_NAME" --resource-group "$COSMOS_RG" \
          --query "[?principalId=='${PRINCIPAL_ID}' && roleDefinitionId.ends_with(@, '0000-0000-0000-0000-000000000002') && contains(scope, '/dbs/enterprise_memory')] | length(@)" -o tsv 2>/dev/null || echo 0)
        if [ "${DATA_ROLE_COUNT:-0}" -ge 1 ]; then
          verdict PASS "Cosmos DB Data Contributor (data-plane) scoped to enterprise_memory"
        else
          verdict FAIL "missing Cosmos DB Data Contributor on enterprise_memory database" "infra/modules/foundry/cosmos-data-rbac.bicep (must run AFTER Capability Host activates)"
        fi
      else
        verdict WARN "skipped Cosmos data-plane RBAC check (Capability Host not yet Succeeded)"
      fi
    else
      verdict WARN "cannot check Cosmos RBAC: connection has no metadata.ResourceId"
    fi

    if [ -n "$SEARCH_RESID" ]; then
      if has_role_assignment "$SEARCH_RESID" "$PRINCIPAL_ID" "8ebe5a00-799e-43f5-93ac-243d3dce84a7"; then
        verdict PASS "Search Index Data Contributor on AI Search service"
      else
        verdict FAIL "missing Search Index Data Contributor" "infra/modules/foundry/ai-search-rbac.bicep"
      fi
      if has_role_assignment "$SEARCH_RESID" "$PRINCIPAL_ID" "7ca78c08-252a-4471-8644-bb5ff32d4ba0"; then
        verdict PASS "Search Service Contributor on AI Search service"
      else
        verdict FAIL "missing Search Service Contributor" "infra/modules/foundry/ai-search-rbac.bicep"
      fi
    else
      verdict WARN "cannot check AI Search RBAC: connection has no metadata.ResourceId"
    fi

    if [ -n "$STORAGE_RESID" ]; then
      if has_role_assignment "$STORAGE_RESID" "$PRINCIPAL_ID" "ba92f5b4-2d11-453d-a403-e96b0029c9fe"; then
        verdict PASS "Storage Blob Data Contributor on storage account"
      else
        verdict FAIL "missing Storage Blob Data Contributor" "infra/modules/foundry/storage-rbac.bicep"
      fi
      if has_role_assignment "$STORAGE_RESID" "$PRINCIPAL_ID" "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"; then
        verdict PASS "Storage Blob Data Owner (scoped) on storage account"
      else
        verdict FAIL "missing Storage Blob Data Owner" "infra/modules/foundry/storage-rbac.bicep"
      fi
    else
      verdict WARN "cannot check Storage RBAC: connection has no metadata.ResourceId"
    fi
  done

  echo "--- [3] Private DNS zone links (RG-scoped) ---"
  for ZONE in privatelink.cognitiveservices.azure.com privatelink.openai.azure.com privatelink.search.windows.net privatelink.documents.azure.com privatelink.blob.core.windows.net privatelink.vaultcore.azure.net; do
    LINKED=$(az network private-dns link vnet list --zone-name "$ZONE" --resource-group "$RG" --query "[].virtualNetwork.id" -o tsv 2>/dev/null)
    if [ -n "$LINKED" ]; then
      verdict PASS "$ZONE linked to $(echo "$LINKED" | wc -l | tr -d ' ') VNet(s)"
    else
      verdict WARN "$ZONE has no VNet link in $RG" "verify the zone lives in a different RG/subscription (hub) before treating as FAIL"
    fi
  done
  echo
done

echo "=============================================================="
echo "SUMMARY: $PASS_COUNT passed, $WARN_COUNT warnings, $FAIL_COUNT failed"
echo "=============================================================="
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
