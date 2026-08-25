---

description: "Dependency-ordered implementation and validation tasks for Chapter 04"
---

# Tasks: Azure API Center (Catalog Core)

**Input**: Design documents from `specs/04-api-center/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `quickstart.md`, and `contracts/api-center-bicep-interface.md`

**Scope guard**: These tasks implement and validate only the API Center instance, its APIM
service link, the four-property governance metadata schema, the RBAC separation-of-duties
model, and the Entra ID-restricted developer portal. They must not create or modify the existing
resource group, VNet, Chapter 01 Foundry account/project/model deployment, or the Chapter 02 APIM
instance's own configuration, and must not register or depend on any MCP server, skill, or A2A
agent API entry, automated API linting/conformance scoring, or VS Code extension / `mcp.json`
generation.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the API Center module family and evidence paths without changing existing
resources.

- [ ] T001 Create the planned API Center module directory and POC composition paths at
      `infra/modules/api-center/` and `infra/envs/poc/`, preserving the existing network,
      Foundry, and APIM module files
- [ ] T002 [P] Create the API Center validation evidence directory and command runner at
      `specs/04-api-center/validation/README.md` and `specs/04-api-center/validation/validate.sh`
- [ ] T003 [P] Create the parameter contract skeleton for target resource names, existing
      resource IDs, RBAC principal/role inputs, and governance metadata enum definitions in
      `infra/envs/poc/api-center.bicepparam`
- [ ] T004 [P] Record the implementation-time API version research gate (R1 outstanding
      confirmation #1) and its resolution status in
      `specs/04-api-center/validation/api-confirmation.md`

## Phase 2: Foundational (Blocking Prerequisites and Research Gates)

**Purpose**: Confirm provider behavior and existing prerequisites before any API Center resource
is declared.

**CRITICAL**: No user story implementation may proceed until the prerequisite and provider gates
in this phase are resolved or explicitly approved as manual gates.

- [ ] T005 [P] Confirm `Microsoft.ApiCenter` resource provider registration and the exact
      `Microsoft.ApiCenter/services`, `.../workspaces/apiSources`, and `.../metadataSchemas` API
      versions available in the target subscription, recording evidence in
      `specs/04-api-center/validation/api-confirmation.md`
- [ ] T006 [P] Confirm the existing `rg-agent-factory-poc` resource group, `eastus2` region, and
      the Chapter 02 APIM instance's resource ID, tier, and `chat/completions` API are reachable,
      recording evidence in `specs/04-api-center/validation/prerequisites.md`
- [ ] T007 [P] Confirm the designated Entra ID security group's object ID already exists in the
      tenant (R5 outstanding confirmation #5) and record it in
      `specs/04-api-center/validation/prerequisites.md`
- [ ] T008 [P] Confirm whether the API Center instance's effective plan/tier, once linked to the
      classic Premium APIM instance, requires an explicit `sku` property or is applied
      automatically by the platform (R1/outstanding confirmation #2), recording the decision in
      `specs/04-api-center/validation/api-confirmation.md`
- [ ] T009 [P] Confirm the exact built-in RBAC role names/IDs available for API Center
      (control-plane and metadata-editor-equivalent roles) in the target subscription, or the
      need for a repository-defined custom role (R4/outstanding confirmation #3), recording the
      decision in `specs/04-api-center/validation/rbac-confirmation.md`
- [ ] T010 [P] Confirm the current developer-portal provisioning mechanism (native
      `Microsoft.ApiCenter` portal resource vs. companion hosting) and how Entra ID
      group-restricted access is expressed for it (R5/outstanding confirmation #4), recording the
      decision in `specs/04-api-center/validation/portal-confirmation.md`
- [ ] T011 Resolve all provider and prerequisite gates T005-T010, document remediation for
      failures, and block implementation/deployment in
      `specs/04-api-center/validation/README.md` while any mandatory gate remains unresolved
- [ ] T012 Define shared parameter assertions, resource naming, existing-resource references
      (APIM resource ID, Entra ID group object ID), and readiness states (`existing`, `deployed`,
      `pending`, `failed`) in `infra/modules/api-center/main.bicep` according to
      `contracts/api-center-bicep-interface.md`

**Checkpoint**: Provider API versions, plan/tier mechanics, RBAC role catalog, portal mechanism,
Entra ID group existence, and APIM/resource-group prerequisites are evidenced before any API
Center resource is provisioned.

## Phase 3: User Story 1 - Platform Engineer Creates the API Center Catalog Instance (Priority: P1) 🎯 MVP

**Goal**: Provision a standalone Azure API Center instance and default workspace in
`rg-agent-factory-poc`/`eastus2`, using only the plan/tier available at no additional cost through
the eligible classic Premium APIM link, with no redundant paid tier.

**Independent Test**: Inspect the deployed API Center resource's name, resource group, region,
and effective plan/tier; confirm it exists independently of any linked service and is reachable
via the Azure control plane.

### Implementation for User Story 1

- [ ] T013 [P] [US1] Implement the `Microsoft.ApiCenter/services` instance and its default
      workspace, with no explicit paid `sku`/plan override, in
      `infra/modules/api-center/main.bicep`
- [ ] T014 [US1] Add instance resource ID, default workspace resource ID, and effective
      plan/tier outputs in `infra/modules/api-center/main.bicep`
- [ ] T015 [US1] Compose the instance module with location and service-name parameters in
      `infra/envs/poc/api-center.bicep`
- [ ] T016 [US1] Define `location` and `apiCenterServiceName` parameter values in
      `infra/envs/poc/api-center.bicepparam`
- [ ] T017 [US1] Compile `infra/modules/api-center/main.bicep` and run the resource-group
      what-if for the instance-only change from `infra/envs/poc/api-center.bicep`, saving the
      non-destructive preview to `specs/04-api-center/validation/us1-what-if.md`
- [ ] T018 [US1] Validate the deployed instance's name, resource group, region, and effective
      plan/tier against the no-additional-cost tier made available by the eligible classic
      Premium APIM link (no redundant paid tier), recording evidence in
      `specs/04-api-center/validation/us1-instance.md`

**Checkpoint**: US1 is complete only when the instance exists independently of any linked
service and its plan/tier does not duplicate a paid tier already available through the APIM link.

## Phase 4: User Story 2 - Platform Engineer Links API Center to the Existing APIM Gateway (Priority: P1)

**Goal**: Create the APIM service link (API source) so the client-facing `chat/completions` API
auto-syncs into the catalog without manual re-entry, and confirm sync health and freshness.

**Independent Test**: Inspect the API Center service link configuration and the catalog's API
list; confirm the APIM instance is a recognized linked source and that APIM's existing
`chat/completions` API appears in the API Center catalog without having been manually registered.

### Implementation for User Story 2

- [ ] T019 [P] [US2] Implement the `Microsoft.ApiCenter/services/workspaces/apiSources` resource
      referencing the existing Chapter 02 APIM instance's resource ID, with
      `importSpecification` set to always import and no `msiResourceId` override, in
      `infra/modules/api-center/apim-link.bicep`
- [ ] T020 [US2] Add service link resource ID and reported sync status outputs in
      `infra/modules/api-center/apim-link.bicep`
- [ ] T021 [US2] Compose the APIM service-link module in `infra/envs/poc/api-center.bicep` with
      an explicit dependency on the instance and default workspace from US1
- [ ] T022 [US2] Add the `apimServiceId` parameter referencing the existing Chapter 02 APIM
      resource ID (by ID only, not redeclared) in `infra/envs/poc/api-center.bicepparam`
- [ ] T023 [US2] Compile `infra/modules/api-center/apim-link.bicep` and run the resource-group
      what-if for the link-only change, saving the preview to
      `specs/04-api-center/validation/us2-what-if.md`
- [ ] T024 [US2] Validate the service link reports healthy/active sync status, confirm
      `chat/completions` appears in the catalog with no manually created duplicate entry, time
      an APIM API change (or initial sync) and confirm reflection within 15 minutes, and confirm
      the catalog contains zero MCP server, skill, or A2A agent entries, recording evidence in
      `specs/04-api-center/validation/us2-link.md`

**Checkpoint**: US2 is complete only when the link reports healthy sync, the synced entry has no
manual duplicate, freshness is within 15 minutes, and the catalog shows zero out-of-scope
entries.

## Phase 5: User Story 3 - Governance Owner Defines Required Metadata for Catalog Entries (Priority: P2)

**Goal**: Define the four required, enum-constrained governance metadata properties
(`owning-team`, `data-classification`, `agent-protocol`, `lifecycle-stage`) and demonstrate they
attach to the synced `chat/completions` entry without error.

**Independent Test**: Inspect the API Center metadata schema definitions directly; confirm each
required property exists with the correct type/enumeration and is available to be attached to
any API, MCP server, or skill entry, independent of whether any entry currently uses it.

### Implementation for User Story 3

- [ ] T025 [P] [US3] Implement the four `Microsoft.ApiCenter/services/metadataSchemas` resources
      (`owning-team`, `data-classification`, `agent-protocol`, `lifecycle-stage`), each with an
      enum-constrained string schema and an `assignedTo` scope that includes APIs, in
      `infra/modules/api-center/metadata-schema.bicep`
- [ ] T026 [US3] Add metadata schema resource ID outputs for all four required properties in
      `infra/modules/api-center/metadata-schema.bicep`
- [ ] T027 [US3] Compose the metadata-schema module in `infra/envs/poc/api-center.bicep` with a
      dependency on the instance from US1
- [ ] T028 [US3] Define the enumerated allowed-value lists for `owningTeam`,
      `dataClassification`, `agentProtocol`, and `lifecycleStage` in
      `infra/envs/poc/api-center.bicepparam`
- [ ] T029 [US3] Compile `infra/modules/api-center/metadata-schema.bicep` and run the
      resource-group what-if for the schema-only change, saving the preview to
      `specs/04-api-center/validation/us3-what-if.md`
- [ ] T030 [US3] Attach all four governance metadata properties to the synced
      `chat/completions` entry, confirm no schema validation errors, and confirm an out-of-enum
      value is rejected, recording evidence in `specs/04-api-center/validation/us3-metadata.md`

**Checkpoint**: US3 is complete only when all four properties exist with enum constraints,
attach cleanly to the real synced entry, and reject an out-of-enum value.

## Phase 6: User Story 4 - Developer Discovers Catalog Contents Through the Developer Portal (Priority: P2)

**Goal**: Deploy the API Center developer portal with mandatory Entra ID authentication,
restricted to the designated security group, denying unauthenticated and non-member access.

**Independent Test**: As a member of the designated Entra ID developer security group, open the
developer portal and search/browse for the known `chat/completions` API entry; confirm it is
discoverable and its governance metadata is visible, without requiring Azure Resource Manager
access.

### Implementation for User Story 4

- [ ] T031 [P] [US4] Implement the developer portal resource with mandatory Entra ID
      authentication and access restricted to the `developerPortalGroupObjectId` group, denying
      unauthenticated and non-member access, in `infra/modules/api-center/portal.bicep`
- [ ] T032 [US4] Add portal resource ID/endpoint and configured allowed-group object ID outputs
      in `infra/modules/api-center/portal.bicep`
- [ ] T033 [US4] Compose the portal module in `infra/envs/poc/api-center.bicep` with a
      dependency on the instance from US1
- [ ] T034 [US4] Add the `developerPortalGroupObjectId` parameter referencing the designated
      Entra ID security group's object ID in `infra/envs/poc/api-center.bicepparam`
- [ ] T035 [US4] Compile `infra/modules/api-center/portal.bicep` and run the resource-group
      what-if for the portal-only change, saving the preview to
      `specs/04-api-center/validation/us4-what-if.md`
- [ ] T036 [US4] Execute developer portal access tests as a group member (success, sees entry +
      metadata), an authenticated non-member (denied), and an unauthenticated user (denied), and
      confirm an MCP/skill/agent search shows an accurate empty result, recording evidence in
      `specs/04-api-center/validation/us4-portal.md`

**Checkpoint**: US4 is complete only when a group member can discover the entry and its metadata
in under one minute, both denied-access cases are enforced, and MCP/skill/agent search returns an
accurate empty result.

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Apply the RBAC separation-of-duties model across all resources, prove idempotency,
fail-closed behavior, and the complete quickstart workflow.

- [ ] T037 [P] Implement the platform engineering control-plane role assignment and the AI CoE
      governance owner's metadata-editor-scoped role assignment (no resource-lifecycle
      permissions), with no role assignment for any developer principal, in
      `infra/modules/api-center/rbac.bicep`
- [ ] T038 Compose the RBAC module in `infra/envs/poc/api-center.bicep` with an explicit
      dependency on the instance from US1
- [ ] T039 [P] Add `platformEngineeringPrincipalId`, `platformEngineeringRoleDefinitionId`,
      `governanceOwnerPrincipalId`, and `governanceOwnerRoleDefinitionId` parameters in
      `infra/envs/poc/api-center.bicepparam`
- [ ] T040 [P] Add role assignment resource ID outputs for both the platform engineering and AI
      CoE governance owner assignments in `infra/modules/api-center/rbac.bicep`
- [ ] T041 Validate that platform engineering holds a control-plane role, the AI CoE governance
      owner holds a distinct metadata-editor-scoped role with no resource-lifecycle permissions,
      and no developer principal holds any role, each scoped only to the API Center resource,
      recording evidence in `specs/04-api-center/validation/rbac.md`
- [ ] T042 [P] Add structured readiness aggregation for instance, link, metadata schema, RBAC,
      and portal states (`existing`, `deployed`, `pending`, `failed`), plus an explicit
      MCP/skill/A2A agent entry count output (expected zero), in
      `infra/modules/api-center/main.bicep`
- [ ] T043 [P] Extend `specs/04-api-center/validation/validate.sh` with fail-closed checks for a
      redundant paid plan/tier, a stale/partial service link, a metadata property missing its
      enumeration constraint or accepting an out-of-enum value, a portal reachable by an
      unauthenticated or non-member user, a governance-owner role with resource-lifecycle rights,
      a developer control-plane role assignment, and any MCP/skill/A2A agent entry
- [ ] T044 [P] Update `specs/04-api-center/quickstart.md` with implemented module paths,
      validation runner usage, evidence filenames, and the required deployment-approval gate
- [ ] T045 [P] Document module inputs/outputs, RBAC/ownership boundaries, and the explicit
      out-of-scope MCP/skill/A2A agent invariant in
      `specs/04-api-center/validation/README.md`
- [ ] T046 Compile every changed API Center module and run the full composed resource-group
      what-if from `infra/envs/poc/api-center.bicep` using
      `infra/envs/poc/api-center.bicepparam`, confirming only declared Chapter 04 resources
      change and saving the preview to `specs/04-api-center/validation/final-what-if.md`
- [ ] T047 Confirm the catalog contains zero MCP servers, zero skills, and zero A2A agent APIs
      after this deployment, recording the scope-boundary check in
      `specs/04-api-center/validation/scope-boundary.md`
- [ ] T048 Re-run the unchanged-parameter what-if a second time and compare it with the first
      preview to verify idempotency and the absence of a duplicate instance, service link, or
      metadata schema definitions, recording the comparison in
      `specs/04-api-center/validation/idempotency.md`
- [ ] T049 Run `az bicep build` for every changed API Center module, execute the full validation
      runner, and record final readiness, pending provider operations, and remediation hints in
      `specs/04-api-center/validation/final-report.md`

## Dependencies & Execution Order

### Phase Dependencies

- Phase 1 has no dependencies and establishes only paths and parameters.
- Phase 2 depends on Phase 1 and blocks all resource implementation until provider and
  prerequisite gates are resolved.
- Phase 3 (US1) depends on Phase 2 and is the MVP standalone-instance increment.
- Phase 4 (US2) depends on the API Center instance and default workspace from Phase 3.
- Phase 5 (US3) depends on the API Center instance from Phase 3; it can be developed in parallel
  with Phase 4 because the metadata schema module attaches to the instance, not the service link,
  though attaching metadata to the real synced entry (T030) requires Phase 4's sync to be
  healthy.
- Phase 6 (US4) depends on the API Center instance from Phase 3; it can be developed in parallel
  with Phases 4-5 because the portal module is independent of the link and schema modules.
- Phase 7 depends on the desired implementation and validation increments and must not expand the
  approved core-catalog boundary (no MCP server, skill, or A2A agent registration).

### User Story Dependencies

- **User Story 1 (P1)**: Starts after Phase 2; no dependency on the link, metadata schema, or
  portal. Independently testable and valuable on its own (the instance exists and is inspectable
  via the control plane).
- **User Story 2 (P1)**: Requires the API Center instance and default workspace from US1; the
  link module file can be developed in parallel with US3/US4 module files once US1's outputs are
  available.
- **User Story 3 (P2)**: Requires the API Center instance from US1; its module file can be
  developed in parallel with US2/US4, but full validation (attaching metadata to the real synced
  entry) requires US2's sync to be healthy first.
- **User Story 4 (P2)**: Requires the API Center instance from US1; its module file can be
  developed in parallel with US2/US3.

### Parallel Opportunities

- T002-T004 and T005-T010 can run in parallel because they touch separate paths or perform
  independent read-only checks.
- After T012, T013 can proceed alone (US1 has no sibling module files); T019, T025, and T031 can
  proceed in parallel once US1's instance/workspace outputs exist, because each owns a separate
  API Center module file (`apim-link.bicep`, `metadata-schema.bicep`, `portal.bicep`).
- T037 can proceed in parallel with T019/T025/T031 once the instance exists, because
  `rbac.bicep` is also a separate file with only the instance as its dependency.
- T039-T040 and T042-T045 can each run in parallel within their respective groups.

## Parallel Example: Post-Foundational Module Development

```bash
# Once T012 (shared contract) and US1's instance/workspace outputs exist, launch independent
# module implementation together:
Task: "Implement the APIM service-link (apiSources) resource in infra/modules/api-center/apim-link.bicep"
Task: "Implement the four governance metadata schema resources in infra/modules/api-center/metadata-schema.bicep"
Task: "Implement the developer portal resource with Entra ID group restriction in infra/modules/api-center/portal.bicep"
Task: "Implement the platform engineering and AI CoE governance owner role assignments in infra/modules/api-center/rbac.bicep"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1 and resolve every Phase 2 prerequisite/provider gate.
2. Implement and preview US1 only (the standalone API Center instance and default workspace).
3. Validate the instance's name, resource group, region, and effective plan/tier show no
   redundant paid tier.
4. Stop if the preview or inspection fails; do not call the catalog an MVP until US1 passes,
   since instance existence is a prerequisite for every other story in this chapter.

### Incremental Delivery

1. Add US2's APIM service link and validate healthy sync, freshness within 15 minutes, and no
   manual duplicate entry — this is what makes the catalog trustworthy rather than merely
   present.
2. Add US3's governance metadata schema and validate clean attachment to the real synced entry
   plus rejection of an out-of-enum value.
3. Add US4's developer portal and validate group-restricted access plus an accurate empty
   MCP/skill/agent search result.
4. Apply the RBAC separation-of-duties model (Phase 7), then finish idempotency, fail-closed
   checks, and final evidence.
5. Report API Center provisioning delays, provider approval requirements, or unresolved RBAC/
   portal state as incomplete rather than claiming deployment success.

## Notes

- Every task uses the required `- [ ] T###` checklist format; `[P]` is used only for independent
  work on separate files, and story tasks carry `[US1]`, `[US2]`, `[US3]`, or `[US4]`.
- Every implementation or evidence task names an exact repository path.
- Live Azure commands must save their output to the named validation evidence file; compiling
  Bicep or producing a what-if does not itself prove deployment.
- The existing resource group, VNet, Foundry account/project/model deployment, and Chapter 02
  APIM instance are immutable prerequisites; this feature only references them by resource ID.
- No task in this file may register, or make deployment success depend on, an MCP server, skill,
  or A2A agent API entry, automated API linting/conformance scoring, or VS Code extension /
  `mcp.json` generation — those remain out of scope until a later increment.
