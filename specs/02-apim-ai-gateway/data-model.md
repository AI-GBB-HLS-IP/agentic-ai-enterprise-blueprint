# Data Model: Staged APIM AI Gateway

## Foundation Entities

| Entity | Key fields | Ownership and rules |
|---|---|---|
| Network policy profile | subnet name, approved NSG ID, route table ID or exception reference, required service endpoints, no delegation | Existing; validated before APIM provisioning |
| APIM public IP | resource ID, Standard SKU, Static allocation | Existing or separately approved; associated with classic internal APIM for platform management |
| APIM service | name, Premium capacity, publisher, internal VNet mode, subnet ID, public IP ID, TLS settings | Stage 1 owned |
| APIM identity | principal ID, tenant ID | Stage 1 owned system identity; no Stage 1 Foundry role |
| Private DNS | `azure-api.net`, VNet link, endpoint A records | Stage 1 owned |
| Observability | workspace, Application Insights, APIM logger/diagnostic, resource diagnostic setting, capacity alert | Stage 1 owned or explicit policy-owned diagnostic handoff |
| Foundation readiness | network, APIM, identity, DNS, observability, endpoint privacy | Independent of integration |

## Integration Entities

| Entity | Key fields | Ownership and rules |
|---|---|---|
| Governance evidence | GenAI review reference, account-enablement reference, policy source | Required Stage 2 input; no secrets |
| Existing Foundry account | account ID/name/resource group, region, public-network state | Existing; never deployed by Chapter 02 |
| Approved model mapping | public name, deployment name, enabled | Stage 2 input and APIM named value |
| Foundry role assignment | APIM principal, OpenAI User role, Foundry account scope | Stage 2 owned |
| APIM backend | HTTPS Foundry URL, managed-identity policy | Stage 2 owned under existing APIM |
| Governed API | API, operation, product binding, subscription and model policies | Stage 2 owned |
| Integration readiness | governance, identity, role, backend, model, API, request, telemetry | Does not alter foundation readiness |

## State Transitions

```text
foundation:
not-started -> preflight-passed -> previewed -> deployed -> ready
                                  \-> blocked/failed

integration:
not-deployed -> governance-approved -> preflight-passed -> previewed -> deployed -> ready
                                      \-> blocked/failed
```

Valid aggregate examples:

- `foundation=ready`, `integration=not-deployed`
- `foundation=ready`, `integration=blocked`
- `foundation=ready`, `integration=ready`

Integration cannot transition beyond `not-deployed` unless foundation is ready. An integration
failure does not transition foundation out of `ready`.

## Handoff

Stage 1 supplies APIM resource group/name/ID and principal ID. Stage 2 re-resolves the existing
APIM resource and principal rather than trusting a caller-supplied principal ID.
