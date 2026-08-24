# Data Model

## Inputs and prerequisites

| Entity | Key fields | Rules |
|---|---|---|
| Network foundation | resource group, VNet, `snet-apim` ID/prefix, `snet-privateendpoints` ID | Existing; resource group is `rg-agent-factory-poc`, VNet is `vnet-agent-factory-poc`, `snet-apim` is `10.0.1.0/24`, unused, NSG-associated, currently undelegated. |
| Foundry deployment | account ID, project ID, model deployment name/version | Existing (Chapter 01); account is `foundry-agent-factory-poc`, model deployment is `gpt-4.1-mini` (`2025-04-14`, Standard, capacity 10). Not modified by this feature. |
| Existing private DNS zones | zone name, resource ID, VNet link | Existing; includes `privatelink.azure-api.net` (unrelated to this feature's new zone) and the Chapter 01 Foundry/Storage/Key Vault zones. Not duplicated or modified. |

## Feature-managed entities

| Entity | Key fields | Rules |
|---|---|---|
| APIM subnet | subnet ID, address range, NSG association | Existing dedicated `snet-apim` subnet; classic Premium does not use the v2 `Microsoft.Web/serverFarms` delegation. |
| APIM instance | name, location, SKU, `virtualNetworkType`, subnet ID, identity | Classic Premium tier, `virtualNetworkType: Internal`, subnet is `snet-apim`; system-assigned managed identity enabled; no public gateway endpoint. |
| Managed identity role assignment | principal ID, role definition ID, scope | `Cognitive Services OpenAI User` scoped only to the `foundry-agent-factory-poc` account; no resource-group or subscription scope. |
| Private DNS zone (`azure-api.net`) | zone name, resource ID, VNet link, A records | New zone, distinct from `privatelink.azure-api.net`; linked to `vnet-agent-factory-poc`; A records created only after the APIM resource publishes its private IP. |
| Foundry backend | name, URL, authentication policy | Points at the Foundry `gpt-4.1-mini` deployment endpoint; uses `authentication-managed-identity` with audience `https://cognitiveservices.azure.com`; no key. |
| Client-facing API | name, path, product, subscription requirement, policies | Single OpenAI-compatible `chat/completions` route; requires a valid subscription key; applies `llm-token-limit` and `llm-emit-token-metric`. |
| Observability stack | Log Analytics workspace, Application Insights component, APIM logger, diagnostic setting | Workspace reused from Chapter 01 if present, else created; logger/diagnostic setting exclude request/response bodies and headers. |
| Validation result | subnet status, APIM status, identity/role status, DNS status, request-test result | Each check is `existing`, `deployed`, `pending`, or `failed`; readiness is false for any failed/pending check, and false if any MCP/A2A component is detected. |

## Relationships and state transitions

`Network foundation + Foundry deployment (existing) -> snet-apim validated -> APIM instance
(VNet-injected) -> managed identity enabled -> Foundry role assignment -> azure-api.net zone +
link -> DNS records (post-IP-publish) -> Foundry backend (managed-identity auth) -> client-facing
API + policies -> observability -> validation ready`

The client-facing API must not be considered ready until the backend authentication, DNS
resolution, and subscription enforcement all pass; token metrics/observability failing does not
block core request routing but must be reported as a partial-readiness condition. The classic
Premium injection subnet must remain dedicated and must not be claimed by another workload.
