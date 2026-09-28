#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/agents/knowledge/sample-corpus/v1"

python3 - "$CORPUS_DIR" <<'PY'
import json
import pathlib
import re
import sys

corpus_dir = pathlib.Path(sys.argv[1])
manifest = json.loads((corpus_dir / "manifest.json").read_text())
source_ids = set()

for document in manifest["documents"]:
    source_id = document["sourceId"]
    if source_id in source_ids:
        sys.exit(f"duplicate source ID: {source_id}")
    source_ids.add(source_id)

    content = " ".join((corpus_dir / document["path"]).read_text().split())
    if f"Source ID: `{source_id}`" not in content:
        sys.exit(f"{document['path']} does not declare its stable source ID")
    normalized_content = re.sub(r"[^a-z0-9 ]", "", content.lower())
    for fact in document["expectedFacts"]:
        normalized_fact = re.sub(r"[^a-z0-9 ]", "", fact.lower())
        if normalized_fact not in normalized_content:
            sys.exit(f"expected fact is not present in {document['path']}: {fact}")

if len(manifest["documents"]) < 1:
    sys.exit("the sample corpus must contain at least one document")
print("Sample corpus manifest and expected facts are consistent.")
PY
