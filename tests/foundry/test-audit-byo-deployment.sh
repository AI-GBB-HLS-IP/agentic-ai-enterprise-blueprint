#!/usr/bin/env bash
set -uo pipefail

# Regression coverage for scripts/foundry/audit-byo-deployment.sh.
#
# The audit script is read-only but still makes many `az` CLI calls (account/project discovery,
# connection/capability-host lookups, RBAC role-assignment queries, DNS zone/link queries). None
# of this can run against live Azure credentials in CI, so every test below stubs `az` with a
# fake executable placed earlier on PATH. The stub's behavior is driven entirely by environment
# variables (set per scenario) and it appends every invocation's full argument list to
# $AZ_CALL_LOG, which tests use to assert exact cross-subscription argument passthrough.
#
# Follows the stubbing/temp-dir/exit-code conventions of test-purge-safety-gate.sh.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
AUDIT_SCRIPT="$REPO_ROOT/scripts/foundry/audit-byo-deployment.sh"

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not available; audit-byo-deployment.sh requires it and so does this test." >&2
  exit 0
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
STUBDIR="$WORKDIR/stub"
mkdir -p "$STUBDIR"

FAILED=0
fail() {
  echo "FAIL: $1" >&2
  FAILED=1
}

# Writes the shared az stub into $STUBDIR/az. Behavior is controlled by environment variables
# set by the caller before invoking the audit script; see the long comment block above each
# handled command below for which variables it reads.
cat >"$STUBDIR/az" <<'STUB'
#!/usr/bin/env bash
set -u

if [ -n "${AZ_CALL_LOG:-}" ]; then
  printf '%s\n' "$*" >>"$AZ_CALL_LOG"
fi

# Finds the value following a given flag name (e.g. "--url", "-q") in the remaining args.
get_opt_val() {
  local name="$1"; shift
  local prev=""
  for a in "$@"; do
    if [ "$prev" = "$name" ]; then
      printf '%s' "$a"
      return
    fi
    prev="$a"
  done
}

case "$1 $2" in
  "account set")
    exit "${ACCOUNT_SET_EXIT:-0}"
    ;;
  "account show")
    case "$*" in
      *"--query name"*) echo "${SUB_NAME:-Test Subscription}" ;;
      *"--query id"*) echo "${SUB_ID:-11111111-1111-1111-1111-111111111111}" ;;
    esac
    exit 0
    ;;
  "extension show")
    exit "${EXT_SHOW_EXIT:-1}"
    ;;
  "extension add")
    exit "${EXT_ADD_EXIT:-1}"
    ;;
  "cosmosdb list")
    [ -n "${COSMOS_LIST_OUT:-}" ] && printf '%s\n' "${COSMOS_LIST_OUT}"
    exit "${COSMOS_LIST_EXIT:-0}"
    ;;
  "graph query")
    qval="$(get_opt_val -q "$@")"
    case "$qval" in
      *"take 1"*)
        exit "${GRAPH_PROBE_EXIT:-0}"
        ;;
      *privateendpoints*)
        printf '%s' "${GRAPH_PE_HITS:-[]}"
        exit 0
        ;;
      *privatednszones*)
        # Zone name is quoted as name =~ '<zone>' in the KQL text; extract it so each zone can
        # have its own fixture (privatelink.services.ai.azure.com must behave differently from
        # e.g. privatelink.blob.core.windows.net in the zone-required test).
        zone="$(printf '%s' "$qval" | sed -n "s/.*name =~ '\([^']*\)'.*/\1/p")"
        fixture_file="${ZONE_HITS_DIR:-}/$zone"
        if [ -n "${ZONE_HITS_DIR:-}" ] && [ -f "$fixture_file" ]; then
          cat "$fixture_file"
        else
          printf '%s' "${ZONE_HITS_DEFAULT:-[]}"
        fi
        exit 0
        ;;
      *)
        printf '%s' "[]"
        exit 0
        ;;
    esac
    ;;
esac

case "$1 $2 $3" in
  "cognitiveservices account list")
    if [ "${ACCOUNT_LIST_EXIT:-0}" -ne 0 ]; then
      echo "simulated az cognitiveservices account list failure" >&2
      exit "${ACCOUNT_LIST_EXIT}"
    fi
    [ -n "${ACCOUNT_LIST_OUT:-}" ] && printf '%s\n' "${ACCOUNT_LIST_OUT}"
    exit 0
    ;;
  "role assignment list")
    query="$(get_opt_val --query "$@")"
    if printf '%s' "$query" | grep -q 'length(@)'; then
      # has_role_assignment(): generic single-role count check. Extract the role GUID from
      # roleDefinitionId.ends_with(@, '<guid>') and look up ROLE_COUNT_<guid-no-dashes>.
      guid="$(printf '%s' "$query" | sed -n "s/.*ends_with(@, '\([^']*\)').*/\1/p")"
      varname="ROLE_COUNT_$(printf '%s' "$guid" | tr -d '-')"
      printf '%s\n' "${!varname:-0}"
    else
      # has_scoped_storage_owner_assignment(): full JSON for the conditional-grant check.
      printf '%s' "${STORAGE_OWNER_JSON:-[]}"
    fi
    exit 0
    ;;
  "network private-endpoint dns-zone-group")
    [ -n "${DNS_ZONE_GROUP_OUT:-}" ] && printf '%s\n' "${DNS_ZONE_GROUP_OUT}"
    exit 0
    ;;
esac

if [ "$1" = "rest" ]; then
  url="$(get_opt_val --url "$@")"
  case "$url" in
    */capabilityHosts\?*)
      if [ "${CAP_HOSTS_EXIT:-0}" -ne 0 ]; then
        echo "simulated capability-host fetch failure" >&2
        exit "${CAP_HOSTS_EXIT}"
      fi
      _val="${CAP_HOSTS_JSON:-}"; [ -z "$_val" ] && _val='{}'
      printf '%s' "$_val"
      exit 0
      ;;
    */projects/*/connections\?*)
      if [ "${PROJ_CONN_EXIT:-0}" -ne 0 ]; then
        echo "simulated project-level connections fetch failure" >&2
        exit "${PROJ_CONN_EXIT}"
      fi
      _val="${PROJ_CONN_JSON:-}"; [ -z "$_val" ] && _val='{}'
      printf '%s' "$_val"
      exit 0
      ;;
    */projects/*\?*)
      if [ "${PROJ_REST_EXIT:-0}" -ne 0 ]; then
        echo "simulated project resource fetch failure" >&2
        exit "${PROJ_REST_EXIT}"
      fi
      _val="${PROJ_JSON:-}"; [ -z "$_val" ] && _val='{}'
      printf '%s' "$_val"
      exit 0
      ;;
    */projects\?*)
      if [ "${PROJECTS_EXIT:-0}" -ne 0 ]; then
        echo "simulated project list failure" >&2
        exit "${PROJECTS_EXIT}"
      fi
      [ -n "${PROJECTS_OUT:-}" ] && printf '%s\n' "${PROJECTS_OUT}"
      exit 0
      ;;
    */connections\?*)
      if [ "${ACCT_CONN_EXIT:-0}" -ne 0 ]; then
        echo "simulated account-level connections fetch failure" >&2
        exit "${ACCT_CONN_EXIT}"
      fi
      _val="${ACCT_CONN_JSON:-}"; [ -z "$_val" ] && _val='{}'
      printf '%s' "$_val"
      exit 0
      ;;
    *)
      if [ "${ACCT_REST_EXIT:-0}" -ne 0 ]; then
        echo "simulated account resource fetch failure" >&2
        exit "${ACCT_REST_EXIT}"
      fi
      _val="${ACCT_JSON:-}"; [ -z "$_val" ] && _val='{}'
      printf '%s' "$_val"
      exit 0
      ;;
  esac
fi

if [ "$1 $2 $3 $4" = "network private-dns link vnet" ] && [ "$5" = "list" ]; then
  zone="$(get_opt_val --zone-name "$@")"
  fixture_file="${DNS_LINK_DIR:-}/$zone"
  if [ -n "${DNS_LINK_DIR:-}" ] && [ -f "$fixture_file" ]; then
    cat "$fixture_file"
  fi
  exit 0
fi

if [ "$1 $2 $3 $4" = "cosmosdb sql role assignment" ] && [ "$5" = "list" ]; then
  printf '%s' "${COSMOS_DATA_JSON:-[]}"
  exit 0
fi

echo "Unhandled az stub invocation: $*" >&2
exit 1
STUB
chmod +x "$STUBDIR/az"

# Defaults shared by most scenarios: one AIServices account, Disabled public network access,
# network-injected, resource-graph extension unavailable (fast WARN-only path) unless a test
# explicitly needs the graph-available branch.
base_env() {
  unset ACCOUNT_SET_EXIT SUB_NAME SUB_ID ACCOUNT_LIST_EXIT ACCOUNT_LIST_OUT \
    ACCT_REST_EXIT ACCT_JSON ACCT_CONN_EXIT ACCT_CONN_JSON \
    PROJECTS_EXIT PROJECTS_OUT PROJ_REST_EXIT PROJ_JSON PROJ_CONN_EXIT PROJ_CONN_JSON \
    CAP_HOSTS_EXIT CAP_HOSTS_JSON COSMOS_LIST_EXIT COSMOS_LIST_OUT \
    EXT_SHOW_EXIT EXT_ADD_EXIT GRAPH_PROBE_EXIT GRAPH_PE_HITS \
    STORAGE_OWNER_JSON COSMOS_DATA_JSON DNS_ZONE_GROUP_OUT ZONE_HITS_DIR ZONE_HITS_DEFAULT \
    DNS_LINK_DIR 2>/dev/null
  SUB_ID="11111111-1111-1111-1111-111111111111"
  SUB_NAME="Test Subscription"
  ACCOUNT_LIST_OUT=$'acct1\trg1'
  ACCT_JSON='{"properties":{"publicNetworkAccess":"Disabled","networkInjections":[{"subnetArmId":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet1/subnets/snet1"}]}}'
  EXT_SHOW_EXIT=1
  EXT_ADD_EXIT=1
  PROJECTS_OUT=""
}

run_audit() {
  env -i PATH="$STUBDIR:/usr/bin:/bin" HOME="${HOME:-/root}" \
    AZ_CALL_LOG="${AZ_CALL_LOG:-$WORKDIR/calls.log}" \
    SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-11111111-1111-1111-1111-111111111111}" \
    RG_FILTER="${RG_FILTER:-}" EXPECTED_VNET_ID="${EXPECTED_VNET_ID:-}" \
    DNS_INTEGRATION_MODE="${DNS_INTEGRATION_MODE:-vnet-link}" \
    SUB_ID="${SUB_ID:-}" SUB_NAME="${SUB_NAME:-}" \
    ACCOUNT_SET_EXIT="${ACCOUNT_SET_EXIT:-0}" \
    ACCOUNT_LIST_EXIT="${ACCOUNT_LIST_EXIT:-0}" ACCOUNT_LIST_OUT="${ACCOUNT_LIST_OUT:-}" \
    ACCT_REST_EXIT="${ACCT_REST_EXIT:-0}" ACCT_JSON="${ACCT_JSON:-}" \
    ACCT_CONN_EXIT="${ACCT_CONN_EXIT:-0}" ACCT_CONN_JSON="${ACCT_CONN_JSON:-}" \
    PROJECTS_EXIT="${PROJECTS_EXIT:-0}" PROJECTS_OUT="${PROJECTS_OUT:-}" \
    PROJ_REST_EXIT="${PROJ_REST_EXIT:-0}" PROJ_JSON="${PROJ_JSON:-}" \
    PROJ_CONN_EXIT="${PROJ_CONN_EXIT:-0}" PROJ_CONN_JSON="${PROJ_CONN_JSON:-}" \
    CAP_HOSTS_EXIT="${CAP_HOSTS_EXIT:-0}" CAP_HOSTS_JSON="${CAP_HOSTS_JSON:-}" \
    COSMOS_LIST_EXIT="${COSMOS_LIST_EXIT:-0}" COSMOS_LIST_OUT="${COSMOS_LIST_OUT:-}" \
    EXT_SHOW_EXIT="${EXT_SHOW_EXIT:-1}" EXT_ADD_EXIT="${EXT_ADD_EXIT:-1}" \
    GRAPH_PROBE_EXIT="${GRAPH_PROBE_EXIT:-0}" GRAPH_PE_HITS="${GRAPH_PE_HITS:-[]}" \
    STORAGE_OWNER_JSON="${STORAGE_OWNER_JSON:-[]}" COSMOS_DATA_JSON="${COSMOS_DATA_JSON:-[]}" \
    DNS_ZONE_GROUP_OUT="${DNS_ZONE_GROUP_OUT:-}" \
    ZONE_HITS_DIR="${ZONE_HITS_DIR:-}" ZONE_HITS_DEFAULT="${ZONE_HITS_DEFAULT:-[]}" \
    DNS_LINK_DIR="${DNS_LINK_DIR:-}" \
    "$AUDIT_SCRIPT"
}

# Some scenarios need per-role-guid assignment counts; run_audit above can't forward an
# arbitrary/sparse set of ROLE_COUNT_* vars through "env -i" generically, so scenarios that need
# them export ROLE_COUNT_* directly and this wrapper re-exports whatever is already in the
# calling shell's environment by name.
run_audit_with_roles() {
  local extra=()
  for v in "$@"; do
    extra+=("$v=${!v}")
  done
  env -i PATH="$STUBDIR:/usr/bin:/bin" HOME="${HOME:-/root}" \
    AZ_CALL_LOG="${AZ_CALL_LOG:-$WORKDIR/calls.log}" \
    SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-11111111-1111-1111-1111-111111111111}" \
    RG_FILTER="${RG_FILTER:-}" EXPECTED_VNET_ID="${EXPECTED_VNET_ID:-}" \
    DNS_INTEGRATION_MODE="${DNS_INTEGRATION_MODE:-vnet-link}" \
    SUB_ID="${SUB_ID:-}" SUB_NAME="${SUB_NAME:-}" \
    ACCOUNT_SET_EXIT="${ACCOUNT_SET_EXIT:-0}" \
    ACCOUNT_LIST_EXIT="${ACCOUNT_LIST_EXIT:-0}" ACCOUNT_LIST_OUT="${ACCOUNT_LIST_OUT:-}" \
    ACCT_REST_EXIT="${ACCT_REST_EXIT:-0}" ACCT_JSON="${ACCT_JSON:-}" \
    ACCT_CONN_EXIT="${ACCT_CONN_EXIT:-0}" ACCT_CONN_JSON="${ACCT_CONN_JSON:-}" \
    PROJECTS_EXIT="${PROJECTS_EXIT:-0}" PROJECTS_OUT="${PROJECTS_OUT:-}" \
    PROJ_REST_EXIT="${PROJ_REST_EXIT:-0}" PROJ_JSON="${PROJ_JSON:-}" \
    PROJ_CONN_EXIT="${PROJ_CONN_EXIT:-0}" PROJ_CONN_JSON="${PROJ_CONN_JSON:-}" \
    CAP_HOSTS_EXIT="${CAP_HOSTS_EXIT:-0}" CAP_HOSTS_JSON="${CAP_HOSTS_JSON:-}" \
    COSMOS_LIST_EXIT="${COSMOS_LIST_EXIT:-0}" COSMOS_LIST_OUT="${COSMOS_LIST_OUT:-}" \
    EXT_SHOW_EXIT="${EXT_SHOW_EXIT:-1}" EXT_ADD_EXIT="${EXT_ADD_EXIT:-1}" \
    GRAPH_PROBE_EXIT="${GRAPH_PROBE_EXIT:-0}" GRAPH_PE_HITS="${GRAPH_PE_HITS:-[]}" \
    STORAGE_OWNER_JSON="${STORAGE_OWNER_JSON:-[]}" COSMOS_DATA_JSON="${COSMOS_DATA_JSON:-[]}" \
    DNS_ZONE_GROUP_OUT="${DNS_ZONE_GROUP_OUT:-}" \
    ZONE_HITS_DIR="${ZONE_HITS_DIR:-}" ZONE_HITS_DEFAULT="${ZONE_HITS_DEFAULT:-[]}" \
    DNS_LINK_DIR="${DNS_LINK_DIR:-}" \
    "${extra[@]}" \
    "$AUDIT_SCRIPT"
}

good_project_json() {
  # identity.principalId=33...33, internalId is a 32-char hex string so
  # PROJECT_WORKSPACE_GUID == abcdef01-2345-6789-abcd-ef0123456789.
  printf '%s' '{"identity":{"type":"SystemAssigned","principalId":"33333333-3333-3333-3333-333333333333"},"properties":{"internalId":"abcdef0123456789abcdef0123456789"}}'
}

#######################################
# 1. Discovery az CLI failures must fail closed (FAIL/ABORT), never a silent clean PASS.
#######################################
echo "==> [1] discovery failures fail closed"

base_env
ACCOUNT_LIST_EXIT=3
if out="$(run_audit 2>&1)"; then
  fail "account-list failure should abort with non-zero exit"
fi
echo "$out" | grep -q "ABORT.*account list" || fail "account-list failure did not print an ABORT message (got: $out)"
echo "$out" | grep -qi "pass" && fail "account-list failure must not print any PASS verdict"

base_env
PROJECTS_OUT=""
PROJECTS_EXIT=7
if out="$(run_audit 2>&1)"; then
  fail "project-list failure should make the script exit non-zero"
fi
echo "$out" | grep -q "FAIL.*could not list projects" || fail "project-list failure did not record a FAIL verdict (got: $out)"

base_env
PROJECTS_OUT=""
ACCT_CONN_EXIT=5
if out="$(run_audit 2>&1)"; then
  fail "account-level connections fetch failure should make the script exit non-zero"
fi
echo "$out" | grep -q "FAIL.*could not fetch account-level connections" || fail "account-level connections failure did not record a FAIL verdict (got: $out)"

base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_EXIT=9
if out="$(run_audit 2>&1)"; then
  fail "project-level connections fetch failure should make the script exit non-zero"
fi
echo "$out" | grep -q "FAIL.*could not fetch project-level connections" || fail "project-level connections failure did not record a FAIL verdict (got: $out)"

base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
CAP_HOSTS_EXIT=11
if out="$(run_audit 2>&1)"; then
  fail "capability-host fetch failure should make the script exit non-zero"
fi
echo "$out" | grep -q "FAIL.*could not fetch Capability Host resource" || fail "capability-host failure did not record a FAIL verdict (got: $out)"

#######################################
# 2. Cross-subscription Cosmos connection: resource ID parsed and --subscription passed through.
#######################################
echo "==> [2] cross-subscription Cosmos connection ID parsing and --subscription passthrough"

OTHER_SUB="22222222-2222-2222-2222-222222222222"
COSMOS_RESID="/subscriptions/$OTHER_SUB/resourceGroups/rg-hub/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-hub"

base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_JSON="$(jq -n --arg rid "$COSMOS_RESID" '{value:[{name:"cosmos-conn",properties:{category:"CosmosDB",metadata:{ResourceId:$rid}}}]}')"
CALL_LOG="$WORKDIR/calls-cross-sub.log"
: >"$CALL_LOG"
AZ_CALL_LOG="$CALL_LOG" out="$(AZ_CALL_LOG="$CALL_LOG" run_audit 2>&1)"
echo "$out" | grep -q "CosmosDB connection: cosmos-conn" || fail "cross-subscription Cosmos connection was not discovered (got: $out)"
expected_call="cosmosdb sql role assignment list --account-name cosmos-hub --resource-group rg-hub --subscription $OTHER_SUB -o json"
grep -qF "$expected_call" "$CALL_LOG" || fail "cosmosdb sql role assignment list was not called with the connection's own --subscription $OTHER_SUB (calls were: $(cat "$CALL_LOG"))"

#######################################
# 3. RBAC scope/condition checks.
#######################################
echo "==> [3] RBAC scope/condition checks"

# 3a. Storage Blob Data Owner: unconditional (unscoped) grant must FAIL, not PASS.
base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_JSON='{"value":[{"name":"storage-conn","properties":{"category":"AzureStorageAccount","metadata":{"ResourceId":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/st1"}}}]}'
STORAGE_OWNER_JSON='[]'
ROLE_COUNT_b7e6dc6df1e8475380330f276bb0955b=1
out="$(run_audit_with_roles ROLE_COUNT_b7e6dc6df1e8475380330f276bb0955b 2>&1)"
echo "$out" | grep -q "FAIL.*Storage Blob Data Owner is assigned but not scoped by condition" || fail "unconditional Storage Blob Data Owner grant was not flagged as unscoped (got: $out)"

# 3b. Storage Blob Data Owner: properly scoped (conditionVersion=2.0 + ABAC condition matching
# workspace GUID and azureml-agent) must PASS.
base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_JSON='{"value":[{"name":"storage-conn","properties":{"category":"AzureStorageAccount","metadata":{"ResourceId":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/st1"}}}]}'
STORAGE_OWNER_JSON='[{"conditionVersion":"2.0","condition":"@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWith '"'"'abcdef01-2345-6789-abcd-ef0123456789-azureml-agent'"'"'"}]'
ROLE_COUNT_ba92f5b42d11453da403e96b0029c9fe=0
out="$(run_audit_with_roles ROLE_COUNT_ba92f5b42d11453da403e96b0029c9fe 2>&1)"
echo "$out" | grep -q "PASS.*Storage Blob Data Owner (scoped)" || fail "properly-scoped Storage Blob Data Owner grant was not PASSed (got: $out)"

# 3c. Cosmos per-container RBAC: all three project-prefixed containers must have the data-plane
# role assignment, not just one.
WORKSPACE_GUID="abcdef01-2345-6789-abcd-ef0123456789"
base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_JSON="$(jq -n --arg rid "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.DocumentDB/databaseAccounts/cosmos1" \
  '{value:[{name:"cosmos-conn",properties:{category:"CosmosDB",metadata:{ResourceId:$rid}}}]}')"
# Only "thread-message-store" has the role; the other two containers are missing it.
COSMOS_DATA_JSON="$(jq -n --arg pid "33333333-3333-3333-3333-333333333333" --arg c "${WORKSPACE_GUID}-thread-message-store" \
  '[{principalId:$pid, roleDefinitionId:"/.../0000-0000-0000-0000-000000000002", scope:("/dbs/x/colls/" + $c)}]')"
out="$(run_audit 2>&1)"
echo "$out" | grep -q "FAIL.*missing Cosmos DB Data Contributor on:.*system-thread-message-store" || fail "partial Cosmos per-container RBAC was not flagged as FAIL (got: $out)"
echo "$out" | grep -q "FAIL.*missing Cosmos DB Data Contributor on:.*agent-entity-store" || fail "partial Cosmos per-container RBAC did not list agent-entity-store as missing (got: $out)"

# All three containers present -> PASS.
base_env
PROJECTS_OUT="acct1/proj1"
PROJ_JSON="$(good_project_json)"
PROJ_CONN_JSON="$(jq -n --arg rid "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/providers/Microsoft.DocumentDB/databaseAccounts/cosmos1" \
  '{value:[{name:"cosmos-conn",properties:{category:"CosmosDB",metadata:{ResourceId:$rid}}}]}')"
COSMOS_DATA_JSON="$(jq -n --arg pid "33333333-3333-3333-3333-333333333333" \
  '[
    {principalId:$pid, roleDefinitionId:"/.../0000-0000-0000-0000-000000000002", scope:"/dbs/x/colls/abcdef01-2345-6789-abcd-ef0123456789-thread-message-store"},
    {principalId:$pid, roleDefinitionId:"/.../0000-0000-0000-0000-000000000002", scope:"/dbs/x/colls/abcdef01-2345-6789-abcd-ef0123456789-system-thread-message-store"},
    {principalId:$pid, roleDefinitionId:"/.../0000-0000-0000-0000-000000000002", scope:"/dbs/x/colls/abcdef01-2345-6789-abcd-ef0123456789-agent-entity-store"}
  ]')"
out="$(run_audit 2>&1)"
echo "$out" | grep -q "PASS.*Cosmos DB Data Contributor (data-plane) present on all 3 project containers" || fail "complete Cosmos per-container RBAC was not PASSed (got: $out)"

#######################################
# 4. Capability Host terminal vs. transient states.
#######################################
echo "==> [4] Capability Host terminal vs transient provisioning states"

for state in Failed Canceled; do
  base_env
  PROJECTS_OUT="acct1/proj1"
  PROJ_JSON="$(good_project_json)"
  CAP_HOSTS_JSON="$(jq -n --arg s "$state" '{value:[{name:"caphost1",properties:{provisioningState:$s}}]}')"
  out="$(run_audit 2>&1)"
  echo "$out" | grep -q "FAIL.*Capability Host 'caphost1' provisioningState=$state" || fail "Capability Host state '$state' was not flagged FAIL (got: $out)"
done

for state in Creating Updating; do
  base_env
  PROJECTS_OUT="acct1/proj1"
  PROJ_JSON="$(good_project_json)"
  CAP_HOSTS_JSON="$(jq -n --arg s "$state" '{value:[{name:"caphost1",properties:{provisioningState:$s}}]}')"
  out="$(run_audit 2>&1)"
  echo "$out" | grep -q "WARN.*Capability Host 'caphost1' provisioningState=$state" || fail "Capability Host state '$state' was not flagged WARN (got: $out)"
  echo "$out" | grep -q "FAIL.*Capability Host 'caphost1'" && fail "transient Capability Host state '$state' must not be a FAIL (got: $out)"
done

#######################################
# 5. DNS zone/link checks.
#######################################
echo "==> [5] DNS zone/link checks"

REQUIRED_ZONE="privatelink.services.ai.azure.com"

# 5a. Required zone missing entirely (in any subscription) -> FAIL, with graph available.
base_env
EXT_SHOW_EXIT=0
GRAPH_PROBE_EXIT=0
ZONE_HITS_DEFAULT='[]'
out="$(run_audit 2>&1)"
echo "$out" | grep -q "FAIL.*$REQUIRED_ZONE not found in any subscription" || fail "missing required zone $REQUIRED_ZONE was not flagged FAIL (got: $out)"

# 5b. vnet-link mode: zone exists but has no link to the account's VNet -> FAIL.
base_env
EXT_SHOW_EXIT=0
GRAPH_PROBE_EXIT=0
DNS_INTEGRATION_MODE="vnet-link"
mkdir -p "$WORKDIR/zone-hits-5b"
echo '[{"resourceGroup":"rg-dns","subscriptionId":"11111111-1111-1111-1111-111111111111"}]' >"$WORKDIR/zone-hits-5b/$REQUIRED_ZONE"
ZONE_HITS_DIR="$WORKDIR/zone-hits-5b"
mkdir -p "$WORKDIR/dns-links-5b"
# No fixture file for this zone => "az network private-dns link vnet list" returns nothing.
DNS_LINK_DIR="$WORKDIR/dns-links-5b"
out="$(DNS_INTEGRATION_MODE="vnet-link" run_audit 2>&1)"
echo "$out" | grep -q "FAIL.*$REQUIRED_ZONE exists.*but has no VNet link" || fail "vnet-link mode did not FAIL an unlinked zone (got: $out)"

# 5c. zone-group mode: same unlinked zone must NOT require a direct VNet link (PASS instead).
base_env
EXT_SHOW_EXIT=0
GRAPH_PROBE_EXIT=0
mkdir -p "$WORKDIR/zone-hits-5c"
echo '[{"resourceGroup":"rg-dns","subscriptionId":"11111111-1111-1111-1111-111111111111"}]' >"$WORKDIR/zone-hits-5c/$REQUIRED_ZONE"
ZONE_HITS_DIR="$WORKDIR/zone-hits-5c"
out="$(DNS_INTEGRATION_MODE="zone-group" run_audit 2>&1)"
echo "$out" | grep -q "PASS.*$REQUIRED_ZONE exists.*zone-group mode: no direct VNet link required" || fail "zone-group mode did not PASS an unlinked zone (got: $out)"
echo "$out" | grep -q "FAIL.*$REQUIRED_ZONE" && fail "zone-group mode must not FAIL a zone solely for lacking a direct VNet link (got: $out)"

#######################################
# 6. publicNetworkAccess != Disabled always FAILs.
#######################################
echo "==> [6] publicNetworkAccess enforcement"

base_env
ACCT_JSON='{"properties":{"publicNetworkAccess":"Enabled","networkInjections":[{"subnetArmId":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet1/subnets/snet1"}]}}'
out="$(run_audit 2>&1)"
echo "$out" | grep -q "FAIL.*publicNetworkAccess=Enabled" || fail "publicNetworkAccess=Enabled was not flagged FAIL even though network-injected (got: $out)"

#######################################
# 7. Final exit codes: non-zero iff any FAIL was recorded.
#######################################
echo "==> [7] final exit codes"

# Clean run: PNA=Disabled, no projects, graph extension unavailable (zone checks degrade to
# WARN/PASS only in that path) -> no FAIL anywhere -> exit 0.
base_env
if ! out="$(run_audit 2>&1)"; then
  fail "a run with zero FAILs should exit 0 (got exit $?; output: $out)"
fi
echo "$out" | grep -q '\[FAIL\]' && fail "the 'clean' scenario unexpectedly recorded a FAIL (got: $out)"
echo "$out" | grep -q "0 failed" || fail "the 'clean' scenario summary did not report 0 failed (got: $out)"

# Same base scenario but with PNA=Enabled guarantees exactly one FAIL -> exit 1.
base_env
ACCT_JSON='{"properties":{"publicNetworkAccess":"Enabled","networkInjections":[{"subnetArmId":"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet1/subnets/snet1"}]}}'
if run_audit >/dev/null 2>&1; then
  fail "a run with at least one FAIL must exit non-zero"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "One or more audit-byo-deployment.sh regression checks failed." >&2
  exit 1
fi

echo "audit-byo-deployment.sh behaves as expected."
