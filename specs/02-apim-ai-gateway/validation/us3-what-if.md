# US3 what-if evidence (T031)

Status: **PASS (what-if executed for full APIM composition)**

## Command

```bash
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam \
  --result-format ResourceIdOnly
```

## Policy/API assertions

- Exactly one client-facing API path: `llm/v1/chat/completions`
- Subscription-key enforcement enabled (`product + api` + `check-header`)
- `llm-token-limit` and `llm-emit-token-metric` present
- No MCP API and no A2A API declarations

## Observed summary (2026-08-23)

- Planned resources include exactly one APIM API:
  `Microsoft.ApiManagement/service/apim-agent-factory-private-poc/apis/enterprise-llm-api`
- Out-of-scope APIM resources (MCP/A2A) are absent from the what-if change set.
