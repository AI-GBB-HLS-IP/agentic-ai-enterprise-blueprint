#!/usr/bin/env bash
set -euo pipefail

: "${RG_NAME:?RG_NAME is required}"
: "${TEMPLATE_FILE:?TEMPLATE_FILE is required}"
: "${PARAMETER_FILE:?PARAMETER_FILE is required}"
: "${DEPLOYMENT_NAME:=foundry-preflight}"

az bicep build --file "$TEMPLATE_FILE" --stdout >/dev/null

az deployment group what-if \
  --resource-group "$RG_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAMETER_FILE" \
  --name "$DEPLOYMENT_NAME" \
  --result-format ResourceIdOnly
