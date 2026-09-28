#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONTRACT_DIR="$REPO_ROOT/agents/contracts"

python3 - "$CONTRACT_DIR" <<'PY'
import json
import pathlib
import sys

contract_dir = pathlib.Path(sys.argv[1])
openapi = json.loads((contract_dir / "lookup.openapi.json").read_text())
fixture = json.loads((contract_dir / "lookup-fixture.json").read_text())
acceptance = json.loads((contract_dir / "lookup-acceptance.json").read_text())

if acceptance["openApi"] != "lookup.openapi.json" or acceptance["fixture"] != "lookup-fixture.json":
    sys.exit("acceptance cases must reference the shared OpenAPI contract and fixture")
if set(acceptance["adapters"]) != {"foundry-prompt", "aks-agent"}:
    sys.exit("the common acceptance contract must cover both initial agent adapters")

operation = openapi["paths"]["/records/{recordId}"]["get"]
if operation["operationId"] != "getSampleRecord":
    sys.exit("lookup operation ID changed unexpectedly")
if set(operation["responses"]) != {"200", "404", "503"}:
    sys.exit("lookup contract must declare fixed success, not-found, and backend-failure responses")
if "security" not in operation:
    sys.exit("lookup operation must declare bearer authentication")

records = {record["recordId"]: record for record in fixture["records"]}
for case in acceptance["cases"]:
    record_id = case["recordId"]
    if case["status"] == 200 and records.get(record_id) != case["expected"]:
        sys.exit(f"success case {case['name']} does not match the shared fixture")
    if case["status"] == 404 and record_id in records:
        sys.exit(f"not-found case {case['name']} unexpectedly exists in the fixture")
    if case["status"] == 503 and record_id != fixture["failureRecordId"]:
        sys.exit(f"backend-failure case {case['name']} does not use the reserved fixture identifier")

print("Shared lookup contract and fixture are consistent.")
PY
