#!/usr/bin/env bash
set -euo pipefail

LOCATION="${LOCATION:-eastus2}"
MODEL_FORMAT="${MODEL_FORMAT:-OpenAI}"
MODEL_NAME="${MODEL_NAME:?MODEL_NAME is required}"
DEPLOYMENT_SKU="${DEPLOYMENT_SKU:-Standard}"
REQUESTED_CAPACITY="${REQUESTED_CAPACITY:?REQUESTED_CAPACITY is required}"

if ! [[ "$REQUESTED_CAPACITY" =~ ^[0-9]+$ ]] || [ "$REQUESTED_CAPACITY" -le 0 ]; then
  echo "Requested capacity must be a positive integer in quota units." >&2
  exit 1
fi

# Azure's cognitiveservices usage list drops the hyphen between "gpt" and "4.1" specifically
# (observed: gpt-4.1, gpt-4.1-mini, gpt-4.1-nano register as gpt4.1, gpt4.1-mini, gpt4.1-nano),
# while other versioned families (gpt-4o, gpt-4-turbo-*, gpt-5.1, gpt-5.4, ...) keep the hyphen
# as-is. Try the exact name first, then fall back to the de-hyphenated variant so preflight
# doesn't false-negative on this naming quirk rather than a real capacity problem.
alt_model_name="$(printf '%s' "$MODEL_NAME" | sed -E 's/^gpt-4\.1/gpt4.1/')"

candidate_model_names=("$MODEL_NAME")
if [ "$alt_model_name" != "$MODEL_NAME" ]; then
  candidate_model_names+=("$alt_model_name")
fi

quota_json="[]"
for candidate_model_name in "${candidate_model_names[@]}"; do
  quota_name="${MODEL_FORMAT}.${DEPLOYMENT_SKU}.${candidate_model_name}"
  quota_query="[?name.value=='${quota_name}']"
  quota_json="$(az cognitiveservices usage list \
    --location "$LOCATION" \
    --query "$quota_query" \
    -o json)"

  if [ "$quota_json" != "[]" ]; then
    break
  fi
done

if [ "$quota_json" = "[]" ]; then
  if [ "$alt_model_name" = "$MODEL_NAME" ]; then
    echo "No quota record found for ${MODEL_FORMAT}.${DEPLOYMENT_SKU}.${MODEL_NAME} in $LOCATION." >&2
  else
    echo "No quota record found for ${MODEL_FORMAT}.${DEPLOYMENT_SKU}.${MODEL_NAME} (also tried ${MODEL_FORMAT}.${DEPLOYMENT_SKU}.${alt_model_name}) in $LOCATION." >&2
  fi
  exit 1
fi

current="$(printf '%s' "$quota_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["currentValue"])')"
limit="$(printf '%s' "$quota_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["limit"])')"

if ! python3 - "$current" "$limit" "$REQUESTED_CAPACITY" <<'PY'
import sys
current, limit, requested = map(float, sys.argv[1:])
if limit - current < requested:
    raise SystemExit(1)
PY
then
  echo "Insufficient quota: current=$current limit=$limit requested=$REQUESTED_CAPACITY." >&2
  exit 1
fi

cat <<EOF
MODEL_PREFLIGHT=PASSED
LOCATION=$LOCATION
MODEL_FORMAT=$MODEL_FORMAT
MODEL_NAME=$MODEL_NAME
DEPLOYMENT_SKU=$DEPLOYMENT_SKU
CURRENT_QUOTA=$current
QUOTA_LIMIT=$limit
REQUESTED_CAPACITY=$REQUESTED_CAPACITY
EOF
