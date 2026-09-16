# Feature Specification: Staged APIM AI Gateway

**Status:** Implementation in progress
**Tracking issue:** #71
**Branch:** `feat/split-apim-foundry-deployment`

## Goal

Deploy Chapter 02 through two independently deployable and independently verifiable stages.
Stage 1 provides a usable private APIM foundation without Foundry. Stage 2 adds a governed
Foundry-backed API after the separate customer Foundry governance process is complete.

## Stage 1 — APIM Foundation

### Inputs

- Existing VNet, APIM subnet, approved NSG, and route table or documented tenant exception.
- Evidence for an `apimsubnet-*` name or a documented naming exception.
- Four required service endpoints and no subnet delegation.
- APIM name, Premium capacity, corporate publisher identity, and approved public IP resource ID.
- Private DNS names and VNet link.
- Application Insights, Log Analytics, diagnostics ownership, and capacity-alert settings.
- Public-network policy handoff (`Enabled` during activation unless an approved private endpoint
  permits `Disabled`).

### Owned Resources

- `Microsoft.ApiManagement/service` with system-assigned identity and internal VNet injection.
- `azure-api.net` private DNS zone, VNet link, and internal endpoint A records.
- Application Insights, APIM logger/diagnostic, and optional Log Analytics workspace.
- APIM resource diagnostic settings when blueprint-owned.
- Average APIM capacity alert with a threshold of 60 percent.

The approved Standard static public IP supports classic internal APIM platform management. Its
presence is not evidence that gateway, portal, management, or SCM endpoints are public.

### Foundation Requirements

- Foundation deployment and validation MUST perform no Foundry account, model, role, backend, or
  governed API lookup.
- APIM MUST use Premium, internal VNet mode, a system-assigned identity, HTTPS backends, TLS 1.2
  or stronger, and disabled legacy protocols/ciphers.
- Subnet validation MUST fail before deployment for an unapproved name, missing approved NSG,
  missing route table without exception evidence, any delegation, or missing required service
  endpoint.
- Diagnostics MUST collect `AllLogs` and `AllMetrics` through the customer-required destination.
  When Azure Policy owns diagnostics, validation MUST inspect the policy-created setting and the
  template MUST NOT deploy a conflicting setting.
- Foundation readiness MUST be independent of integration status.

### Foundation Outputs

`apimServiceId`, `apimServiceName`, `apimGatewayHostname`, `apimPrincipalId`,
`privateIpAddresses`, DNS and observability resource IDs, `foundationReadiness`, and
`integrationReadiness: not-deployed`.

## Stage 2 — Foundry Integration

### Inputs

- Existing APIM service name and resource group.
- Existing Foundry account name, resource group, and resource ID.
- GenAI Review Board approval and Foundry account-enablement evidence references.
- Maintained customer policy source for allowed regions and approved models.
- Foundry private-access requirement.
- Approved public-model to deployment mappings.
- Backend, API, product, token-limit, and API-version settings.

### Owned Resources

- `Cognitive Services OpenAI User` assignment scoped only to the selected Foundry account.
- APIM Foundry backend using HTTPS and system-assigned managed identity.
- Approved-model named value.
- Governed chat API, operation, product binding, and policies.

Stage 2 references APIM as existing and MUST NOT deploy or modify the APIM service, VNet
injection, private DNS, Application Insights, Log Analytics, APIM resource diagnostics, or
capacity alert.

### Integration Requirements

- Integration preflight MUST fail if governance evidence is absent, the Foundry account is outside
  the approved region policy, public network access is enabled, no approved model mapping is
  supplied, or a mapped deployment does not exist.
- The APIM principal ID MUST be derived from the existing APIM resource.
- Unsupported model aliases and unauthenticated requests MUST fail before Foundry forwarding.
- No Foundry key, connection string, prompt, completion, or subscription credential may be logged
  or stored by the integration templates.
- Integration failure MUST NOT change foundation readiness.

### Integration Outputs

Role assignment, backend, API, product, approved-model named value and count, model mappings, and
`integrationReadiness`.

## Validation Modes

- `validate.sh foundation` compiles and checks only Stage 1 and performs no Cognitive Services
  lookup.
- `validate.sh integration` verifies the existing APIM identity, Foundry governance and runtime
  prerequisites, then compiles/checks Stage 2.
- `validate.sh all` runs foundation and integration in that order.

Offline structural checks are distinct from Azure what-if and runtime evidence. A missing Azure
session, inaccessible resource, or absent approval reference is `BLOCKED`, never a successful
fallback.

## Acceptance Criteria

1. Foundation compiles, previews, and can deploy with no Foundry parameter or permission.
2. Foundation validation proves customer network, security, private endpoint, DNS, diagnostics,
   and capacity-monitoring controls.
3. Integration compiles and references the existing APIM identity.
4. Integration preview contains only integration-owned resources.
5. Readiness and evidence are reported separately for both stages.
6. Reapplying either stage with unchanged inputs proposes no duplicate or unexpected changes.
7. Stage 2 request and telemetry checks prove allowed requests succeed and rejected requests do
   not reach Foundry, without logging secrets or payloads.

## Rollback

Stage 2 rollback removes only integration-owned role/API/backend/model resources. Stage 1
rollback follows the APIM foundation procedure and does not modify Foundry.
