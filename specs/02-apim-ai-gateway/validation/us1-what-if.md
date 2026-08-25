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

- `snet-apim` remains undelegated (classic Premium requires no subnet delegation)
- APIM classic Premium (internal VNet injection)
- APIM-related DNS/identity/backend/API/observability resources from Chapter 02 scope

## Out-of-scope checks

- No mutations to existing Foundry account/project/model deployment
- No mutation to `snet-privateendpoints`
- No reuse or mutation of existing `privatelink.azure-api.net`

## Observed summary (2026-08-25)

- Resource changes: **15 create**, **38 ignore**; `snet-apim` is left undelegated and unchanged
  (no `Microsoft.Web/serverFarms` delegation is applied).
- Potential post-provisioning record: `azure-api.net/A/apim-agent-factory-private-poc` (created once APIM
  private IP is available).
