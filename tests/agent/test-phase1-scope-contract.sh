#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
acceptance = json.loads((root / "agents/contracts/lookup-acceptance.json").read_text())
chapter_07 = " ".join((root / "chapters/07-prompt-agent.md").read_text().split()).lower()
chapter_08 = " ".join((root / "chapters/08-hosted-agent.md").read_text().split()).lower()

if set(acceptance["adapters"]) != {"foundry-prompt", "aks-agent"}:
    sys.exit("initial acceptance must target only the Foundry prompt and AKS agents")
if any("hosted" in adapter.lower() for adapter in acceptance["adapters"]):
    sys.exit("the Foundry-managed Hosted Agent must not be an initial acceptance target")
for phrase in (
    "same poc tool permission",
    "diagnostic only",
    "do not establish per-agent authorization",
):
    if phrase not in chapter_07:
        sys.exit(f"Chapter 07 is missing the shared Foundry caller boundary: {phrase}")
for phrase in (
    "follow-on",
    "reuse the sample corpus",
    "knowledge and tool contracts",
    "common acceptance suite",
    "identity, network, memory, or telemetry",
):
    if phrase not in chapter_08:
        sys.exit(f"Chapter 08 is missing the scoped Hosted Agent follow-on contract: {phrase}")

print("Phase 1 acceptance and hosted-agent follow-on scope contracts passed.")
PY
