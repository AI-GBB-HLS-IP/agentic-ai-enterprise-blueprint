# Chapter 02 — Build the AI Gateway

## Objective

Chapter 02 deploys the AI gateway in two independently controlled stages:

1. **Stage 1 — APIM foundation** deploys an internal, VNet-injected API Management service,
   system-assigned identity, private DNS, Application Insights, Log Analytics diagnostics, and
   capacity monitoring. It does not discover, validate, or modify Microsoft Foundry.
2. **Stage 2 — Foundry integration** references the existing APIM service and an independently
   approved Foundry account, then adds the account-scoped role assignment, managed-identity
   backend, approved-model mapping, governed API, product, and policies.

Azure API Management does not require Foundry, and the customer Foundry deployment guidance does
not require APIM. A platform team can complete Stage 1 while GenAI approval, Foundry account
enablement, or model availability is pending, then resume at Stage 2 without replacing APIM or
changing foundation-owned networking, DNS, or monitoring.

## Architecture

```text
Stage 1: APIM foundation
Approved VNet/subnet -> Internal APIM + managed identity
                     -> private azure-api.net DNS
                     -> Application Insights and Log Analytics
                     -> AllLogs, AllMetrics, and capacity alert

Stage 2: Foundry integration
Existing APIM identity -> Cognitive Services OpenAI User on one Foundry account
Existing APIM service  -> HTTPS backend using managed identity
                       -> approved-model mapping
                       -> subscription-protected governed API
```

The classic APIM tiers use a customer-approved Standard static public IP for Azure platform
management. That resource does **not** make the gateway public: gateway, portal, management, and
SCM endpoints remain internal and must resolve to the APIM private VIP.

## Stage 1 — APIM Foundation

### Prerequisites

- Azure CLI and Bicep CLI support through `az bicep`.
- Permission to read the existing VNet/subnet and deploy APIM, DNS, and monitoring resources.
- A supported classic APIM tier:
  - **Developer, capacity 1** for smoke testing and acceptance validation;
  - **Premium** for production deployments.
- An approved APIM subnet:
  - name matches `apimsubnet-*`, or a documented tenant-approved naming exception is supplied;
  - approved NSG is attached;
  - approved APIM route table is attached, or a documented active-policy exception is supplied;
  - no subnet delegation is configured;
  - service endpoints include `Microsoft.AzureActiveDirectory`, `Microsoft.KeyVault`,
    `Microsoft.Sql`, and `Microsoft.Storage`.
- A customer-approved Standard, static public IP in the APIM resource group.
- A corporate APIM publisher email.
- A policy decision for diagnostics: blueprint-owned, or policy-owned and validated in place.

The repository's current brownfield example documents a tenant exception: the active landing-zone
policy denies route tables on subnets using the shared hybrid NSG. Operators must provide that
exception evidence instead of silently omitting the route table.

### Configure Foundation Parameters

Edit `infra/envs/poc/apim.bicepparam`. It contains only:

- APIM name, publisher, supported tier and capacity, and approved public IP;
- existing VNet, subnet, NSG, and route-table/exception evidence;
- private DNS configuration;
- public-network access fixed to `Enabled` until a separately validated private endpoint exists;
- Application Insights, Log Analytics, diagnostics ownership, and capacity alert settings.

It contains no Foundry account, model, backend, API, product, or token-policy input.

### Validate and Preview

```bash
specs/02-apim-ai-gateway/validation/validate.sh foundation

az deployment group what-if \
  --resource-group <apim-resource-group> \
  --name apim-foundation-preview \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
  --result-format ResourceIdOnly
```

The preview must contain only APIM, private DNS, and monitoring resources. It must perform no
`Microsoft.CognitiveServices` lookup and require no Foundry permission.

### Deploy and Checkpoint

```bash
az deployment group create \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

Record these outputs for the Stage 2 handoff:

- `apimServiceId`
- `apimServiceName`
- `apimPrincipalId`
- `apimGatewayHostname`
- `privateIpAddresses`
- `foundationReadiness`

A successful Stage 1 checkpoint reports foundation readiness independently and integration
readiness as `not-deployed`. No Foundry-backed API exists yet.

When Azure Policy owns the APIM resource diagnostic setting, validate its destination and enabled
AllLogs/AllMetrics categories first. Then set `APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE` to
the real evidence reference and redeploy Stage 1 so `foundationReadiness` can report `deployed`.

### Private DNS and Optional Enterprise Custom Domains

The default `azure-api.net` private zone and VNet link are sufficient for consumers in the
deployment VNet or explicitly linked networks. Internal APIM endpoints use A records for the
gateway, developer portal, legacy portal, management endpoint, and SCM endpoint.

When consumers must resolve APIM across the broader enterprise network, complete this separate,
conditional extension:

1. Obtain customer-approved internal custom endpoint names.
2. Obtain certificates issued by an approved enterprise CA.
3. Configure the APIM custom domains and certificate lifecycle controls.
4. Request enterprise internal DNS A records that resolve each approved name to the APIM private
   VIP.
5. Validate name resolution and TLS from each required network segment.

Custom domains are not required for the default VNet-local foundation.

## Stage 2 — Foundry Integration

### Prerequisites

- Stage 1 foundation readiness is `deployed`.
- The customer GenAI Review Board case and Foundry account enablement are complete.
- The existing Foundry account is in a customer-approved region and uses private access.
- At least one supplied model mapping is on the customer-approved model list and resolves to an
  existing deployment.
- The operator can read APIM and Foundry and assign `Cognitive Services OpenAI User` at the
  selected Foundry account scope.

### Configure Integration Parameters

Export `APIM_STAGE1_SERVICE_ID` and `APIM_STAGE1_FOUNDATION_READINESS` from the validated Stage 1
deployment outputs. Then use `infra/envs/poc/apim-foundry-integration.bicepparam` to supply the
existing APIM resource group and service name, Foundry account identity, governance evidence,
explicitly approved regions, approved models, backend/API/product names, token limit, and Foundry
API version.

### Validate, Preview, and Deploy

```bash
specs/02-apim-ai-gateway/validation/validate.sh integration

az deployment group what-if \
  --resource-group <apim-resource-group> \
  --name apim-foundry-integration-preview \
  --template-file infra/envs/poc/apim-foundry-integration.bicep \
  --parameters infra/envs/poc/apim-foundry-integration.bicepparam \
  --result-format ResourceIdOnly

az deployment group create \
  --resource-group <apim-resource-group> \
  --name apim-foundry-integration \
  --template-file infra/envs/poc/apim-foundry-integration.bicep \
  --parameters infra/envs/poc/apim-foundry-integration.bicepparam
```

Stage 2 must propose only the Foundry account-scoped role assignment and APIM backend, named
value/model mapping, API, operation, product, and policies. It references APIM as existing and
does not deploy the APIM service, private DNS, Application Insights, Log Analytics, diagnostics,
or capacity alert.

### End-to-End Checkpoint

Run `validate.sh integration` after deployment and verify:

- APIM's existing system identity received only `Cognitive Services OpenAI User` on the selected
  Foundry account;
- the backend uses HTTPS and `authentication-managed-identity` for
  `https://cognitiveservices.azure.com`;
- approved aliases resolve to approved deployments;
- unsupported models fail before backend forwarding;
- missing subscription credentials fail before Foundry;
- successful request telemetry is attributable without recording credentials, prompts, or
  completions.

Use `validate.sh all` only when both stages and all Stage 2 governance evidence are available.

## Rollback

- **Stage 2 rollback** removes only integration-owned role assignment and APIM API/backend/product
  resources. The APIM service, network, DNS, identity, and monitoring remain intact.
- **Stage 1 rollback** follows the APIM foundation recovery procedure. It is independent of
  Foundry resource lifecycle and does not delete or modify the Foundry account.

## Future Gateway Capabilities

MCP exposure, A2A routing, Content Safety, semantic caching, and secondary backends remain later
chapters or future increments. They are not deployed by either Chapter 02 stage.

## References

- [AI Gateway capabilities](https://learn.microsoft.com/azure/api-management/genai-gateway-capabilities)
- [APIM virtual network concepts](https://learn.microsoft.com/azure/api-management/virtual-network-concepts)
- [APIM resource requirements for VNet injection](https://learn.microsoft.com/azure/api-management/virtual-network-injection-resources)
- [Azure Monitor supported metrics for APIM](https://learn.microsoft.com/azure/azure-monitor/reference/supported-metrics/microsoft-apimanagement-service-metrics)

## Next Step

After both stages are ready, proceed to
[Chapter 03 — Build an Agent with Microsoft Agent Framework](./03-agent-framework.md).
