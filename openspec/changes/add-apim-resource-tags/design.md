## Context

See `proposal.md` for motivation. The APIM foundation currently accepts only `apimPublicIpTags`, merges it with a mandatory `ProjectCode: APIM` tag, and applies the result to the dedicated public IP. Other taggable resources are created across the APIM service, observability, and private DNS modules, while several child and extension resources do not expose a supported Azure resource tag surface.

The deployment supports both blueprint-owned and externally owned dependencies. In particular, Log Analytics can be supplied by resource ID and private DNS can be externally managed, so tag propagation must never mutate those external resources.

## Goals / Non-Goals

**Goals:**

- Provide an explicit tag object for each taggable resource created by the APIM foundation.
- Preserve current public IP tagging semantics and existing caller compatibility.
- Keep resource ownership boundaries visible in parameter names and module interfaces.
- Validate the compiled resource-to-tag mapping rather than only checking that parameters exist.

**Non-Goals:**

- Applying tags to existing customer-owned VNets, subnets, Log Analytics workspaces, or external DNS resources.
- Adding synthetic metadata fields to APIM child resources, private DNS records, or diagnostic settings that do not support independent Azure resource tags.
- Implementing implicit inheritance from resource-group tags or a single shared tag object.
- Retagging resources created by the separate APIM-to-Foundry integration stage.

## Decisions

### Use one object parameter per taggable resource

The environment template will expose:

- `apimPublicIpTags`
- `apimServiceTags`
- `logAnalyticsWorkspaceTags`
- `applicationInsightsTags`
- `capacityAlertTags`
- `privateDnsZoneTags`

Each corresponding `.bicepparam` input will read a distinct JSON environment variable. New inputs default to `{}`; the existing public IP input keeps its current default and mandatory merge behavior.

This explicit model is preferred over a single shared tag object because it allows different ownership, cost-center, and governance metadata without hidden inheritance. A shared base-tags-plus-overrides model was considered but rejected because merge precedence would make the deployment contract harder to audit and would not satisfy callers that require fully independent tag sets.

### Pass tags only through the module that owns the resource

`apimServiceTags` will flow to the APIM service module. Observability tag objects will flow only to the observability module, and `privateDnsZoneTags` will flow only to the private DNS module. The environment template remains the composition boundary and does not construct a universal tag map.

This keeps module interfaces aligned with resource ownership and prevents unrelated modules from receiving tags they cannot use.

### Preserve mandatory public IP tag precedence

The existing `union(apimPublicIpTags, { ProjectCode: 'APIM' })` behavior remains unchanged so the blueprint-controlled value wins on conflict. No mandatory tags are introduced for the other resources as part of this change.

This avoids changing an established governance invariant while keeping all new tag inputs caller-controlled.

### Apply tags only when the blueprint creates the resource

The conditional Log Analytics workspace resource receives `logAnalyticsWorkspaceTags` only when no existing workspace ID is supplied. The private DNS zone receives `privateDnsZoneTags` only in blueprint ownership mode. The deployment does not issue tag updates against external resource IDs.

This prevents an APIM deployment from unexpectedly changing metadata on shared or customer-managed infrastructure.

### Validate compiled resource mappings

Regression tests will compile the APIM foundation and assert that every supported resource references the correct parameter or module input. Validation scripts and contract documentation will also assert the new environment-variable interface.

Compiled-template assertions are preferred over text-only checks because they detect incorrect module wiring, conditional resource handling, and accidental tag reuse between resources.

### Preserve caller tag objects without publishing live values

Tag objects will flow through the parameter and module layers without renaming keys, rewriting values, or imposing a blueprint-specific tag schema beyond the existing mandatory public IP `ProjectCode` override. Documentation and test fixtures will use generic values such as `Environment: Example` or `Owner: PlatformTeam`; live customer tag keys and values will not be copied into committed artifacts.

This preserves support for customer governance conventions, including Azure-valid punctuation in tag keys, while keeping deployment-specific metadata out of the repository.

## Risks / Trade-offs

- **[Risk] Multiple independent JSON inputs increase deployment configuration volume.** → Document each variable in one table and provide minimal defaults so callers only set the tags they need.
- **[Risk] Azure Policy may append or modify tags after deployment.** → Tests validate the submitted ARM contract; live validation distinguishes blueprint-supplied tags from policy-added tags.
- **[Risk] Operators may assume tags are applied to external dependencies.** → Parameter descriptions and documentation explicitly state that existing workspaces and external DNS resources are not mutated.
- **[Risk] A resource type may change tag support in a future API version.** → Keep the supported resource list explicit and guard it with Bicep compilation and resource-specific regression assertions.
- **[Risk] Live customer tag values could be copied into examples or fixtures.** → Require sanitized generic examples and add confidentiality-focused review assertions where practical.

## Migration Plan

1. Add the new optional tag parameters to environment and module interfaces.
2. Add the corresponding environment variables to standard and customer example parameter files.
3. Apply tags to each supported blueprint-owned resource while preserving the public IP merge invariant.
4. Update validation, regression tests, contracts, and deployment guidance.
5. Deploy with omitted new inputs to confirm backward compatibility, then deploy distinct tag objects to confirm independent behavior.

Rollback removes the new optional parameters and resource tag assignments. Existing Azure tags already applied by a deployment may remain until explicitly removed, so rollback validation must account for Azure's normal tag update semantics.
