#!/usr/bin/env bash
set -euo pipefail

: "${RG_NAME:?RG_NAME is required}"
: "${TEMPLATE_FILE:?TEMPLATE_FILE is required}"
: "${PARAMETER_FILE:?PARAMETER_FILE is required}"
: "${DEPLOYMENT_NAME:=foundry-$(date -u +%Y%m%d%H%M%S)}"

if [ "${1:-}" != "--execute" ]; then
  echo "Refusing deployment. Run what-if first, then pass --execute after approval." >&2
  exit 2
fi

"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/what-if.sh"

az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file "$TEMPLATE_FILE" \
  --parameters "$PARAMETER_FILE" \
  --name "$DEPLOYMENT_NAME" \
  --mode Incremental
