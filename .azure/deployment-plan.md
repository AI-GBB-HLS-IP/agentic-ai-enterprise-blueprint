# Deployment Plan: Chapter 02 APIM AI Gateway

**Status**: Validated
**Recipe**: Bicep resource-group deployment
**Target resource group**: `rg-agent-factory-poc`
**Location**: `eastus2`
**Date**: 2026-08-23

## Scope

Deploy the approved Chapter 02 core gateway from `infra/envs/poc/apim.bicep` using
`infra/envs/poc/apim.bicepparam`. This deployment creates the private classic Premium APIM gateway,
managed-identity Foundry authorization, private DNS, one governed chat completions API, token
policies, and observability resources.

The deployment must not modify the existing Foundry account/project/model deployment,
`snet-privateendpoints`, or `privatelink.azure-api.net`, and must not create MCP, A2A, public
fallback, Content Safety, semantic-cache, or secondary-backend resources.

## Preconditions

- Chapter 01 resource group, VNet, subnet, Foundry account, and `gpt-4.1-mini` deployment exist.
- `snet-apim` is unused and has the expected NSG association.
- The resource-group what-if has been reviewed and contains only approved changes.
- Live deployment was explicitly authorized by the user in this session.

## Execution

```bash
./specs/02-apim-ai-gateway/validation/validate.sh
az deployment group create \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
  --name apim-deployment
```

For classic Premium internal VNet injection, validate the service schema and required network
posture before provisioning. If the provider requires public access during activation, set
`APIM_PUBLIC_NETWORK_ACCESS=Enabled` only for initial activation and immediately converge to
`Disabled` after provisioning:

```bash
APIM_PUBLIC_NETWORK_ACCESS=Enabled FOUNDRY_ACCOUNT_ID="$(az cognitiveservices account show \
  -g rg-agent-factory-poc -n foundry-agent-factory-poc --query id -o tsv)" \
  az deployment group create --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam --name apim-deployment
az apim update -g rg-agent-factory-poc -n apim-agent-factory-poc --public-network-access Disabled
```

APIM provisioning may take 45 minutes or longer. After provisioning, validate subnet posture,
internal gateway reachability, account-scoped RBAC, private DNS resolution, authenticated and
unauthenticated API requests, token metrics, secret-safe diagnostics, and idempotency.

## Validation Proof

- [x] All validation checks pass
  - [x] 1. Core validation (CLI, auth, build, validate, what-if) — `FOUNDRY_ACCOUNT_ID=...`
    `specs/02-apim-ai-gateway/validation/validate.sh` passed on 2026-08-24; what-if shows the
    new private Premium APIM stack and ignores the retained capacity probe.
  - [ ] 2. Linting (optional)
  - [ ] 3. Azure Policy Validation
  - [x] Previous core validation (CLI, auth, build, validate, what-if) — `validate-deployment.sh` passed on
    2026-08-23 with authenticated Azure CLI, clean compilation, template validation, and
    non-destructive what-if.
- `./specs/02-apim-ai-gateway/validation/validate.sh` passed with the resolved Foundry account ID.
- Bicep compilation passed for all APIM modules and the POC composition.
- Resource-group what-if showed 15 creates and one `snet-apim` subnet deployment, with existing
  Foundry/network resources ignored; the conditional APIM gateway DNS A record is created after
  private IP publication.
- Static RBAC review confirmed `Cognitive Services OpenAI User` is scoped to the existing Foundry
  account resource only.
- Runtime validation remains to be collected after deployment.
- Static RBAC review reconfirmed the account-scoped `Cognitive Services OpenAI User` role
  assignment in `infra/modules/apim/main.bicep`.

## Deployment attempt

- `apim-deployment` was attempted on 2026-08-23 after explicit user authorization.
- The first attempt was rejected because APIM requires public network access to be enabled during
  initial service activation; the template was updated to support a staged activation and
  immediate lock-down.
- The staged Premium v2 retry was rejected by Azure with
  `ApiServiceCreationDisabledForSubscription`: new `PremiumV2` APIM services in `East US 2` are
  unavailable for this subscription at this time.
- No APIM service was created. The explicitly required `snet-apim` delegation succeeded; dependent
  backend creation failed because the APIM service was unavailable.
- Deployment is blocked pending Azure capacity becoming available or an approved alternate-region
  network/resource-group design. Do not retry repeatedly in `eastus2` until capacity changes.

## Current approved target

The approved non-production architecture is classic APIM `Premium` with internal VNet injection.
Premium v2 remains preferable for the long-term blueprint, but is not the current deployment
target because its East US 2 capacity is unavailable. The classic Premium deployment must be
validated independently; the prior Premium v2 failure is retained as historical evidence.
