# Quickstart Validation Guide

This guide validates the Chapter 02 APIM gateway implementation under:

- `infra/modules/apim/`
- `infra/envs/poc/apim.bicep`
- `infra/envs/poc/apim.bicepparam`

It assumes Azure CLI, Bicep CLI, subscription access, and a private test host
(`vm-fnd-jbox`) reachable via Bastion in `vnet-agent-factory-poc`.

## Prerequisites

1. Confirm the existing resource group, VNet, `snet-apim` subnet, and Chapter 01 Foundry
   deployment (account, project, `gpt-4.1-mini` model deployment) are present.
2. Confirm `snet-apim` is currently unused and has no conflicting resource before delegation.
3. Confirm the deployment plan in `.azure/` (if used locally) has recorded approval before any
   step below runs against the live subscription.
4. Run the local deterministic validator first:

```bash
./specs/02-apim-ai-gateway/validation/validate.sh
```

If the script reports live-gate blockers, do not mark deployment readiness as passed.

## Validate the deployment preview

```bash
az bicep build --file infra/modules/apim/main.bicep
az bicep build --file infra/modules/apim/private-dns.bicep
az bicep build --file infra/modules/apim/backend.bicep
az bicep build --file infra/modules/apim/api.bicep
az bicep build --file infra/modules/apim/observability.bicep
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

Expected: only declared Chapter 02 resources are created (subnet delegation, APIM instance,
private DNS zone/link/records, role assignment, backend, API, observability); no changes to
the existing VNet, Foundry account/project/model deployment, or `privatelink.azure-api.net`
zone.

Save output to `specs/02-apim-ai-gateway/validation/us1-what-if.md` (US1 scope) and
`specs/02-apim-ai-gateway/validation/us3-what-if.md` (US3 scope).

## Validate subnet delegation and APIM network posture

```bash
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-apim \
  --query 'delegations'
az apim show -g rg-agent-factory-poc -n <apim-name> \
  --query '{virtualNetworkType:virtualNetworkType,identity:identity,publicIpAddresses:publicIpAddresses}'
```

Expected: the dedicated subnet and existing NSG association are preserved; the APIM instance has
`virtualNetworkType: Internal`, a system-assigned identity, and no public IP addresses.

Save output to `specs/02-apim-ai-gateway/validation/us1-gateway.md`.

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

Save output to `specs/02-apim-ai-gateway/validation/us2-identity-dns.md`.

## Validate the client-facing API

Send ten consecutive non-streaming `chat/completions` requests from a private client, with a
valid APIM subscription key, to the client-facing API path. Expected: at least 9 of 10 succeed
and are attributable to the `gpt-4.1-mini` deployment.

Confirm the `approved-models` APIM named value exists and is non-secret. Its value is a
base64-encoded projection of the `approvedModels` array in
`infra/envs/poc/apim.bicepparam`; do not maintain a second model allowlist directly in the
policy.

Send a request with an unlisted model name. Expected: APIM returns `400` with error code
`unsupported_model` before forwarding the request to Foundry. Send a request with the listed
public model name and confirm APIM resolves it to the configured Foundry deployment.

Send one request with no subscription key (or an invalid one). Expected: APIM rejects it (401/
403) and the request never reaches the Foundry backend — confirm via APIM/Foundry request logs
that no corresponding Foundry-side call occurred.

Save output to `specs/02-apim-ai-gateway/validation/us3-requests.md`.

## Validate token metrics and observability

Inspect the Application Insights component and Log Analytics workspace for emitted
`llm-emit-token-metric` telemetry attributable to the calling subscription. Confirm no request
body, response body, or subscription key is present in the diagnostic logs.

Save output to `specs/02-apim-ai-gateway/validation/us3-observability.md`.

## Validate scope boundary

```bash
az apim api list -g rg-agent-factory-poc -n <apim-name> -o table
```

Expected: exactly one API (the client-facing `chat/completions` route). No MCP server API and
no A2A agent API exist after this deployment — confirming the increment stayed within its
approved core-gateway boundary.

## Validate idempotency

Re-run the same what-if with unchanged parameters and verify no duplicate APIM/DNS/role/API
resources are proposed.

Save output comparison to `specs/02-apim-ai-gateway/validation/idempotency.md`.

## Failure cases

The validation must fail with an affected resource and remediation hint for: missing or
incorrect `snet-apim` delegation, a public gateway endpoint being present, an overly broad role
assignment scope, an unresolved or public-resolving DNS hostname, a successful unauthenticated
request, missing/incorrect token metrics, or the presence of any MCP/A2A component.

Record the consolidated readiness and blockers in
`specs/02-apim-ai-gateway/validation/final-report.md`.
