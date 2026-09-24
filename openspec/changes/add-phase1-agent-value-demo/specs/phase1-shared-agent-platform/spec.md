## Purpose

Defines the secure shared platform foundation and approval-gated activation sequence for the
Phase 1 agent value demonstration.

## ADDED Requirements

### Requirement: Shared Phase 1 service foundation
The platform SHALL provide one shared Phase 1 Cosmos DB account, Storage account, Azure AI
Search service, agent Application Insights component, and Log Analytics workspace integration
for the initial value demonstration.

#### Scenario: Deploy foundation before Foundry approval
- **WHEN** Foundry approval is not yet available
- **THEN** the shared service instances can be deployed and validated without creating a Foundry project, project connections, capability host, or Foundry-managed Cosmos DB structures

#### Scenario: Preserve APIM telemetry boundary
- **WHEN** the agent observability resources are deployed
- **THEN** the existing APIM Application Insights component remains dedicated to APIM gateway telemetry and a separate Application Insights component is available for agent and application telemetry

### Requirement: Approval-gated platform activation
The deployment SHALL separate pre-approval platform preparation from operations that require an
approved Foundry project.

#### Scenario: Block Foundry-dependent activation
- **WHEN** the Foundry project endpoint and project managed identity are unavailable
- **THEN** knowledge-base creation, project data connections, project RBAC, capability-host activation, and agent deployment remain blocked without failing the completed shared-resource deployment

#### Scenario: Continue after approval
- **WHEN** the Foundry project and required approvals become available
- **THEN** the deployment can add project connections, project RBAC, capability-host activation, grounding, and agent integrations without replacing the shared service instances

### Requirement: Private and identity-based access
The shared platform SHALL disable public data-plane access where the selected service supports
the required private deployment model and SHALL use Microsoft Entra managed identities for
service-to-service authentication.

#### Scenario: Validate private connectivity
- **WHEN** a shared service is marked ready
- **THEN** its required private endpoint is approved, its private name resolves from an approved network location, and no unintended public data-plane route is enabled

#### Scenario: Reject embedded credentials
- **WHEN** an agent or platform component accesses Cosmos DB, Storage, Azure AI Search, APIM, or telemetry ingestion
- **THEN** it uses an approved managed identity or workload identity and does not require a committed account key, connection secret, or access token

### Requirement: Reusable non-sensitive sample corpus
The pre-approval stage SHALL place a small generic, non-sensitive document corpus in a dedicated
Storage container for later Foundry IQ ingestion.

#### Scenario: Prepare grounding data
- **WHEN** the pre-approval stage completes
- **THEN** the sample documents are readable through the approved identity and private route and have stable identifiers suitable for deterministic grounding tests

### Requirement: Phase 1 sharing is not a permanent global contract
The platform SHALL identify these service instances as shared Phase 1 resources and SHALL NOT
represent the deployment as the final multi-project resource topology.

#### Scenario: Document deferred scale decisions
- **WHEN** the Phase 1 architecture is reviewed
- **THEN** multi-project isolation, dedicated-versus-shared placement, capacity, chargeback, retention, and lifecycle decisions are explicitly recorded as Phase 2 work
