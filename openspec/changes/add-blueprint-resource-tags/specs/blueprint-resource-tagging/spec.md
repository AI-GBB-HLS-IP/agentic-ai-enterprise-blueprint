## Purpose

Defines consistent, independently configurable Azure resource tags and declared-ownership
boundaries for taggable resources managed across the enterprise blueprint. "Blueprint-created"
includes previously blueprint-created resources redeployed through create/update paths; it is not
proof of resource ownership in Azure.

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
non-contradictory deployment inputs SHALL remain valid without supplying the new tag inputs. The
declared-ownership input check intentionally rejects previously tolerated contradictory inputs;
omitting tag inputs does not bypass that check. Every archived Stage 1
APIM tag input (`apimServiceTags`, `apimPublicIpTags`, `privateDnsZoneTags`,
`privateDnsVnetLinkTags`, `applicationInsightsTags`, `logAnalyticsWorkspaceTags`, and
`capacityAlertTags`) SHALL remain accepted with its documented resource mapping and default value.

#### Scenario: Existing caller omits new tag inputs
- **WHEN** an otherwise valid, non-contradictory existing parameter file omits all newly introduced
  resource-specific tag inputs
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

### Requirement: Tag inputs respect declared ownership
The blueprint SHALL apply tag inputs only to resources managed through its create/update paths,
including redeployment of previously blueprint-created resources. It SHALL NOT apply those inputs
to resources referenced through existing-resource or BYO paths. It SHALL reject contradictions
determinable from caller-supplied ownership inputs and active create/update targets, comparing full
resource identities rather than bare names.

Operators MUST verify that each create/update target is either absent or already blueprint-owned
in the intended Azure cloud and deployment scope and prevent conflicting concurrent deployments.
If ownership cannot be established, operators MUST stop or use a supported existing-resource/BYO
path instead of adopting an unrelated resource through the create/update path.

Selecting a create/update path does not prove ownership: ARM may update a same-named unrelated
resource, including one created after an operator's check. Automatic discovery of undeclared name
collisions, ownership attestation, and concurrency enforcement are outside this capability. This
change SHALL NOT introduce ownership manifests, evidence-file gates, freshness limits, or new
deployment wrappers as prerequisites; existing unrelated deployment prerequisites remain unchanged.

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

#### Scenario: Previously blueprint-created resource is redeployed
- **WHEN** the operator redeploys a previously blueprint-created resource through its managed
  create/update path
- **THEN** the resource receives the current effective tags with the documented defaults and merge
  precedence, without a new ownership manifest, attestation, or evidence-file requirement

#### Scenario: Caller declares contradictory ownership inputs
- **WHEN** a caller-supplied external resource ID identifies the same full resource identity as an
  active create/update target, such as either existing per-purpose NSG ID matching either active
  NSG target while `sharedHybridNsgId` is empty and `reuseExistingNsgs` is false
- **THEN** evaluated input validation fails deterministically instead of creating/updating and
  tagging that resource

#### Scenario: Same resource name exists in a different scope
- **WHEN** a supplied external resource ID has the same resource name as a create/update target
  but a different subscription or resource group
- **THEN** the ownership-input check does not reject it as an identity collision solely because
  the names match

#### Scenario: Shared NSG reference suppresses creation
- **WHEN** a valid non-empty `sharedHybridNsgId` disables the per-purpose NSG module
- **THEN** the ownership-input check does not reject the deployment for a collision with those
  inactive NSG targets, and no blueprint tag input is applied to the referenced shared NSG

#### Scenario: Create/update guidance documents operator responsibilities
- **WHEN** guidance describes a tagged create/update path for network, DNS, optional Bastion,
  Foundry, or APIM Stage 1, through a script or direct deployment command
- **THEN** it requires operator ownership verification and prevention of conflicting concurrent
  deployments and states that selecting a create branch is not proof of ownership

#### Scenario: Undeclared collision or concurrent creation is outside the guarantee
- **WHEN** guidance describes an unrelated resource already occupying the target identity or being
  created there after the operator checks it
- **THEN** it states that ARM may retag that resource and that this capability does not detect or
  prevent the collision or race, rather than claiming compilation or input checks prove ownership

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
propagation, compiled resource mappings, create/update versus reference behavior, and exclusion of
referenced existing/BYO resources from tag assignments for every supported tag input. The resource
inventory SHALL map every in-scope entry point and resource to its ownership branch, tag contract,
implementation task, and acceptance scenario (or unsupported reason). Offline checks SHALL NOT be
presented as proof against undeclared Azure name collisions or concurrent writers.

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
