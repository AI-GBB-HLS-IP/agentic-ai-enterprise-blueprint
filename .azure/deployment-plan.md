# Deployment Plan: Chapter 02 APIM AI Gateway

**Status**: Not Validated (mandatory live Azure gates BLOCKED — see Validation Proof)
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
posture before provisioning. The deployed private service is `apim-agent-factory-private-poc`, so
the service name and DNS record name are supplied as explicit parameter overrides:

```bash
FOUNDRY_ACCOUNT_ID="$(az cognitiveservices account show \
  -g rg-agent-factory-poc -n foundry-agent-factory-poc --query id -o tsv)" \
  az deployment group create --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
    apimServiceName=apim-agent-factory-private-poc \
    privateDnsRecordName=apim-agent-factory-private-poc \
  --name apim-deployment
```

`publicNetworkAccess` stays `Enabled`. The gateway is already private through internal VNet
injection; this flag only governs the control-plane surface. Azure rejects the lock-down below
with `DisablingPublicNetworkAccessRequiredPrivateEndpoint` until the service has at least one
approved Private Endpoint connection, so it is a **deferred** step, not part of the normal
deployment procedure:

```bash
# BLOCKED until an APIM Private Endpoint is provisioned and approved.
az apim update -g rg-agent-factory-poc -n apim-agent-factory-private-poc \
  --public-network-access false
```

APIM provisioning may take 45 minutes or longer. After provisioning, validate subnet posture,
internal gateway reachability, account-scoped RBAC, private DNS resolution, authenticated and
unauthenticated API requests, token metrics, secret-safe diagnostics, and idempotency.

## Validation Proof

- [ ] All validation checks pass — **blocked**: `us1-gateway.md`, `us2-identity-dns.md`,
  `us3-requests.md`, and `us3-observability.md` still report **BLOCKED (live Azure gate
  unresolved)** per the gate policy in `specs/02-apim-ai-gateway/validation/README.md`.
  - [x] 2026-08-27 approved-model update validation — branch
    `feat/apim-approved-models` at `74ba4e7`; Bicep template and parameter compilation,
    resource-group validation, repository fail-closed checks, and non-destructive what-if passed.
    The preview adds the non-secret `approved-models` named value and updates the existing APIM
    backend/API policy configuration without changing the Foundry deployment or network
    architecture.
  - [x] 2026-08-27 approved-model deployment — PR #29 merged as `c379616`; scoped deployment
    `apim-approved-models-20260827` succeeded. The live non-secret `approved-models` named value
    contains one enabled `gpt-4.1-mini` public-name-to-deployment mapping.
  - [x] 2026-08-27 private-client runtime validation — the APIM hostname resolved to `10.0.1.4`;
    a request without a subscription key returned 401; the approved model returned 200 and
    `gpt-4.1-mini-2025-04-14`; the unapproved model returned 400 with `unsupported_model`; and
    10 of 10 consecutive approved-model requests succeeded.
  - [x] Static RBAC review — APIM system-assigned identity retains only the
    `Cognitive Services OpenAI User` assignment scoped to
    `foundry-agent-factory-poc`; the deployment identity has inherited management-group Owner
    access for the target resource group.
  - [x] Azure Policy review — active subscription assignments are Defender provisioning
    policies and do not deny the scoped APIM configuration update.
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
- Runtime validation passed after deployment. Azure currently requires an approved APIM Private
  Endpoint before `publicNetworkAccess` can be disabled; the internally injected gateway remains
  private while this control-plane access flag is enabled.
- Static RBAC review reconfirmed the account-scoped `Cognitive Services OpenAI User` role
  assignment in `infra/modules/apim/main.bicep`.
- The private convergence deployment succeeded as
  `apim-private-convergence-20260824183738`; APIM, API, backend, DNS, RBAC, and observability
  resources were created.
- Disabling `publicNetworkAccess` was rejected by Azure because this APIM service has no approved
  Private Endpoint. The gateway is still `Premium` and `Internal`; a future lock-down step must
  provision and approve an APIM Private Endpoint first.
- Live diagnostic category inspection for the deployed private service
  `apim-agent-factory-private-poc` (created from `infra/envs/poc/apim.bicep` with the
  `apimServiceName` override documented in Execution) returned
  `GatewayLogs`, `WebSocketConnectionLogs`, `DeveloperPortalAuditLogs`, `GatewayLlmLogs`,
  `GatewayMCPLogs`, and `AllMetrics`; the unsupported `GatewayRequests` category was removed.
- `az bicep build --file infra/envs/poc/apim.bicep --stdout` passed after moving
  `llm-emit-token-metric` to the inbound policy section and setting the product subscription
  limit to 1.

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
