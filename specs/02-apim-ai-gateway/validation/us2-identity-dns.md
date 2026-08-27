# US2 identity and private DNS evidence (T024)

Status: **PASS**

Validation date: 2026-08-27

## Live result

- APIM system-assigned identity has `Cognitive Services OpenAI User` scoped only to
  `foundry-agent-factory-poc`.
- The `azure-api.net` private DNS zone is linked to `vnet-agent-factory-poc`; link state is
  `Completed`.
- From `vm-fnd-jbox`, `apim-agent-factory-private-poc.azure-api.net` resolved to `10.0.1.4`.
- The backend policy uses `authentication-managed-identity` with audience
  `https://cognitiveservices.azure.com`.
- The `approved-models` Named Value is non-secret, and no Foundry API key is stored in the Bicep
  parameters or APIM backend policy.

## Reproduction commands

```bash
APIM_PRINCIPAL_ID=$(az apim show -g rg-agent-factory-poc -n apim-agent-factory-private-poc --query identity.principalId -o tsv)

az role assignment list \
  --assignee "$APIM_PRINCIPAL_ID" \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-poc/providers/Microsoft.CognitiveServices/accounts/foundry-agent-factory-poc \
  --query "[].{role:roleDefinitionName,scope:scope}" -o table

az network private-dns zone show -g rg-agent-factory-poc -n azure-api.net
az network private-dns link vnet list -g rg-agent-factory-poc -z azure-api.net -o table
```

From `vm-fnd-jbox`:

```bash
nslookup apim-agent-factory-private-poc.azure-api.net
```

## Pass criteria

- Role is `Cognitive Services OpenAI User` scoped only to the Foundry account resource
- `azure-api.net` exists and is linked to `vnet-agent-factory-poc`
- APIM gateway hostname resolves to a private address (10.x)
- No key/secret references in Bicep policy/backend configuration
