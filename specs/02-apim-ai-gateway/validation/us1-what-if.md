# US1 what-if evidence (T017)

Status: **PASS (what-if executed)**

## Command

```bash
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
  --result-format ResourceIdOnly
```

## Expected allowed change set

- `snet-apim` delegation to `Microsoft.Web/serverFarms`
- APIM Premium v2 (internal VNet injection)
- APIM-related DNS/identity/backend/API/observability resources from Chapter 02 scope

## Out-of-scope checks

- No mutations to existing Foundry account/project/model deployment
- No mutation to `snet-privateendpoints`
- No reuse or mutation of existing `privatelink.azure-api.net`

## Observed summary (2026-08-23)

- Resource changes: **15 create**, **1 deploy** (`snet-apim` delegation update), **38 ignore**.
- Potential post-provisioning record: `azure-api.net/A/apim-agent-factory-private-poc` (created once APIM
  private IP is available).
