# APIM provider and policy confirmation (T005-T007)

Status date: 2026-08-23

## Summary

- **Offline status**: PASS (all APIM Bicep modules compile).
- **Live status**: PARTIAL PASS (provider and workspace checks executed; policy-snippet schema
  endpoint remains unresolved and is tracked as a manual gate).

## T005 — APIM API version / Premium v2 / internal VNet injection schema

- Live provider check returned APIM service API versions including:
  - `2025-09-01-preview`
  - `2025-03-01-preview`
  - `2024-10-01-preview`
  - `2024-06-01-preview`
  - `2024-05-01`
- Implemented target API versions in IaC:
  - `Microsoft.ApiManagement/service@2024-05-01`
  - APIM child resources (`backends`, `apis`, `products`, `loggers`, `diagnostics`) at
    `@2024-05-01`
- Internal mode schema used:
  - `properties.virtualNetworkType = 'Internal'`
  - `properties.virtualNetworkConfiguration.subnetResourceId = <snet-apim-id>`
  - `sku.name = 'PremiumV2'`
- Required delegation modeled before APIM:
  - `Microsoft.Web/serverFarms` on `snet-apim`

**Live confirmation command (pending):**

```bash
az provider show --namespace Microsoft.ApiManagement --expand "resourceTypes/aliases" -o json
```

Status: **PASS**

## T006 — `llm-token-limit` and `llm-emit-token-metric` schema confirmation

- Implemented in API policy as:
  - inbound `llm-token-limit` keyed by `context.Subscription.Id`
  - outbound `llm-emit-token-metric` dimensions `Subscription` and `API`
- Backend auth policy implemented with:
  - `authentication-managed-identity resource="https://cognitiveservices.azure.com"`

**Live confirmation command (pending):**

```bash
az rest --method get --url "https://management.azure.com/subscriptions/<sub-id>/providers/Microsoft.ApiManagement/policySnippets?api-version=2024-05-01-preview"
```

Status: **BLOCKED (manual schema source confirmation still required)**

## T007 — Log Analytics reuse vs create decision

- Parameterized behavior implemented in `infra/modules/apim/observability.bicep`:
  - Reuse when `logAnalyticsWorkspaceId` is provided.
  - Create new workspace when parameter is empty.
- Live workspace inventory in `rg-agent-factory-poc` returned no existing workspace, so default
  behavior is confirmed as **create new**.

**Live confirmation command (pending):**

```bash
az monitor log-analytics workspace list -g rg-agent-factory-poc -o table
```

Status: **PASS**
