# Quickstart: Staged APIM AI Gateway

## Stage 1 — APIM Foundation

Stage 1 requires Azure networking and APIM approvals only. Foundry may be unavailable.

Use one untracked customer parameter file; no duplicate environment-variable setup is required:

```bash
cp infra/envs/poc/apim.customer.example.bicepparam \
  infra/envs/poc/apim.customer.bicepparam
```

Populate the fallback values or export the corresponding `APIM_*` environment variables, then use
the standard Azure deployment sequence:

```bash
export APIM_FOUNDATION_PARAMETERS_FILE='infra/envs/poc/apim.customer.bicepparam'

az deployment group validate \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group what-if \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group create \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"
```

The template creates the customer-named Standard/static APIM platform public IP, DNS label, and
`ProjectCode=APIM` tag. The customer example defaults `APIM_PRIVATE_DNS_MODE` to `external`
for customer-managed corporate DNS through the hub. Verify the preview contains
only APIM foundation, public IP, monitoring, and alert resources and no Foundry resources or
workload-owned private DNS zone.

After deployment, use the advanced validator only for runtime evidence:

```bash
VALIDATION_PHASE=runtime \
RUN_WHAT_IF=false \
APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

For evidence capture and the unchanged-preview procedure, see
[`validation/stage1-smoke-test.md`](validation/stage1-smoke-test.md).

The expected checkpoint is `foundationReadiness=deployed` and
`integrationReadiness=not-deployed`. The approved classic-tier public IP may exist for platform
management; validate that APIM service endpoints remain internal instead of treating the public
IP resource itself as exposure.

## Optional Enterprise DNS Extension

The default private `azure-api.net` zone supports the deployment VNet and explicitly linked
networks. For broader enterprise resolution, separately obtain approved custom domains and CA
certificates, configure APIM custom hostnames, and request internal DNS A records to the APIM
private VIP.

## Stage 2 — Foundry Integration

Begin only after Stage 1 is ready and customer Foundry governance is complete.

1. Export the validated Stage 1 outputs as `APIM_STAGE1_SERVICE_ID` and the JSON
   `APIM_STAGE1_FOUNDATION_READINESS`, then populate
   `infra/envs/poc/apim-foundry-integration.bicepparam` with the Foundry account, governance
   evidence, explicitly approved regions, approved model mappings, and API policy settings.
2. Run integration preflight:

   ```bash
   specs/02-apim-ai-gateway/validation/validate.sh integration
   ```

3. Preview integration-owned changes:

   ```bash
   az deployment group what-if \
     --resource-group <apim-resource-group> \
     --name apim-foundry-integration-preview \
     --template-file infra/envs/poc/apim-foundry-integration.bicep \
     --parameters infra/envs/poc/apim-foundry-integration.bicepparam \
     --result-format ResourceIdOnly
   ```

4. Confirm the preview adds only the Foundry account-scoped role assignment and APIM
   backend/model/API/product/policies. It must not declare APIM, DNS, workspace, Application
   Insights, diagnostic settings, or alerts.
5. Deploy and validate:

   ```bash
   az deployment group create \
     --resource-group <apim-resource-group> \
     --name apim-foundry-integration \
     --template-file infra/envs/poc/apim-foundry-integration.bicep \
     --parameters infra/envs/poc/apim-foundry-integration.bicepparam

   specs/02-apim-ai-gateway/validation/validate.sh integration
   ```

6. Record `validation/integration-runtime.md` with authorized, unsupported-model,
   unauthenticated, and telemetry results.

Use `validate.sh all` to run both stages in order when every Stage 2 prerequisite is available.
