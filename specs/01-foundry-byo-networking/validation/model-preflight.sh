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

quota_name="${MODEL_FORMAT}.${DEPLOYMENT_SKU}.${MODEL_NAME}"
quota_json="$(az cognitiveservices usage list \
  --location "$LOCATION" \
  --query "[?name.value=='OpenAI.Standard.$MODEL_NAME' || name.value=='$quota_name']" \
  -o json)"

if [ "$quota_json" = "[]" ]; then
  echo "No quota record found for $quota_name in $LOCATION." >&2
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
