#!/usr/bin/env bash
# Prints the live APIM custom domains as a JSON array on stdout, for the
# APIM_EXISTING_HOSTNAMES_JSON variable read by infra/envs/poc/apim*.bicepparam.
#
# Run this before EVERY APIM deployment when hostnameMode is 'preserve' (default) or 'merge'.
# Skipping it sends an empty list and the deployment removes all live custom domains.
#
# Usage:
#   export APIM_EXISTING_HOSTNAMES_JSON="$(scripts/apim/get-existing-hostnames.sh <resource-group> <apim-name>)"
#
# Prints [] when the service does not exist yet (first deployment). Messages go to stderr.
set -euo pipefail

rg="${1:?resource group required}"
name="${2:?APIM service name required}"

if ! az apim show -g "$rg" -n "$name" -o none 2>/dev/null; then
  echo "APIM '$name' not found in '$rg'; returning an empty list." >&2
  echo '[]'
  exit 0
fi

# Default *.azure-api.net endpoints are implicit; only custom domains are returned.
# The full live object is passed through so no domain setting is lost; only the read-only
# certificate details are removed.
live="$(az apim show -g "$rg" -n "$name" \
  --query "properties.hostnameConfigurations[?hostName && !ends_with(hostName, '.azure-api.net') && !ends_with(hostName, '.azure-api.net.')]" \
  -o json)"

# APIM never returns uploaded PFX certificates, so domains that use one (no keyVaultId and not
# APIM-managed) cannot be preserved. They are dropped; declare them in hostnameConfigurations.
python3 -c '
import json, sys
live = json.loads(sys.argv[1]) or []
keep = []
for e in live:
    if e.get("keyVaultId") or e.get("certificateSource") == "Managed":
        for k in ("certificate", "certificateStatus"):
            e.pop(k, None)
        keep.append(e)
    else:
        print("WARNING: %s %s uses an uploaded PFX and cannot be preserved; declare it in "
              "hostnameConfigurations with hostnameMode=merge or replace, or it is removed."
              % (e["type"], e["hostName"]), file=sys.stderr)
print(json.dumps(keep))
' "$live"
