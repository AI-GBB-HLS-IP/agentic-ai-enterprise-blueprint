#!/usr/bin/env bash
set -uo pipefail

# az CLI's animated spinner ("Running ...") writes carriage returns (\r) to redraw itself in
# place; in some terminals/screenshot tools that leaves a stray leftover glyph at column 0 which
# the next echo partially overwrites instead of clearing (e.g. "ACCOUNT:" rendering as
# ")CCOUNT:"). Disable it so every line this script prints starts on a clean row.
export AZURE_CORE_NO_PROGRESS=true

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
#   SUBSCRIPTION_ID=<sub-id-or-name> ./audit-byo-deployment.sh
#   SUBSCRIPTION_ID=<sub-id-or-name> RG_FILTER=<resource-group-substring> ./audit-byo-deployment.sh
#   SUBSCRIPTION_ID=<sub-id-or-name> EXPECTED_VNET_ID=<hub/spoke VNet resource ID> ./audit-byo-deployment.sh
#   SUBSCRIPTION_ID=<sub-id-or-name> DNS_INTEGRATION_MODE=zone-group ./audit-byo-deployment.sh
#   SUBSCRIPTION_ID=<sub-id-or-name> SKIP_EXTENSION_INSTALL=1 ./audit-byo-deployment.sh
#
# EXPECTED_VNET_ID (optional) asserts which VNet this deployment is supposed to be private-linked
# into. When set, [1] fails loudly if the account's actual VNet (from networkInjections or its
# private endpoint) doesn't match it, and [3]'s zone-link checks use it as a fallback target when
# no VNet could be auto-detected at all -- instead of silently downgrading every zone-link check
# to a WARN. Omit it to rely on auto-detection only.
#
# DNS_INTEGRATION_MODE (optional, defaults to "vnet-link") selects which brownfield DNS
# integration contract [3] validates against (infra/envs/poc/foundry-dns.bicep:10-20,120-143):
# "vnet-link" expects each required private DNS zone to be directly linked to the workload VNet;
# "zone-group" is for an existing/central DNS zone attached only via each resource's
# private-endpoint DNS zone group (no direct VNet link expected or required).
#
# Requires: az CLI (logged in), jq. Optional: the "resource-graph" az extension
# (az extension add --name resource-graph) -- without it, DNS zone VNet-link checks in [3]
# and private endpoint DNS zone-group checks (account [1], project [4]) can only look within
# each account's own resource group and fall back to a WARN instead of a definitive PASS/FAIL,
# e.g. for zones/endpoints that live in a different subscription (hub). The script probes the
# extension at startup (not just checks it's installed) since an installed-but-non-functional
# extension would otherwise silently downgrade every cross-subscription check to a WARN too.
#
# SKIP_EXTENSION_INSTALL=1 (optional) opts out of the automatic "az extension add --name
# resource-graph" attempt above -- useful behind restricted egress, in locked-down CI runners, or
# anywhere auto-installing CLI extensions is undesirable. When set, the script degrades
# gracefully straight to the WARN path described above instead of attempting the install; it
# never crashes with a raw az error. Install the extension manually first
# (az extension add --name resource-graph) to get the stronger cross-subscription checks.

: "${SUBSCRIPTION_ID:?SUBSCRIPTION_ID is required}"
# Strip CR/whitespace that commonly survives a copy/paste from Windows terminals or docs;
# az CLI treats a trailing \r as part of the identifier and fails to resolve it, which (without
# this trim) silently left the previous subscription active instead of erroring clearly.
# Trimmed with sed rather than "xargs" (no arguments): xargs re-splits/re-quotes its input with
# shell-style word-parsing rules, so a legitimate value containing a single quote (e.g. a
# subscription display name like "Team's Subscription") raises "unmatched single quote" and
# yields an empty/wrong result instead of just trimming whitespace.
trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
SUBSCRIPTION_ID="$(trim "$(printf '%s' "$SUBSCRIPTION_ID" | tr -d '\r')")"
RG_FILTER="$(trim "$(printf '%s' "${RG_FILTER:-}" | tr -d '\r')")"
EXPECTED_VNET_ID="$(trim "$(printf '%s' "${EXPECTED_VNET_ID:-}" | tr -d '\r')")"
# Per this repo's DNS-mode contract (infra/envs/poc/foundry-dns.bicep:10-20,120-143), brownfield
# DNS integration is explicitly either "vnet-link" (zones in the workload subscription, linked
# directly to the workload VNet) or "zone-group" (existing central/hub zones attached only via
# each private endpoint's privateDnsZoneGroup association, with NO direct VNet link). The [3]
# zone-link checks below used to unconditionally FAIL any deployment lacking a direct VNet link,
# which incorrectly rejects a valid zone-group deployment. Default to vnet-link (this script's
# original/most common assumption) and require an explicit, validated value otherwise.
DNS_INTEGRATION_MODE="$(trim "$(printf '%s' "${DNS_INTEGRATION_MODE:-vnet-link}" | tr -d '\r')")"
case "$DNS_INTEGRATION_MODE" in
  vnet-link|zone-group) ;;
  *)
    echo "ABORT: DNS_INTEGRATION_MODE must be 'vnet-link' or 'zone-group' (got: '$DNS_INTEGRATION_MODE')" >&2
    exit 1
    ;;
esac
API_VERSION="2025-04-01-preview"

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

verdict() {
  local status="$1" message="$2" hint="${3:-}"
  case "$status" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)); echo "    ✅ [PASS] $message" ;;
    WARN) WARN_COUNT=$((WARN_COUNT + 1)); echo "    ⚠️  [WARN] $message"; [ -n "$hint" ] && echo "           -> $hint" ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)); echo "    ❌ [FAIL] $message"; [ -n "$hint" ] && echo "           -> $hint" ;;
  esac
}

# SUBSCRIPTION_ID may be a GUID or a display name; az account set accepts either, so don't
# re-compare the raw input against the resolved GUID (that always fails for a name, and masks
# the real "az account set failed" case with a confusing mismatch message instead of az's own
# error). Instead, require the set to succeed, then normalize to the resolved GUID for every
# downstream management.azure.com call.
AZ_SET_ERR="$(mktemp)"
trap 'rm -f "$AZ_SET_ERR"' EXIT
if ! az account set --subscription "$SUBSCRIPTION_ID" 2>"$AZ_SET_ERR"; then
  echo "ABORT: 'az account set --subscription $SUBSCRIPTION_ID' failed:" >&2
  cat "$AZ_SET_ERR" >&2
  exit 1
fi
SUBSCRIPTION_NAME="$(az account show --query name -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

echo "🔎 Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
[ -n "$RG_FILTER" ] && echo "🔎 Resource group filter: $RG_FILTER"
echo

ACCOUNTS_ERR="$(mktemp)"
# RG_FILTER is user-supplied and must never be interpolated into the JMESPath string literal
# server-side -- a value containing a single quote would break (or, worse, manipulate) the query
# syntax. Instead, always fetch the full unfiltered list and apply the substring match locally
# with a literal (non-regex) index() lookup in awk below, which is injection-safe regardless of
# RG_FILTER's contents.
ACCOUNTS_RAW=$(az cognitiveservices account list --query "[?kind=='AIServices'].{name:name, rg:resourceGroup}" -o tsv 2>"$ACCOUNTS_ERR")
ACCOUNTS_EXIT=$?
# A failed account-list call (bad auth, wrong API version, network error, throttling, ...) must
# never be treated the same as "this subscription legitimately has zero accounts" -- with
# errexit disabled (see set -uo pipefail above; -e is intentionally off so a single failed az
# call inside the per-account/project loop can be handled as a FAIL instead of killing the whole
# audit), a bare $(...) capture on its own can't tell those two cases apart, so the exit status
# must be checked explicitly here.
if [ "$ACCOUNTS_EXIT" -ne 0 ]; then
  echo "ABORT: 'az cognitiveservices account list' failed (exit $ACCOUNTS_EXIT):" >&2
  cat "$ACCOUNTS_ERR" >&2
  rm -f "$ACCOUNTS_ERR"
  exit 1
fi
rm -f "$ACCOUNTS_ERR"

if [ -n "$RG_FILTER" ]; then
  # Fixed-string (-F) substring match on the "rg" (2nd TSV) column only, so a resource group
  # name that happens to contain filter-like characters (., *, [, etc.) can't be misread as a
  # pattern, and the match stays anchored to the resource-group field rather than the name field.
  ACCOUNTS=$(printf '%s\n' "$ACCOUNTS_RAW" | awk -F'\t' -v rg="$RG_FILTER" 'index($2, rg) > 0')
else
  ACCOUNTS="$ACCOUNTS_RAW"
fi

if [ -z "$ACCOUNTS" ]; then
  echo "No AIServices accounts found."
  exit 0
fi

# Runs an "az rest --method get" call and captures stdout/exit status/stderr separately so
# callers can tell "the API call failed" apart from "the API call succeeded and returned no/empty
# data" -- the two look identical through a plain $(...) capture, but only the latter is safe to
# treat as "nothing found" in a PASS/WARN/FAIL verdict. Sets AZ_REST_OUT, AZ_REST_EXIT, AZ_REST_ERR;
# does not print a verdict itself so callers can choose FAIL text appropriate to what was being
# fetched.
az_rest_get() {
  local url="$1" err_file
  err_file="$(mktemp)"
  AZ_REST_OUT=$(az rest --method get --url "$url" -o json 2>"$err_file")
  AZ_REST_EXIT=$?
  AZ_REST_ERR="$(head -3 "$err_file")"
  rm -f "$err_file"
  return "$AZ_REST_EXIT"
}

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
# JMESPath's ends_with is a function, not a method -- "roleDefinitionId.ends_with(@, ...)" is not
# valid JMESPath/az-CLI query syntax and makes the whole --query argument error out at parse time;
# with "|| echo 0" catching that error, every call silently returned 0 and every management-plane
# RBAC check falsely reported the role as missing. The correct call form is
# ends_with(roleDefinitionId, '...').
has_role_assignment() {
  local scope="$1" principal_id="$2" role_guid="$3"
  local count
  count=$(az role assignment list --scope "$scope" \
    --query "[?principalId=='${principal_id}' && ends_with(roleDefinitionId, '${role_guid}')] | length(@)" \
    -o tsv 2>/dev/null || echo 0)
  [ "${count:-0}" -ge 1 ]
}

# Storage Blob Data Owner is approved only as a conditional, project-scoped grant restricted to
# this project's own {workspaceId}-azureml-agent container (infra/modules/foundry/storage-rbac.bicep:32-40,
# conditionVersion 2.0 ABAC condition). The role-definition GUID alone can't distinguish that from
# an unconditional, account-wide grant of the same role -- the latter gives the project full blob
# ownership over every other project's containers in the same storage account too, so it must not
# be reported as "scoped". A loose substring match on just the workspace GUID and the literal text
# "azureml-agent" anywhere in the condition string can be satisfied by a crafted/malformed
# condition (e.g. one with a negated clause or an always-true OR branch, or one that matches an
# unrelated attribute that merely happens to contain those substrings) while still granting
# account-wide access -- so instead require the exact predicate structure the reference bicep
# generates: StringStartsWithIgnoreCase on the workspace GUID AND StringLikeIgnoreCase on
# '*-azureml-agent', both against the Resource:name attribute, joined by AND (not OR).
has_scoped_storage_owner_assignment() {
  local scope="$1" principal_id="$2" workspace_guid="$3"
  local json count
  json=$(az role assignment list --scope "$scope" --query "[?principalId=='${principal_id}' && ends_with(roleDefinitionId, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')]" -o json 2>/dev/null)
  local attr_ref='@Resource\[Microsoft\.Storage/storageAccounts/blobServices/containers:name\]'
  local pattern="${attr_ref}[[:space:]]+StringStartsWithIgnoreCase[[:space:]]+'${workspace_guid}'[[:space:]]+AND[[:space:]]+${attr_ref}[[:space:]]+StringLikeIgnoreCase[[:space:]]+'\\*-azureml-agent'"
  count=$(echo "${json:-[]}" | jq --arg pat "$pattern" \
    '[.[] | select(.conditionVersion=="2.0" and ((.condition // "") | test($pat)))] | length')
  [ "${count:-0}" -ge 1 ]
}

# Verifies RESOURCE_ID has a private endpoint whose privateDnsZoneGroups includes EXPECTED_ZONE.
# A VNet-linked zone only enables DNS *queries* from that VNet; the zone-group association on
# the resource's own private endpoint (infra/modules/foundry/private-endpoint-dns.bicep) is what
# actually creates that resource's A record. Missing it is a common root cause of the
# "customer-managed downstream dependency returned an error" failure even when the zone itself
# is correctly linked. Requires the resource-graph extension to search beyond the account's RG.
check_pe_dns_group() {
  local label="$1" resource_id="$2" expected_zone="$3"
  if [ -z "$resource_id" ]; then
    verdict WARN "cannot check $label private endpoint: no resource ID resolved"
    return
  fi
  if [ "$GRAPH_AVAILABLE" != true ]; then
    verdict WARN "cannot check $label private endpoint/DNS zone group without the resource-graph extension" \
      "run: az extension add --name resource-graph"
    return
  fi
  local pe_hits pe_count matched
  pe_hits=$(az graph query -q "Resources | where type =~ 'microsoft.network/privateendpoints' | mv-expand conn=properties.privateLinkServiceConnections | where tostring(conn.properties.privateLinkServiceId) =~ '$resource_id' | project name, resourceGroup, subscriptionId" --query data -o json 2>/dev/null)
  pe_count=$(echo "${pe_hits:-[]}" | jq 'length')
  if [ "${pe_count:-0}" -eq 0 ]; then
    verdict FAIL "no private endpoint found targeting $label" "$resource_id"
    return
  fi
  matched=false
  while IFS=$'\t' read -r pe_name pe_rg pe_sub; do
    [ -z "$pe_name" ] && continue
    if az network private-endpoint dns-zone-group list --endpoint-name "$pe_name" --resource-group "$pe_rg" --subscription "$pe_sub" \
         --query "[].privateDnsZoneConfigs[].privateDnsZoneId" -o tsv 2>/dev/null | grep -qi "/privateDnsZones/${expected_zone}\$"; then
      matched=true
      break
    fi
  done < <(echo "$pe_hits" | jq -r '.[] | "\(.name)\t\(.resourceGroup)\t\(.subscriptionId)"')
  if [ "$matched" = true ]; then
    verdict PASS "$label private endpoint has a DNS zone group for $expected_zone"
  else
    verdict FAIL "$label private endpoint exists but has no DNS zone group for $expected_zone" \
      "infra/modules/foundry/private-endpoint-dns.bicep -- without this, the A record is never created even though the zone itself may be fine"
  fi
}

# This repo's approved reference contract always configures subnet delegation
# (properties.networkInjections -- infra/modules/foundry/main.bicep:146-153, FR-003/FR-005a in
# specs/01-foundry-byo-networking/spec.md); there is no supported private-endpoint-only
# alternative topology. When there's no networkInjections subnet, still resolve the VNet from the
# account's own private endpoint (if one exists) purely for diagnostic display/[3] zone-link
# comparison purposes -- it must not be treated as an equally-valid substitute for the required
# network injection.
resolve_vnet_via_private_endpoint() {
  local resource_id="$1"
  [ "$GRAPH_AVAILABLE" != true ] && return
  az graph query -q "Resources | where type =~ 'microsoft.network/privateendpoints' | mv-expand conn=properties.privateLinkServiceConnections | where tostring(conn.properties.privateLinkServiceId) =~ '$resource_id' | project subnetId=tostring(properties.subnet.id) | take 1" \
    --query "data[0].subnetId" -o tsv 2>/dev/null | sed 's#/subnets/.*##'
}

# Detected once: both the zone-link check in [3] and check_pe_dns_group need it, and extension
# availability doesn't vary per account. This is a read-only, local az-CLI-config change (it
# installs nothing into the customer's Azure environment), so it's safe to attempt automatically
# rather than making the customer run "az extension add" themselves and decode a possibly cryptic
# error on their own -- some tenants/orgs deny CLI extension installs via policy, and when that
# happens we want the *real* denial reason surfaced here, not just a generic "not installed".
# A successful "az extension show" only confirms it's installed, not that it actually works (an
# outdated version, an unregistered Resource Graph RP, or a principal without Reader anywhere can
# all leave it installed but still failing every query) -- so probe it with a real query too.
GRAPH_AVAILABLE=true
GRAPH_ERR=""
if ! az extension show --name resource-graph >/dev/null 2>&1; then
  # Some environments (restricted egress, locked-down CI runners, org policy against ad-hoc
  # local config changes) want to opt out of this auto-install entirely rather than have it
  # silently attempt a network call. SKIP_EXTENSION_INSTALL=1 degrades gracefully to the same
  # WARN-instead-of-PASS/FAIL path used for any other extension failure, with a clear message
  # telling the user how to install it manually if they do want the stronger checks.
  if [ "${SKIP_EXTENSION_INSTALL:-}" = "1" ]; then
    GRAPH_AVAILABLE=false
    GRAPH_ERR="SKIP_EXTENSION_INSTALL=1 is set; skipped 'az extension add --name resource-graph'."
  else
    GRAPH_INSTALL_ERR="$(mktemp)"
    if az extension add --name resource-graph >/dev/null 2>"$GRAPH_INSTALL_ERR"; then
      : # installed successfully; fall through to the functional probe below
    else
      GRAPH_AVAILABLE=false
      GRAPH_ERR="$(head -3 "$GRAPH_INSTALL_ERR")"
    fi
    rm -f "$GRAPH_INSTALL_ERR"
  fi
fi
if [ "$GRAPH_AVAILABLE" = true ]; then
  GRAPH_PROBE_ERR="$(mktemp)"
  if ! az graph query -q "Resources | take 1" >/dev/null 2>"$GRAPH_PROBE_ERR"; then
    GRAPH_AVAILABLE=false
    GRAPH_ERR="$(head -3 "$GRAPH_PROBE_ERR")"
  fi
  rm -f "$GRAPH_PROBE_ERR"
fi
if [ "$GRAPH_AVAILABLE" != true ]; then
  echo "⚠️  resource-graph extension is unavailable -- cross-subscription DNS zone-link and"
  echo "   private-endpoint zone-group checks below will degrade to WARN instead of PASS/FAIL"
  echo "   (manual verification needed for those specific lines; every other check is unaffected)."
  if [ -n "$GRAPH_ERR" ]; then
    echo "   Reason reported by az:"
    echo "$GRAPH_ERR" | sed 's/^/     /'
  fi
  echo "   If your organization's policy denies installing CLI extensions, this is expected --"
  echo "   no action needed here; otherwise try: az extension add --name resource-graph"
  echo
fi

# mapfile/readarray is Bash-4+ only and breaks under macOS's default Bash 3.2; build the array
# with a portable read loop instead (repo convention, see .specify/scripts/bash/create-new-feature.sh).
ACCOUNT_LINES=()
while IFS= read -r ACCOUNT_LINE; do
  [ -n "$ACCOUNT_LINE" ] && ACCOUNT_LINES+=("$ACCOUNT_LINE")
done <<< "$ACCOUNTS"
for LINE in "${ACCOUNT_LINES[@]}"; do
  IFS=$'\t' read -r NAME RG <<< "$LINE"
  echo "=============================================================="
  echo "📦 ACCOUNT: $NAME   (RG: $RG)"
  echo "=============================================================="

  ACCT_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME?api-version=$API_VERSION"
  if ! az_rest_get "$ACCT_URL"; then
    verdict FAIL "could not fetch account resource (az rest exit $AZ_REST_EXIT)" "$AZ_REST_ERR"
    echo
    continue
  fi
  ACCT_JSON="$AZ_REST_OUT"

  echo "--- [1] 🌐 Network injection / public network access ---"
  PNA=$(echo "$ACCT_JSON" | jq -r '.properties.publicNetworkAccess // "Unknown"')
  # Property name is "subnetArmId", not "subnetArnResourceId" -- see
  # infra/modules/foundry/main.bicep:147-152. The wrong name silently reads as empty for every
  # correctly network-injected account, which misreports it as having no network injection.
  SUBNET=$(echo "$ACCT_JSON" | jq -r '.properties.networkInjections[0].subnetArmId // empty')
  ACCOUNT_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME"
  PE_ONLY_VNET_ID=""
  if [ -n "$SUBNET" ]; then
    verdict PASS "network-injected (subnet: $SUBNET)"
  else
    # No networkInjections subnet -- still derive the VNet via the account's own private
    # endpoint, if any, purely so the [3] zone-link checks below have a real VNet to compare
    # against instead of degrading to WARN. This is diagnostic only: per the approved reference
    # contract (infra/modules/foundry/main.bicep:146-153, FR-003/FR-005a in
    # specs/01-foundry-byo-networking/spec.md), network injection is always required -- a
    # private-endpoint-only account is not a supported alternative topology, so its absence
    # must FAIL rather than PASS even when a private endpoint is present.
    PE_ONLY_VNET_ID=$(resolve_vnet_via_private_endpoint "$ACCOUNT_RESOURCE_ID")
    if [ -n "$PE_ONLY_VNET_ID" ]; then
      verdict FAIL "no subnet delegation (publicNetworkAccess=$PNA) -- found a private endpoint (VNet: $PE_ONLY_VNET_ID) but no networkInjections subnet" \
        "infra/modules/foundry/main.bicep:146-153 -- network injection is always required by this repo's approved pattern; private endpoints are an additional DNS/private-access mechanism, not a substitute for the network-injected delegated subnet"
    else
      verdict FAIL "no networkInjections subnet and no private endpoint VNet could be resolved (publicNetworkAccess=$PNA)" \
        "infra/modules/foundry/main.bicep:146-153 -- network injection is always required by this repo's approved pattern"
    fi
  fi
  # publicNetworkAccess is read above (PNA) for display, but was never enforced: a
  # network-injected account that still allows public network access used to earn PASS
  # regardless. specs/01-foundry-byo-networking/spec.md:132-135 requires
  # publicNetworkAccess=Disabled for a BYO-VNet deployment -- check it unconditionally.
  if [ "$PNA" != "Disabled" ]; then
    verdict FAIL "publicNetworkAccess=$PNA (expected Disabled for a BYO-VNet deployment)" \
      "specs/01-foundry-byo-networking/spec.md:132-135 -- set publicNetworkAccess to Disabled"
  fi
  DETECTED_VNET_ID=""
  [ -n "$SUBNET" ] && DETECTED_VNET_ID="${SUBNET%/subnets/*}"
  [ -z "$DETECTED_VNET_ID" ] && DETECTED_VNET_ID="$PE_ONLY_VNET_ID"
  if [ -n "$EXPECTED_VNET_ID" ]; then
    # ARM resource IDs are case-insensitive, so compare lowercased forms (same approach as the
    # DNS zone-link check in [3] below, which already uses "grep -qix" for this reason) -- a
    # direct case-sensitive comparison would false-FAIL a functionally identical VNet ID that
    # merely differs in casing (e.g. "resourceGroups" vs "resourcegroups").
    if [ -n "$DETECTED_VNET_ID" ] && [ "$(printf '%s' "$DETECTED_VNET_ID" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$EXPECTED_VNET_ID" | tr '[:upper:]' '[:lower:]')" ]; then
      verdict FAIL "account's VNet ($DETECTED_VNET_ID) does not match EXPECTED_VNET_ID ($EXPECTED_VNET_ID)" \
        "either EXPECTED_VNET_ID is wrong, or this account is private-linked into the wrong VNet"
    elif [ -n "$DETECTED_VNET_ID" ]; then
      verdict PASS "account's VNet matches EXPECTED_VNET_ID"
    fi
  fi
  check_pe_dns_group "Foundry account (cognitiveservices)" "$ACCOUNT_RESOURCE_ID" "privatelink.cognitiveservices.azure.com"
  check_pe_dns_group "Foundry account (openai)" "$ACCOUNT_RESOURCE_ID" "privatelink.openai.azure.com"
  check_pe_dns_group "Foundry account (services-ai)" "$ACCOUNT_RESOURCE_ID" "privatelink.services.ai.azure.com"

  echo "--- [2] 🗂️  Projects ---"
  PROJECTS_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects?api-version=$API_VERSION"
  # This list endpoint returns each project's "name" fully-qualified as "<account>/<project>"
  # (not just "<project>"), unlike most ARM child-resource listings. Strip everything up to the
  # last "/" so $PROJ is the bare project name -- otherwise concatenating "$NAME/$PROJ" below
  # builds an invalid double-qualified URL that 404s.
  # pipefail (set above) makes ${PIPESTATUS[0]} reflect the "az rest" call's own exit status
  # rather than the trailing sed's -- a failed list call (auth/API-version/network error) must
  # be recorded as a FAIL, not treated the same as "this account legitimately has zero projects"
  # which previously let it dodge every project/RBAC check below without any recorded failure.
  PROJECTS=$(az rest --method get --url "$PROJECTS_URL" --query "value[].name" -o tsv 2>/dev/null | sed 's#.*/##')
  PROJECTS_EXIT="${PIPESTATUS[0]}"
  if [ "$PROJECTS_EXIT" -ne 0 ]; then
    verdict FAIL "could not list projects (az rest exit $PROJECTS_EXIT)" \
      "verify API version $API_VERSION and that you have Reader access on this account"
    echo
    continue
  fi
  if [ -z "$PROJECTS" ]; then
    echo "  (no projects found)"
  fi

  ACCT_CONN_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/connections?api-version=$API_VERSION"
  if ! az_rest_get "$ACCT_CONN_URL"; then
    verdict FAIL "could not fetch account-level connections (az rest exit $AZ_REST_EXIT)" "$AZ_REST_ERR"
    ACCT_CONN_JSON='{"value":[]}'
  else
    ACCT_CONN_JSON="$AZ_REST_OUT"
  fi

  for PROJ in $PROJECTS; do
    echo "  --- 🧩 Project: $PROJ ---"
    PROJ_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ?api-version=$API_VERSION"
    PROJ_REST_ERR="$(mktemp)"
    PROJ_JSON=$(az rest --method get --url "$PROJ_URL" -o json 2>"$PROJ_REST_ERR")
    PROJ_REST_EXIT=$?
    if [ "$PROJ_REST_EXIT" -ne 0 ]; then
      verdict FAIL "could not fetch project resource (az rest exit $PROJ_REST_EXIT)" \
        "$(head -1 "$PROJ_REST_ERR")"
      rm -f "$PROJ_REST_ERR"
      continue
    fi
    rm -f "$PROJ_REST_ERR"
    PRINCIPAL_ID=$(echo "$PROJ_JSON" | jq -r '.identity.principalId // empty')
    if [ -z "$PRINCIPAL_ID" ]; then
      IDENTITY_TYPE=$(echo "$PROJ_JSON" | jq -r '.identity.type // "none"')
      PROJ_RESOURCE_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ"
      verdict FAIL "could not resolve project managed identity principalId (identity.type=$IDENTITY_TYPE)" \
        "expected identity.type=SystemAssigned with a populated principalId; if type=none the project has no managed identity, if SystemAssigned but principalId is empty the identity may still be provisioning -- re-run in a few minutes, or check 'az resource show --ids $PROJ_RESOURCE_ID --query identity' directly"
      continue
    fi

    # The Foundry Agent Service platform formats the project's internalId (a raw 32-char hex
    # GUID) into standard dashed-GUID form to derive the project-specific Cosmos container names
    # ({workspaceId}-thread-message-store, {workspaceId}-system-thread-message-store,
    # {workspaceId}-agent-entity-store) and the Storage container name
    # ({workspaceId}-azureml-agent) -- see infra/modules/foundry/main.bicep:172-175 and
    # capability-host.bicep:47-55. Needed below for the per-container Cosmos RBAC check and the
    # Storage Blob Data Owner ABAC-condition check.
    PROJ_INTERNAL_ID=$(echo "$PROJ_JSON" | jq -r '.properties.internalId // empty')
    PROJECT_WORKSPACE_GUID=""
    if [ "${#PROJ_INTERNAL_ID}" -eq 32 ]; then
      PROJECT_WORKSPACE_GUID="${PROJ_INTERNAL_ID:0:8}-${PROJ_INTERNAL_ID:8:4}-${PROJ_INTERNAL_ID:12:4}-${PROJ_INTERNAL_ID:16:4}-${PROJ_INTERNAL_ID:20:12}"
    fi

    PROJ_CONN_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ/connections?api-version=$API_VERSION"
    if ! az_rest_get "$PROJ_CONN_URL"; then
      verdict FAIL "could not fetch project-level connections (az rest exit $AZ_REST_EXIT)" "$AZ_REST_ERR"
      PROJ_CONN_JSON='{"value":[]}'
    else
      PROJ_CONN_JSON="$AZ_REST_OUT"
    fi

    COSMOS_ROW=$(find_connection "CosmosDB" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    STORAGE_ROW=$(find_connection "AzureStorageAccount" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    SEARCH_ROW=$(find_connection "CognitiveSearch" "$PROJ_CONN_JSON" "$ACCT_CONN_JSON")
    COSMOS_RESID="${COSMOS_ROW##*|}"; STORAGE_RESID="${STORAGE_ROW##*|}"; SEARCH_RESID="${SEARCH_ROW##*|}"

    echo "  [1] 🔌 Required connections (Cosmos DB / Storage / AI Search):"
    COSMOS_FALLBACK_RESID=""
    if [ -n "$COSMOS_ROW" ]; then
      verdict PASS "CosmosDB connection: ${COSMOS_ROW%%|*} (${COSMOS_ROW#*|})"
    else
      # Distinguish "Cosmos account exists but was never wired up as a project connection" from
      # "no Cosmos account was provisioned at all" -- these need different remediation, and the
      # generic hint alone left the customer unsure which one they were looking at. When exactly
      # one candidate account is found, also remember its resource ID so [3] can still check its
      # RBAC directly -- without a connection, the Capability Host can never activate anyway, but
      # confirming RBAC is (or isn't) already in place on that account is still useful diagnostic
      # signal while the connection gap gets fixed.
      COSMOS_ACCOUNTS_IN_RG=$(az cosmosdb list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null)
      COSMOS_ACCOUNTS_COUNT=$(echo "$COSMOS_ACCOUNTS_IN_RG" | grep -c . || true)
      if [ -n "$COSMOS_ACCOUNTS_IN_RG" ]; then
        verdict FAIL "no CosmosDB connection (but found Cosmos account(s) in $RG: $(echo "$COSMOS_ACCOUNTS_IN_RG" | paste -sd, -))" \
          "infra/modules/foundry/project-connections.bicep -- create a project connection of category=CosmosDB pointing to the existing account; Capability Host activation and Cosmos RBAC both depend on this connection existing"
        if [ "$COSMOS_ACCOUNTS_COUNT" -eq 1 ]; then
          COSMOS_FALLBACK_RESID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.DocumentDB/databaseAccounts/$COSMOS_ACCOUNTS_IN_RG"
        fi
      else
        verdict FAIL "no CosmosDB connection and no Cosmos account found in $RG" \
          "infra/modules/foundry/cosmos-rbac.bicep -- a Cosmos DB account must be provisioned for this project before a connection can be created; Capability Host activation depends on this"
      fi
    fi
    [ -n "$STORAGE_ROW" ] && verdict PASS "AzureStorageAccount connection: ${STORAGE_ROW%%|*} (${STORAGE_ROW#*|})" || verdict FAIL "no AzureStorageAccount connection" "infra/modules/foundry/project-connections.bicep"
    [ -n "$SEARCH_ROW" ] && verdict PASS "CognitiveSearch connection: ${SEARCH_ROW%%|*} (${SEARCH_ROW#*|})" || verdict FAIL "no CognitiveSearch connection" "infra/modules/foundry/project-connections.bicep"

    echo "  [2] 🏠 Capability Host:"
    CAP_HOSTS_URL="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME/projects/$PROJ/capabilityHosts?api-version=$API_VERSION"
    if ! az_rest_get "$CAP_HOSTS_URL"; then
      verdict FAIL "could not fetch Capability Host resource (az rest exit $AZ_REST_EXIT)" "$AZ_REST_ERR"
      CAP_HOSTS_JSON='{"value":[]}'
    else
      CAP_HOSTS_JSON="$AZ_REST_OUT"
    fi
    CAP_HOST_NAME=$(echo "$CAP_HOSTS_JSON" | jq -r '.value[0].name // empty')
    CAP_HOST_STATE=""
    if [ -n "$CAP_HOST_NAME" ]; then
      CAP_HOST_STATE=$(echo "$CAP_HOSTS_JSON" | jq -r '.value[0].properties.provisioningState // "Unknown"')
      case "$CAP_HOST_STATE" in
        Succeeded)
          verdict PASS "Capability Host '$CAP_HOST_NAME' provisioningState=Succeeded"
          ;;
        Failed|Canceled)
          # Terminal failure states -- these will never self-resolve, unlike the transient
          # in-progress states below, so they must count as a hard failure, not a WARN.
          verdict FAIL "Capability Host '$CAP_HOST_NAME' provisioningState=$CAP_HOST_STATE" \
            "infra/modules/foundry/capability-host.bicep -- this is a terminal state; re-deploy or inspect the deployment error, it will not resolve on its own"
          ;;
        *)
          # Transient/in-progress states (Creating, Updating, Accepted, ...) may still resolve.
          verdict WARN "Capability Host '$CAP_HOST_NAME' provisioningState=$CAP_HOST_STATE" \
            "infra/modules/foundry/capability-host.bicep"
          ;;
      esac
    else
      verdict FAIL "no Capability Host found" "infra/modules/foundry/capability-host.bicep (depends on cosmosDBRbac, storageRbac, aiSearchRbac)"
    fi

    echo "  [3] 🔐 RBAC on project managed identity ($PRINCIPAL_ID):"
    COSMOS_CHECK_RESID="$COSMOS_RESID"
    [ -z "$COSMOS_CHECK_RESID" ] && COSMOS_CHECK_RESID="$COSMOS_FALLBACK_RESID"
    if [ -n "$COSMOS_CHECK_RESID" ]; then
      if [ -z "$COSMOS_RESID" ]; then
        echo "    (no project connection -- checking RBAC directly against the one Cosmos account found in $RG)"
      fi
      if has_role_assignment "$COSMOS_CHECK_RESID" "$PRINCIPAL_ID" "230815da-be43-4aae-9cb4-875f7bd000aa"; then
        verdict PASS "Cosmos DB Operator (mgmt-plane) on Cosmos account"
      else
        verdict FAIL "missing Cosmos DB Operator role on Cosmos account" "infra/modules/foundry/cosmos-rbac.bicep"
      fi
      COSMOS_ACCT_NAME=$(basename "$COSMOS_CHECK_RESID")
      COSMOS_RG=$(echo "$COSMOS_CHECK_RESID" | sed -n 's#.*/resourceGroups/\([^/]*\)/.*#\1#p')
      # The Cosmos connection's ResourceId can point to an account in a subscription different
      # from the one currently active via "az account set" above -- this blueprint explicitly
      # supports a project connecting to a Cosmos account in another subscription (see
      # infra/modules/foundry/main.bicep:215-219,400-402). Parse the subscription ID straight out
      # of the resource ID and pass it explicitly rather than relying on whatever subscription
      # happens to be active, so the query below targets the right one.
      COSMOS_SUBSCRIPTION_ID=$(echo "$COSMOS_CHECK_RESID" | sed -n 's#^/subscriptions/\([^/]*\)/.*#\1#p')
      [ -z "$COSMOS_SUBSCRIPTION_ID" ] && COSMOS_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
      if [ -n "$PROJECT_WORKSPACE_GUID" ]; then
        # cosmos-data-rbac.bicep creates THREE project-specific container-scoped Cosmos DB Data
        # Contributor assignments ({workspaceId}-thread-message-store,
        # {workspaceId}-system-thread-message-store, {workspaceId}-agent-entity-store), not one
        # account-wide grant. Previously a single match on any one of them was enough to PASS;
        # require all three. This check is intentionally NOT gated on Capability Host state:
        # these assignments are created after the Capability Host activates, so skipping the
        # check until it's already Succeeded hides exactly the diagnostic signal needed when the
        # host is missing or failed.
        DATA_PLANE_JSON=$(az cosmosdb sql role assignment list --account-name "$COSMOS_ACCT_NAME" --resource-group "$COSMOS_RG" --subscription "$COSMOS_SUBSCRIPTION_ID" -o json 2>/dev/null)
        MISSING_CONTAINERS=()
        for CONTAINER_SUFFIX in thread-message-store system-thread-message-store agent-entity-store; do
          CONTAINER_NAME="${PROJECT_WORKSPACE_GUID}-${CONTAINER_SUFFIX}"
          # infra/modules/foundry/cosmos-rbac.bicep:38-69 always scopes these assignments to
          # ".../dbs/enterprise_memory/colls/<container-name>" specifically. Matching any scope
          # ending in just "/colls/<container-name>" would also accept an assignment on a
          # same-named container under an unrelated/wrong database, producing a false PASS.
          MATCH_COUNT=$(echo "${DATA_PLANE_JSON:-[]}" | jq --arg pid "$PRINCIPAL_ID" --arg c "$CONTAINER_NAME" \
            '[.[]? | select(.principalId==$pid and (.roleDefinitionId | endswith("0000-0000-0000-0000-000000000002")) and (.scope | endswith("/dbs/enterprise_memory/colls/" + $c)))] | length')
          [ "${MATCH_COUNT:-0}" -ge 1 ] || MISSING_CONTAINERS+=("$CONTAINER_NAME")
        done
        if [ "${#MISSING_CONTAINERS[@]}" -eq 0 ]; then
          verdict PASS "Cosmos DB Data Contributor (data-plane) present on all 3 project containers (thread-message-store, system-thread-message-store, agent-entity-store)"
        else
          MISSING_LIST=$(IFS=,; echo "${MISSING_CONTAINERS[*]}")
          verdict FAIL "missing Cosmos DB Data Contributor on: $MISSING_LIST" \
            "infra/modules/foundry/cosmos-data-rbac.bicep (created after Capability Host activates)"
        fi
      else
        verdict WARN "cannot verify per-container Cosmos RBAC: could not derive project workspace ID from properties.internalId"
      fi
    else
      verdict WARN "cannot check Cosmos RBAC: no connection and no single Cosmos account resolved in $RG" \
        "either no Cosmos account exists in this RG, or more than one was found and the right one is ambiguous without a project connection -- see [1] above"
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
      if [ -z "$PROJECT_WORKSPACE_GUID" ]; then
        verdict WARN "cannot verify Storage Blob Data Owner scoping: could not derive project workspace ID from properties.internalId"
      elif has_scoped_storage_owner_assignment "$STORAGE_RESID" "$PRINCIPAL_ID" "$PROJECT_WORKSPACE_GUID"; then
        verdict PASS "Storage Blob Data Owner (scoped) on storage account"
      elif has_role_assignment "$STORAGE_RESID" "$PRINCIPAL_ID" "b7e6dc6d-f1e8-4753-8033-0f276bb0955b"; then
        verdict FAIL "Storage Blob Data Owner is assigned but not scoped by condition to this project's container" \
          "infra/modules/foundry/storage-rbac.bicep:32-40 -- expected conditionVersion=2.0 with an ABAC condition restricted to ${PROJECT_WORKSPACE_GUID}*-azureml-agent; an unconditional, account-wide grant gives this project blob ownership over every other project's data too"
      else
        verdict FAIL "missing Storage Blob Data Owner" "infra/modules/foundry/storage-rbac.bicep"
      fi
    else
      verdict WARN "cannot check Storage RBAC: connection has no metadata.ResourceId"
    fi

    echo "  [4] 🧷 Private endpoint DNS zone groups (Cosmos DB / Storage / AI Search):"
    check_pe_dns_group "Cosmos DB" "$COSMOS_CHECK_RESID" "privatelink.documents.azure.com"
    check_pe_dns_group "Storage" "$STORAGE_RESID" "privatelink.blob.core.windows.net"
    check_pe_dns_group "AI Search" "$SEARCH_RESID" "privatelink.search.windows.net"
  done

  echo "--- [3] 🌐 Private DNS zone links ---"
  # Zones routinely live in a hub subscription/RG different from the Foundry account's. Use
  # Azure Resource Graph (searches every subscription the caller can see, not just $RG) to find
  # the zone wherever it is, then check whether it's actually linked to *this* account's VNet --
  # not just linked to something. Falls back to the old RG-scoped check (as a WARN, since it
  # can't prove a negative across subscriptions) if the resource-graph extension isn't available.
  VNET_ID="$DETECTED_VNET_ID"
  if [ -z "$VNET_ID" ] && [ -n "$EXPECTED_VNET_ID" ]; then
    VNET_ID="$EXPECTED_VNET_ID"
    echo "    (no VNet auto-detected for this account -- using EXPECTED_VNET_ID as the comparison target)"
  fi

  for ZONE in privatelink.cognitiveservices.azure.com privatelink.openai.azure.com privatelink.services.ai.azure.com privatelink.search.windows.net privatelink.documents.azure.com privatelink.blob.core.windows.net privatelink.vaultcore.azure.net; do
    if [ "$GRAPH_AVAILABLE" != true ]; then
      if [ "$DNS_INTEGRATION_MODE" = "zone-group" ]; then
        verdict WARN "cannot check $ZONE without the resource-graph extension in zone-group mode" \
          "run: az extension add --name resource-graph -- or rely on the private-endpoint DNS zone-group checks above for connectivity proof"
        continue
      fi
      LINKED=$(az network private-dns link vnet list --zone-name "$ZONE" --resource-group "$RG" --query "[].virtualNetwork.id" -o tsv 2>/dev/null)
      if [ -n "$LINKED" ]; then
        verdict PASS "$ZONE linked to $(echo "$LINKED" | wc -l | tr -d ' ') VNet(s) in $RG"
      else
        verdict WARN "$ZONE not found/linked in $RG" \
          "cannot search other subscriptions without the resource-graph extension -- run 'az extension add --name resource-graph' and re-run this script for a definitive answer"
      fi
      continue
    fi

    ZONE_HITS=$(az graph query -q "Resources | where type =~ 'microsoft.network/privatednszones' and name =~ '$ZONE' | project resourceGroup, subscriptionId" --query data -o json 2>/dev/null)
    ZONE_COUNT=$(echo "${ZONE_HITS:-[]}" | jq 'length')

    if [ "${ZONE_COUNT:-0}" -eq 0 ]; then
      verdict FAIL "$ZONE not found in any subscription you have access to" \
        "zone must exist -- see infra/modules/network/private-dns.bicep"
      continue
    fi

    if [ "$DNS_INTEGRATION_MODE" = "zone-group" ]; then
      # zone-group mode (infra/envs/poc/foundry-dns.bicep:120-143) is for an existing/central DNS
      # zone attached only through each resource's private-endpoint zone-group association, with
      # no direct link from this zone to the workload VNet expected or required. Don't demand one;
      # the per-resource check_pe_dns_group calls in [1]/[4] above are the authoritative proof of
      # connectivity in this mode.
      ZONE_LOCATIONS=$(echo "$ZONE_HITS" | jq -r '.[] | "\(.subscriptionId)/\(.resourceGroup)"' | paste -sd, -)
      verdict PASS "$ZONE exists ($ZONE_LOCATIONS) -- zone-group mode: no direct VNet link required, see the private-endpoint DNS zone-group checks above for the authoritative connectivity proof"
      continue
    fi

    if [ -z "$VNET_ID" ]; then
      verdict WARN "$ZONE exists ($ZONE_COUNT match(es)) but account has no networkInjections subnet to compare against" \
        "see [1] above -- cannot confirm the link targets the right VNet without a known subnet"
      continue
    fi

    FOUND_LINK=false
    FOUND_WHERE=""
    while IFS=$'\t' read -r ZONE_RG ZONE_SUB; do
      [ -z "$ZONE_RG" ] && continue
      LINK_IDS=$(az network private-dns link vnet list --zone-name "$ZONE" --resource-group "$ZONE_RG" --subscription "$ZONE_SUB" --query "[].virtualNetwork.id" -o tsv 2>/dev/null)
      if echo "$LINK_IDS" | grep -qix "$VNET_ID"; then
        FOUND_LINK=true
        FOUND_WHERE="$ZONE_SUB/$ZONE_RG"
        break
      fi
    done < <(echo "$ZONE_HITS" | jq -r '.[] | "\(.resourceGroup)\t\(.subscriptionId)"')

    if [ "$FOUND_LINK" = true ]; then
      verdict PASS "$ZONE linked to this VNet (zone in $FOUND_WHERE)"
    else
      ZONE_LOCATIONS=$(echo "$ZONE_HITS" | jq -r '.[] | "\(.subscriptionId)/\(.resourceGroup)"' | paste -sd, -)
      verdict FAIL "$ZONE exists ($ZONE_LOCATIONS) but has no VNet link to $VNET_ID" \
        "link the zone to this VNet, or confirm hub-VNet peering + DNS forwarding provides resolution instead"
    fi
  done
  echo
done

echo "=============================================================="
if [ "$FAIL_COUNT" -gt 0 ]; then
  SUMMARY_ICON="❌"
elif [ "$WARN_COUNT" -gt 0 ]; then
  SUMMARY_ICON="⚠️ "
else
  SUMMARY_ICON="✅"
fi
echo "$SUMMARY_ICON SUMMARY: $PASS_COUNT passed, $WARN_COUNT warnings, $FAIL_COUNT failed"
echo "=============================================================="
[ "$FAIL_COUNT" -gt 0 ] && exit 1
exit 0
