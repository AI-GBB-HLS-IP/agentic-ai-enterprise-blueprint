# Feature Specification: Azure API Center (Catalog Core)

**Feature Branch**: `spec/04-api-center`

**Created**: 2026-08-25

**Status**: Draft

**Input**: User description: "Create specs/04-api-center/spec.md for Chapter 04, Azure API Center. Use the Chapter 02 APIM AI Gateway deployment as an existing prerequisite and scope an API Center instance linked to APIM, with governance metadata and a developer portal, deferring MCP server/skill/agent registry population to a later increment since no such backends currently exist."

**Blueprint reference**: Chapter [04-api-center](../../chapters/04-api-center.md).

**Governing deployment plan**: Not yet created for this chapter. Tracked under
[Issue #26](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/26)
(`type: spec`, `area: api-center`, `priority: p1`), consistent with how Chapter 02 was tracked
under [Issue #17](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/17).

## Scope and Implementation Status

This feature defines the requirements for the **core** increment of Chapter 04. Two existing
prerequisites are assumed: the Network Foundation (resource group `rg-agent-factory-poc`, VNet
`vnet-agent-factory-poc`, `snet-privateendpoints` (`10.0.4.0/24`)) and the Chapter 02 APIM AI
Gateway — a private, VNet-injected, classic Premium Azure API Management instance in
`rg-agent-factory-poc`/`eastus2`, exposing exactly one governed, OpenAI-compatible
`chat/completions` API for the `foundry-agent-factory-poc` account's `gpt-4.1-mini` deployment
(see [specs/02-apim-ai-gateway/spec.md](../02-apim-ai-gateway/spec.md)). The Foundry account
itself is an assumed prerequisite consistent with the Chapter 01 and Chapter 02 specifications;
Foundry model-approval work tracked separately (e.g. Issue #14) is **not** a dependency of this
feature and does not block its scope.

**Approved initial boundary for this increment**: this feature covers creating the Azure API
Center instance, linking it to the existing APIM instance so that APIM's runtime API(s)
auto-sync into the catalog, defining the governance metadata schema (owner, data classification,
agent protocol, lifecycle stage) that registered assets must carry, and standing up the developer
portal for catalog discovery and access.

**Explicitly out of scope for this increment**: Chapter 02 explicitly deferred MCP server
publication and A2A agent routing because no MCP tool, skill, or agent backend currently exists
in this POC to publish or route to (see the Chapter 02 spec's Scope and Implementation Status).
Consequently, this feature **MUST NOT** depend on, register, or validate any MCP server, skill,
or agent/A2A API entry as a required outcome — the API Center MCP server registry, skill
registry, and agent (A2A) API registration described in the blueprint's Parts 3–5 are a
**stretch goal deferred to a later increment**, to be revisited once Chapter 02 (or a later
chapter) actually publishes an MCP server, skill, or agent backend. Automated API governance
linting/conformance scoring (blueprint Part 7) and the VS Code extension / `mcp.json` generation
workflow (blueprint Part 8) are likewise deferred; they depend on a populated catalog with real
registered assets to be meaningful.

The API Center instance, APIM link, governance metadata schema, and developer portal described
below are requirements for this feature; they are not claimed to be deployed by this
specification.

## Clarifications

### Session 2026-08-25

- Q: Who or what should technically enforce that platform engineers, the AI CoE governance
  owner, and developers each get different access levels to the API Center instance? → A: Azure
  RBAC role assignments — platform engineering holds control-plane Contributor/Owner on the API
  Center resource; the AI CoE governance owner holds a scoped, metadata-editor role limited to
  managing the governance metadata schema and catalog metadata (not resource lifecycle);
  developers access only the developer portal via Entra ID group membership, with no
  control-plane role.
- Q: Should "lifecycle stage" be a required governance metadata property alongside owning team,
  data classification, and agent protocol, or is it optional/deferred for this increment? → A:
  Required now — "lifecycle stage" is a fourth enumerated required property defined in this
  increment.
- Q: After an API changes in APIM (e.g., a new API is published), how quickly must that change be
  reflected in the API Center catalog for the sync to count as "healthy"? → A: Within 15 minutes.
- Q: Does this increment need to record an audit trail (who changed governance metadata, when a
  sync occurred, who accessed the portal) for AI CoE oversight, or is that out of scope until a
  later increment? → A: Deferred — rely on default Azure Monitor/diagnostic logging only for this
  increment; an explicit audit-trail/reporting capability is a later increment.
- Q: Who specifically should be able to access the developer portal — all authenticated users in
  the tenant, or only members of a designated Entra ID group/role scoped to this POC? → A:
  Restricted to members of a designated Entra ID security group scoped to this POC.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform engineer creates the API Center catalog instance (Priority: P1)

As an IT Platform Engineer, I need to create an Azure API Center instance in the existing
resource group so that the organization has a single design-time catalog for APIs, independent
of and complementary to the APIM runtime gateway.

**Why this priority**: The catalog instance is the foundation every other capability in this
chapter (linking, metadata, portal) depends on; nothing else can be validated before it exists.

**Independent Test**: Inspect the deployed API Center resource's name, resource group, region,
and plan/tier; confirm it exists independently of any linked service and is reachable via the
Azure control plane.

**Acceptance Scenarios**:

1. **Given** the prerequisite resource group `rg-agent-factory-poc` exists, **When** the API
   Center deployment is applied, **Then** an API Center instance is created in `eastus2` within
   that resource group.
2. **Given** the API Center instance is linked to an eligible APIM tier (classic Premium, per
   Chapter 02), **When** the plan/tier is inspected, **Then** the instance uses the plan tier
   made available at no additional cost by that eligible link, and no redundant paid tier is
   provisioned.

---

### User Story 2 - Platform engineer links API Center to the existing APIM gateway (Priority: P1)

As an IT Platform Engineer, I need to link the API Center instance to the Chapter 02 APIM
instance so that the client-facing `chat/completions` API automatically syncs into the catalog
without manual re-entry, keeping the catalog accurate as APIM's APIs change.

**Why this priority**: Auto-sync is the mechanism that makes the catalog trustworthy; a catalog
that must be manually kept in sync with APIM provides little governance value and is the next
capability after the instance itself exists.

**Independent Test**: Inspect the API Center service link configuration and the catalog's API
list; confirm the APIM instance is a recognized linked source and that APIM's existing
`chat/completions` API appears in the API Center catalog without having been manually registered.

**Acceptance Scenarios**:

1. **Given** the Chapter 02 APIM instance exists in the same resource group, **When** the service
   link is created, **Then** API Center records the APIM resource ID as a linked source and the
   link shows a healthy/active sync status.
2. **Given** the link is active, **When** the API Center catalog is queried, **Then** the APIM
   client-facing `chat/completions` API appears automatically, with no manually created duplicate
   entry for the same API.
3. **Given** no MCP server, skill, or A2A agent API currently exists behind APIM, **When** the
   catalog is inspected, **Then** it contains zero MCP server, skill, or agent entries, and this
   absence is not treated as a defect for this increment.

---

### User Story 3 - Governance owner defines required metadata for catalog entries (Priority: P2)

As an AI CoE / governance owner, I need a defined set of custom metadata properties (owning
team, data classification, agent protocol, lifecycle stage) so that every asset registered in
the catalog — now or in future increments — carries the minimum governance information needed
for discovery and oversight, before any MCP server, skill, or agent is ever registered.

**Why this priority**: Defining the governance schema before assets are registered ensures
future registrations (Chapter 02+ MCP/agent work) are governed from day one, but this depends on
the catalog and link already existing.

**Independent Test**: Inspect the API Center metadata schema definitions directly; confirm each
required property exists with the correct type/enumeration and is available to be attached to
any API, MCP server, or skill entry, independent of whether any entry currently uses it.

**Acceptance Scenarios**:

1. **Given** the API Center instance exists, **When** the metadata schema is inspected, **Then**
   it defines at minimum an "owning team", a "data classification", an "agent protocol", and a
   "lifecycle stage" property, each with a constrained (enumerated) set of allowed values.
2. **Given** the metadata schema is defined, **When** the auto-synced `chat/completions` API
   entry is inspected, **Then** it can be annotated with the defined metadata properties without
   error, demonstrating the schema is usable against a real catalog entry.

---

### User Story 4 - Developer discovers catalog contents through the developer portal (Priority: P2)

As a developer (or platform validator standing in for one), I need a self-service developer
portal so that I can browse and search the catalog to see what APIs currently exist and their
governance metadata, without needing direct Azure control-plane access or asking another team.

**Why this priority**: The portal is the user-facing payoff of the catalog and link (Stories 1–2)
and the metadata schema (Story 3); it demonstrates the discoverability value of this chapter, but
naturally depends on there being an instance, a link, and metadata to browse.

**Independent Test**: As a member of the designated Entra ID developer security group, open the
developer portal and search/browse for the known `chat/completions` API entry; confirm it is
discoverable and its governance metadata is visible, without requiring Azure Resource Manager
access.

**Acceptance Scenarios**:

1. **Given** the developer portal is deployed, **When** a member of the designated Entra ID
   developer security group browses it, **Then** they can find the synced `chat/completions` API
   and view its title, description, and governance metadata.
2. **Given** Entra ID authentication is configured for the portal, **When** an unauthenticated
   user or an authenticated user who is not a member of the designated developer security group
   attempts to access it, **Then** access is denied.
3. **Given** no MCP server, skill, or agent entries exist in this increment, **When** a portal
   user searches for these categories, **Then** the portal correctly shows an empty result rather
   than an error, and this is not treated as a defect.

### Edge Cases

- The API Center instance must not be provisioned with a paid plan tier that duplicates a tier
  already available at no additional cost through the eligible APIM link; validation must confirm
  the effective plan/tier before deployment.
- If the APIM service link fails to establish (e.g., transient permission or propagation delay),
  the catalog must not silently show a stale or partial API list; validation must confirm sync
  status explicitly rather than assuming success.
- A metadata property with an enumerated value must reject an out-of-enum value when attached to
  a catalog entry, rather than silently accepting free text.
- A developer portal user searching for MCP servers, skills, or agents before any exist must see
  an accurate empty state, not an error, broken page, or misleading "coming soon" claim.
- Re-running the API Center and link deployment must not create a duplicate service link, a
  duplicate API Center instance, or duplicate metadata schema definitions.
- Removing or renaming the linked APIM instance's `chat/completions` API must be reflected in the
  catalog on next sync, not silently ignored or left stale indefinitely.
- This feature must not register any MCP server, skill, or A2A agent API as a side effect of
  creating the instance, the link, or the metadata schema; validation must confirm the catalog
  contains no such entries until a later increment explicitly adds one.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST create an Azure API Center instance in `rg-agent-factory-poc`
  (`eastus2`), independent of any specific linked service.
- **FR-002**: The feature MUST use the plan/tier made available at no additional cost through
  linking to the existing eligible (classic Premium) APIM instance, and MUST NOT provision a
  redundant paid tier.
- **FR-003**: The feature MUST create a service link between the API Center instance and the
  existing Chapter 02 APIM instance so that APIM's APIs auto-sync into the catalog.
- **FR-004**: The feature MUST validate that the auto-synced client-facing `chat/completions` API
  appears in the API Center catalog within 15 minutes of an APIM API change, without manual
  re-entry, and MUST NOT create a duplicate manual entry for the same API.
- **FR-005**: The feature MUST define a governance metadata schema with, at minimum, an owning
  team property, a data classification property, an agent protocol property, and a lifecycle
  stage property, each constrained to an enumerated set of allowed values.
- **FR-006**: The feature MUST demonstrate that the defined metadata schema can be attached to the
  auto-synced `chat/completions` catalog entry without error.
- **FR-007**: The feature MUST deploy a developer portal for the API Center instance with Entra ID
  authentication enabled, restricting access to members of a designated Entra ID security group
  scoped to this POC and denying access to unauthenticated users or authenticated users outside
  that group.
- **FR-008**: The developer portal MUST allow an authenticated member of the designated developer
  security group to browse and
  search the catalog and view an entry's title, description, and governance metadata.
- **FR-009**: The feature MUST NOT register, or depend on the existence of, any MCP server, skill,
  or A2A agent API entry; the catalog MUST correctly reflect zero such entries for this
  increment, and this is not a defect.
- **FR-010**: The feature MUST NOT configure automated API definition linting/conformance scoring
  (governance dashboard) or the VS Code extension / MCP client configuration generation workflow;
  these remain scoped to a later increment once real MCP server, skill, or agent entries exist.
- **FR-011**: Infrastructure changes for this feature MUST be represented as parameterized
  infrastructure-as-code and MUST be validated with a non-destructive preview of intended changes
  before deployment.
- **FR-012**: The deployment MUST be idempotent: reapplying the same declared configuration MUST
  NOT produce unexpected resource changes or duplicate API Center instances, service links, or
  metadata schema definitions.
- **FR-013**: The feature MUST preserve separation of duties via distinct Azure RBAC role
  assignments: platform engineering holds control-plane Contributor/Owner on the API Center
  resource (instance, APIM link, portal lifecycle); the AI CoE / governance owner holds a scoped
  role limited to defining and maintaining the governance metadata schema and annotating catalog
  entries, without resource-lifecycle permissions; developers receive no control-plane role and
  access the catalog only through the developer portal via Entra ID group membership.
- **FR-014**: The feature MUST rely on default Azure Monitor / diagnostic-settings logging for
  the API Center resource as its baseline observability for this increment; an explicit
  governance audit trail (metadata change history, sync event history, portal access reporting)
  is deferred to a later increment and MUST NOT be treated as a gap for this feature.

### Key Entities

- **API Center instance**: The design-time catalog resource that is the single source of
  discoverability for APIs, and — in later increments — MCP servers, skills, and agents.
- **APIM service link**: The linked-source relationship between the API Center instance and the
  Chapter 02 APIM instance that drives auto-sync of runtime APIs into the catalog.
- **Governance metadata schema**: The defined set of custom properties (owning team, data
  classification, agent protocol, lifecycle stage) that catalog entries can and, per policy,
  should carry.
- **Catalog entry**: A synced or registered asset (currently limited to the APIM
  `chat/completions` API) visible in the catalog with its associated metadata.
- **Developer portal**: The Entra ID-secured, self-service web experience through which
  developers browse and search the catalog.
- **Validation result**: Evidence of instance/link health, successful metadata attachment,
  portal access enforcement, and confirmed absence of out-of-scope MCP/skill/agent entries.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can stand up the API Center instance and link it to the
  existing APIM gateway without manually re-entering any API that already exists in APIM.
- **SC-002**: 100% of APIM client-facing APIs present at link time (currently one:
  `chat/completions`) appear in the API Center catalog through auto-sync within 15 minutes,
  verified without any manual catalog edit.
- **SC-003**: 100% of the defined governance metadata properties (owning team, data
  classification, agent protocol, lifecycle stage) can be attached to a real catalog entry with
  no schema validation errors.
- **SC-004**: 100% of access attempts by unauthenticated users or authenticated users outside the
  designated developer security group are denied, while a member of that group can locate the
  known catalog entry and its metadata in under one
  minute of browsing/searching.
- **SC-005**: Reapplying the declared configuration produces zero unexpected changes and creates
  no duplicate API Center instances, service links, or metadata schema definitions.
- **SC-006**: A validation report confirms zero MCP server, skill, or A2A agent entries exist in
  the catalog after this feature is deployed, distinguishing this increment's boundary from later
  chapter work that will populate the registry.

## Assumptions

- The Chapter 02 APIM AI Gateway specification has been implemented (or is implemented before
  this feature is validated end-to-end) and its named resource group, region, and private,
  classic Premium APIM instance exposing the `chat/completions` API are available in the target
  subscription.
- The Chapter 01 Foundry account (`foundry-agent-factory-poc`) is an assumed upstream
  prerequisite consistent with the Chapter 01 and Chapter 02 specifications; Foundry model
  approval (tracked separately, e.g. Issue #14) is not a dependency of this feature.
- The POC uses one Azure region (`eastus2`) and one resource group (`rg-agent-factory-poc`),
  consistent with the existing Network Foundation, Foundry, and APIM deployments.
- No MCP server, skill, or A2A agent backend currently exists in this POC; the MCP server
  registry, skill registry, and agent (A2A) API registration described in the Chapter 04
  blueprint are deferred to a later increment once such backends exist to register, mirroring how
  Chapter 02 deferred MCP publication and A2A routing for the same reason.
- Automated API governance linting/conformance scoring and VS Code extension / MCP client
  configuration generation are deferred to the same later increment, since both depend on a
  catalog populated with real, non-trivial entries to provide meaningful value.
- This feature is tracked under
  [Issue #26](https://github.com/AI-GBB-HLS-IP/agentic-ai-enterprise-blueprint/issues/26)
  (`type: spec`, `area: api-center`, `priority: p1`), consistent with how Chapter 02 is tracked
  under Issue #17.
- The executing platform identity has sufficient subscription/resource-group permissions to
  create the API Center instance, the APIM service link, metadata schema definitions, and the
  developer portal; directory role assignment follows the repository's governance process.
