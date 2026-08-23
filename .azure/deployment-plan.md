# Azure Deployment Plan: Chapter 02 APIM AI Gateway

> **Status:** Planning

Generated: 2026-08-23

---

## 1. Project Overview

**Goal:** Deploy a private, VNet-injected Azure API Management (APIM) Premium v2 gateway for the
existing Chapter 01 Foundry deployment. The gateway will expose the approved
`gpt-4.1-mini` deployment through a governed OpenAI-compatible API and authenticate to Foundry
using its system-assigned managed identity.

**Path:** Add components to the existing infrastructure-as-code project.

**Tracking:** [Issue #17](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/17)
on branch `feat/apim-ai-gateway`.

**Approved initial boundary:** Core gateway only. MCP server publication and A2A agent routing
remain later Chapter 02 increments because no tool or agent backends currently exist.

---

## 2. Requirements

| Attribute | Value |
|---|---|
| Classification | POC |
| Scale | Small: one gateway, one Foundry backend, one model deployment |
| Budget | Premium v2 POC; user explicitly selected the required private VNet-injected tier |
| Subscription | `6384661b-af38-401c-8609-337e5042460d` (`ME-MngEnvMCAP545510-ivorobeychik-1`) |
| Location | `eastus2` |
| Resource group | Existing `rg-agent-factory-poc` |
| VNet | Existing `vnet-agent-factory-poc` |
| APIM subnet | Existing dedicated `snet-apim` (`10.0.1.0/24`); unused, NSG-associated, and has no delegation |
| Foundry backend | Existing `foundry-agent-factory-poc` / `gpt-4.1-mini` (`2025-04-14`, Standard capacity 10) |

---

## 3. Components Detected

| Component | Type | Technology | Path |
|---|---|---|---|
| Network foundation | Infrastructure | Bicep | `infra/modules/network/` |
| POC composition | Infrastructure | Bicep | `infra/envs/poc/main.bicep` |
| Foundry platform | Infrastructure | Bicep | `infra/envs/poc/foundry.bicep` and `infra/modules/foundry/` |
| Chapter 02 guide | Documentation | Markdown | `chapters/02-ai-gateway.md` |

The live subscription has no APIM instance in `rg-agent-factory-poc`; it has three APIM services
in East US 2 outside this resource group.

---

## 4. Recipe Selection

**Selected:** Bicep

**Rationale:** This repository already deploys the POC resource group through parameterized,
resource-group-scoped Bicep modules. The APIM gateway will consume existing VNet, Foundry, and
DNS resources, so Bicep preserves the established deployment model without adding an `azd`
application wrapper.

---

## 5. Architecture

**Stack:** Private API Management gateway and Azure PaaS observability.

```text
Private POC client / jump box
  -> APIM Premium v2 (internal VNet injection, snet-apim)
  -> APIM system-assigned managed identity
  -> Foundry private endpoint (snet-privateendpoints)
  -> gpt-4.1-mini deployment
```

### Service Mapping

| Component | Azure service | SKU / configuration |
|---|---|---|
| AI Gateway | `Microsoft.ApiManagement/service` | Premium v2, internal VNet injection, system-assigned managed identity |
| Gateway DNS | `Microsoft.Network/privateDnsZones` | New private `azure-api.net` zone, linked to the POC VNet with APIM internal endpoint records |
| Foundry authorization | `Microsoft.Authorization/roleAssignments` | `Cognitive Services OpenAI User`, assigned to the APIM identity at the Foundry account scope |
| Model backend | `Microsoft.ApiManagement/service/backends` | Private Foundry OpenAI-compatible endpoint; no API key |
| Client-facing model API | `Microsoft.ApiManagement/service/apis` and policy | OpenAI-compatible `chat/completions` route, subscription enforcement, rate limit, token limit, managed-identity backend auth, and token metrics |
| Observability | Log Analytics, Application Insights, APIM logger and diagnostic setting | 30-day workspace retention; request and gateway telemetry with secrets and request bodies excluded |

### Security and networking decisions

1. Keep `snet-apim` dedicated to APIM. It is currently empty and its lack of delegation is
   compatible with Premium v2 VNet injection.
2. Update `nsg-apim` only with the documented Premium v2 required network rules, retaining the
   existing control-plane and load-balancer rules. Validation must fail if required inbound,
   outbound, DNS, or Foundry-private-endpoint connectivity is absent.
3. Create `azure-api.net`, not a duplicate or replacement for the existing
   `privatelink.azure-api.net` zone. Link it to `vnet-agent-factory-poc` and create records for
   the APIM internal endpoints after APIM publishes its private IP address.
4. Enable APIM's system-assigned managed identity. Assign the role-definition ID
   `5e0bd9bd-7b93-4f28-af87-19fc36ad61bd` (`Cognitive Services OpenAI User`) only at
   `/subscriptions/6384661b-af38-401c-8609-337e5042460d/resourceGroups/rg-agent-factory-poc/providers/Microsoft.CognitiveServices/accounts/foundry-agent-factory-poc`.
5. APIM policy uses `authentication-managed-identity` with the
   `https://cognitiveservices.azure.com` audience. It will never contain or forward a Foundry API
   key.
6. Require an APIM subscription for the POC model API. Retrieve a test subscription key only at
   test time; do not put it in Bicep parameters, source control, Key Vault, or the validation
   report. A call without it must be rejected before it reaches Foundry.
7. No public endpoints, public fallback, semantic cache, Content Safety resource, MCP tool
   backend, A2A backend, or secondary model backend are in this increment.

---

## 6. Provisioning Limit Checklist

| Resource type | Number to deploy | Current / total after deployment | Limit or capacity evidence | Result |
|---|---:|---:|---|---|
| `Microsoft.ApiManagement/service` | 1 | 3 / 4 in East US 2 | Microsoft.ApiManagement returns no quota records through `az quota`; Microsoft publishes APIM limits per service instance. A Bicep what-if is required before deployment to test regional provisioning acceptance. | Preflight required |
| `Microsoft.Network/privateDnsZones` | 1 | 7 / 8 in target resource group | Network quota API is not needed for the existing POC VNet; the new zone is a single global control-plane resource. Bicep what-if verifies name availability and permissions. | Within planned scope |
| `Microsoft.Network/privateDnsZones/virtualNetworkLinks` | 1 | 7 / 8 in target resource group | One additional link to the existing POC VNet. Bicep what-if verifies no conflicting registration link. | Within planned scope |
| `Microsoft.Authorization/roleAssignments` | 1 | 0 Foundry-scope assignments / 1 | Role definition exists in the selected subscription and is scoped to one existing Foundry account. | Within planned scope |
| APIM backend, API, policy, product, logger, and diagnostic setting | 1 each | 0 / 1 each on the new APIM service | Premium v2 per-instance APIM limits exceed this one-backend, one-API POC configuration. | Within planned scope |
| Log Analytics workspace and Application Insights component | 1 each | 0 / 1 each in target resource group | Standard Azure Monitor resource limits exceed the single POC deployment. | Within planned scope |

**Capacity status:** No quota exhaustion is indicated. Regional APIM capacity cannot be reserved or
proved by the quota API, so the non-destructive what-if is a mandatory deployment gate.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace and live Chapter 01 resources
- [x] Gather POC scope, budget posture, subscription, and region
- [x] Scan the Bicep network and Foundry composition
- [x] Select Bicep as the deployment recipe
- [x] Check APIM network prerequisites, provider registration, role definition, and quota API support
- [x] Plan the private gateway architecture
- [ ] User approved this plan

### Phase 2: Execution

- [ ] Create Chapter 02 specification, implementation plan, and dependency-ordered tasks
- [ ] Add parameterized APIM, DNS, RBAC, API, policy, and observability Bicep modules
- [ ] Build every changed Bicep module
- [ ] Run the resource-group what-if and resolve all unexpected changes
- [ ] Confirm APIM service identity and Foundry role assignment
- [ ] Confirm private DNS records and private name resolution from `vm-fnd-jbox`
- [ ] Execute ten private, non-streaming requests through APIM to `gpt-4.1-mini`
- [ ] Confirm at least nine successful responses and reject an unauthenticated APIM request
- [ ] Update this plan status to `Ready for Validation`

### Phase 3: Validation

- [ ] Invoke `azure-validate`
- [ ] All recipe-specific checks pass
- [ ] Update this plan status to `Validated`
- [ ] Record validation proof below

### Phase 4: Deployment

- [ ] Invoke `azure-deploy`
- [ ] Deployment succeeds
- [ ] Record the private gateway endpoint and test evidence without recording secrets
- [ ] Update this plan status to `Deployed`

---

## 8. Validation Proof

| Check | Command or method | Result | Timestamp |
|---|---|---|---|
| APIM subnet | Azure CLI subnet inspection | Pass: `/24`, unused, NSG-associated, no delegation | 2026-08-23 |
| APIM provider | Azure CLI provider inspection | Pass: registered; East US 2 supported | 2026-08-23 |
| Foundry inference role | Azure CLI role-definition inspection | Pass: `Cognitive Services OpenAI User` exists | 2026-08-23 |
| APIM quota API | `check-quota.sh Microsoft.ApiManagement eastus2` | No quota records returned; what-if remains required | 2026-08-23 |

**Validated by:** Pending `azure-validate` workflow completion.

---

## 9. Files to Generate

| File | Purpose | Status |
|---|---|---|
| `.azure/deployment-plan.md` | Governing deployment plan | Complete; awaiting approval |
| `specs/02-apim-ai-gateway/spec.md` | Chapter 02 scope and acceptance criteria | Pending approval |
| `specs/02-apim-ai-gateway/plan.md` | Implementation design | Pending approval |
| `specs/02-apim-ai-gateway/tasks.md` | Dependency-ordered execution tasks | Pending approval |
| `infra/modules/apim/*.bicep` | APIM, DNS, role, policy, and observability modules | Pending approval |
| `infra/envs/poc/apim.bicep` | POC composition and parameters | Pending approval |

## 10. Next Step

Obtain approval for this plan. No infrastructure generation, validation, or Azure deployment may
begin until approval is recorded.
