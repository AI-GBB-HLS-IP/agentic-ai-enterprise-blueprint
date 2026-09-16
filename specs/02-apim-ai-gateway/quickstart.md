# Quickstart: Staged APIM AI Gateway

## Stage 1 — APIM Foundation

Stage 1 requires Azure networking and APIM approvals only. Foundry may be unavailable.

For the exact customer-subscription environment variables, evidence capture, expected resource
inventory, runtime checks, and unchanged-preview procedure, use
[`validation/stage1-smoke-test.md`](validation/stage1-smoke-test.md).

1. Populate `infra/envs/poc/apim.bicepparam` with approved network, public IP, publisher,
   DNS, diagnostics, and monitoring values.
2. Run offline and live preflight:

   ```bash
   VALIDATION_PHASE=preview \
     specs/02-apim-ai-gateway/validation/validate.sh foundation
   ```

3. Preview only the foundation:

   ```bash
   az deployment group what-if \
     --resource-group <apim-resource-group> \
     --name apim-foundation-preview \
     --template-file infra/envs/poc/apim.bicep \
     --parameters infra/envs/poc/apim.bicepparam \
     --result-format ResourceIdOnly
   ```

4. Verify the preview contains APIM, `azure-api.net` DNS, and monitoring resources only. It must
   contain no Cognitive Services lookup, role assignment, backend, model mapping, product, or
   governed API.
5. Deploy:

   ```bash
   az deployment group create \
     --resource-group <apim-resource-group> \
     --name apim-foundation \
     --template-file infra/envs/poc/apim.bicep \
     --parameters infra/envs/poc/apim.bicepparam
   ```

6. From an authorized internal network, run runtime validation and record
   `validation/foundation-runtime.md`:

   ```bash
   VALIDATION_PHASE=runtime \
   RUN_WHAT_IF=false \
   APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
     specs/02-apim-ai-gateway/validation/validate.sh foundation
   ```

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

1. Populate `infra/envs/poc/apim-foundry-integration.bicepparam` with the existing APIM reference,
   Foundry account, governance evidence, allowed regions, approved model mappings, and API policy
   settings.
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
