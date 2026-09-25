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
- **THEN** the shared service instances can be deployed and validated without creating a Foundry account, project, project connections, capability host, or Foundry-managed Cosmos DB structures

#### Scenario: Preserve APIM telemetry boundary
- **WHEN** the agent observability resources are deployed
- **THEN** the existing APIM Application Insights component remains dedicated to APIM gateway telemetry and a separate Application Insights component is available for agent and application telemetry

#### Scenario: Resolve the agent telemetry workspace
- **WHEN** the agent Application Insights component is deployed
- **THEN** it is bound to the supplied approved Log Analytics workspace, and an unavailable or unapproved workspace blocks agent observability rather than triggering creation of a new workspace

### Requirement: Approval-gated platform activation
The deployment SHALL separate pre-approval platform preparation from operations that require an
approved Foundry account and project. Shared-service provisioning, account provisioning, and
project onboarding SHALL have independent deployment boundaries. Project onboarding SHALL
reference the supplied account and shared-service identities without provisioning those resources.

#### Scenario: Provision one account after approval
- **WHEN** the account stage's shared-resource and network prerequisites are ready and account provisioning is approved
- **THEN** the account stage provisions or validates one POC account and its account-level connectivity without creating a project or replacing the shared assets

#### Scenario: Block Foundry-dependent activation
- **WHEN** the Foundry project endpoint and project managed identity are unavailable
- **THEN** knowledge-base creation, project data connections, project RBAC, capability-host activation, and agent deployment remain blocked without failing the completed shared-resource deployment

#### Scenario: Continue after approval
- **WHEN** the Foundry project and required approvals become available
- **THEN** the deployment can add project connections, project RBAC, capability-host activation, grounding, and agent integrations without replacing the shared service instances

#### Scenario: Missing shared-resource handoff
- **WHEN** account activation or project onboarding lacks a required shared resource ID, endpoint reuse decision, or approved network association
- **THEN** that stage reports the missing prerequisite as blocked and does not fall back to creating a new shared resource or duplicate endpoint

### Requirement: Repeatable onboarding on one POC account
The POC SHALL support onboarding projects individually onto one supplied Foundry account.
Adding or redeploying a project SHALL preserve the account, existing projects, shared service
identities, existing private endpoints, and existing project data. A second-project check SHALL
demonstrate this behavior without requiring a second full agent demonstration.

#### Scenario: Onboard a second project
- **WHEN** a second approved project is onboarded using the same account and shared-resource IDs
- **THEN** it receives its own project identity, scoped connections, and persistence permissions without replacing the first project's resources, data, or permissions

#### Scenario: Repeat project onboarding
- **WHEN** onboarding is rerun for the same project
- **THEN** resource identities remain stable and no duplicate account, shared service, endpoint, or project is created

#### Scenario: Retain the legacy deployment interface
- **WHEN** an existing non-contradictory caller uses the combined Foundry deployment entry point
- **THEN** its documented parameters, outputs, and DNS staging remain supported while the new POC path uses the separate lifecycle stages

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
- **THEN** production multi-project isolation, per-business-unit accounts, dedicated-versus-shared placement, capacity, chargeback, retention, and enterprise lifecycle decisions remain Phase 2 work, distinct from the POC's repeatable project onboarding
