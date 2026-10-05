#!/usr/bin/env bash
set -euo pipefail

# Lists (default) or purges/deletes (--execute) Foundry leftovers for a failed/retried
# deployment: a live Cognitive Services (AIServices) account stuck in a non-Succeeded
# provisioning state, and soft-deleted copies of the account and/or Key Vault. Azure soft-deletes
# these resource types on delete/failed-create cleanup; a soft-deleted resource with the same
# name blocks recreation until it is purged, and a live resource stuck in a Failed state can
# likewise block a clean redeploy until it is deleted. This script never infers a subscription;
# Azure CLI's active subscription must be selected by the caller.

: "${LOCATION:?LOCATION is required (the region the failed resources were created in)}"
: "${RG_NAME:?RG_NAME is required (the original resource group of the failed account)}"
: "${FOUNDRY_ACCOUNT_NAME:?FOUNDRY_ACCOUNT_NAME is required}"
: "${FOUNDRY_KEY_VAULT_NAME:=}"

EXECUTE=false
if [ "${1:-}" = "--execute" ]; then
  EXECUTE=true
fi

echo "Checking for a live Cognitive Services account: $FOUNDRY_ACCOUNT_NAME in $RG_NAME"
if live_output="$(az cognitiveservices account show --resource-group "$RG_NAME" --name "$FOUNDRY_ACCOUNT_NAME" --query "properties.provisioningState" -o tsv 2>&1)"; then
  live_state="$(printf '%s' "$live_output" | tr -d '[:space:]')"
  if [ -z "$live_state" ]; then
    echo "Could not determine the provisioning state of '$FOUNDRY_ACCOUNT_NAME'; refusing to continue." >&2
    exit 1
  fi
else
  lookup_status=$?
  if [[ "$live_output" =~ (^|[^[:alnum:]_])ResourceNotFound([^[:alnum:]_]|$) ]]; then
    live_state=""
  else
    printf "Failed to look up live Cognitive Services account '%s': %s\n" "$FOUNDRY_ACCOUNT_NAME" "$live_output" >&2
    exit "$lookup_status"
  fi
fi

if [ -z "$live_state" ]; then
  echo "No live Cognitive Services account named '$FOUNDRY_ACCOUNT_NAME' found in $RG_NAME."
elif [ "$live_state" = "Succeeded" ]; then
  echo "Live Cognitive Services account '$FOUNDRY_ACCOUNT_NAME' is healthy (provisioningState: Succeeded). Leaving it in place."
else
  echo "Live Cognitive Services account '$FOUNDRY_ACCOUNT_NAME' exists with provisioningState: $live_state."
  if [ "$live_state" = "Failed" ] && [ "$EXECUTE" = true ]; then
    echo "Deleting Cognitive Services account '$FOUNDRY_ACCOUNT_NAME'..."
    az cognitiveservices account delete --resource-group "$RG_NAME" --name "$FOUNDRY_ACCOUNT_NAME"
    echo "Deleted. It may now appear as soft-deleted below; re-run this script to purge it."
  elif [ "$EXECUTE" = true ]; then
    echo "Provisioning state '$live_state' is not an explicitly allowed terminal failure state; leaving it in place."
  else
    echo "Refusing to delete. Only a Failed-state account is eligible; re-run with --execute after reviewing the resource above."
  fi
fi

echo "Checking for soft-deleted Cognitive Services account: $FOUNDRY_ACCOUNT_NAME (location: $LOCATION)"
account_count="$(az cognitiveservices account list-deleted --query "length([?name=='$FOUNDRY_ACCOUNT_NAME'])" -o tsv | tr -d '[:space:]')"

if [ "$account_count" = "0" ] || [ -z "$account_count" ]; then
  echo "No soft-deleted Cognitive Services account named '$FOUNDRY_ACCOUNT_NAME' found."
else
  az cognitiveservices account list-deleted --query "[?name=='$FOUNDRY_ACCOUNT_NAME']" -o json
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
  vault_count="$(az keyvault list-deleted --query "length([?name=='$FOUNDRY_KEY_VAULT_NAME'])" -o tsv | tr -d '[:space:]')"

  if [ "$vault_count" = "0" ] || [ -z "$vault_count" ]; then
    echo "No soft-deleted Key Vault named '$FOUNDRY_KEY_VAULT_NAME' found."
  else
    az keyvault list-deleted --query "[?name=='$FOUNDRY_KEY_VAULT_NAME']" -o json
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
