#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: validate-policy-inputs.sh --input <path-to-json> | --json <json-string>

Validates the Network Foundation policy handoff object.
EOF
}

input_path=""
json_payload=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --input" >&2
        usage
        exit 1
      fi
      input_path="$2"
      shift 2
      ;;
    --json)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --json" >&2
        usage
        exit 1
      fi
      json_payload="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$input_path" && -z "$json_payload" ]]; then
  echo "A JSON payload or input file is required." >&2
  usage
  exit 1
fi

if [[ -n "$input_path" ]]; then
  if [[ ! -f "$input_path" ]]; then
    echo "Input file not found: $input_path" >&2
    exit 1
  fi
  json_payload="$(<"$input_path")"
fi

python3 - "$json_payload" <<'PY'
import json
import re
import sys

raw = sys.argv[1]

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"Invalid JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(data, dict):
    print("policyInputs validation failed: top-level JSON must be an object.", file=sys.stderr)
    raise SystemExit(1)

policy = data.get("policyInputs")
if not isinstance(policy, dict):
    print("policyInputs validation failed: policyInputs must be an object.", file=sys.stderr)
    raise SystemExit(1)

for key in ("publicNetworkAccessDisabled", "localAuthDisabled"):
    if key not in policy:
        print(f"policyInputs validation failed: missing required boolean '{key}'.", file=sys.stderr)
        raise SystemExit(1)
    value = policy[key]
    if not isinstance(value, bool):
        print(f"policyInputs validation failed: '{key}' must be a JSON boolean, not {type(value).__name__}.", file=sys.stderr)
        raise SystemExit(1)
    if value is not True:
        print(f"policyInputs validation failed: '{key}' must be true.", file=sys.stderr)
        raise SystemExit(1)

allowed = policy.get("allowedModelSkus")
if not isinstance(allowed, list) or len(allowed) == 0:
    print("policyInputs validation failed: allowedModelSkus must be a non-empty array.", file=sys.stderr)
    raise SystemExit(1)

seen = set()
for entry in allowed:
    if not isinstance(entry, str):
        print("policyInputs validation failed: allowedModelSkus entries must be strings.", file=sys.stderr)
        raise SystemExit(1)

    value = entry.strip()
    if value == "":
        print("policyInputs validation failed: allowedModelSkus entries cannot be empty or whitespace-only.", file=sys.stderr)
        raise SystemExit(1)

    if value != entry:
        print("policyInputs validation failed: allowedModelSkus entries must be exact strings without leading or trailing whitespace.", file=sys.stderr)
        raise SystemExit(1)

    if re.search(r"\s", value):
        print("policyInputs validation failed: allowedModelSkus entries cannot contain whitespace.", file=sys.stderr)
        raise SystemExit(1)

    if any(ch in value for ch in "*?[]{}()!^$+|\\"):
        print("policyInputs validation failed: allowedModelSkus entries cannot contain wildcards or pattern syntax.", file=sys.stderr)
        raise SystemExit(1)

    if value in seen:
        print(f"policyInputs validation failed: duplicate allowedModelSkus entry '{value}'.", file=sys.stderr)
        raise SystemExit(1)

    seen.add(value)

print(json.dumps(policy, separators=(",", ":")))
PY
