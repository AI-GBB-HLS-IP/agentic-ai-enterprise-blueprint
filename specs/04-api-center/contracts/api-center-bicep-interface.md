# API Center Bicep Module Interface

The implementation should expose a resource-group-scoped API Center module family and an
environment parameter file. This is a design contract, not infrastructure code.

## Required parameters

- `location`, `apiCenterServiceName`
- Existing references: `apimServiceId` (the existing Chapter 02 APIM instance's resource ID, not
  redeclared or modified)
- `developerPortalGroupObjectId` (the designated Entra ID security group's object ID, restricting
  developer portal access)
- `platformEngineeringPrincipalId` / `platformEngineeringRoleDefinitionId` (control-plane role
  assignment target and role)
- `governanceOwnerPrincipalId` / `governanceOwnerRoleDefinitionId` (metadata-editor role
  assignment target and role — must not equal a resource-lifecycle role)
- Governance metadata schema definitions: an enumerated allowed-value list for each of
  `owningTeam`, `dataClassification`, `agentProtocol`, `lifecycleStage`

## Outputs

- API Center instance resource ID and default workspace resource ID
- APIM service link (API source) resource ID and its reported sync status
- Metadata schema resource IDs for all four required properties
- Developer portal resource ID/endpoint and its configured allowed-group object ID
- RBAC role assignment resource IDs for the platform engineering and AI CoE governance owner
  assignments
- A structured validation/readiness result distinguishing existing, deployed, pending, and
  failed resources, and explicitly reporting the catalog's MCP server/skill/A2A agent entry count
  (expected zero for this increment)

## Contract invariants

The module must not create or modify the existing resource group, VNet, the Chapter 02 APIM
instance, or the Chapter 01 Foundry account/project/model deployment; it references the APIM
instance and the Entra ID security group by ID only. It must fail closed when:

- The configured `location` is not supported by `Microsoft.ApiCenter`; API Center location must
  not be inferred from or forced to match the existing APIM runtime location.
- The configured location differs from the existing POC runtime region without an approved
  and merged constitution amendment.
- The API Center instance would be provisioned with a paid plan/tier that duplicates a tier
  already available at no additional cost through the eligible APIM link (FR-002).
- The APIM service link (API source) resource ID does not match the existing Chapter 02 APIM
  instance, or a second service link to the same APIM instance would be created on a re-apply
  (no duplicate service link, no duplicate API Center instance, no duplicate metadata schema
  definitions — FR-012).
- Any of the four required governance metadata properties (`owningTeam`, `dataClassification`,
  `agentProtocol`, `lifecycleStage`) is missing, is not constrained to an enumerated set of
  allowed values, or would accept an out-of-enum value when attached to a catalog entry
  (FR-005/FR-006).
- The developer portal would be reachable by an unauthenticated user, or by an authenticated user
  who is not a member of the configured `developerPortalGroupObjectId` group (FR-007).
- The AI CoE governance owner's role assignment would include resource-lifecycle permissions
  (e.g., delete/create on the API Center instance or the APIM service link), rather than being
  limited to governance metadata schema and catalog-entry annotation management (FR-013).
- Any developer principal would receive a control-plane role assignment on the API Center
  resource, rather than accessing the catalog solely through the developer portal's Entra ID
  group gate (FR-013).
- An MCP server, skill, or A2A agent API entry would be created, registered, or otherwise
  required to exist as part of this module family (FR-009).
- Automated API definition linting/conformance scoring, or VS Code extension/`mcp.json`
  generation configuration, would be provisioned by this module family (FR-010).
