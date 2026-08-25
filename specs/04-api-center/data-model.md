# Data Model

## Inputs and prerequisites

| Entity | Key fields | Rules |
|---|---|---|
| Network foundation | resource group, VNet | Existing; resource group is `rg-agent-factory-poc`, region `eastus2`. Not modified by this feature. |
| Foundry deployment | account ID, project ID, model deployment name | Existing (Chapter 01); `foundry-agent-factory-poc`, `gpt-4.1-mini`. Not referenced directly by this feature except transitively via APIM. |
| APIM AI Gateway | resource ID, name, SKU tier, `chat/completions` API | Existing (Chapter 02); classic Premium, private, VNet-injected instance in `rg-agent-factory-poc`. Referenced by resource ID only; this feature does not modify `infra/modules/apim/` or the APIM instance's own configuration. |
| Entra ID security group | object ID, display name | Existing, provisioned outside this feature by identity/governance process; referenced by object ID only for portal access restriction and (separately) for the AI CoE governance owner's principal, if the same group is reused for that role assignment. |

## Feature-managed entities

| Entity | Key fields | Rules |
|---|---|---|
| API Center instance | name, location, resource group, effective plan/tier, default workspace | Created in `rg-agent-factory-poc`/`eastus2`; no redundant paid tier beyond what the eligible classic Premium APIM link makes available at no additional cost (FR-002); independent of any specific linked service until the link is created. |
| APIM service link (API source) | resource ID, linked APIM resource ID, import specification, sync status | Child of the instance's default workspace; references the existing APIM instance by ID; `importSpecification` set to always import; sync status must report healthy/active, not stale or partial; exactly one link per APIM instance — re-applying must not create a duplicate (FR-012). |
| Governance metadata schema / properties | property name, title, schema (`enum` of allowed values), assigned scope | Four required properties: `owning-team`, `data-classification`, `agent-protocol`, `lifecycle-stage` (FR-005); each constrained to an enumerated set of allowed values; an out-of-enum value attached to any entry must be rejected, not silently accepted. |
| Catalog entry | source, title, description, attached metadata values, sync timestamp | Currently limited to the auto-synced APIM `chat/completions` API; must appear via auto-sync within 15 minutes of an APIM API change (FR-004); must not be manually duplicated; MUST NOT include any MCP server, skill, or A2A agent entry in this increment (FR-009). |
| Developer portal | title, description, Entra ID auth configuration, allowed group object ID | Entra ID authentication mandatory; access restricted to the designated security group only; unauthenticated users and authenticated non-members are denied (FR-007); browsing/search must surface a catalog entry's title, description, and governance metadata to an authorized member (FR-008). |
| RBAC role assignments | principal, role, scope | Three non-overlapping assignments: platform engineering (control-plane Contributor/Owner-equivalent, resource-scoped), AI CoE governance owner (metadata-editor-scoped role, no resource-lifecycle rights), developers (no control-plane role — access only via the developer portal's own Entra ID group gate) (FR-013). |
| Validation result | instance status, link/sync status, metadata-attachment status, portal-access test results, registry-emptiness check | Each check is `existing`, `deployed`, `pending`, or `failed`; readiness is false for any failed/pending check, and false if any MCP server, skill, or A2A agent entry is detected in the catalog. |

## Relationships and state transitions

`Network foundation + APIM AI Gateway (existing, referenced by ID) -> API Center instance created
-> default workspace exists -> APIM service link (API source) created -> sync status becomes
healthy -> chat/completions catalog entry appears (<=15 min) -> governance metadata schema
(4 properties) defined -> metadata attached to the synced entry without error -> RBAC role
assignments applied (platform engineering, AI CoE governance owner; no developer control-plane
role) -> developer portal deployed -> Entra ID group restriction configured on the portal ->
validation ready`

The developer portal must not be considered ready until Entra ID authentication and the
group-restriction configuration both pass; the catalog is not considered ready until the service
link reports healthy sync status and the synced entry carries all four required metadata
properties. A "ready" validation result additionally requires an explicit, passing check that the
catalog contains zero MCP server, skill, or A2A agent entries — this absence is a required
passing condition for this increment, not merely an unverified assumption. Re-running the
deployment with unchanged parameters must not transition any entity to a duplicated instance,
duplicated link, or duplicated metadata-schema state.
