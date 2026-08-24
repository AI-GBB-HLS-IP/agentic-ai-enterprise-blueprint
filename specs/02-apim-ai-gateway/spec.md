# Feature Specification: APIM AI Gateway (Core Gateway)

**Feature Branch**: `feat/apim-ai-gateway`

**Created**: 2026-08-23

**Status**: Draft

**Input**: User description: "Create specs/02-apim-ai-gateway/spec.md for Chapter 02, APIM AI Gateway. Use the Chapter 01 Foundry deployment as an existing prerequisite and scope a private, VNet-injected APIM gateway that exposes the approved model deployment through a governed, OpenAI-compatible API with managed identity authentication."

**Blueprint reference**: Chapter [02-ai-gateway](../../chapters/02-ai-gateway.md).

**Governing deployment plan**: [`.azure/deployment-plan.md`](../../.azure/deployment-plan.md), tracked by
[Issue #17](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/17).

## Scope and Implementation Status

This feature defines the requirements for the **core** increment of Chapter 02. The Chapter 01
Foundry deployment is an existing prerequisite: resource group `rg-agent-factory-poc`, VNet
`vnet-agent-factory-poc`, the dedicated `snet-apim` subnet (`10.0.1.0/24`, unused, NSG-associated,
currently undelegated), `snet-privateendpoints` (`10.0.4.0/24`), the Foundry account
`foundry-agent-factory-poc`, and its `gpt-4.1-mini` model deployment are assumed to exist and be
usable. Unlike `snet-foundry`, `snet-apim` was intentionally left undelegated by Network
Foundation; this feature uses it for classic Premium VNet injection. Premium v2 remains the
preferred future tier, but is currently capacity-constrained.

**Approved initial boundary (per the governing deployment plan)**: this feature covers only the
private APIM gateway, its managed-identity authentication to Foundry, one governed
OpenAI-compatible client-facing API, and observability. **MCP server publication (Chapter 02
Part 6) and A2A agent routing (Chapter 02 Part 7) are explicitly out of scope** for this
increment and are deferred to later Chapter 02 increments, because no tool or agent backends
currently exist to publish or route to.

The APIM instance, networking configuration, identity and role assignment, private DNS
integration, client-facing API and policies, and observability described below are requirements
for this feature; they are not claimed to be deployed by this specification.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform engineer deploys a private, VNet-injected AI Gateway (Priority: P1)

As an IT Platform Engineer, I need to deploy Azure API Management with VNet injection into the
existing network foundation so that all model traffic has a private, governed entry point instead
of direct access to Foundry.

**Why this priority**: The gateway is the single chokepoint the rest of the platform depends on;
no governed model access, tool publication, or agent routing can exist before it.

**Independent Test**: From the prerequisite resource group, inspect the deployed APIM instance's
SKU, VNet injection mode, and subnet association; confirm it is reachable only from inside the
platform VNet.

**Acceptance Scenarios**:

1. **Given** the network foundation and dedicated `snet-apim` subnet exist, **When** the APIM
   deployment is applied, **Then** a classic Premium instance with internal VNet injection is created
   in `snet-apim` with no public gateway endpoint enabled.
2. **Given** `snet-apim` currently has no delegation, **When** the deployment is applied,
   **Then** it uses the dedicated `snet-apim` subnet without adding a v2-specific delegation,
   and the subnet's existing NSG association is preserved with documented classic Premium rules.

---

### User Story 2 - Platform engineer connects the gateway to Foundry with managed identity (Priority: P1)

As an IT Platform Engineer, I need APIM to authenticate to the existing Foundry model deployment
using its system-assigned managed identity so that no Foundry API key is issued, stored, or at
risk of leaking.

**Why this priority**: Key-based backend authentication is the exact anti-pattern this platform
exists to eliminate; identity-based auth must be proven before any client traffic is allowed
through.

**Independent Test**: Inspect the APIM managed identity, its role assignment scope on the Foundry
account, and the backend policy configuration; confirm no Foundry key is present anywhere in
configuration, source control, or logs.

**Acceptance Scenarios**:

1. **Given** APIM has a system-assigned managed identity, **When** the role assignment is
   inspected, **Then** it holds `Cognitive Services OpenAI User` scoped only to the
   `foundry-agent-factory-poc` account, with no broader subscription- or resource-group-level
   grant.
2. **Given** the backend policy is configured, **When** it is inspected, **Then** it uses
   `authentication-managed-identity` with the `https://cognitiveservices.azure.com` audience and
   contains no API key, connection string, or shared secret.
3. **Given** private DNS integration is required, **When** the APIM internal (VNet-injected) endpoints are
   provisioned, **Then** the APIM gateway hostname resolves to a private VNet IP from inside the platform
   VNet using the `azure-api.net` private DNS zone linked to `vnet-agent-factory-poc`.

---

### User Story 3 - Developer calls the approved model through one governed API (Priority: P2)

As a developer (or platform validator standing in for one), I need a single, subscription-key
protected, OpenAI-compatible API so that I can call the approved `gpt-4.1-mini` deployment without
ever holding a Foundry credential, and so that unauthorized or unauthenticated calls are rejected
before they reach Foundry.

**Why this priority**: This is the first demonstration of platform value — governed model access
— but it depends on the private gateway (Story 1) and identity trust (Story 2) already working.

**Independent Test**: From a private client inside the VNet, send a set of `chat/completions`
requests through APIM with a valid subscription key, and a separate set with no key; confirm the
valid requests succeed and reach the intended model, and the invalid requests are rejected by
APIM before reaching Foundry.

**Acceptance Scenarios**:

1. **Given** a valid APIM subscription key, **When** a non-streaming `chat/completions` request
   is sent to the client-facing API, **Then** it returns a successful response attributable to
   the `gpt-4.1-mini` deployment.
2. **Given** no subscription key or an invalid key, **When** the same request is sent, **Then**
   APIM rejects it and the request never reaches the Foundry backend.
3. **Given** token and rate limit policies are configured, **When** request volume is inspected
   through APIM's emitted token metrics, **Then** consumption is attributable to the calling
   subscription.

### Edge Cases

- `snet-apim` must meet the classic Premium VNet injection requirements before provisioning;
  validation must confirm it is dedicated and has no conflicting resource claim.
- The `azure-api.net` private DNS zone must not duplicate or conflict with the existing
  `privatelink.azure-api.net` zone created in Network Foundation; validation must fail if a naming
  or record conflict is detected.
- APIM's private endpoint IP addresses are not known until after the APIM resource is
  provisioned; DNS records must be created only after the addresses are published, and validation
  must fail if resolution is attempted before that point.
- A request without a subscription key, or with an expired/incorrect key, must be rejected by
  APIM policy and must not be forwarded to Foundry under any circumstance.
- Regional APIM capacity cannot be confirmed through the quota API; a non-destructive preview of
  intended changes is required before deployment as the deployment-acceptance gate.
- A client attempts to call an unapproved model alias or an unsupported backend; the API must
  reject the request rather than silently forwarding it to Foundry.
- MCP server publication or A2A agent routing must not be enabled as a side effect of this
  feature; validation must confirm no MCP or A2A API is present until a later increment
  explicitly adds one.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST deploy an Azure API Management instance on the classic Premium tier
  with internal VNet injection into the existing `snet-apim` subnet (`10.0.1.0/24`) in
  `rg-agent-factory-poc`.
- **FR-001a**: The feature MUST validate that `snet-apim` meets classic Premium VNet injection
  requirements before APIM is provisioned and MUST NOT add an App Service/v2 delegation.
- **FR-002**: The APIM instance MUST NOT expose a public gateway endpoint; all client access
  MUST be reachable only from inside `vnet-agent-factory-poc` or its peered/authorized networks.
- **FR-003**: The feature MUST enable APIM's system-assigned managed identity and MUST assign it
  the `Cognitive Services OpenAI User` role scoped only to the `foundry-agent-factory-poc`
  account — not at subscription or resource-group scope.
- **FR-004**: The feature MUST configure the Foundry backend using `authentication-managed-identity`
  with the `https://cognitiveservices.azure.com` audience, and MUST NOT store, forward, or log a
  Foundry API key anywhere in configuration, policy, or source control.
- **FR-005**: The feature MUST create a private DNS zone named `azure-api.net` (distinct from the
  existing `privatelink.azure-api.net` zone from Network Foundation), link it to
  `vnet-agent-factory-poc`, and create records for the APIM internal endpoints only after APIM
  publishes its private IP address.
- **FR-006**: The feature MUST expose exactly one client-facing, OpenAI-compatible
  `chat/completions` API routed to the approved `gpt-4.1-mini` deployment.
- **FR-007**: The client-facing API MUST require a valid APIM subscription key; requests without
  one, or with an invalid one, MUST be rejected by APIM before reaching the Foundry backend.
- **FR-008**: The feature MUST apply a token rate limit policy and MUST emit token consumption
  metrics attributable to the calling subscription for cost accounting.
- **FR-009**: The feature MUST configure Application Insights and a Log Analytics-backed
  diagnostic setting for APIM, with request and gateway telemetry captured and secrets/request
  bodies excluded from logs.
- **FR-010**: The feature MUST NOT publish an MCP server or import an A2A agent API; these remain
  scoped to later Chapter 02 increments per the governing deployment plan.
- **FR-011**: The feature MUST NOT introduce a public fallback path, a Content Safety resource, a
  secondary model backend, or semantic caching in this increment.
- **FR-012**: Infrastructure changes for this feature MUST be represented as parameterized
  infrastructure-as-code and MUST be validated with a non-destructive preview of intended changes
  before deployment, given regional APIM capacity cannot be confirmed through the quota API.
- **FR-013**: The deployment MUST be idempotent: reapplying the same declared configuration MUST
  NOT produce unexpected resource changes or duplicate DNS zones, role assignments, APIs, or
  policies.
- **FR-014**: The feature MUST NOT modify existing `snet-apim` NSG rules beyond the documented
  classic Premium required network rules, and MUST preserve existing control-plane and load-balancer
  rules.
- **FR-015**: The feature MUST preserve separation of duties: platform engineering owns gateway
  and network configuration; AI CoE governs which model(s) and policies are approved; developers
  consume the gateway through a subscription key without direct infrastructure access.

### Key Entities

- **APIM instance**: The classic Premium, VNet-injected gateway that is the single entry point for all
  model traffic in this increment.
- **Managed identity and role assignment**: APIM's system-assigned identity and its
  narrowly-scoped `Cognitive Services OpenAI User` grant on the Foundry account.
- **Foundry backend**: The private, managed-identity-authenticated route from APIM to the
  `gpt-4.1-mini` deployment.
- **Private DNS zone (`azure-api.net`) and link**: The new zone and VNet link required for
  private resolution of the APIM internal endpoints.
- **Client-facing API and policy**: The single OpenAI-compatible `chat/completions` route,
  subscription enforcement, rate limit, and token metric emission.
- **Observability stack**: Application Insights, Log Analytics workspace, APIM logger, and
  diagnostic setting.
- **Validation result**: Evidence of subnet/network readiness, identity/role correctness, DNS
  resolution, successful and rejected request outcomes, and absence of out-of-scope components
  (MCP, A2A, public fallback).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can deploy the private APIM gateway and connect it to the
  existing Foundry deployment without provisioning or storing a single API key or shared secret.
- **SC-002**: 100% of client-facing requests without a valid APIM subscription key are rejected
  by APIM and never reach the Foundry backend.
- **SC-003**: At least 9 of 10 consecutive valid, non-streaming `chat/completions` requests
  through the private gateway succeed and are attributable to the `gpt-4.1-mini` deployment.
- **SC-004**: 100% of APIM private endpoint DNS names resolve to private VNet addresses, with
  zero public gateway endpoints enabled.
- **SC-005**: Reapplying the declared configuration produces zero unexpected changes and creates
  no duplicate DNS zones, role assignments, backends, APIs, or policies.
- **SC-006**: A validation report confirms no MCP server or A2A agent API exists after this
  feature is deployed, distinguishing this increment's boundary from later Chapter 02 work.

## Assumptions

- The Chapter 01 Foundry specification has been completed and its named resource group, VNet,
  subnets, Foundry account, and `gpt-4.1-mini` model deployment are available in the target
  subscription.
- The POC uses one Azure region (`eastus2`), consistent with the existing Foundry deployment.
- `snet-apim` is currently unused and already NSG-associated, but undelegated; this feature adds
  classic Premium VNet injection requirements, and no other workload is expected to claim this subnet.
- The executing platform identity has sufficient subscription/resource-group permissions to
  deploy APIM, configure private DNS, and assign roles; directory role assignment follows the
  repository's governance process.
- No deployment, validation, or infrastructure generation proceeds until the governing deployment
  plan (`.azure/deployment-plan.md`) is approved, per its own approval gate.
- MCP server publication, A2A agent routing, multi-model backend pools, semantic caching, and
  Content Safety integration are out of scope for this increment and are deferred to later
  Chapter 02 work once tool and agent backends exist to justify them.
