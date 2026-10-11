#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
if command -v bicep >/dev/null 2>&1; then
  bicep_bin="$(command -v bicep)"
elif [[ -x "$HOME/.azure/bin/bicep" ]]; then
  bicep_bin="$HOME/.azure/bin/bicep"
else
  echo "BLOCKED: Bicep CLI is required for evaluated APIM endpoint tests." >&2
  exit 3
fi

output="$("$bicep_bin" test "$SCRIPT_DIR/bicep/endpoints.tests.bicep" 2>&1)" || {
  printf '%s\n' "$output" >&2
  exit 1
}
grep -q 'All 2 evaluations passed' <<<"$output" || {
  printf '%s\n' "$output" >&2
  exit 1
}
for template in infra/envs/poc/apim.bicep infra/modules/apim/private-dns.bicep infra/envs/poc/apim-foundry-integration.bicep; do
  "$bicep_bin" build "$REPO_ROOT/$template" --stdout >/dev/null
done
for parameters in apim.bicepparam apim.customer.example.bicepparam; do
  env APIM_HOSTNAME_CONFIGURATIONS_JSON='[{"type":"Proxy","hostName":"api.example.com","certificateKey":"gateway"}]' \
    APIM_HOSTNAME_CERTIFICATES_JSON='{"gateway":{"encodedCertificate":"fixture-not-a-certificate","certificatePassword":"fixture-not-a-secret"}}' \
    "$bicep_bin" build-params "$REPO_ROOT/infra/envs/poc/$parameters" --stdout |
    jq -e '
      .parametersJson | fromjson | .parameters |
      .hostnameConfigurations.value == [{type:"Proxy",hostName:"api.example.com",certificateKey:"gateway"}]
      and .hostnameCertificates.value.gateway ==
        {encodedCertificate:"fixture-not-a-certificate",certificatePassword:"fixture-not-a-secret"}
    ' >/dev/null
done
env -u APIM_HOSTNAME_CONFIGURATIONS_JSON "$bicep_bin" build-params "$REPO_ROOT/infra/envs/poc/apim.customer.example.bicepparam" --stdout |
  jq -e '.parametersJson | fromjson | .parameters.hostnameConfigurations.value | length == 3' >/dev/null
env -u APIM_HOSTNAME_CERTIFICATES_JSON APIM_GATEWAY_PFX_BASE64=fixture-individual-certificate \
  APIM_GATEWAY_PFX_PASSWORD=fixture-individual-password \
  "$bicep_bin" build-params "$REPO_ROOT/infra/envs/poc/apim.customer.example.bicepparam" --stdout |
  jq -e '
    .parametersJson | fromjson | .parameters.hostnameCertificates.value.gateway ==
      {encodedCertificate:"fixture-individual-certificate",certificatePassword:"fixture-individual-password"}
  ' >/dev/null
echo "PASS: evaluated APIM endpoint selection, bindings, evidence, and readiness predicates"
