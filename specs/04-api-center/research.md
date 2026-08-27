# Research: Azure API Center (Catalog Core)

## R1: API Center instance resource type, API version, and plan/tier

**Decision**: Use `Microsoft.ApiCenter/services@2024-03-01` (the current stable GA API version)
for the instance, created with no explicit paid `sku`/plan override — allow the platform to apply
the Standard-plan-at-no-additional-cost benefit that Azure grants when an API Center instance is
subsequently linked to an eligible APIM tier (Standard, Standard v2, Premium, or Premium v2). Use
the `2024-06-01-preview` API version only for the specific child resource types (service link,
metadata schemas) that require it, if the stable GA version does not yet expose those child
resource shapes in the target subscription — to be reconfirmed against the live subscription's
resource-provider registration during implementation. Keep the API Center deployment location
parameterized and validate regional provider support before deployment; use `eastus` as the
initial POC parameter value rather than assuming the existing `eastus2` APIM runtime location is
also supported by API Center.

**Rationale**: The blueprint chapter's cost tip explicitly states the Standard plan is available
at no extra cost when linked to an eligible APIM tier, and the Chapter 02 APIM instance is
classic Premium — an eligible tier. Provisioning a separate paid tier up front, before the link
exists, risks creating a redundant charge that FR-002 explicitly forbids. Using the stable GA API
version for the top-level service resource minimizes preview-API churn risk for the
longest-lived resource in this feature; only add a preview API version where a specific child
resource type (e.g., `apiSources`) is not yet available in the GA API version.

**Alternatives considered**:
- *Provision a fixed paid `sku`/plan at creation time* — rejected; violates FR-002's "no
  redundant paid tier" requirement and the spec's Edge Cases section, which explicitly calls out
  this failure mode as something validation must catch.
- *Use only the `2024-06-01-preview` API version for every resource in this module family* —
  deferred as a fallback only if the GA version's schema proves insufficient for the service link
  or metadata schema resources; preview APIs are avoided by default per the "reconfirm against
  the live subscription" pattern established in Chapter 02's research (R1/outstanding
  confirmations).

## R2: APIM service link (auto-sync) resource shape

**Decision**: Model the APIM-to-API-Center link as a
`Microsoft.ApiCenter/services/workspaces/apiSources` resource (parented under the instance's
default workspace) with an `azureApiManagementSource.resourceId` pointing at the existing
Chapter 02 APIM instance's resource ID, `importSpecification` set to always import the API
definition, and no `msiResourceId` override — relying on the API Center instance's
system-assigned managed identity, which Azure automatically grants the built-in
"API Management Service Reader" role over the linked APIM instance.

**Rationale**: This is the documented mechanism for linking an existing APIM instance as an API
source so its APIs sync into the catalog automatically, without requiring a manually created or
maintained user-assigned identity for a single-APIM, single-catalog POC. It also keeps the trust
boundary minimal: the granted role is read-only against APIM, consistent with API Center being a
design-time/read-oriented companion to APIM rather than a data-plane participant.

**Alternatives considered**:
- *User-assigned managed identity (`msiResourceId`)* — rejected as unnecessary complexity for a
  single-APIM-instance POC; mirrors the Chapter 02 R3 decision to prefer system-assigned identity
  over user-assigned unless multiple resources need to share one.
- *Manual API registration mirroring APIM's `chat/completions` API* — rejected; this is exactly
  the "manually re-entering an API that already exists in APIM" failure mode FR-001/SC-001
  explicitly disallow, and would create the duplicate-entry edge case called out in `spec.md`.

## R3: Governance metadata schema definition pattern

**Decision**: Define four `Microsoft.ApiCenter/services/metadataSchemas` resources — one each for
`owning-team`, `data-classification`, `agent-protocol`, and `lifecycle-stage` — each with a
`schema` of `{"type": "string", "enum": [...]}` and an `assignedTo` targeting scope that includes
APIs (so the schema is attachable to the auto-synced `chat/completions` entry) and, for forward
compatibility once later increments populate them, MCP servers/agents to the extent the API
version supports declaring that scope now without requiring those entry types to exist yet.

**Rationale**: This mirrors exactly the four properties and their enumerated-value clarification
already resolved in `spec.md`'s Clarifications and FR-005, and matches the blueprint chapter's
Part 5 example schema shapes for `owning-team`, `data-classification`, and `agent-protocol`,
extended with the fourth required `lifecycle-stage` property this increment's clarification
added. Using an `enum`-constrained string schema (rather than free text) is what makes the
"reject an out-of-enum value" edge case in `spec.md` enforceable by the platform itself rather
than by convention.

**Alternatives considered**:
- *Free-text string metadata* — rejected; cannot satisfy the spec's requirement that an
  out-of-enum value be rejected rather than silently accepted.
- *A single composite metadata object instead of four distinct schemas* — rejected; four distinct
  named properties match the spec's Key Entities/FR-005 phrasing and are independently
  assignable/auditable, whereas a composite object would require all four values to be set or
  omitted together, reducing per-property enforcement clarity.

## R4: RBAC role selection for separation of duties

**Decision**: Use the built-in **Contributor** (or, if a narrower built-in "API Center
Contributor"-equivalent role exists in the target subscription's role catalog, prefer that)
role scoped to the API Center resource for platform engineering. For the AI CoE governance owner,
use the built-in **API Center Data Reader**/**API Center Service Contributor**-family role that
grants metadata and catalog-entry management without granting resource-delete/lifecycle rights —
or, if no sufficiently narrow built-in role exists in the subscription's current role catalog, use
a repository-defined custom role limited to `Microsoft.ApiCenter/services/metadataSchemas/*` and
catalog-entry metadata actions only, excluding
`Microsoft.ApiCenter/services/delete`/`Microsoft.ApiCenter/services/workspaces/apiSources/*`
actions. Developers receive no role assignment on the API Center resource at all; their access is
solely the developer portal's own Entra ID group gate.

**Rationale**: This directly implements the spec's clarified RBAC answer (FR-013): three
non-overlapping levels of access, matching the constitution's Separation of Duties principle.
Preferring a built-in role over a custom role where one exists reduces long-term maintenance
burden; a custom role is treated as a fallback, not a default, because custom role definitions
are themselves an infrastructure artifact requiring their own review.

**Alternatives considered**:
- *Single shared Contributor role for both platform engineering and the AI CoE owner* — rejected;
  violates FR-013 and the constitution's Separation of Duties principle by not distinguishing
  resource-lifecycle rights from metadata-only rights.
- *Grant developers a read-only control-plane role (e.g., Reader) on the API Center resource in
  addition to portal access* — rejected; FR-013 explicitly states developers receive no
  control-plane role, only portal access via Entra ID group membership.

## R5: Developer portal provisioning and Entra ID group restriction

**Decision**: Provision the API Center developer portal using the current
`Microsoft.ApiCenter` portal-enablement mechanism available in the target subscription (the
`az apic portal create` CLI command's underlying ARM resource/extension, to be confirmed exactly
against the live subscription's provider registration during implementation), and restrict access
by assigning the designated Entra ID security group (referenced by object ID, not created by this
feature) the portal's read/discovery role, with no role or access path granted to any other
principal, including unauthenticated/anonymous access.

**Rationale**: The spec's clarification is explicit that the portal must be restricted to a
designated Entra ID security group, not all tenant users. Referencing an existing group by object
ID (rather than creating a new group via a Microsoft Graph Bicep extension) keeps this feature's
scope aligned with FR-013's separation-of-duties model — group membership governance is an
identity-team/AI CoE concern, not something this infrastructure feature should create or own.

**Alternatives considered**:
- *Open portal access to all authenticated tenant users* — rejected; directly contradicts the
  spec's clarified answer restricting access to a designated group.
- *Create the Entra ID group as part of this feature's Bicep (via the Microsoft Graph Bicep
  extension)* — rejected as out of scope; the spec's assumptions describe the group as
  "designated," implying it is provisioned/owned by an identity/governance process, not this
  infrastructure feature. This feature only references the group's object ID as a parameter.

## Outstanding implementation-time confirmations

The following must be reconfirmed against the live subscription's provider API during
implementation, not assumed from this research alone (consistent with the Chapter 01/02 pattern
of treating provider behavior as a research gate, not a hard-coded guess):

1. The exact `Microsoft.ApiCenter/services`, `.../workspaces/apiSources`, and
   `.../metadataSchemas` API versions registered and available in the target subscription, and
   whether any of them still require a preview API version, plus confirmation that the configured
   `location` currently supports the selected resource type and API version.
2. Whether the API Center instance's effective plan/tier, once linked to the classic Premium
   APIM instance, is expressed as an explicit `sku` value the module must set, or is applied
   automatically by the platform without a corresponding Bicep property.
3. The exact built-in RBAC role names/IDs available for API Center in this subscription (data
   reader, metadata contributor, service contributor equivalents), to select the narrowest role
   that satisfies R4 without a custom role if possible.
4. The precise current mechanism (native ARM resource vs. companion Azure Static Web
   Apps-based hosting) by which the developer portal is provisioned and how Entra ID
   group-based access restriction is expressed for it in Bicep, including whether portal
   deployment requires a separate app registration this feature must reference (not create).
5. Confirmation of the designated Entra ID security group's object ID and that it already exists
   in the tenant before this feature's parameters reference it.
