# Data Model

## Inputs and prerequisites

| Entity | Key fields | Rules |
|---|---|---|
| Network foundation | resource group, VNet, subnet IDs, subnet prefixes, DNS zone IDs | Existing; resource group is `rg-agent-factory-poc`, VNet is `vnet-agent-factory-poc`, Foundry subnet is `10.0.2.0/24` with `Microsoft.App/environments`, PE subnet is `10.0.4.0/24`. |
| Private DNS zone | zone name, resource ID, VNet link | Existing and linked to the VNet; no duplicate zone or link creation. Required zones are Cognitive Services/Foundry, Storage Blob, Key Vault, plus Azure OpenAI and SQL when applicable. |

## Feature-managed entities

| Entity | Key fields | Rules |
|---|---|---|
| Foundry account | name, location, kind, SKU, public network access, network ACLs, network injection | Same region/resource group as foundation; public access disabled; default deny; network injection set before agents. |
| Foundry project | name, account ID, display metadata | Child of account; create before private endpoint if required by provider behavior. |
| Supporting resource | type, name, location, public access, identity/configuration | Storage and Key Vault required; SQL conditional. Same region/resource group; private access only. |
| Private endpoint | name, target resource ID, subnet ID, group ID, connection state, DNS zone group | PE subnet only; connection must be approved; every required PE must have a DNS zone group mapped to an existing zone. |
| Model deployment | deployment name, model name/version/format, SKU/serving option, capacity, quota evidence | Exactly one approved deployment; no fallback; quota and regional availability preflight required. |
| Validation result | resource status, network status, DNS result, quota result, smoke-test result | Each prerequisite and managed resource is `existing`, `deployed`, `pending`, or `failed`; readiness is false for any failed/pending check. |

## Relationships and state transitions

`Network foundation (existing) -> account -> project -> supporting resources -> private endpoints/DNS groups -> model deployment -> validation ready`

Model deployment is permitted only after account/project provisioning, BYO VNet configuration, approved private endpoints, DNS resolution, and quota preflight succeed. BYO VNet changes after agent creation are unsupported and must be rejected by validation.

