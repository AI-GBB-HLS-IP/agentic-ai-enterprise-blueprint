# US1 what-if validation

The previously captured output predated the staged deployment contract and is not valid evidence
for the current templates. It has been removed rather than edited into a result that was not
actually produced by Azure.

## Tenant Phase 2: main Foundry deployment

Run:

```bash
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/foundry.bicep \
  --parameters infra/envs/poc/foundry.bicepparam
```

Expected when rerun: the preview creates or updates the Foundry resources and bare
`Microsoft.Network/privateEndpoints`. It must not list any
`Microsoft.Network/privateEndpoints/privateDnsZoneGroups` resources.

## Tenant Phase 3: DNS zone group association

After Phase 2 succeeds, populate an untracked `foundry-dns.bicepparam` with full private endpoint
ARM resource IDs and run:

```bash
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/foundry-dns.bicep \
  --parameters infra/envs/poc/foundry-dns.bicepparam
```

Expected when rerun: in `vnet-link` mode, the preview also creates or updates the Foundry-managed
`privatelink.services.ai.azure.com` zone and its VNet link; in `zone-group` mode it lists
private DNS zone group child resources only for the supplied endpoint IDs. `foundryPrivateEndpointId` and
`keyVaultPrivateEndpointId` are required; `storagePrivateEndpointId`, `cosmosDBPrivateEndpointId`, and
`aiSearchPrivateEndpointId` may be empty. The IDs may reference endpoints in other resource groups or subscriptions.

No live Phase 2 or Phase 3 what-if rerun is recorded here yet.
