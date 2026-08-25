# US3 observability evidence (T033)

Status: **BLOCKED (live Azure gate unresolved)**

## Live checks to capture

```bash
az monitor app-insights component show -g rg-agent-factory-poc -a appi-apim-agent-factory-poc

az monitor diagnostic-settings list \
  --resource /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-poc/providers/Microsoft.ApiManagement/service/apim-agent-factory-private-poc
```

KQL examples:

```kusto
customMetrics
| where name == "llm-emit-token-metric"
| summarize total = sum(value) by tostring(customDimensions.Subscription), tostring(customDimensions.API)
```

```kusto
traces
| where message has "Ocp-Apim-Subscription-Key" or message has "\"messages\""
```

## Pass criteria

- Token metrics are emitted and attributable to Subscription/API dimensions.
- Diagnostic logging exists for APIM gateway requests.
- Request/response payload bodies and subscription keys are absent from captured logs.
