## Purpose

Defines consistent, independently configurable Azure resource tags and ownership boundaries for
taggable resources created across the enterprise blueprint.

## ADDED Requirements

### Requirement: Blueprint-owned taggable resources have explicit tag inputs
The blueprint SHALL expose an explicit tag input for every taggable resource that it creates,
including taggable network, private DNS, optional Bastion, Foundry, supporting-service, private
endpoint, and APIM foundation resources.

#### Scenario: Different resources require different governance metadata
- **WHEN** a caller supplies different tag objects for two or more blueprint-owned resources
- **THEN** each created resource receives its independently selected tag object rather than an
  implicitly shared tag set

#### Scenario: Repeated resource families are configured independently
- **WHEN** the blueprint creates multiple taggable resources in a repeated family such as private
  DNS zones, virtual network links, or private endpoints
- **THEN** the caller can assign a distinct tag object to each logical resource in that family

#### Scenario: Caller supplies an unknown repeated-family key
- **WHEN** a caller supplies a key outside the documented accepted key set for a repeated-family
  tag map
- **THEN** deployment validation fails with an error that identifies the affected parameter and
  rejected key rather than silently dropping its tags

### Requirement: New tag inputs are backward compatible
Every newly introduced resource-specific tag input SHALL default to an empty object, and existing
deployment inputs SHALL remain valid without supplying the new tag inputs. Every archived Stage 1
APIM tag input (`apimServiceTags`, `apimPublicIpTags`, `privateDnsZoneTags`,
`privateDnsVnetLinkTags`, `applicationInsightsTags`, `logAnalyticsWorkspaceTags`, and
`capacityAlertTags`) SHALL remain accepted with its documented resource mapping and default value.

#### Scenario: Existing caller omits new tag inputs
- **WHEN** an existing parameter file omits all newly introduced resource-specific tag inputs
- **THEN** template validation and deployment proceed without a missing-parameter error

#### Scenario: Existing Foundry caller uses the shared tag input
- **WHEN** an existing Foundry deployment supplies only the previously supported shared tag object
- **THEN** blueprint-created Foundry resources retain those tags unless a resource-specific tag
  input explicitly overrides a key

#### Scenario: Archived APIM tag inputs remain available
- **WHEN** a deployment supplies any archived Stage 1 APIM tag input
- **THEN** the named input is still accepted and is still applied to its originally documented
  resource with its originally documented default

### Requirement: Resource-specific tags have deterministic precedence
When a legacy shared tag object and a resource-specific tag object both apply to a
blueprint-created resource, the blueprint SHALL merge them deterministically with the
resource-specific value winning on duplicate keys. Existing documented mandatory
blueprint-controlled tags SHALL retain their documented highest precedence.

#### Scenario: Resource-specific tag overrides a shared Foundry tag
- **WHEN** the shared Foundry tag object and a Foundry resource-specific tag object contain the same
  key with different values
- **THEN** the created resource uses the resource-specific value

#### Scenario: Caller conflicts with a mandatory blueprint tag
- **WHEN** a caller-provided tag object conflicts with a documented mandatory tag such as the APIM
  public IP `ProjectCode`
- **THEN** the deployed resource uses the documented blueprint-controlled value

### Requirement: External resources are never retagged
The blueprint SHALL apply tag inputs only to resources it creates and SHALL NOT issue tag updates
against existing, customer-owned, policy-owned, or externally supplied resources. For a
conditional create-or-reference path with a deterministic blueprint-owned name, this protection is
a partial mitigation: it prevents retagging when the caller declares existing ownership through the
documented existing-ID/reuse parameters, but it does not perform a runtime existence lookup for an
undeclared same-named resource the caller never flagged.

#### Scenario: Brownfield network resources are supplied
- **WHEN** a deployment references an existing VNet, route table, shared NSG, or reusable
  customer-owned NSG
- **THEN** the deployment does not apply blueprint tag inputs to those referenced resources

#### Scenario: Existing Foundry dependency is supplied
- **WHEN** a deployment references an existing Storage account, AI Search service, Cosmos DB
  account, private endpoint, or other supported external dependency
- **THEN** the deployment does not apply the corresponding blueprint tag input to that existing
  resource

#### Scenario: External DNS zone, record, or zone-group ownership mode is selected
- **WHEN** a private DNS zone, record, or private endpoint DNS zone group is managed outside the
  blueprint, such as brownfield `zone-group` mode
- **THEN** the deployment does not create a tag update for that external zone, record, or zone
  group

#### Scenario: Brownfield creates a virtual network link to an externally owned zone
- **WHEN** brownfield `vnet-link` mode creates a virtual network link from the caller-supplied VNet
  to an existing, externally owned private DNS zone
- **THEN** the created link receives its resource-specific link tag input, while the externally
  owned zone it links to receives no tag update

#### Scenario: Deterministic name collides with an undeclared external resource
- **WHEN** a create-or-reference path would create a resource whose deterministic blueprint-owned
  name already exists in Azure and the caller did not declare that name as externally owned via the
  documented existing-ID/reuse parameters
- **THEN** this requirement's protection does not apply to that undeclared collision, and admin-
  approved, out-of-band name coordination remains required until a runtime existence check is
  added by separately tracked network-foundation preflight validation

### Requirement: Caller tag values remain opaque and confidential
The blueprint SHALL preserve Azure-valid caller-provided tag keys and values without
blueprint-specific normalization, and committed specifications, documentation, tests, parameters,
and validation artifacts SHALL use sanitized generic tag data.

#### Scenario: Caller supplies custom Azure-valid tags
- **WHEN** a resource-specific tag object contains caller-approved keys or values with
  Azure-supported punctuation
- **THEN** the deployment passes those keys and values unchanged to the target resource

#### Scenario: Repository examples demonstrate tagging
- **WHEN** a committed example, test fixture, or validation artifact contains tag configuration
- **THEN** it uses generic non-customer identifiers and values

### Requirement: Unsupported tag surfaces are explicit
The deployment contract SHALL identify blueprint-created resources that do not support independent
Azure resource tags and SHALL NOT introduce synthetic tag parameters for those resources.

#### Scenario: Operator reviews the resource inventory
- **WHEN** an operator reviews the tagging contract
- **THEN** it distinguishes taggable resources from unsupported child or extension resources,
  including role assignments, subnets, private DNS records and zone groups, diagnostic settings,
  and applicable APIM or Foundry child resources

#### Scenario: APIM Foundry integration resources are reviewed
- **WHEN** the Stage 2 APIM-to-Foundry integration tag surface is evaluated
- **THEN** role assignments, APIM backends, named values, APIs, operations, products, bindings, and
  policies are documented as unsupported for independent Azure resource tags unless the selected
  resource API explicitly supports them

### Requirement: Tag propagation and ownership boundaries are validated
Automated validation SHALL verify parameter exposure, default values, merge precedence, module
propagation, compiled resource mappings, conditional creation behavior, and protection of external
resources for every supported tag input.

#### Scenario: Tag input is missing or miswired
- **WHEN** a supported resource-specific tag input is removed, mapped to the wrong resource, or
  omitted from compiled deployment output
- **THEN** an offline validation or regression test fails with a resource-specific assertion

#### Scenario: External resource would be retagged
- **WHEN** a compiled deployment path attempts to apply tags to a referenced external resource
- **THEN** an ownership-boundary regression test fails

#### Scenario: Foundry live approval is unavailable
- **WHEN** Foundry approval or an authorized customer environment is unavailable
- **THEN** offline compilation and regression checks remain mandatory while approval-dependent live
  validation is recorded as `BLOCKED` rather than passed or failed
