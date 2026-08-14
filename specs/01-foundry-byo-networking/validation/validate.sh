#!/usr/bin/env bash
set -euo pipefail

RG_NAME="${RG_NAME:-rg-agent-factory-poc}"
VNET_NAME="${VNET_NAME:-vnet-agent-factory-poc}"
LOCATION="${LOCATION:-eastus2}"

required_providers=(
  Microsoft.CognitiveServices
  Microsoft.Network
  Microsoft.App
  Microsoft.Storage
  Microsoft.KeyVault
  Microsoft.Sql
)

echo "Checking resource group and location..."
az group show --name "$RG_NAME" \
  --query "location=='$LOCATION' && properties.provisioningState=='Succeeded'" -o tsv | grep -qx true

VNET_ID="$(az network vnet show -g "$RG_NAME" -n "$VNET_NAME" --query id -o tsv)"

echo "Checking Foundry delegated subnet..."
foundry_prefix="$(az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" \
  -n snet-foundry --query addressPrefix -o tsv)"
foundry_delegation="$(az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" \
  -n snet-foundry --query "delegations[?serviceName=='Microsoft.App/environments'] | length(@)" -o tsv)"
test "$foundry_prefix" = "10.0.2.0/24"
test "$foundry_delegation" -gt 0

echo "Checking private-endpoint subnet..."
az network vnet subnet show -g "$RG_NAME" --vnet-name "$VNET_NAME" -n snet-privateendpoints \
  --query "addressPrefix=='10.0.4.0/24'" -o tsv | grep -qx true

echo "Checking provider registrations..."
for provider in "${required_providers[@]}"; do
  state="$(az provider show --namespace "$provider" --query registrationState -o tsv)"
  test "$state" = Registered
done

zones=(
  privatelink.cognitiveservices.azure.com
  privatelink.openai.azure.com
  privatelink.azure-api.net
  privatelink.vaultcore.azure.net
  privatelink.blob.core.windows.net
  privatelink.database.windows.net
)

echo "Checking private DNS zones and VNet links..."
for zone in "${zones[@]}"; do
  az network private-dns zone show -g "$RG_NAME" -n "$zone" --query name -o tsv | grep -qx "$zone"
  az network private-dns link vnet list -g "$RG_NAME" -z "$zone" \
    --query "[?virtualNetwork.id=='$VNET_ID'] | length(@)" -o tsv | grep -qx 1
done

echo "Network Foundation prerequisites passed."
