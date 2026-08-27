#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

: "${RG_NAME:=rg-agent-factory-poc}"
: "${LOCATION:=eastus2}"
: "${VNET_NAME:=vnet-agent-factory-poc}"
: "${APIM_SUBNET_NAME:=snet-apim}"
: "${PRIVATE_ENDPOINT_SUBNET_NAME:=snet-privateendpoints}"
: "${FOUNDRY_ACCOUNT_NAME:=foundry-agent-factory-poc}"
: "${MODEL_DEPLOYMENT_NAME:=gpt-4.1-mini}"
: "${APIM_TEMPLATE_FILE:=infra/envs/poc/apim.bicep}"
: "${APIM_PARAMETER_FILE:=infra/envs/poc/apim.bicepparam}"
: "${APIM_DEPLOYMENT_NAME:=apim-preflight}"
: "${APIM_NAME:=apim-agent-factory-private-poc}"

required_files=(
  "infra/modules/apim/main.bicep"
  "infra/modules/apim/private-dns.bicep"
  "infra/modules/apim/backend.bicep"
  "infra/modules/apim/api.bicep"
  "infra/modules/apim/observability.bicep"
  "infra/envs/poc/apim.bicep"
  "infra/envs/poc/apim.bicepparam"
)

echo "== APIM offline validation =="
for file in "${required_files[@]}"; do
  if [[ ! -f "$REPO_ROOT/$file" ]]; then
    echo "ERROR: missing required file: $file" >&2
    exit 1
  fi
done

bicep_files=(
  "infra/modules/apim/main.bicep"
  "infra/modules/apim/private-dns.bicep"
  "infra/modules/apim/backend.bicep"
  "infra/modules/apim/api.bicep"
  "infra/modules/apim/observability.bicep"
  "infra/envs/poc/apim.bicep"
)

compile_blocked=false
if command -v az >/dev/null 2>&1; then
  for file in "${bicep_files[@]}"; do
    echo "Compiling $file"
    az bicep build --file "$REPO_ROOT/$file" --stdout >/dev/null
  done
elif command -v bicep >/dev/null 2>&1; then
  for file in "${bicep_files[@]}"; do
    echo "Compiling $file"
    bicep build "$REPO_ROOT/$file" --stdout >/dev/null
  done
else
  echo "BLOCKED: Neither Azure CLI nor standalone Bicep CLI is installed; compilation skipped."
  compile_blocked=true
fi

echo "== Static fail-closed guard checks =="
grep -q "virtualNetworkType: 'Internal'" "$REPO_ROOT/infra/modules/apim/main.bicep"
grep -q "authentication-managed-identity" "$REPO_ROOT/infra/modules/apim/backend.bicep"
grep -q "Microsoft.ApiManagement/service/namedValues" "$REPO_ROOT/infra/modules/apim/api.bicep"
grep -qE "approvedModels:[[:space:]]*approvedModels" "$REPO_ROOT/infra/envs/poc/apim.bicep"
grep -qE "param[[:space:]]+approvedModels[[:space:]]*=[[:space:]]*\\[" "$REPO_ROOT/infra/envs/poc/apim.bicepparam"

if grep -R -n "approvedModelName" "$REPO_ROOT/infra/modules/apim" "$REPO_ROOT/infra/envs/poc/apim.bicep" >/dev/null; then
  echo "ERROR: hardcoded single-model policy parameter detected." >&2
  exit 1
fi

if grep -R -n -E "Content Safety|semantic cache|secondary backend" "$REPO_ROOT/infra/modules/apim" >/dev/null; then
  echo "ERROR: out-of-scope capability detected in APIM modules." >&2
  exit 1
fi

if grep -R -n -E "api[-_]?key|subscriptionKey|keyVault" "$REPO_ROOT/infra/modules/apim/backend.bicep" >/dev/null; then
  echo "ERROR: backend module appears to include secret/key-based auth." >&2
  exit 1
fi

if grep -R -n -E "/mcp/|/a2a/|service/apis/.+mcp|service/apis/.+a2a" "$REPO_ROOT/infra/modules/apim" >/dev/null; then
  echo "ERROR: MCP/A2A resources are out of scope for Chapter 02 core gateway." >&2
  exit 1
fi

live_blocked="$compile_blocked"

if ! command -v az >/dev/null 2>&1; then
  echo "BLOCKED: Azure CLI is not installed; live Azure prerequisite checks skipped."
  live_blocked=true
elif ! az account show >/dev/null 2>&1; then
  echo "BLOCKED: No active Azure login/session; live Azure prerequisite checks skipped."
  live_blocked=true
else
  echo "== Live read-only prerequisite checks =="
  az group show --name "$RG_NAME" \
    --query "location=='$LOCATION' && properties.provisioningState=='Succeeded'" -o tsv | grep -qx true

  VNET_ID="$(az network vnet show -g "$RG_NAME" -n "$VNET_NAME" --query id -o tsv)"

  az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" -n "$APIM_SUBNET_NAME" \
    --query "addressPrefix=='10.0.1.0/24'" -o tsv | grep -qx true

  az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" -n "$PRIVATE_ENDPOINT_SUBNET_NAME" \
    --query "addressPrefix=='10.0.4.0/24'" -o tsv | grep -qx true

  az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" -n "$APIM_SUBNET_NAME" \
    --query "networkSecurityGroup.id!=null" -o tsv | grep -qx true

  az cognitiveservices account show -g "$RG_NAME" -n "$FOUNDRY_ACCOUNT_NAME" \
    --query "location=='$LOCATION'" -o tsv | grep -qx true

  az cognitiveservices account deployment show \
    --resource-group "$RG_NAME" \
    --name "$FOUNDRY_ACCOUNT_NAME" \
    --deployment-name "$MODEL_DEPLOYMENT_NAME" \
    --query "name=='$MODEL_DEPLOYMENT_NAME'" -o tsv | grep -qx true

  az network private-dns zone show -g "$RG_NAME" -n "privatelink.azure-api.net" \
    --query "name=='privatelink.azure-api.net'" -o tsv | grep -qx true || true

  az deployment group what-if \
    --resource-group "$RG_NAME" \
    --template-file "$REPO_ROOT/$APIM_TEMPLATE_FILE" \
    --parameters "$REPO_ROOT/$APIM_PARAMETER_FILE" \
    --name "$APIM_DEPLOYMENT_NAME" \
    --result-format ResourceIdOnly

  if az apim show -g "$RG_NAME" -n "$APIM_NAME" >/dev/null 2>&1; then
    az apim show -g "$RG_NAME" -n "$APIM_NAME" \
      --query "virtualNetworkType=='Internal' && (publicIPAddresses==null || length(publicIPAddresses)==\`0\`)" -o tsv | grep -qx true

    APIM_PRINCIPAL_ID="$(az apim show -g "$RG_NAME" -n "$APIM_NAME" --query identity.principalId -o tsv)"
    FOUNDRY_SCOPE="$(az cognitiveservices account show -g "$RG_NAME" -n "$FOUNDRY_ACCOUNT_NAME" --query id -o tsv)"
    az role assignment list --assignee "$APIM_PRINCIPAL_ID" --scope "$FOUNDRY_SCOPE" \
      --query "[?roleDefinitionName=='Cognitive Services OpenAI User'] | length(@)" -o tsv | grep -qx 1
  else
    echo "INFO: APIM resource not deployed yet; runtime posture checks remain pending."
  fi

  echo "Live prerequisite checks completed."
fi

if [[ "$live_blocked" == true ]]; then
  if [[ "$compile_blocked" == true ]]; then
    echo "Static checks passed; Bicep compilation and live gates remain blocked."
  else
    echo "Offline checks passed; live gates are blocked pending Azure access."
  fi
  exit 3
fi

echo "All APIM validations passed."
