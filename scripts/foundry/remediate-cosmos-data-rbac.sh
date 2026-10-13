#!/usr/bin/env bash
set -euo pipefail

# Restore only missing SQL data grants for one existing project's three containers.
# Usage: FOUNDRY_PROJECT_ID=<full-project-resource-id> bash "$0"
# Execute additionally requires EXPECTED_PRINCIPAL_ID copied from the dry-run.

die() { echo "ERROR: $*" >&2; exit 1; }

EXECUTE=false
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=true ;;
    *) die "Unknown argument: $arg. Usage: $0 [--execute]" ;;
  esac
done

: "${FOUNDRY_PROJECT_ID:?FOUNDRY_PROJECT_ID must be a full Foundry project resource ID}"
CAPABILITY_HOST_NAME="${CAPABILITY_HOST_NAME:-caphostproj}"
EXPECTED_PRINCIPAL_ID="${EXPECTED_PRINCIPAL_ID:-}"
API_VERSION="2025-04-01-preview"
GUID_PATTERN='^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$'

for tool in az jq python3; do
  command -v "$tool" >/dev/null 2>&1 || die "Required command not found: $tool"
done

shopt -s nocasematch
if [[ ! "$FOUNDRY_PROJECT_ID" =~ ^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.CognitiveServices/accounts/([^/]+)/projects/([^/]+)$ ]]; then
  die "FOUNDRY_PROJECT_ID must identify Microsoft.CognitiveServices/accounts/projects."
fi
PROJECT_SUBSCRIPTION="${BASH_REMATCH[1]}"
[[ "$PROJECT_SUBSCRIPTION" =~ $GUID_PATTERN ]] || die "Project subscription must be a GUID."
[[ "$CAPABILITY_HOST_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid CAPABILITY_HOST_NAME."
if [ -n "$EXPECTED_PRINCIPAL_ID" ]; then
  [[ "$EXPECTED_PRINCIPAL_ID" =~ $GUID_PATTERN ]] || die "EXPECTED_PRINCIPAL_ID must be a GUID."
fi
if [ "$EXECUTE" = true ] && [ -z "$EXPECTED_PRINCIPAL_ID" ]; then
  die "--execute requires EXPECTED_PRINCIPAL_ID from the reviewed dry-run."
fi

PROJECT_URL="https://management.azure.com${FOUNDRY_PROJECT_ID}"
ACCOUNT_URL="https://management.azure.com${FOUNDRY_PROJECT_ID%/*/*}"
PROJECT_JSON="$(az rest --method get --url "${PROJECT_URL}?api-version=${API_VERSION}" \
  --subscription "$PROJECT_SUBSCRIPTION" -o json)"
PRINCIPAL_ID="$(printf '%s' "$PROJECT_JSON" | jq -er '.identity.principalId')"
[[ "$PRINCIPAL_ID" =~ $GUID_PATTERN ]] || die "Project has no valid managed identity principal ID."
if [ -n "$EXPECTED_PRINCIPAL_ID" ] && [[ "$PRINCIPAL_ID" != "$EXPECTED_PRINCIPAL_ID" ]]; then
  die "Project identity differs from EXPECTED_PRINCIPAL_ID; review a new dry-run."
fi
RAW_WORKSPACE_ID="$(printf '%s' "$PROJECT_JSON" | jq -er '.properties.internalId')"
[[ "$RAW_WORKSPACE_ID" =~ ^[[:xdigit:]]{32}$ ]] || die "Project internalId must be 32 hex characters."
WORKSPACE_ID="${RAW_WORKSPACE_ID:0:8}-${RAW_WORKSPACE_ID:8:4}-${RAW_WORKSPACE_ID:12:4}-${RAW_WORKSPACE_ID:16:4}-${RAW_WORKSPACE_ID:20:12}"

HOST_JSON="$(az rest --method get \
  --url "${PROJECT_URL}/capabilityHosts/${CAPABILITY_HOST_NAME}?api-version=${API_VERSION}" \
  --subscription "$PROJECT_SUBSCRIPTION" -o json)"
printf '%s' "$HOST_JSON" | jq -e '
  .properties.provisioningState == "Succeeded" and
  .properties.capabilityHostKind == "Agents" and
  (.properties.threadStorageConnections | type == "array" and length == 1) and
  (.properties.threadStorageConnections[0] | type == "string" and length > 0)
' >/dev/null || die "Host must be a Succeeded Agents host with exactly one thread-storage connection."
CONNECTION_NAME="$(printf '%s' "$HOST_JSON" | jq -r '.properties.threadStorageConnections[0]')"
PROJECT_CONNECTIONS="$(az rest --method get \
  --url "${PROJECT_URL}/connections?api-version=${API_VERSION}" \
  --subscription "$PROJECT_SUBSCRIPTION" -o json)"
ACCOUNT_CONNECTIONS="$(az rest --method get \
  --url "${ACCOUNT_URL}/connections?api-version=${API_VERSION}" \
  --subscription "$PROJECT_SUBSCRIPTION" -o json)"
for json in "$PROJECT_CONNECTIONS" "$ACCOUNT_CONNECTIONS"; do
  printf '%s' "$json" | jq -e '.value | type == "array"' >/dev/null ||
    die "Connections response must contain a value array."
  printf '%s' "$json" | jq -e '(.nextLink // "") == ""' >/dev/null ||
    die "Paginated connection listing is unsupported; no permissions changed."
done
CONNECTION="$(jq -cn --arg name "$CONNECTION_NAME" \
  --argjson project "$PROJECT_CONNECTIONS" --argjson account "$ACCOUNT_CONNECTIONS" '
  [$project.value[] | select((.name | split("/") | last | ascii_downcase) == ($name | ascii_downcase))] as $p |
  (if ($p | length) > 0 then $p else
    [$account.value[] | select((.name | split("/") | last | ascii_downcase) == ($name | ascii_downcase))]
  end) | if length == 1 then .[0] else error("Host connection is missing or ambiguous") end
')"
printf '%s' "$CONNECTION" | jq -e '
  (.properties.category | ascii_downcase) == "cosmosdb" and
  .properties.authType == "AAD"
' >/dev/null || die "Host thread storage must reference an AAD CosmosDb connection."
COSMOS_ID="$(printf '%s' "$CONNECTION" | jq -er '.properties.metadata.ResourceId')"
if [[ ! "$COSMOS_ID" =~ ^/subscriptions/([^/]+)/resourceGroups/([^/]+)/providers/Microsoft\.DocumentDB/databaseAccounts/([^/]+)$ ]]; then
  die "Connection ResourceId must identify a Cosmos DB account."
fi
COSMOS_SUBSCRIPTION="${BASH_REMATCH[1]}"
COSMOS_RG="${BASH_REMATCH[2]}"
COSMOS_NAME="${BASH_REMATCH[3]}"
[[ "$COSMOS_SUBSCRIPTION" =~ $GUID_PATTERN ]] || die "Cosmos subscription must be a GUID."
COSMOS_ARGS=(--subscription "$COSMOS_SUBSCRIPTION" --resource-group "$COSMOS_RG" --account-name "$COSMOS_NAME")
ACTUAL_COSMOS_ID="$(az cosmosdb show --subscription "$COSMOS_SUBSCRIPTION" \
  --resource-group "$COSMOS_RG" --name "$COSMOS_NAME" --query id -o tsv)"
[[ "$ACTUAL_COSMOS_ID" == "$COSMOS_ID" ]] || die "Resolved Cosmos account differs from connection ResourceId."
shopt -u nocasematch

CONTAINERS="$(az cosmosdb sql container list "${COSMOS_ARGS[@]}" \
  --database-name enterprise_memory -o json)"
printf '%s' "$CONTAINERS" | jq -e 'type == "array"' >/dev/null || die "Invalid container listing."
SUFFIXES=(thread-message-store system-thread-message-store agent-entity-store)
for suffix in "${SUFFIXES[@]}"; do
  container="${WORKSPACE_ID}-${suffix}"
  printf '%s' "$CONTAINERS" | jq -e --arg name "$container" \
    'any(.[]; .name == $name)' >/dev/null || die "Required container does not exist: $container"
done

ROLE_ID="${COSMOS_ID}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
list_assignments() {
  ASSIGNMENTS="$(az cosmosdb sql role assignment list "${COSMOS_ARGS[@]}" -o json)"
  printf '%s' "$ASSIGNMENTS" | jq -e '
    type == "array" and all(.[];
      (.principalId | type == "string") and
      (.roleDefinitionId | type == "string") and
      (.scope | type == "string"))
  ' >/dev/null || die "Invalid SQL role assignment listing."
}
has_assignment() {
  printf '%s' "$ASSIGNMENTS" | jq -e --arg pid "$PRINCIPAL_ID" --arg role "$ROLE_ID" \
    --arg scope "$1" --arg relative "${1#"$COSMOS_ID"}" '
    any(.[]; ((.principalId // "" | ascii_downcase) == ($pid | ascii_downcase)) and
      ((.roleDefinitionId // "" | ascii_downcase) == ($role | ascii_downcase)) and
      ((.scope // "" | ascii_downcase) as $s |
        $s == ($scope | ascii_downcase) or $s == ($relative | ascii_downcase)))
  ' >/dev/null
}
list_assignments
echo "Project: $FOUNDRY_PROJECT_ID"
echo "Principal: $PRINCIPAL_ID"
echo "Workspace: $WORKSPACE_ID"
echo "Cosmos account: $COSMOS_ID"
echo "Mode: $([ "$EXECUTE" = true ] && echo execute || echo dry-run)"

for suffix in "${SUFFIXES[@]}"; do
  container="${WORKSPACE_ID}-${suffix}"
  scope="${COSMOS_ID}/dbs/enterprise_memory/colls/${container}"
  if has_assignment "$scope"; then
    echo "PRESENT: $scope"
    continue
  fi
  # Match ARM guid() and cosmos-data-rbac.bicep so later IaC uses the same resource.
  assignment_id="$(python3 - "$WORKSPACE_ID" "$container" "$ROLE_ID" "$PRINCIPAL_ID" <<'PY'
import sys
import uuid
print(uuid.uuid5(uuid.UUID("11fb06fb-712d-4ddd-98c7-e71bbd588830"), "-".join(sys.argv[1:])))
PY
)"
  if [ "$EXECUTE" = true ]; then
    echo "CREATING: $scope (assignment $assignment_id)"
    az cosmosdb sql role assignment create "${COSMOS_ARGS[@]}" \
      --principal-id "$PRINCIPAL_ID" --role-definition-id "$ROLE_ID" \
      --scope "$scope" --role-assignment-id "$assignment_id" -o none
  else
    echo "[DRY-RUN] Would grant Cosmos DB Built-in Data Contributor: $scope (assignment $assignment_id)"
  fi
done

if [ "$EXECUTE" = true ]; then
  list_assignments
  for suffix in "${SUFFIXES[@]}"; do
    scope="${COSMOS_ID}/dbs/enterprise_memory/colls/${WORKSPACE_ID}-${suffix}"
    has_assignment "$scope" || die "Read-back did not find the expected grant: $scope. Inspect existing grants before retrying."
  done
  echo "PASS: all three project-container assignments verified in the management plane."
  echo "Permission propagation and live agent recovery remain unverified; retry authenticated agent listing."
else
  echo "Dry-run complete; no Azure permissions changed."
  echo "Review the targets, then set EXPECTED_PRINCIPAL_ID=$PRINCIPAL_ID and rerun with --execute."
fi
