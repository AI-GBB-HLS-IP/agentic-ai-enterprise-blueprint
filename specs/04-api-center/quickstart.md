# Quickstart Validation Guide

This guide validates the Chapter 04 API Center implementation under:

- `infra/modules/api-center/`
- `infra/envs/poc/api-center.bicep`
- `infra/envs/poc/api-center.bicepparam`

It assumes Azure CLI, Bicep CLI, subscription access, the existing Chapter 02 APIM AI Gateway
deployment, and the designated Entra ID security group's object ID.

## Prerequisites

1. Confirm the existing resource group (`rg-agent-factory-poc`) and the Chapter 02 APIM instance
   (`eastus2`, classic Premium, private, exposing `chat/completions`) are present.
2. Confirm the API Center `location` value in `api-center.bicepparam` is currently supported by
   `Microsoft.ApiCenter`; the proposed initial POC value is `eastus`.
3. Confirm the required constitution amendment is merged before using an API Center location
   different from the existing `eastus2` runtime region.
4. Confirm the designated Entra ID security group for developer portal access already exists and
   its object ID is available.
5. Confirm the deployment plan has recorded approval before any step below runs against the live
   subscription.
6. Run the local deterministic validator first (if present under
   `specs/04-api-center/validation/`), consistent with the Chapter 02 pattern; if it reports
   live-gate blockers, do not mark deployment readiness as passed.

## Validate the deployment preview

```bash
az bicep build --file infra/modules/api-center/main.bicep
az bicep build --file infra/modules/api-center/apim-link.bicep
az bicep build --file infra/modules/api-center/metadata-schema.bicep
az bicep build --file infra/modules/api-center/rbac.bicep
az bicep build --file infra/modules/api-center/portal.bicep
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/api-center.bicep \
  --parameters infra/envs/poc/api-center.bicepparam
```

Expected: only declared Chapter 04 resources are created (API Center instance, default
workspace, APIM service link, four metadata schema definitions, RBAC role assignments, developer
portal); no changes to the existing VNet, Foundry account/project/model deployment, or the
Chapter 02 APIM instance's own configuration.

Save output to `specs/04-api-center/validation/us1-what-if.md`.

## Validate the API Center instance and plan/tier (User Story 1)

```bash
az apic show -g rg-agent-factory-poc -n <api-center-name> \
  --query '{name:name,location:location,plan:properties}'
```

Expected: the instance exists in the configured, provider-supported location within
`rg-agent-factory-poc`, independent of any linked service, and its effective plan/tier does not
duplicate a paid tier already available at no additional cost through the eligible classic
Premium APIM link. The deployed location must exactly match the parameter value, and the existing
APIM instance must remain in `eastus2`.

Save output to `specs/04-api-center/validation/us1-instance.md`.

## Validate the APIM service link and auto-sync (User Story 2)

```bash
az apic service list -g rg-agent-factory-poc --query "[?name=='<api-center-name>']"
az apic api list -g rg-agent-factory-poc -n <api-center-name> -o table
```

Expected: the APIM instance is a recognized linked source with a healthy/active sync status, and
the `chat/completions` API appears in the catalog with no manually created duplicate entry. Time
an APIM API change (or the initial sync) and confirm catalog reflection within 15 minutes.
Confirm the catalog contains zero MCP server, skill, or A2A agent entries at this point.

Save output to `specs/04-api-center/validation/us2-link.md`.

## Validate the governance metadata schema (User Story 3)

```bash
az apic metadata list -g rg-agent-factory-poc -n <api-center-name> -o table
```

Expected: at minimum, `owning-team`, `data-classification`, `agent-protocol`, and
`lifecycle-stage` properties exist, each with a constrained enumerated set of allowed values.
Attach all four properties to the synced `chat/completions` entry and confirm no schema
validation errors; attempt to attach an out-of-enum value and confirm it is rejected.

Save output to `specs/04-api-center/validation/us3-metadata.md`.

## Validate RBAC / separation of duties

```bash
az role assignment list --scope <api-center-resource-id> -o table
```

Expected: platform engineering holds a control-plane role, the AI CoE governance owner holds a
distinct metadata-editor-scoped role with no resource-lifecycle permissions, and no developer
principal holds any role on this resource.

Save output to `specs/04-api-center/validation/rbac.md`.

## Validate developer portal access (User Story 4)

As a member of the designated Entra ID security group, open the developer portal and
search/browse for the known `chat/completions` entry. Expected: the entry is discoverable within
one minute, and its title, description, and governance metadata are visible.

As an authenticated user who is not a member of the group, and separately as an unauthenticated
user, attempt to access the portal. Expected: both attempts are denied.

Search the portal for MCP servers, skills, and agents. Expected: the portal shows an accurate
empty result, not an error or broken page.

Save output to `specs/04-api-center/validation/us4-portal.md`.

## Validate scope boundary

```bash
az apic mcp-server list -g rg-agent-factory-poc -n <api-center-name> -o table
```

Expected: zero MCP servers, zero skills, and zero A2A agent APIs exist after this deployment —
confirming the increment stayed within its approved core-catalog boundary and did not depend on
or create any of the blueprint's Parts 3–5, 7, or 8 capabilities.

## Validate idempotency

Re-run the same what-if with unchanged parameters and verify no duplicate API Center instance,
service link, or metadata schema definitions are proposed.

Save output comparison to `specs/04-api-center/validation/idempotency.md`.

## Failure cases

The validation must fail with an affected resource and remediation hint for: a redundant paid
plan/tier being provisioned, an unsupported configured location, a deployed location that differs
from the parameter value, a cross-region control-plane deployment without the required governance
approval delivered through a merged constitution amendment (no waiver, exception flag, manual
override, or deployment-plan approval may substitute), a service link that fails to establish or
reports stale/partial sync, a metadata property missing its enumeration constraint or accepting
an out-of-enum value, a developer portal reachable by an unauthenticated or non-member user, an
RBAC assignment that grants the AI CoE governance owner resource-lifecycle rights or grants any
developer a control-plane role, or the presence of any MCP server, skill, or A2A agent entry.

Record the consolidated readiness and blockers in
`specs/04-api-center/validation/final-report.md`.
