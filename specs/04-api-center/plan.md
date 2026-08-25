# Implementation Plan: Azure API Center (Catalog Core)

**Branch**: `spec/04-api-center` | **Date**: 2026-08-25 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/04-api-center/spec.md`

## Summary

Implement a resource-group-scoped Bicep module family that deploys an Azure API Center instance
into the existing `rg-agent-factory-poc` resource group, links it to the existing Chapter 02 APIM
instance so its client-facing `chat/completions` API auto-syncs into the catalog, defines a
governance metadata schema (owning team, data classification, agent protocol, lifecycle stage)
attachable to any catalog entry, and stands up an Entra ID-secured developer portal restricted to
a designated security group. No MCP server, skill, or A2A agent entry is registered by this
increment — the catalog must demonstrably contain zero such entries, consistent with the spec's
explicit deferral of blueprint Parts 3–5, 7, and 8 to a later increment.

## Technical Context

**Language/Version**: Bicep (repository-supported CLI/provider API versions; confirm
`Microsoft.ApiCenter/services`, `.../workspaces/apiSources`, and `.../metadataSchemas` API
version available in the target subscription)

**Primary Dependencies**: Azure Resource Manager; `Microsoft.ApiCenter` (service, default
workspace, API source link, metadata schemas), `Microsoft.ApiManagement` (existing instance
referenced by ID only), `Microsoft.Authorization` (role assignments for the separation-of-duties
RBAC model), Microsoft Graph/Entra ID (existing designated security group, referenced by object
ID — not created by this feature); Azure CLI/Bicep CLI (`az apic ...` equivalents used only for
validation, not as a substitute for IaC)

**Storage**: N/A — this feature adds no new data stores; the catalog, metadata schema, and portal
configuration are properties of the API Center resource itself

**Testing**: `az bicep build`, `az deployment group what-if`, Azure CLI/`az apic` inspection
commands, portal access tests (in-group vs. out-of-group vs. unauthenticated), sync-latency
timing against the 15-minute freshness target

**Target Platform**: Single-region Azure POC subscription, resource-group deployment in
`rg-agent-factory-poc` (`eastus2`)

**Project Type**: Infrastructure-as-code modules and validation documentation

**Performance Goals**: The auto-synced `chat/completions` API entry must appear in the catalog
within 15 minutes of an APIM API change (spec FR-004/SC-002); developer portal search/browse for
a known entry completes in under one minute for an authorized user (SC-004)

**Constraints**: The existing resource group, APIM instance, and Foundry account are immutable
prerequisites referenced by ID/name only; no MCP server, skill, or A2A agent entry may be
registered as a side effect of this deployment; the API Center plan/tier MUST NOT duplicate a tier
already available at no additional cost through the eligible APIM link; the developer portal MUST
deny unauthenticated users and authenticated non-members of the designated Entra ID group; no
control-plane RBAC role may be granted to developers; re-applying the deployment MUST NOT create
duplicate instances, service links, or metadata schema definitions

**Scale/Scope**: One API Center instance, one APIM service link, one governance metadata schema
(four required properties), one auto-synced catalog entry (`chat/completions`), one developer
portal, one Entra ID security group reference; no MCP server registry, skill registry, A2A agent
registration, API linting/conformance scoring, or VS Code/`mcp.json` generation workflow in this
increment

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **Separation of duties:** PASS. Per the spec's clarified RBAC model (FR-013), platform
  engineering's Bicep grants itself/its principal control-plane Contributor/Owner on the API
  Center resource (instance, APIM link, portal lifecycle) only; the AI CoE governance owner
  receives a distinct, scoped metadata-editor role limited to the governance metadata schema and
  catalog annotations, with no resource-lifecycle permissions; developers receive no
  control-plane role at all and reach the catalog only through the portal via Entra ID group
  membership. These are three non-overlapping role assignments, matching CODEOWNERS boundaries.
- **Spec before infra:** PASS. This plan follows the approved, clarified `spec.md`; no Bicep
  exists yet in `infra/modules/api-center/` and none will be generated until this plan and a
  subsequent `tasks.md` are complete and explicitly approved.
- **Private by default/no bypass:** PASS. API Center is a design-time control-plane/catalog
  resource, not a data-plane traffic path — it does not proxy model or tool traffic, so it does
  not introduce a new public data path around APIM. The developer portal is the only
  user-facing surface this feature adds, and it is fail-closed: Entra ID authentication is
  mandatory and access is restricted to the designated security group, with no anonymous or
  tenant-wide fallback. Content Safety/logging bypass is not applicable to this feature (no
  model traffic flows through API Center).
- **Incremental/testable slices:** PASS. Instance creation, the APIM service link, the metadata
  schema, and the developer portal each have an independent test in `spec.md` (User Stories
  1-4), and each can be verified without the others being fully validated first (e.g., the
  instance's existence is testable before the link is healthy).
- **IaC/validation:** PASS. Design uses parameterized Bicep, existing-resource references by
  ID/name, `az bicep build`, and `what-if`; because API Center plan/tier eligibility depends on
  the linked APIM tier rather than a quota API, `what-if` plus an explicit tier/plan inspection
  step is treated as a mandatory pre-deployment gate (mirroring the Chapter 02 pattern of
  distrusting quota-adjacent assumptions).
- **Gate status:** PASS before research.

**Post-Phase-1 re-evaluation:** PASS, unchanged. The Phase 1 design in
[data-model.md](data-model.md), [contracts/api-center-bicep-interface.md](contracts/api-center-bicep-interface.md),
and [quickstart.md](quickstart.md) preserves the three-role RBAC split with no new shared role,
introduces no public endpoint or data-plane traffic path (the portal remains the sole,
group-restricted user surface), keeps each of the four user stories independently testable via
the Phase 1 validation result entity and quickstart scenarios, and adds no infrastructure outside
`infra/modules/api-center/` and `infra/envs/poc/api-center.bicep`/`.bicepparam` — it does not
alter `infra/modules/apim/` or `infra/modules/foundry/`. No constitution violation was introduced
during design; the Complexity Tracking table below remains empty.

## Project Structure

### Documentation (this feature)

```text
specs/04-api-center/
├── spec.md               # Feature specification (approved, clarified)
├── plan.md               # This file
├── research.md           # Phase 0 output
├── data-model.md         # Phase 1 output
├── quickstart.md         # Phase 1 output
├── contracts/            # Phase 1 output
│   └── api-center-bicep-interface.md
└── tasks.md              # Phase 2 output (/speckit.tasks — not created by this plan)
```

### Source layout

```text
infra/
├── envs/poc/
│   ├── main.bicep                 # existing network environment composition
│   ├── foundry.bicep              # existing Foundry environment composition
│   ├── apim.bicep                 # existing APIM environment composition
│   ├── api-center.bicep           # NEW: API Center environment composition
│   └── api-center.bicepparam      # NEW: API Center environment parameters
└── modules/api-center/
    ├── main.bicep                 # API Center service + default workspace
    ├── apim-link.bicep            # APIM service link (api source) for auto-sync
    ├── metadata-schema.bicep      # governance metadata schema (owning team, data
    │                              #   classification, agent protocol, lifecycle stage)
    ├── rbac.bicep                 # control-plane + metadata-editor role assignments
    └── portal.bicep               # developer portal + Entra ID group access restriction
```

**Structure Decision**: Add a focused `infra/modules/api-center/` module family and a POC
environment composition/parameter file pair, mirroring the Chapter 02 `infra/modules/apim/`
pattern exactly (one module per concern, one environment composition file, one `.bicepparam`
file). Reference the existing resource group, the Chapter 02 APIM instance, and the designated
Entra ID security group by ID/object ID only. Do not alter `infra/modules/apim/` or
`infra/modules/foundry/` internals in any way; those modules are read-only inputs to this
feature's parameter file (the APIM resource ID and, if needed, its identity/tier metadata).

## Resource and module design

1. **Environment composition (`infra/envs/poc/api-center.bicep`):** pass location, the API
   Center service name, the existing APIM resource ID (referenced, not redeclared), the
   designated Entra ID security group object ID, and the governance metadata schema property
   definitions as parameters.
2. **Instance module (`main.bicep`):** create the `Microsoft.ApiCenter/services` resource (the
   exact API version to be confirmed in `research.md`) in `rg-agent-factory-poc`/`eastus2`, plus
   its implicit/default workspace, with no plan/tier parameter that would provision a redundant
   paid SKU beyond what the eligible APIM link makes available at no additional cost.
3. **APIM service-link module (`apim-link.bicep`):** create a
   `Microsoft.ApiCenter/services/workspaces/apiSources` resource (or the equivalent current
   resource type — confirmed in research) referencing the existing APIM instance's resource ID,
   configured to auto-import APIs so the `chat/completions` API syncs without manual re-entry, and
   explicitly scoped to import APIs only (no MCP server or A2A registration behavior implied by
   this link, since APIM currently exposes neither).
4. **Metadata-schema module (`metadata-schema.bicep`):** define four
   `Microsoft.ApiCenter/services/metadataSchemas` (or equivalent) resources — owning team, data
   classification, agent protocol, and lifecycle stage — each with an enumerated (`enum`)
   string schema, matching the four required properties clarified in `spec.md`.
5. **RBAC module (`rbac.bicep`):** assign platform engineering's principal a control-plane
   Contributor/Owner-equivalent role scoped to the API Center resource only; assign the AI CoE
   governance owner's principal a metadata-editor-scoped role (the least-privileged built-in or
   custom role that permits managing metadata schemas and catalog entry annotations without
   resource-lifecycle permissions — confirmed in research); assign no control-plane role to
   developers.
6. **Developer portal module (`portal.bicep`):** provision the API Center developer portal and
   restrict its access to the designated Entra ID security group (by object ID), denying both
   unauthenticated access and authenticated access from outside that group; the exact portal
   resource/configuration shape (native `Microsoft.ApiCenter` portal resource vs. a companion
   hosting mechanism) is confirmed in research.
7. **Validation module/script contract:** report instance provisioning state, service-link health
   and sync-latency evidence, metadata schema attachment success against the real
   `chat/completions` entry, portal access-control test results (member/non-member/unauthenticated),
   and an explicit "zero MCP/skill/agent entries" check.

Dependency order is: confirm the API Center resource provider is registered and the existing
APIM instance/resource group are reachable by ID → deploy the API Center instance and default
workspace → create the APIM service link (api source) → define the four metadata schema
properties → attach RBAC role assignments (platform engineering, AI CoE governance owner) →
deploy the developer portal → configure Entra ID group restriction on the portal → run
validation (sync latency, metadata attachment, portal access, zero-registry check).

## Validation and quota strategy

- Compile every Bicep module and run resource-group `what-if`; attach output to the PR, since
  API Center plan/tier eligibility depends on the linked APIM tier rather than a quota API.
- Confirm the API Center instance's effective plan/tier matches what the eligible classic Premium
  APIM link makes available at no additional cost, and that no redundant paid tier is created.
- Verify the APIM service link (api source) reports a healthy/active sync status and that the
  `chat/completions` API appears in the catalog with no manually created duplicate entry.
- Time an APIM API change (or the initial sync) end-to-end and confirm catalog reflection occurs
  within 15 minutes, per the clarified freshness target.
- Attach all four governance metadata properties to the synced `chat/completions` entry and
  confirm no schema validation errors; confirm an out-of-enum value is rejected.
- Verify RBAC role assignments: platform engineering has resource-lifecycle permissions, the AI
  CoE governance owner has metadata-only permissions, and developers hold no control-plane role,
  each scoped only to the API Center resource (not the resource group or subscription).
- Test developer portal access as a group member (success, sees entry + metadata), an
  authenticated non-member (denied), and an unauthenticated user (denied).
- Confirm the catalog contains zero MCP server, skill, or A2A agent entries after deployment.
- Re-run the same what-if with unchanged parameters and confirm no duplicate instance, service
  link, or metadata schema definitions are proposed.

## Research questions and risks

See [research.md](research.md) for sources and decisions. Implementation must confirm: the exact
`Microsoft.ApiCenter/services`, `.../workspaces/apiSources`, and `.../metadataSchemas` Bicep
resource types and API versions available in the target subscription; the precise built-in or
custom RBAC role(s) that grant the AI CoE governance owner metadata-only permissions without
resource-lifecycle rights; the current developer-portal provisioning/configuration mechanism and
how Entra ID security-group restriction is expressed for it; and whether the eligible-APIM-link
free tier is expressed as a specific SKU/plan value or inferred automatically by the platform at
deployment time.

## Phase 0: Research

Documented in [research.md](research.md): resolves the API Center resource type/API version
question, the APIM service-link (api source) shape, the governance metadata schema definition
pattern, the RBAC role selection for the AI CoE governance owner, and the developer portal /
Entra ID group restriction mechanism.

## Phase 1: Design artifacts

- [data-model.md](data-model.md) defines prerequisites, managed entities (API Center instance,
  APIM service link, governance metadata schema/properties, catalog entry, developer portal,
  Entra ID security group reference, validation result), and readiness transitions.
- [contracts/api-center-bicep-interface.md](contracts/api-center-bicep-interface.md) defines
  planned module inputs, outputs, and fail-closed invariants (no MCP/skill/agent entries
  registered, portal denies non-group members, no duplicate service link on redundant apply).
- [quickstart.md](quickstart.md) defines runnable preview, link, metadata, and portal-access
  validation scenarios.

## Complexity Tracking

No constitution violations. The module split (instance, APIM service link, metadata schema,
RBAC, developer portal) mirrors the Chapter 02 module granularity and keeps each piece
independently testable without altering the existing APIM or Foundry modules or introducing any
MCP server, skill, or A2A agent registration ahead of its later increment.
