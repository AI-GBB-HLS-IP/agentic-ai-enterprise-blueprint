# Feature Specification: Microsoft Foundry with BYO Networking

**Feature Branch**: `spec/01-foundry-byo-networking`

**Created**: 2026-08-14

**Status**: Implemented and deployed; validation partially complete

**Input**: User description: "Create specs/01-foundry-byo-networking/spec.md for Chapter 01, Microsoft Foundry with BYO Networking. Use the network foundation as an existing prerequisite and scope deployment, supporting resources, private connectivity, BYO VNet configuration, model deployment, and validation."

**Blueprint reference**: Chapter [01-foundry-byo-networking](../../chapters/01-foundry-byo-networking.md).

## Scope and Implementation Status

This feature defines the requirements for Chapter 01. The Network Foundation is an existing
prerequisite: resource group `rg-agent-factory-poc`, VNet `vnet-agent-factory-poc`, delegated
subnet `snet-foundry` (`10.0.2.0/24`, delegated to `Microsoft.App/environments`),
`snet-privateendpoints` (`10.0.4.0/24`), and the required private DNS zones are assumed to
exist and be usable.

The Foundry account, project configuration, supporting resources, private endpoints, DNS
integration, BYO VNet association, and approved model deployment are deployed in the POC.
Remaining validation and negative-path tasks continue to be tracked in `tasks.md` and the
`validation/` evidence files.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform engineer provisions a private Foundry foundation (Priority: P1)

As an IT Platform Engineer, I need to deploy Microsoft Foundry and its required supporting
resources into the existing network foundation so that AI workloads have a private, governed
platform to build on.

**Why this priority**: Foundry is the first platform capability that consumes the network and
enables all later agent, knowledge, and evaluation work.

**Independent Test**: From the prerequisite resource group, inspect the deployed resource
inventory and networking settings; confirm Foundry and its required dependencies are present,
private by default, and connected to the designated subnets.

**Acceptance Scenarios**:

1. **Given** the network foundation exists in the target resource group, **When** the Foundry
   deployment is applied, **Then** the Foundry account/project and required supporting resources
   are created in the selected POC region without public network access.
2. **Given** supporting resources are required by Foundry, **When** the deployment is inspected,
   **Then** storage and Key Vault are present, and SQL is included only when required by the
   selected Foundry workload.

---

### User Story 2 - Platform engineer enables BYO VNet and private name resolution (Priority: P1)

As an IT Platform Engineer, I need Foundry to use the existing VNet and private endpoints so
that agent traffic and access to dependent services remain inside the enterprise network
boundary.

**Why this priority**: Private connectivity is the security and compliance outcome of this
chapter; a publicly reachable Foundry deployment is not an acceptable increment.

**Independent Test**: Verify the Foundry networking configuration, private endpoint connection
states, DNS zone links, and name resolution from a private workload in the VNet.

**Acceptance Scenarios**:

1. **Given** Foundry networking is being configured before agents are created, **When** BYO VNet
   is configured, **Then** `vnet-agent-factory-poc`, `snet-foundry`, and
   `snet-privateendpoints` are selected with the required roles and address ranges.
2. **Given** private endpoints exist for Foundry and dependencies, **When** a private workload
   resolves their service names, **Then** each name resolves to a private VNet address and not
   a public address.
3. **Given** a private endpoint connection is pending, rejected, or unhealthy, **When** the
   validation is run, **Then** the deployment is reported as not ready and the issue identifies
   the affected resource.

---

### User Story 3 - AI CoE deploys and validates an approved model (Priority: P2)

As an AI CoE member, I need an approved model deployment and a smoke test so that the team can
prove the Foundry platform is usable without bypassing private networking or governance.

**Why this priority**: A model deployment demonstrates useful platform value, but it depends on
the private Foundry foundation being healthy first.

**Independent Test**: Deploy one approved model within available regional quota and make a
controlled test request through the private Foundry endpoint; confirm the request succeeds and
the result is attributable to the intended model deployment.

**Acceptance Scenarios**:

1. **Given** the selected region has sufficient quota and the Foundry networking checks pass,
   **When** the approved model is deployed, **Then** it is available in the Foundry project
   with the documented model name, version, and capacity.
2. **Given** the model is deployed, **When** a smoke test is sent through the private endpoint,
   **Then** it returns a valid response without requiring public network access.
3. **Given** quota is insufficient or the model is unavailable in the region, **When** model
   deployment is attempted, **Then** deployment stops with an actionable failure and no
   alternate public endpoint is enabled.

### Edge Cases

- The delegated subnet reaches 80% utilization or cannot allocate capacity during an upgrade;
  validation must flag capacity risk and block agent onboarding until resolved.
- The required private DNS zone already exists from Network Foundation; the deployment must
  reuse it rather than create a conflicting duplicate.
- A private endpoint is provisioned but its DNS zone group or VNet link is missing; validation
  must fail rather than treating the endpoint as private.
- A supporting resource is in a different region or resource group from Foundry; validation
  must report the placement mismatch.
- BYO VNet configuration is attempted after agents already exist; the operation must be treated
  as unsupported and require a clean, pre-agent configuration path.
- A model deployment exceeds available quota; the feature must remain undeployed or incomplete
  rather than silently selecting an unapproved model or public route.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST deploy a Microsoft Foundry account and project in the selected
  single POC region within `rg-agent-factory-poc`.
- **FR-002**: The Foundry account MUST have public network access disabled and MUST default to
  denying unsolicited network access.
- **FR-003**: The feature MUST use the existing `vnet-agent-factory-poc` and MUST configure
  `snet-foundry` (`10.0.2.0/24`) as the Foundry delegated subnet for
  `Microsoft.App/environments`.
- **FR-004**: The feature MUST use `snet-privateendpoints` (`10.0.4.0/24`) for private
  endpoints and MUST NOT add public IP addresses for Foundry or its supporting resources.
- **FR-005**: The feature MUST provision Foundry's required supporting resources, including
  private storage and Key Vault; SQL Database MUST be provisioned when required by the selected
  Foundry workload.
- **FR-006**: The feature MUST create private endpoints for Foundry and each required supporting
  resource, and each private endpoint MUST have an approved connection state before validation
  can pass.
- **FR-007**: The feature MUST integrate private endpoints with the existing private DNS zones
  for Cognitive Services/Foundry, Azure OpenAI when used, Storage Blob, Key Vault, and SQL when
  used, with VNet links to `vnet-agent-factory-poc`.
- **FR-008**: The feature MUST configure BYO VNet before any Foundry agents are created, using
  `vnet-agent-factory-poc`, `snet-foundry`, and `snet-privateendpoints`.
- **FR-009**: The feature MUST deploy one approved model only after region and model quota are
  confirmed, and MUST record the model name, version, serving option, and capacity used.
- **FR-010**: The feature MUST provide a repeatable validation that checks resource placement,
  public network settings, subnet delegation and ranges, private endpoint states, DNS links,
  private name resolution, model availability, and a smoke-test response.
- **FR-011**: Infrastructure changes for this feature MUST be represented as parameterized
  infrastructure-as-code and MUST be validated with a preview of intended changes before merge.
- **FR-012**: The deployment MUST be idempotent: reapplying the same declared configuration
  MUST NOT produce unexpected resource changes or duplicate DNS zones, endpoints, or model
  deployments.
- **FR-013**: The feature MUST distinguish prerequisite resources that already exist from
  Chapter 01 resources that remain to be deployed; validation output MUST identify each status.
- **FR-014**: The feature MUST preserve separation of duties: platform engineering owns resource
  and network configuration, while AI CoE approves model selection and developers do not receive
  direct infrastructure administration access.

### Key Entities

- **Foundry account and project**: The AI platform resource and its project-level workspace,
  including network settings and model deployments.
- **Delegated subnet**: `snet-foundry`, the existing `/24` subnet reserved for Foundry-managed
  agent infrastructure.
- **Private endpoint**: A private network interface connecting Foundry or a supporting resource
  to `snet-privateendpoints`.
- **Private DNS zone and link**: Existing service-specific name-resolution zones linked to the
  platform VNet and associated with private endpoint DNS records.
- **Supporting resource**: Storage, Key Vault, and conditionally SQL resources required by the
  Foundry workload.
- **Model deployment**: An approved model name/version and serving capacity available to the
  Foundry project.
- **Validation result**: Evidence of prerequisite status, deployment status, connectivity,
  DNS resolution, quota, and smoke-test outcome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can deploy the Foundry foundation and required private
  connectivity from the existing network foundation in under 30 minutes, excluding provider
  approval or quota-wait time.
- **SC-002**: 100% of Foundry and required supporting service endpoints tested by the validation
  procedure resolve to private VNet addresses, with zero unintended public endpoints enabled.
- **SC-003**: 100% of required private endpoints report an approved connection state and 100% of
  required DNS zones are linked to the platform VNet before the feature is marked ready.
- **SC-004**: One approved model smoke test succeeds through the private Foundry path in at
  least 9 of 10 consecutive attempts when the service is available.
- **SC-005**: Reapplying the declared configuration produces zero unexpected changes and creates
  no duplicate private DNS zones, endpoint connections, or model deployments.
- **SC-006**: A platform engineer can determine from the validation report whether each
  prerequisite and Chapter 01 resource is existing, deployed by this feature, pending, or failed
  without inspecting implementation files.

## Assumptions

- The Network Foundation specification has been completed and its named resource group, VNet,
  subnets, and private DNS zones are available in the target subscription.
- The POC uses one Azure region, assumed to be `eastus2` unless the approved deployment
  parameters specify another region.
- The executing platform identity has sufficient subscription/resource-group permissions to
  deploy resources, configure private endpoints, and perform validation; directory role
  assignment is handled through the repository's governance process.
- Foundry's current supported BYO VNet configuration is available in the selected region and
  is configured before agent creation.
- Storage and Key Vault are always required for this feature; SQL is conditional on the selected
  Foundry workload.
- Model choice, version, serving option, and capacity are approved by the AI CoE and constrained
  by available regional quota before implementation.
- Multi-region deployment, hub-and-spoke migration, agent implementation, APIM gateway
  configuration, and production scale-out are out of scope for Chapter 01.
