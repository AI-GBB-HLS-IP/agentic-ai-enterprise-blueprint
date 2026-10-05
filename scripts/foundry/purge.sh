#!/usr/bin/env bash
set -euo pipefail

# Lists (default) or purges (--execute) soft-deleted Foundry leftovers for a failed/retried
# deployment: the Cognitive Services (AIServices) account and, optionally, the Key Vault. Azure
# soft-deletes these resource types on delete/failed-create cleanup; a soft-deleted resource with
# the same name blocks recreation until it is purged. This script never infers a subscription;
# Azure CLI's active subscription must be selected by the caller.

: "${LOCATION:?LOCATION is required (the region the failed resources were created in)}"
: "${RG_NAME:?RG_NAME is required (the original resource group of the failed account)}"
: "${FOUNDRY_ACCOUNT_NAME:?FOUNDRY_ACCOUNT_NAME is required}"
: "${FOUNDRY_KEY_VAULT_NAME:=}"

EXECUTE=false
if [ "${1:-}" = "--execute" ]; then
  EXECUTE=true
fi

echo "Checking for soft-deleted Cognitive Services account: $FOUNDRY_ACCOUNT_NAME (location: $LOCATION)"
deleted_account_json="$(az cognitiveservices account list-deleted --query "[?name=='$FOUNDRY_ACCOUNT_NAME']" -o json)"

if [ "$deleted_account_json" = "[]" ]; then
  echo "No soft-deleted Cognitive Services account named '$FOUNDRY_ACCOUNT_NAME' found."
else
  echo "$deleted_account_json"
  if [ "$EXECUTE" = true ]; then
    echo "Purging Cognitive Services account '$FOUNDRY_ACCOUNT_NAME'..."
    az cognitiveservices account purge \
      --resource-group "$RG_NAME" \
      --location "$LOCATION" \
      --name "$FOUNDRY_ACCOUNT_NAME"
    echo "Purged."
  else
    echo "Refusing to purge. Re-run with --execute after reviewing the resource above."
  fi
fi

if [ -n "$FOUNDRY_KEY_VAULT_NAME" ]; then
  echo "Checking for soft-deleted Key Vault: $FOUNDRY_KEY_VAULT_NAME (location: $LOCATION)"
  deleted_vault_json="$(az keyvault list-deleted --query "[?name=='$FOUNDRY_KEY_VAULT_NAME']" -o json)"

  if [ "$deleted_vault_json" = "[]" ]; then
    echo "No soft-deleted Key Vault named '$FOUNDRY_KEY_VAULT_NAME' found."
  else
    echo "$deleted_vault_json"
    if [ "$EXECUTE" = true ]; then
      echo "Purging Key Vault '$FOUNDRY_KEY_VAULT_NAME'..."
      az keyvault purge --name "$FOUNDRY_KEY_VAULT_NAME" --location "$LOCATION"
      echo "Purged."
    else
      echo "Refusing to purge. Re-run with --execute after reviewing the resource above."
    fi
  fi
fi

if [ "$EXECUTE" = false ]; then
  echo "Dry run complete. No resources were purged."
fi
