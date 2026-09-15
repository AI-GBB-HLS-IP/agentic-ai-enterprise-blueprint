#!/usr/bin/env bash
# Verifies specs/01-foundry-byo-networking/validation/model-preflight.sh falls back to the
# de-hyphenated "gpt4.1" quota-bucket name when the hyphenated "gpt-4.1" form (matching the
# deployment model name) has no quota record — a real Azure Cognitive Services naming quirk
# discovered against a live tenant. Stubs `az` so no network/credentials are required.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/specs/01-foundry-byo-networking/validation/model-preflight.sh"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> model-preflight.sh falls back from gpt-4.1 to gpt4.1 when the hyphenated bucket is absent"
cat > "$workdir/az" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
query=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--query" ]; then
    query="${args[$((i + 1))]}"
  fi
done

if [[ "$query" == *"gpt4.1']"* ]]; then
  echo '[{"name":{"value":"OpenAI.GlobalStandard.gpt4.1"},"currentValue":10,"limit":90000}]'
else
  echo '[]'
fi
STUB
chmod +x "$workdir/az"
output="$(PATH="$workdir:$PATH" LOCATION=eastus MODEL_FORMAT=OpenAI MODEL_NAME=gpt-4.1 \
  DEPLOYMENT_SKU=GlobalStandard REQUESTED_CAPACITY=10 "$SCRIPT")"
echo "$output" | grep -qx "MODEL_PREFLIGHT=PASSED"
echo "$output" | grep -qx "MODEL_NAME=gpt-4.1"

echo "==> model-preflight.sh falls back from gpt-4.1-mini to gpt4.1-mini"
cat > "$workdir/az" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
query=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--query" ]; then
    query="${args[$((i + 1))]}"
  fi
done

if [[ "$query" == *"gpt4.1-mini']"* ]]; then
  echo '[{"name":{"value":"OpenAI.GlobalStandard.gpt4.1-mini"},"currentValue":0,"limit":450000}]'
else
  echo '[]'
fi
STUB
chmod +x "$workdir/az"
output="$(PATH="$workdir:$PATH" LOCATION=eastus MODEL_FORMAT=OpenAI MODEL_NAME=gpt-4.1-mini \
  DEPLOYMENT_SKU=GlobalStandard REQUESTED_CAPACITY=10 "$SCRIPT")"
echo "$output" | grep -qx "MODEL_PREFLIGHT=PASSED"

echo "==> model-preflight.sh does not alter names outside the gpt-4.1 family (gpt-5.1 stays hyphenated)"
cat > "$workdir/az" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
query=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [ "${args[$i]}" = "--query" ]; then
    query="${args[$((i + 1))]}"
  fi
done

if [[ "$query" == *"gpt-5.1']"* ]]; then
  echo '[{"name":{"value":"OpenAI.GlobalStandard.gpt-5.1"},"currentValue":0,"limit":30000}]'
else
  echo '[]'
fi
STUB
chmod +x "$workdir/az"
output="$(PATH="$workdir:$PATH" LOCATION=eastus MODEL_FORMAT=OpenAI MODEL_NAME=gpt-5.1 \
  DEPLOYMENT_SKU=GlobalStandard REQUESTED_CAPACITY=10 "$SCRIPT")"
echo "$output" | grep -qx "MODEL_PREFLIGHT=PASSED"

echo "==> model-preflight.sh reports both attempted names when neither exists"
cat > "$workdir/az" <<'STUB'
#!/usr/bin/env bash
echo '[]'
STUB
chmod +x "$workdir/az"
set +e
error_output="$(PATH="$workdir:$PATH" LOCATION=eastus MODEL_FORMAT=OpenAI MODEL_NAME=gpt-4.1 \
  DEPLOYMENT_SKU=GlobalStandard REQUESTED_CAPACITY=10 "$SCRIPT" 2>&1 1>/dev/null)"
exit_code=$?
set -e
test "$exit_code" -ne 0
echo "$error_output" | grep -q "OpenAI.GlobalStandard.gpt-4.1"
echo "$error_output" | grep -q "OpenAI.GlobalStandard.gpt4.1"

echo "Model preflight quota-name fallback tests passed."
