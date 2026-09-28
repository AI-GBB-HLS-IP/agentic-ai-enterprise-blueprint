#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/agents/knowledge/sample-corpus/v1"
CASES_FILE="$REPO_ROOT/agents/knowledge/grounding-acceptance.json"

python3 - "$CORPUS_DIR/manifest.json" "$CASES_FILE" "$CORPUS_DIR" <<'PY'
import json
import pathlib
import re
import sys

manifest_path = pathlib.Path(sys.argv[1])
cases_path = pathlib.Path(sys.argv[2])
corpus_dir = pathlib.Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text())
acceptance = json.loads(cases_path.read_text())

if acceptance["corpusVersion"] != manifest["corpusVersion"]:
    sys.exit("grounding cases must target the current corpus version")
documents = {document["sourceId"]: document for document in manifest["documents"]}
policy = acceptance["retrievalPolicy"]
if policy["minimumRelevantSourcesForAnswerable"] < 1 or policy["maximumUnsupportedClaims"] != 0:
    sys.exit("grounding policy must require a relevant source and prohibit unsupported claims")
if policy["unanswerableOutcome"] != "insufficient_knowledge":
    sys.exit("unanswerable queries must use the insufficient-knowledge outcome")

for case in acceptance["cases"]:
    if case["answerable"]:
        if len(case["expectedSourceIds"]) < policy["minimumRelevantSourcesForAnswerable"]:
            sys.exit(f"answerable case {case['caseId']} has too few expected sources")
        fact_text = " ".join(case["expectedAnswer"].lower().split())
        source_facts = []
        for source_id in case["expectedSourceIds"]:
            if source_id not in documents:
                sys.exit(f"case {case['caseId']} references unknown source ID {source_id}")
            source_facts.extend(documents[source_id]["expectedFacts"])
        normalized_answer = re.sub(r"[^a-z0-9 ]", "", fact_text)
        if not any(
            normalized_answer in re.sub(r"[^a-z0-9 ]", "", " ".join(fact.lower().split()))
            for fact in source_facts
        ):
            document_text = " ".join(
                " ".join((corpus_dir / documents[source_id]["path"]).read_text().lower().split())
                for source_id in case["expectedSourceIds"]
            )
            if normalized_answer not in re.sub(r"[^a-z0-9 ]", "", document_text):
                sys.exit(f"case {case['caseId']} expected answer is not supported by its source")
    elif case["expectedSourceIds"] or case["expectedAnswer"] is not None:
        sys.exit(f"unanswerable case {case['caseId']} must not declare an expected source or answer")

print("Grounding acceptance cases map to the shared sample corpus.")
PY
