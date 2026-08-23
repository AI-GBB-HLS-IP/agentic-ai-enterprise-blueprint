# Quickstart Validation Guide

This guide validates the design after implementation without prescribing implementation
bodies. It assumes Azure CLI, Bicep CLI, subscription access, and a private test host
(`vm-fnd-jbox`) reachable via Bastion in `vnet-agent-factory-poc`.

## Prerequisites

1. Confirm the existing resource group, VNet, `snet-apim` subnet, and Chapter 01 Foundry
   deployment (account, project, `gpt-4.1-mini` model deployment) are present.
2. Confirm `snet-apim` is currently unused and has no conflicting resource before delegation.
3. Confirm the deployment plan in `.azure/` (if used locally) has recorded approval before any
   step below runs against the live subscription.

## Validate the deployment preview

```bash
az bicep build --file infra/modules/apim/main.bicep
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

Expected: only declared Chapter 02 resources are created (subnet delegation, APIM instance,
private DNS zone/link/records, role assignment, backend, API, observability); no changes to
the existing VNet, Foundry account/project/model deployment, or `privatelink.azure-api.net`
zone.

## Validate subnet delegation and APIM network posture

```bash
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-apim \
  --query 'delegations'
az apim show -g rg-agent-factory-poc -n <apim-name> \
  --query '{virtualNetworkType:virtualNetworkType,identity:identity,publicIpAddresses:publicIpAddresses}'
```

Expected: the subnet delegation shows `Microsoft.Web/serverFarms`; the APIM instance has
`virtualNetworkType: Internal`, a system-assigned identity, and no public IP addresses.

## Validate identity and role assignment

```bash
az role assignment list \
  --assignee <apim-principal-id> \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-poc/providers/Microsoft.CognitiveServices/accounts/foundry-agent-factory-poc
```

Expected: exactly one assignment, `Cognitive Services OpenAI User`, scoped only to the Foundry
account (not the resource group or subscription).

## Validate private DNS

```bash
az network private-dns zone show -g rg-agent-factory-poc -n azure-api.net
az network private-dns link vnet list -g rg-agent-factory-poc -z azure-api.net -o table
```

From `vm-fnd-jbox`, resolve the APIM gateway hostname and confirm it returns a private
`10.0.1.x` address, not a public IP.

## Validate the client-facing API

Send ten consecutive non-streaming `chat/completions` requests from a private client, with a
valid APIM subscription key, to the client-facing API path. Expected: at least 9 of 10 succeed
and are attributable to the `gpt-4.1-mini` deployment.

Send one request with no subscription key (or an invalid one). Expected: APIM rejects it (401/
403) and the request never reaches the Foundry backend — confirm via APIM/Foundry request logs
that no corresponding Foundry-side call occurred.

## Validate token metrics and observability

Inspect the Application Insights component and Log Analytics workspace for emitted
`llm-emit-token-metric` telemetry attributable to the calling subscription. Confirm no request
body, response body, or subscription key is present in the diagnostic logs.

## Validate scope boundary

```bash
az apim api list -g rg-agent-factory-poc -n <apim-name> -o table
```

Expected: exactly one API (the client-facing `chat/completions` route). No MCP server API and
no A2A agent API exist after this deployment — confirming the increment stayed within its
approved core-gateway boundary.

## Failure cases

The validation must fail with an affected resource and remediation hint for: missing or
incorrect `snet-apim` delegation, a public gateway endpoint being present, an overly broad role
assignment scope, an unresolved or public-resolving DNS hostname, a successful unauthenticated
request, missing/incorrect token metrics, or the presence of any MCP/A2A component.
