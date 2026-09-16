## Purpose

Defines a two-stage Chapter 02 deployment contract so the APIM platform foundation can be
provisioned and validated before an approved Foundry account and model deployment are available.

## ADDED Requirements

### Requirement: APIM foundation is independently deployable
The system SHALL provide an APIM foundation stage that deploys or configures the APIM-specific
networking, internal VNet-injected APIM service, system-assigned managed identity, private DNS or
an explicit external DNS handoff, and monitoring without requiring a Foundry account, Foundry
endpoint, Foundry resource ID, or model deployment.

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
subnet and MUST preserve the existing private-network policy handoff and subnet protections. The
foundation preflight MUST validate the active customer policy profile, including the approved
APIM subnet naming convention (`apimsubnet-*` in the referenced VPCx guidance, or a documented
tenant-approved exception), approved NSG association, approved APIM route-table association or
documented tenant exception, no subnet delegation, and the required
`Microsoft.AzureActiveDirectory`, `Microsoft.KeyVault`, `Microsoft.Sql`, and
`Microsoft.Storage` service endpoints.

#### Scenario: Validate foundation network posture
- **WHEN** the foundation stage is deployed
- **THEN** APIM uses internal VNet injection, its gateway either resolves privately through the
  blueprint DNS configuration or emits the records required by customer DNS, and no public
  gateway path is introduced

#### Scenario: Customer network profile is satisfied
- **WHEN** foundation preflight evaluates the target APIM subnet
- **THEN** the subnet satisfies the customer-approved naming, NSG, route-table or approved
  exception, service-endpoint, and no-delegation controls before APIM provisioning begins

#### Scenario: Reject invalid APIM subnet
- **WHEN** the supplied subnet does not satisfy the selected APIM tier's network requirements
- **THEN** foundation validation fails before APIM provisioning and reports the blocking network
  condition without evaluating Foundry readiness

### Requirement: Classic internal APIM public IP is not a public gateway
When the selected classic APIM tier requires a public IP resource for Azure platform management
traffic, the POC APIM foundation stage SHALL create the approved Standard/static public IP from
customer-supplied naming, DNS-label, and tag inputs and associate it with APIM while keeping every
APIM service endpoint in internal VNet mode.

#### Scenario: Provision classic internal APIM
- **WHEN** the customer-approved classic APIM configuration requires a public IP
- **THEN** the deployment supplies that public IP for APIM platform operation and validation
  still confirms that gateway, portal, management, and SCM endpoints are not publicly reachable

#### Scenario: Validate private gateway posture
- **WHEN** an APIM public IP resource exists for control-plane requirements
- **THEN** validation does not classify the foundation as publicly exposed solely because that
  public IP exists and instead verifies the APIM virtual network mode and endpoint reachability

### Requirement: Foundation identity is created without Foundry authorization
The APIM foundation stage SHALL enable the APIM system-assigned managed identity but MUST NOT
create a Foundry role assignment or require permission to assign roles on a Foundry resource.

#### Scenario: Inspect foundation identity
- **WHEN** the foundation stage completes
- **THEN** APIM exposes a managed identity principal ID for later integration and no
  Foundry-scoped role assignment is present in the foundation deployment

### Requirement: Foundation observability is available before integration
The APIM foundation stage SHALL configure its Application Insights, Log Analytics, logger, and
diagnostic settings independently of any Foundry backend or governed AI API. It MUST emit APIM
AllLogs and AllMetrics to the customer-required diagnostic destination and MUST provide or verify
the customer-required alert when average APIM capacity exceeds 60 percent.

#### Scenario: Validate foundation telemetry
- **WHEN** APIM foundation validation runs before Foundry integration
- **THEN** APIM resource and gateway telemetry can be inspected and the result does not depend on
  model request telemetry

#### Scenario: Validate customer monitoring controls
- **WHEN** the foundation monitoring configuration is inspected
- **THEN** AllLogs and AllMetrics are collected through the enforced diagnostic settings and the
  average-capacity alert threshold is 60 percent

### Requirement: Foundation satisfies customer APIM security policy
The APIM foundation stage MUST use a customer-approved Developer or Premium tier, MUST use an
approved corporate administrator email, MUST require HTTPS to backends, MUST allow only TLS 1.2
or stronger, and MUST disable prohibited legacy protocols and weak ciphers. The blueprint SHALL
continue to select Premium for its production-like private gateway implementation.

#### Scenario: Preview customer-compliant APIM settings
- **WHEN** the foundation template is compiled and evaluated against customer policy
- **THEN** its tier, administrator identity, internal network mode, backend transport, protocol,
  and cipher settings satisfy the VPCx Azure 2.0 APIM controls

### Requirement: Foundry integration is a separate deferred stage
The system SHALL provide a Foundry integration stage that runs against an existing APIM
foundation only after the customer's GenAI Review Board approval and Foundry enablement process
are complete and an approved Foundry account and model deployment are privately available in an
allowed customer region.

#### Scenario: Integration prerequisites are available
- **WHEN** APIM foundation outputs, an approved Foundry account, and at least one approved model
  mapping are supplied
- **THEN** the integration stage creates the Foundry-scoped role assignment, managed-identity
  backend, model mapping, and governed AI API

#### Scenario: Foundry governance gate is incomplete
- **WHEN** the required customer GenAI approval, account enablement, approved region, private
  connectivity, or model allowlisting evidence is missing
- **THEN** the integration stage is blocked with the missing Foundry-specific gate and the APIM
  foundation remains independently deployable

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
identity and MUST NOT introduce Foundry keys, connection strings, or shared secrets. The client
subscription key MUST be consumed by APIM and removed before forwarding the backend request.

#### Scenario: Inspect backend policy
- **WHEN** the integrated backend policy is inspected
- **THEN** it uses managed-identity authentication for the Cognitive Services audience and
  contains no key-based Foundry credential or forwarded client subscription key

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
validation procedure for each stage separately. It SHALL also distinguish the public IP resource
required by classic internal APIM from public reachability of APIM service endpoints.

#### Scenario: Operator follows foundation guidance
- **WHEN** an operator follows the APIM foundation instructions while Foundry approval is pending
- **THEN** every required command, parameter, and validation check can be completed without a
  Foundry dependency

#### Scenario: Operator resumes with integration guidance
- **WHEN** Foundry and an approved model later become available
- **THEN** the operator can apply only the integration stage using the existing APIM foundation
  outputs and complete end-to-end governed model validation

### Requirement: Enterprise DNS extension is explicit
The foundation guidance SHALL identify the default `*.azure-api.net` private-resolution scope and
SHALL document customer-approved custom domains, approved certificates, and internal enterprise
DNS records as a separate conditional step when APIM must be resolvable beyond the deployment
VNet across the enterprise network.

#### Scenario: VNet-local gateway usage
- **WHEN** APIM consumers resolve and access the gateway only from the deployment VNet or
  explicitly linked networks
- **THEN** the private `azure-api.net` configuration is sufficient and no custom domain is
  required

#### Scenario: Enterprise-wide internal gateway usage
- **WHEN** APIM must be resolvable across the broader customer network
- **THEN** the operator is directed to configure approved custom endpoint domains and
  certificates and request internal DNS A records to the APIM private VIP
