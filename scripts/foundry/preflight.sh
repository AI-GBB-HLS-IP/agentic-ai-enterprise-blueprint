#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

: "${RG_NAME:=rg-agent-factory-poc}"
: "${VNET_NAME:=vnet-agent-factory-poc}"
: "${LOCATION:=eastus2}"
: "${MODEL_FORMAT:=OpenAI}"
: "${DEPLOYMENT_SKU:=Standard}"
: "${MODEL_NAME:?MODEL_NAME is required}"
: "${REQUESTED_CAPACITY:?REQUESTED_CAPACITY is required}"

RG_NAME="$RG_NAME" \
VNET_NAME="$VNET_NAME" \
LOCATION="$LOCATION" \
"$REPO_ROOT/specs/01-foundry-byo-networking/validation/validate.sh"

LOCATION="$LOCATION" \
MODEL_FORMAT="$MODEL_FORMAT" \
MODEL_NAME="$MODEL_NAME" \
DEPLOYMENT_SKU="$DEPLOYMENT_SKU" \
REQUESTED_CAPACITY="$REQUESTED_CAPACITY" \
"$REPO_ROOT/specs/01-foundry-byo-networking/validation/model-preflight.sh"

echo "Foundry preflight passed."
