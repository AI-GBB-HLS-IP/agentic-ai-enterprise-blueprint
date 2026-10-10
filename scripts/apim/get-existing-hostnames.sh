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

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if ! az apim show -g "$rg" -n "$name" --query "hostnameConfigurations" -o json >"$tmp" 2>"$tmp.err"; then
  if grep -qi "ResourceNotFound\|could not be found\|not found" "$tmp.err"; then
    rm -f "$tmp.err"
    echo "APIM '$name' not found in '$rg'; returning an empty list." >&2
    echo '[]'
    exit 0
  fi
  echo "ERROR: az apim show failed:" >&2
  cat "$tmp.err" >&2
  rm -f "$tmp.err"
  exit 1
fi
rm -f "$tmp.err"

python3 - "$tmp" <<'PY'
import json, sys

raw = open(sys.argv[1]).read().strip()
try:
    live = json.loads(raw) if raw else []
except ValueError:
    sys.exit("ERROR: az apim show did not return JSON: %r" % raw[:200])
live = live or []

keep = []
for e in live:
    # BuiltIn is the default *.azure-api.net endpoint, which APIM manages implicitly.
    if e.get("certificateSource") == "BuiltIn" or str(e.get("hostName", "")).lower().rstrip(".").endswith(".azure-api.net"):
        continue
    # APIM never returns uploaded PFX certificates, so those domains cannot be preserved.
    if e.get("keyVaultId") or e.get("certificateSource") == "Managed":
        for k in ("certificate", "certificateStatus", "certificatePassword", "encodedCertificate"):
            e.pop(k, None)
        keep.append(e)
    else:
        print("WARNING: %s %s uses an uploaded PFX and cannot be preserved; declare it in "
              "hostnameConfigurations with hostnameMode=merge or replace, or it is removed."
              % (e.get("type"), e.get("hostName")), file=sys.stderr)
print(json.dumps(keep))
PY
