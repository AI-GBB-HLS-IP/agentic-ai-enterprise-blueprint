#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CAPTURE="$REPO_ROOT/scripts/apim/get-existing-hostnames.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/bin"
cat >"$workdir/bin/az" <<'MOCK_AZ'
#!/usr/bin/env bash
set -euo pipefail
case "${AZ_MOCK_MODE:-}" in
  notfound)
    echo "(ResourceNotFound) The Resource 'Microsoft.ApiManagement/service/x' was not found." >&2
    exit 3
    ;;
  denied)
    echo "(AuthorizationFailed) The client does not have authorization to perform this action." >&2
    exit 1
    ;;
  empty)
    exit 0
    ;;
  none)
    echo 'null'
    ;;
  *)
    cat <<'JSON'
[
  {"type":"Proxy","hostName":"apim-example.azure-api.net","certificateSource":"BuiltIn","keyVaultId":null,"defaultSslBinding":false},
  {"type":"Proxy","hostName":"pfx.example.com","certificateSource":"Custom","keyVaultId":null,"certificate":{"thumbprint":"AA"},"defaultSslBinding":true},
  {"type":"Management","hostName":"kv.example.com","certificateSource":"KeyVault","keyVaultId":"https://kv.example/secrets/x","identityClientId":"0000","negotiateClientCertificate":true,"certificate":{"thumbprint":"BB"},"certificateStatus":null,"certificatePassword":null,"encodedCertificate":null},
  {"type":"DeveloperPortal","hostName":"managed.example.com","certificateSource":"Managed","keyVaultId":null,"certificateStatus":"Completed"}
]
JSON
    ;;
esac
MOCK_AZ
chmod +x "$workdir/bin/az"
export PATH="$workdir/bin:$PATH"

# Key Vault and managed domains are kept with all settings; PFX and built-in are omitted.
AZ_MOCK_MODE=ok "$CAPTURE" rg apim >"$workdir/out.json" 2>"$workdir/err.txt" ||
  fail "capture must succeed for a service with mixed domains"
python3 - "$workdir/out.json" <<'PY' || fail "captured output does not match the contract"
import json, sys
d = json.load(open(sys.argv[1]))
names = sorted(e["hostName"] for e in d)
assert names == ["kv.example.com", "managed.example.com"], names
kv = next(e for e in d if e["hostName"] == "kv.example.com")
assert kv["keyVaultId"] == "https://kv.example/secrets/x"
assert kv["identityClientId"] == "0000" and kv["negotiateClientCertificate"] is True
for e in d:
    for k in ("certificate", "certificateStatus", "certificatePassword", "encodedCertificate"):
        assert k not in e, (e["hostName"], k)
PY
grep -Fq 'WARNING: Proxy pfx.example.com uses an uploaded PFX' "$workdir/err.txt" ||
  fail "uploaded PFX domains must produce a stderr warning"
if grep -Fq 'azure-api.net' "$workdir/err.txt"; then
  fail "the built-in endpoint must not be reported as a PFX loss"
fi

# A missing service is a legitimate first deployment.
out="$(AZ_MOCK_MODE=notfound "$CAPTURE" rg apim 2>/dev/null)" ||
  fail "a missing service must not fail"
[[ "$out" == "[]" ]] || fail "a missing service must print []"

# Null or empty az output yields [] without a traceback.
for mode in none empty; do
  out="$(AZ_MOCK_MODE=$mode "$CAPTURE" rg apim 2>"$workdir/err.txt")" ||
    fail "$mode az output must not fail"
  [[ "$out" == "[]" ]] || fail "$mode az output must print []"
  if grep -Fq Traceback "$workdir/err.txt"; then
    fail "$mode az output must not produce a Python traceback"
  fi
done

# Other az failures must not become [], which would delete live domains on deployment.
if out="$(AZ_MOCK_MODE=denied "$CAPTURE" rg apim 2>"$workdir/err.txt")"; then
  fail "an authorization failure must fail the capture"
fi
[[ -z "$out" ]] || fail "a failed capture must not print a hostname list"
grep -Fq 'AuthorizationFailed' "$workdir/err.txt" ||
  fail "the az error must be shown to the operator"

echo "APIM hostname capture tests passed."
