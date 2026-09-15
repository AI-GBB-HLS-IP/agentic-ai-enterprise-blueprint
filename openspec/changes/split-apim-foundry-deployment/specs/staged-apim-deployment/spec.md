## Purpose

Defines a two-stage Chapter 02 deployment contract so the APIM platform foundation can be
provisioned and validated before an approved Foundry account and model deployment are available.

## ADDED Requirements

### Requirement: APIM foundation is independently deployable
The system SHALL provide an APIM foundation stage that deploys or configures the APIM-specific
networking, internal VNet-injected APIM service, system-assigned managed identity, private DNS,
and monitoring without requiring a Foundry account, Foundry endpoint, Foundry resource ID, or
model deployment.

#### Scenario: Deploy foundation while Foundry approval is pending
- **WHEN** the network inputs are valid and no Foundry resource is available
- **THEN** the APIM foundation deployment completes without attempting to discover, validate,
  reference, or modify a Foundry resource

#### Scenario: Preview foundation without Foundry parameters
- **WHEN** an operator runs the foundation deployment preview using only foundation parameters
- **THEN** the preview includes APIM foundation resources and contains no Foundry role assignment,
  backend, model mapping, or governed AI API

### Requirement: Foundation networking remains private and stage-scoped
The APIM foundation stage MUST configure APIM for internal VNet injection using the approved APIM
subnet and MUST preserve the existing private-network policy handoff and subnet protections.

#### Scenario: Validate foundation network posture
- **WHEN** the foundation stage is deployed
- **THEN** APIM uses internal VNet injection, its gateway resolves privately through the APIM DNS
  configuration, and no public gateway path is introduced

#### Scenario: Reject invalid APIM subnet
- **WHEN** the supplied subnet does not satisfy the selected APIM tier's network requirements
- **THEN** foundation validation fails before APIM provisioning and reports the blocking network
  condition without evaluating Foundry readiness

### Requirement: Foundation identity is created without Foundry authorization
The APIM foundation stage SHALL enable the APIM system-assigned managed identity but MUST NOT
create a Foundry role assignment or require permission to assign roles on a Foundry resource.

#### Scenario: Inspect foundation identity
- **WHEN** the foundation stage completes
- **THEN** APIM exposes a managed identity principal ID for later integration and no
  Foundry-scoped role assignment is present in the foundation deployment

### Requirement: Foundation observability is available before integration
The APIM foundation stage SHALL configure its Application Insights, Log Analytics, logger, and
diagnostic settings independently of any Foundry backend or governed AI API.

#### Scenario: Validate foundation telemetry
- **WHEN** APIM foundation validation runs before Foundry integration
- **THEN** APIM resource and gateway telemetry can be inspected and the result does not depend on
  model request telemetry

### Requirement: Foundry integration is a separate deferred stage
The system SHALL provide a Foundry integration stage that runs against an existing APIM
foundation only after an approved Foundry account and model deployment are available.

#### Scenario: Integration prerequisites are available
- **WHEN** APIM foundation outputs, an approved Foundry account, and at least one approved model
  mapping are supplied
- **THEN** the integration stage creates the Foundry-scoped role assignment, managed-identity
  backend, model mapping, and governed AI API

#### Scenario: Foundry is not yet available
- **WHEN** the integration stage is invoked without a resolvable approved Foundry account or
  model deployment
- **THEN** the integration stage fails with a Foundry-specific prerequisite error and the
  deployed APIM foundation remains unchanged and usable for foundation validation

### Requirement: Foundry authorization remains least privilege
The Foundry integration stage MUST grant the APIM managed identity only the role required for
model invocation and MUST scope that assignment to the selected Foundry account.

#### Scenario: Validate role assignment scope
- **WHEN** the integration role assignment is inspected
- **THEN** it grants `Cognitive Services OpenAI User` to the APIM principal at the Foundry account
  scope and not at resource-group or subscription scope

### Requirement: Governed AI API is created only by integration
The Foundry backend, approved-model mapping, and client-facing governed AI API SHALL be owned by
the Foundry integration stage and MUST NOT be emitted by the APIM foundation stage.

#### Scenario: Foundation-only API inventory
- **WHEN** an operator lists APIs after deploying only the foundation stage
- **THEN** no Foundry-backed governed AI API or approved-model mapping exists

#### Scenario: Integrated API inventory
- **WHEN** the Foundry integration stage completes
- **THEN** the approved governed AI API is present, resolves allowed public model names to
  approved Foundry deployments, and rejects unsupported model aliases before backend forwarding

### Requirement: Backend authentication uses managed identity
The Foundry integration stage MUST configure APIM-to-Foundry authentication with APIM's managed
identity and MUST NOT introduce Foundry keys, connection strings, or shared secrets.

#### Scenario: Inspect backend policy
- **WHEN** the integrated backend policy is inspected
- **THEN** it uses managed-identity authentication for the Cognitive Services audience and
  contains no key-based Foundry credential

### Requirement: Each stage has an independent readiness result
The deployment and validation interfaces SHALL report foundation readiness separately from
Foundry integration readiness so a pending integration does not cause a successfully deployed
foundation to be reported as failed.

#### Scenario: Foundation ready and integration pending
- **WHEN** all foundation checks pass and Foundry integration has not been requested
- **THEN** foundation readiness is `deployed` or equivalent and integration readiness is
  `not-deployed` or `pending`, without an overall foundation failure

#### Scenario: Integration validation fails
- **WHEN** a Foundry-specific role, backend, model, policy, or request check fails
- **THEN** integration readiness reports the affected failure while foundation readiness remains
  based only on foundation resources and checks

### Requirement: Staged deployment is idempotent and non-disruptive
Both stages SHALL be independently idempotent, and applying the Foundry integration stage after
the foundation stage MUST NOT replace or reconfigure the APIM service, its VNet injection,
private DNS foundation, or monitoring resources.

#### Scenario: Reapply foundation
- **WHEN** the foundation stage is reapplied with unchanged parameters
- **THEN** no duplicate or unexpected APIM, identity, DNS, network, or monitoring changes are
  proposed

#### Scenario: Add integration to existing foundation
- **WHEN** the integration stage is applied to a validated APIM foundation
- **THEN** only the Foundry role assignment, backend, model mapping, governed API, and their
  policies are added or updated

### Requirement: Chapter guidance describes stage-specific prerequisites
Chapter 02 documentation SHALL state that Azure API Management does not require Foundry and that
customer Foundry deployment guidance does not require APIM, then identify the prerequisites and
validation procedure for each stage separately.

#### Scenario: Operator follows foundation guidance
- **WHEN** an operator follows the APIM foundation instructions while Foundry approval is pending
- **THEN** every required command, parameter, and validation check can be completed without a
  Foundry dependency

#### Scenario: Operator resumes with integration guidance
- **WHEN** Foundry and an approved model later become available
- **THEN** the operator can apply only the integration stage using the existing APIM foundation
  outputs and complete end-to-end governed model validation
