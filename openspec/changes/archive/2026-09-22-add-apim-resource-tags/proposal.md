## Why

The APIM foundation currently applies caller-defined Azure tags only to the dedicated public IP, leaving the APIM service, observability resources, and private DNS zone without independently configurable tags. Enterprise deployments need explicit per-resource tag inputs so ownership, cost allocation, environment, and governance metadata can be applied without forcing every resource to share one tag set.

## What Changes

- Add a per-resource tagging contract for every taggable resource created by the APIM foundation deployment.
- Preserve the existing `apimPublicIpTags` behavior, including the required `ProjectCode: APIM` override.
- Add separate tag inputs for the APIM service, created Log Analytics workspace, Application Insights component, capacity alert, blueprint-owned private DNS zone, and blueprint-owned private DNS virtual network link.
- Update APIM parameter files and environment-variable interfaces so deployment automation can provide each tag object independently.
- Update validation scripts and regression tests to verify tag inputs, module propagation, conditional resource behavior, and compiled ARM output.
- Document which APIM child resources and Azure diagnostic resources do not support independent Azure resource tags.
- Use only generic, sanitized tag keys and values in committed examples; live customer tag values remain deployment-time inputs.

## Capabilities

### New Capabilities

- `apim-resource-tagging`: Defines independently configurable Azure tag behavior for taggable resources created by the APIM foundation deployment.

### Modified Capabilities

None.

## Impact

- APIM foundation interfaces in `infra/envs/poc/apim.bicep` and its `.bicepparam` files.
- APIM service, observability, and private DNS modules under `infra/modules/apim/`.
- APIM validation and regression scripts under `specs/02-apim-ai-gateway/validation/` and `tests/foundry/`.
- APIM deployment contracts, quickstart guidance, and customer parameter documentation.
- Existing callers remain compatible because every new tag object has a safe default.
