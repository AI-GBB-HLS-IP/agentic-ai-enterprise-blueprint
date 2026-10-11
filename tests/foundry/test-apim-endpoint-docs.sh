#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

consumers=(
  chapters/02-ai-gateway.md chapters/04-api-center.md chapters/05-react-discovery-ui.md
  chapters/07-prompt-agent.md chapters/08-hosted-agent.md chapters/09-work-iq.md
  chapters/10-serverless-agent.md chapters/13-m365-custom-engine.md
  chapters/21-foundry-project-blueprint.md chapters/21a-self-service-portal.md
  chapters/24-developer-build-experience.md chapters/25-cicd-gates.md
  chapters/26-end-to-end-walkthrough.md chapters/27-developer-journey.md
  infra/envs/poc/README.md specs/02-apim-ai-gateway/quickstart.md
  specs/02-apim-ai-gateway/validation/us3-requests.md
)
for file in "${consumers[@]}"; do
  grep -q 'APIM_GATEWAY_URL' "$file" || {
    echo "FAIL: $file lacks the selected gateway handoff" >&2
    exit 1
  }
  if grep -Eq 'https://apim-[[:alnum:]-]+(\.developer)?\.azure-api\.net' "$file"; then
    echo "FAIL: $file still hardcodes an APIM built-in client URL" >&2
    exit 1
  fi
done
for file in chapters/04-api-center.md chapters/07-prompt-agent.md chapters/09-work-iq.md chapters/10-serverless-agent.md; do
  grep -q '/mcp/enterprise-tools/mcp' "$file"
done
grep -q '/mcp/expense-api/mcp' chapters/10-serverless-agent.md
grep -q "/agents/travel/a2a" chapters/08-hosted-agent.md
grep -q "VITE_APIM_URL=.*APIM_GATEWAY_URL" chapters/05-react-discovery-ui.md
[[ "$(grep -c 'VITE_API_CENTER_URL="https://apic-agents-platform.azure-api.net"' chapters/05-react-discovery-ui.md)" -eq 2 ]]
grep -Fq '"AZURE_OPENAI_ENDPOINT": os.environ["AZURE_OPENAI_ENDPOINT"]' chapters/08-hosted-agent.md
grep -Fq '.selectedHostnames.developerPortal' chapters/23-tool-governance.md
grep -Fq 'managementPortalUri:[$portal]' chapters/23-tool-governance.md
grep -q 'Topology boundary' chapters/14-copilot-studio-vnet.md
grep -q 'privatelink.azure-api.net' chapters/14-copilot-studio-vnet.md

for file in infra/envs/poc/README.md specs/02-apim-ai-gateway/validation/foundation-runtime.md; do
  awk '/^```json/{capture=1;next} /^```/{if(capture){exit}} capture' "$file" |
    jq -e '
      . as $record |
      all(["validationType","status","owner","scope","approvalReference","evidenceSummary","timestampUtc",
           "apimServiceId","endpointMode","endpointAccessPath","validationReference","routingApprovalReference"][];
          $record[.] | type == "string" and length > 0) and
      .validationType == "apim-endpoint-access" and .status == "blocked" and .owner == "network-owner" and
      (.selectedHostnames | keys) == ["developerPortal","gateway","management"]
    ' >/dev/null
done
for file in infra/envs/poc/apim.bicepparam infra/envs/poc/apim.customer.example.bicepparam; do
  for variable in APIM_ENDPOINT_MODE APIM_ENDPOINT_ACCESS_PATH APIM_CUSTOM_ENDPOINT_HOSTNAMES APIM_ENDPOINT_VALIDATION_EVIDENCE; do
    grep -q "$variable" "$file"
    grep -q "$variable" specs/02-apim-ai-gateway/validation/validate.sh
    grep -q "$variable" infra/envs/poc/README.md
  done
done
for file in infra/envs/poc/apim-foundry-integration.bicepparam infra/envs/poc/apim-foundry-integration.customer.example.bicepparam; do
  grep -q APIM_STAGE1_ENDPOINT_ACCESS "$file"
done
echo "PASS: D5 selected client URLs, preserved routes/backend boundaries, and redacted evidence templates"
