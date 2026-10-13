#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/foundry/remediate-cosmos-data-rbac.sh"
for tool in jq python3; do
  command -v "$tool" >/dev/null || { echo "Required test dependency missing: $tool" >&2; exit 1; }
done
workdir="$(mktemp -d "${REPO_ROOT}/tests/foundry/.remediate-cosmos-test.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT
export MOCK_DIR="$workdir"
export FOUNDRY_PROJECT_ID="/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/foundry-rg/providers/Microsoft.CognitiveServices/accounts/test-foundry/projects/test-project"
export EXPECTED_PRINCIPAL_ID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
export PATH="$workdir:$PATH"

cat >"$workdir/az" <<'MOCK'
#!/usr/bin/env python3
import json
import os
import sys
import uuid
from pathlib import Path

args = sys.argv[1:]
root = Path(os.environ["MOCK_DIR"])
scenario = os.environ.get("SCENARIO", "")
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\n")
def option(name):
    return args[args.index(name) + 1]
def output(value):
    print(json.dumps(value))
    sys.exit(0)
def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)

project_sub = "00000000-0000-0000-0000-000000000000"
cosmos_sub = "11111111-1111-1111-1111-111111111111"
cosmos_id = f"/subscriptions/{cosmos_sub}/resourceGroups/cosmos-rg/providers/Microsoft.DocumentDB/databaseAccounts/test-cosmos"
pid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
workspace = "12345678-1234-1234-1234-123456789abc"
role = cosmos_id + "/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
suffixes = ["thread-message-store", "system-thread-message-store", "agent-entity-store"]
def assignment(suffix):
    return {"principalId": pid, "roleDefinitionId": role,
            "scope": cosmos_id + f"/dbs/enterprise_memory/colls/{workspace}-{suffix}"}

if args[:1] == ["rest"]:
    assert option("--subscription") == project_sub
    url = option("--url").split("?")[0]
    if "/connections" in url:
        is_project = "/projects/" in url
        connection = {"name": "cosmos-connection", "properties": {
            "category": "CosmosDB" if scenario == "uppercase-category" else "CosmosDb",
            "authType": "ApiKey" if scenario == "wrong-auth" else "AAD",
            "metadata": {"ResourceId": cosmos_id}}}
        if scenario == "wrong-category":
            connection["properties"]["category"] = "AzureStorageAccount"
        values = [connection] if is_project else []
        if scenario == "account-connection":
            values = [] if is_project else [connection]
        if scenario == "missing-connection":
            values = []
        if scenario == "ambiguous-connection" and is_project:
            values = [connection, connection]
        if scenario == "connection-error" and is_project:
            fail("connection read denied")
        output({"value": values, "nextLink": "https://example.com/next" if scenario == "paginated" else None})
    if "/capabilityHosts/" in url:
        output({"properties": {
            "capabilityHostKind": "Agents",
            "provisioningState": "Failed" if scenario == "failed-host" else "Succeeded",
            "threadStorageConnections": ["cosmos-connection"]}})
    output({"identity": {"principalId": "" if scenario == "missing-identity" else pid},
            "properties": {"internalId": "bad" if scenario == "bad-workspace" else workspace.replace("-", "")}})

assert option("--subscription") == cosmos_sub, "Cross-subscription target must be explicit"
assert option("--resource-group") == "cosmos-rg"
if args[:2] == ["cosmosdb", "show"]:
    assert option("--name") == "test-cosmos"
    print(cosmos_id if scenario != "wrong-account" else cosmos_id + "-other")
    sys.exit(0)
assert option("--account-name") == "test-cosmos"
if args[:4] == ["cosmosdb", "sql", "container", "list"]:
    assert option("--database-name") == "enterprise_memory"
    if scenario == "container-error":
        fail("container read denied")
    selected = suffixes[:2] if scenario == "missing-container" else suffixes
    output([{"name": workspace + "-" + s} for s in selected])

state_file = root / "assignments.json"
if not state_file.exists():
    existing = []
    if scenario == "one-present":
        existing = [assignment(suffixes[0])]
    if scenario == "all-present":
        existing = [assignment(s) for s in suffixes]
    if scenario == "relative-present":
        existing = [dict(assignment(s), scope=assignment(s)["scope"][len(cosmos_id):]) for s in suffixes]
    if scenario == "other-principal":
        existing = [dict(assignment(s), principalId="99999999-8888-7777-6666-555555555555") for s in suffixes]
    if scenario == "broad-grant":
        existing = [{"principalId": pid, "roleDefinitionId": role,
                     "scope": cosmos_id + "/dbs/enterprise_memory"}]
    state_file.write_text(json.dumps(existing))
state = json.loads(state_file.read_text())
if args[:5] == ["cosmosdb", "sql", "role", "assignment", "list"]:
    if scenario == "assignment-error":
        fail("assignment read denied")
    if scenario == "invalid-assignments":
        output([{}])
    if scenario == "readback-missing":
        output([])
    output(state)
if args[:5] == ["cosmosdb", "sql", "role", "assignment", "create"]:
    scope = option("--scope")
    assert scope in [assignment(s)["scope"] for s in suffixes], "Must target exact project container"
    assert option("--principal-id") == pid
    assert option("--role-definition-id") == role
    container = scope.split("/")[-1]
    expected_id = str(uuid.uuid5(uuid.UUID("11fb06fb-712d-4ddd-98c7-e71bbd588830"),
                                "-".join([workspace, container, role, pid])))
    assert option("--role-assignment-id") == expected_id, "Must match ARM guid inputs"
    if scenario == "create-error" or (scenario == "partial-create-error" and state):
        fail("assignment write denied")
    state.append({"principalId": pid, "roleDefinitionId": role, "scope": scope})
    state_file.write_text(json.dumps(state))
    sys.exit(0)
fail("Unexpected Azure operation: " + repr(args))
MOCK
chmod +x "$workdir/az"

reset_case() {
  export SCENARIO="$1"
  : >"$workdir/calls.jsonl"
  rm -f "$workdir/assignments.json"
}
create_count() {
  python3 - "$workdir/calls.jsonl" <<'PY'
import json
import sys
print(sum(json.loads(line)[:5] == ["cosmosdb", "sql", "role", "assignment", "create"]
          for line in open(sys.argv[1])))
PY
}
fail() { echo "FAIL: $*" >&2; exit 1; }
run_script() { bash "$SCRIPT" "$@" >"$workdir/output" 2>"$workdir/error"; }

reset_case ""
run_script
[[ "$(create_count)" == 0 ]] || fail "Dry-run wrote permissions"
grep -q 'DRY-RUN.*thread-message-store' "$workdir/output" || fail "Missing grant plan"
echo "PASS: dry-run resolves CosmosDb and performs no writes"

reset_case ""
if EXPECTED_PRINCIPAL_ID="" run_script --execute; then fail "Execute accepted no approved identity"; fi
[[ ! -s "$workdir/calls.jsonl" ]] || fail "Unapproved execute called Azure"
reset_case ""
if EXPECTED_PRINCIPAL_ID="99999999-8888-7777-6666-555555555555" run_script --execute; then
  fail "Identity mismatch accepted"
fi
[[ "$(create_count)" == 0 ]] || fail "Identity mismatch wrote"
echo "PASS: execute requires matching approved identity"

for scenario in "" uppercase-category account-connection other-principal broad-grant; do
  reset_case "$scenario"
  run_script --execute || { cat "$workdir/error"; fail "Execute failed: $scenario"; }
  [[ "$(create_count)" == 3 ]] || fail "Expected three exact grants: $scenario"
  grep -q 'all three.*verified' "$workdir/output" || fail "Missing verification"
done
echo "PASS: categories, account inheritance, cross-subscription scope, ARM GUIDs, and exact grants"

reset_case one-present
run_script --execute
[[ "$(create_count)" == 2 ]] || fail "Should add only two missing assignments"
run_script --execute
[[ "$(create_count)" == 2 ]] || fail "Rerun created duplicate assignments"
reset_case all-present
run_script --execute
[[ "$(create_count)" == 0 ]] || fail "Existing assignments were changed"
reset_case relative-present
run_script --execute
[[ "$(create_count)" == 0 ]] || fail "Existing relative-scope assignments were changed"
echo "PASS: partial and complete grants are preserved; rerun is idempotent"

for scenario in missing-identity bad-workspace failed-host missing-connection ambiguous-connection \
  wrong-category wrong-auth paginated connection-error wrong-account missing-container container-error \
  assignment-error invalid-assignments; do
  reset_case "$scenario"
  if run_script --execute; then fail "Unsafe preflight accepted: $scenario"; fi
  [[ "$(create_count)" == 0 ]] || fail "Preflight failure wrote: $scenario"
done
echo "PASS: unsafe targets, missing prerequisites, and read failures block all writes"

for scenario in create-error partial-create-error readback-missing; do
  reset_case "$scenario"
  if run_script --execute; then fail "Failure reported success: $scenario"; fi
  grep -q 'all three.*verified' "$workdir/output" && fail "False verification: $scenario"
done
echo "PASS: write and read-back failures are explicit"

reset_case ""
if FOUNDRY_PROJECT_ID="invalid" run_script; then fail "Invalid project ID accepted"; fi
[[ ! -s "$workdir/calls.jsonl" ]] || fail "Invalid project called Azure"
if run_script --unknown; then fail "Unknown argument accepted"; fi
echo "PASS: invalid inputs are rejected"
echo "Cosmos data RBAC remediation tests passed."
