## Purpose

Defines how APIM foundation deployments accept and apply independent Azure resource tags to each taggable resource that the blueprint creates.

## ADDED Requirements

### Requirement: Independent tag inputs
The APIM foundation deployment SHALL expose a separate tag object for the dedicated public IP, APIM service, created Log Analytics workspace, Application Insights component, capacity alert, blueprint-owned private DNS zone, and blueprint-owned private DNS virtual network link.

#### Scenario: Distinct tags are supplied
- **WHEN** a caller supplies different tag objects for two or more supported resources
- **THEN** each created resource contains only its own supplied tag object plus any resource-specific mandatory tags

#### Scenario: One tag object is changed
- **WHEN** a caller changes the tag object for one supported resource and leaves the other tag inputs unchanged
- **THEN** the deployment updates that resource's tags without replacing the tag objects assigned to the other resources

### Requirement: Backward-compatible defaults
Every newly introduced tag input SHALL default to an empty object so existing APIM foundation callers remain deployable without supplying new parameters.

#### Scenario: Existing caller omits new tag inputs
- **WHEN** an existing parameter file supplies the previously supported APIM inputs but omits all newly introduced tag objects
- **THEN** template validation and deployment proceed without a missing-parameter error

### Requirement: Public IP mandatory tag preservation
The APIM public IP SHALL continue to merge caller-supplied public IP tags with the mandatory `ProjectCode: APIM` tag, and the mandatory value SHALL win if the caller supplies a conflicting `ProjectCode`.

#### Scenario: Caller supplies additional public IP tags
- **WHEN** the public IP tag object contains tags other than `ProjectCode`
- **THEN** the public IP contains those tags and `ProjectCode` is set to `APIM`

#### Scenario: Caller conflicts with mandatory project code
- **WHEN** the public IP tag object supplies a `ProjectCode` value other than `APIM`
- **THEN** the deployed public IP uses `ProjectCode: APIM`

### Requirement: Conditional resource tag behavior
The deployment SHALL apply tag inputs only to resources created by the APIM foundation and SHALL NOT attempt to mutate externally owned resources.

#### Scenario: Existing Log Analytics workspace is supplied
- **WHEN** the caller provides an existing Log Analytics workspace resource ID
- **THEN** the deployment does not apply the Log Analytics workspace tag input to that existing workspace

#### Scenario: Blueprint-owned private DNS is disabled
- **WHEN** private DNS deployment mode is external
- **THEN** the deployment does not create or tag a private DNS zone or private DNS virtual network link

#### Scenario: Blueprint creates conditional resources
- **WHEN** the foundation creates a Log Analytics workspace, private DNS zone, or private DNS virtual network link
- **THEN** the created resource receives its corresponding tag object

### Requirement: Supported tag surface is explicit
The APIM deployment contract SHALL identify which created resources accept independent Azure resource tags and SHALL identify created child or extension resources that do not expose a supported independent tag input.

#### Scenario: Operator reviews the deployment interface
- **WHEN** an operator reads the APIM parameter contract or deployment guidance
- **THEN** the contract explicitly lists the supported tag parameters and the created resources without independent Azure resource tags: APIM logger and diagnostic children, Azure Monitor diagnostic settings, and private DNS A records.

### Requirement: Caller tag values remain opaque and confidential
The deployment SHALL preserve caller-supplied Azure tag keys and values without blueprint-specific normalization, and committed specifications, documentation, tests, and examples SHALL use generic sanitized tag data rather than live customer values.

#### Scenario: Caller supplies an Azure-valid custom tag
- **WHEN** a tag object contains a caller-approved key or value with Azure-supported punctuation
- **THEN** the deployment passes that key and value unchanged to the corresponding resource

#### Scenario: Documentation shows tag configuration
- **WHEN** documentation, parameter examples, or automated tests demonstrate per-resource tagging
- **THEN** the example uses generic non-customer tag keys and values

### Requirement: Tag contract validation
Automated validation SHALL verify that each supported tag input is exposed through the customer parameter interface, propagated to the correct module, and emitted on the corresponding taggable resource in compiled deployment output.

#### Scenario: Tag input is missing or miswired
- **WHEN** a supported tag parameter is removed, passed to the wrong module, or omitted from its target resource
- **THEN** the APIM validation or regression suite fails with a resource-specific tagging assertion
