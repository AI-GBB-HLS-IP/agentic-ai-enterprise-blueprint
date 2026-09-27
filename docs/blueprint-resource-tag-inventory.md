# Blueprint Resource Tag Inventory

This inventory is the single contract matrix for `add-blueprint-resource-tags`. A
blueprint-created resource includes a resource redeployed through a managed create/update
declaration; it does not prove that the target is owned in Azure. Existing or BYO resources are
referenced without applying blueprint tag inputs.

## Network and DNS

| Entry point / resource | Ownership branch | Tag input and precedence | Unsupported or excluded surface | Tasks / scenarios |
|---|---|---|---|---|
| `main.bicep` / VNet | Greenfield managed resource | `virtualNetworkTags`, default `{}` | Existing VNet is not declared here | 2.1; independent resource tags |
| `network/main.bicep` / APIM NSG | Greenfield managed module | `apimNsgTags`, default `{}` | Existing/shared NSG paths are outside this module | 2.1, 5.1 |
| `network/main.bicep` / compute NSG | Greenfield managed module | `computeNsgTags`, default `{}` | Existing/shared NSG paths are outside this module | 2.1, 5.1 |
| `network/private-dns.bicep` / private DNS zones | Greenfield managed resources | `privateDnsZoneTags.<purpose>`, default `{}` per key | DNS records are not independently tagged by this contract | 2.2; repeated-family keys |
| `network/private-dns.bicep` / VNet links | Greenfield managed resources | `privateDnsVnetLinkTags.<purpose>`, default `{}` per key | None | 2.2; repeated-family keys |
| `brownfield-network.bicep` / APIM and compute NSGs | Managed only when `sharedHybridNsgId` is empty and `reuseExistingNsgs` is `false` | `apimNsgTags` and `computeNsgTags`, default `{}` | Existing VNet, route table, shared NSG, reused NSGs, and subnet children are not retagged | 2.4; BYO exclusion |
| `brownfield-dns.bicep` / VNet links | Managed only in `vnet-link` mode | `privateDnsVnetLinkTags.<purpose>`, default `{}` per key | Existing DNS zones, records, private endpoints, and zone groups are not retagged; map must be empty in `zone-group` mode | 2.5; DNS-mode scenarios |
| Optional Bastion public IP and host | Blocked pending network foundation tasks T025 and T059-T063 | Planned `bastionPublicIpTags` and `bastionHostTags`, default `{}` | No implementation or completion claim until the optional Bastion contract is complete | 2.3 |

Accepted greenfield DNS keys are `cognitiveServices`, `azureOpenAI`, `apim`, `keyVault`,
`storageBlob`, `sql`, `cosmosDB`, and `aiSearch`. Brownfield DNS accepts only
`cognitiveServices`, `azureOpenAI`, `keyVault`, `storageBlob`, `cosmosDB`, and `aiSearch` in
`vnet-link` mode. Unknown keys fail with the affected parameter and rejected logical key.

## Foundry

| Entry point / resource | Ownership branch | Tag input and precedence | Unsupported or excluded surface | Tasks / scenarios |
|---|---|---|---|---|
| `foundry/main.bicep` / account | Managed account resource | `union(tags, foundryAccountTags)`, resource-specific value wins | Existing account is outside this entry point | 3.1 |
| `foundry/main.bicep` / project | Managed child resource | `union(tags, foundryProjectTags)`, resource-specific value wins | Project child APIs without independent tag support are not given synthetic inputs | 3.1, 3.6 |
| `foundry/supporting-resources.bicep` / Key Vault | Managed module | `union(tags, keyVaultTags)` | No tag input is applied to a referenced external vault | 3.2 |
| `foundry/storage.bicep` / Storage | Managed only when the Storage ID is empty | `union(tags, storageTags)` | Existing Storage is referenced without tags | 3.2 |
| `foundry/ai-search.bicep` / AI Search | Managed only when the Search ID is empty | `union(tags, aiSearchTags)` | Existing Search is referenced without tags | 3.2 |
| `foundry/cosmos-db.bicep` / Cosmos DB | Managed only when the Cosmos ID is empty | `union(tags, cosmosDBTags)` | Existing Cosmos is referenced without tags | 3.2 |
| `foundry/private-endpoint.bicep` / private endpoints | Managed only for created endpoints | `privateEndpointTags.<purpose>` layered over shared `tags`, default `{}` per key | Supplied or skipped BYO endpoints are not updated; zone groups are separate | 3.3 |
| `foundry-dns.bicep` / services.ai zone and VNet link | Managed only in `vnet-link` mode | `union(tags, servicesAiPrivateDnsZoneTags)` and `union(tags, servicesAiPrivateDnsVnetLinkTags)` | Existing zones and all `zone-group` resources are not retagged | 3.4 |

Accepted Foundry private-endpoint keys are `foundry`, `storage`, `keyVault`, `cosmosDB`, and
`aiSearch`. The shared `tags` object remains the compatibility base for all managed Foundry
resources.

## APIM

| Entry point / resource | Ownership branch | Tag input and precedence | Unsupported or excluded surface | Tasks / scenarios |
|---|---|---|---|---|
| `apim.bicep` / APIM service | Stage 1 managed resource | Existing `apimServiceTags`, default `{}` | Stage 2 references the Stage 1 service | 4.1, 4.3 |
| `apim.bicep` / public IP | Stage 1 managed resource | Existing `apimPublicIpTags`, with mandatory `ProjectCode: APIM` final precedence | No tag update through Stage 2 | 4.1, mandatory-tag scenario |
| `apim/private-dns.bicep` / zone and VNet link | Stage 1 managed only in blueprint DNS mode | Existing `privateDnsZoneTags` and `privateDnsVnetLinkTags` | External DNS mode and DNS records are not retagged | 4.1 |
| `apim/observability.bicep` / Application Insights, Log Analytics, alert | Stage 1 create/update branch | Existing `applicationInsightsTags`, `logAnalyticsWorkspaceTags`, and `capacityAlertTags`; existing workspace is reference-only | Diagnostic settings are an unsupported independent tag surface | 4.1, 4.3 |
| `apim-foundry-integration.bicep` / role assignments and APIM children | Stage 2 managed integration | No synthetic tag inputs | Role assignments, backends, named values, APIs, operations, products, bindings, and policies are unsupported unless a selected API explicitly exposes tags | 4.2 |

## Ownership and validation boundary

Operators must verify that each managed target is absent or already blueprint-owned in the
intended subscription, resource group, type, and name, and must prevent conflicting concurrent
deployments. ARM create-or-update behavior can still retag an undeclared resource occupying the
target identity; compilation and input checks do not prove live ownership or prevent races.

## Validation record

Completed offline checks include the network and Foundry regression suites, the APIM review
regressions, `OFFLINE_ONLY=true specs/02-apim-ai-gateway/validation/validate.sh all`, the
repository confidentiality scan, compilation of all affected Bicep entry points, sanitized
parameter compilation (including Stage 2 with explicit generic readiness inputs), and
`openspec validate add-blueprint-resource-tags --strict`. Existing Bicep linter warnings remain
for unrelated API-schema and interpolation diagnostics.

Approval-dependent Foundry what-if, runtime, live ownership verification, collision detection, and
concurrent-deployment evidence are **BLOCKED** until an authorized Azure environment and
deployment window are available. Offline compilation and input-contract checks do not establish
those live guarantees. Optional Bastion tagging remains blocked by network-foundation tasks T025
and T059-T063.
