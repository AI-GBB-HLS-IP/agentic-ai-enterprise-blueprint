# Network module (`infra/modules/network`)

This module provisions the Network Foundation MVP for the POC:

- VNet `vnet-agent-factory-poc` (`10.0.0.0/16` by default)
- 5 fixed workload subnets (named after the customer's VPCx `hybridsubnet-*` convention — these
  are internal-only subnets; there is no `dmzsubnet-*` yet since nothing in this POC is
  internet-facing):
  - `hybridsubnet-apim` (`10.0.1.0/24`)
  - `hybridsubnet-foundry` (`10.0.2.0/24`, delegated to `Microsoft.App/environments`)
  - `hybridsubnet-compute` (`10.0.3.0/24`)
  - `hybridsubnet-privateendpoints` (`10.0.4.0/24`, private endpoint network policies disabled)
  - `hybridsubnet-cicdagents` (`10.0.5.0/24`)
- NSGs for APIM and compute subnets, named after the customer's VPCx
  `hybrid-nsg-{subscription_name}-{region}` convention (one NSG per subnet purpose, since APIM and
  compute have distinct rule sets)
- Private DNS zones + VNet links for:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.azure-api.net`
  - `privatelink.vaultcore.azure.net`
  - `privatelink.blob.core.windows.net`
  - `privatelink.database.windows.net`
  - `privatelink.documents.azure.com` (Cosmos DB — required by the Foundry Agent Service's thread
    storage whenever the capability host is enabled)
  - `privatelink.search.windows.net` (AI Search — required by the Foundry Agent Service's
    vector-store connection whenever the capability host is enabled)

Subnet sizes above are the **fixed greenfield recommendation** (fixed per FR-002/FR-013a) and MUST NOT be
resized. Brownfield mode reuses the same purpose keys and DNS zone list but sizes each subnet to
what the admin-allocated existing VNet actually supports; see the worked brownfield example below.

## Foundry delegated subnet sizing (greenfield vs. brownfield POC)

Per Microsoft's [Foundry Agent Service networking guidance](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive),
subnet delegation is configured once at the **Foundry account level** and shared by every project
under that account — a project never needs its own delegated subnet. Recommended sizing:

| Size | Usable IPs | Max concurrent agent sessions (approx; per Microsoft guidance) | Use |
|---|---|---|---|
| `/27` | ~27 | ~17 | Documented technical minimum; very little headroom |
| `/26` | ~59 | ~50 | Blueprint POC recommendation; used when the admin-allocated VNet is too small for `/24` |
| `/24` | ~251 | absorbs platform upgrade/scaling spikes | **Microsoft's production recommendation** |

**Worked example** — brownfield POC constrained to an admin-allocated `/25` VNet (128 addresses,
too small to fit the `/24` production recommendation). All 5 purpose-keyed subnets fit as an exact,
CIDR-aligned allocation (illustrative CIDRs; real values remain customer-approved per FR-013):

| Purpose key | Relative CIDR | Size | Usable IPs |
|---|---|---|---|
| `foundry` | `.0/26` | 64 | 59 |
| `apim` | `.64/28` | 16 | 11 |
| `privateEndpoints` | `.80/28` | 16 | 11 |
| `compute` | `.96/28` | 16 | 11 |
| `cicdAgents` | `.112/28` | 16 | 11 |

This caps the POC at ~50 concurrent agent sessions (~47 at the recommended 80% utilization
target) — an explicit, documented capacity trade-off versus Microsoft's `/24` production sizing,
not a silent default. See `specs/00-network-foundation/spec.md` FR-013c–FR-013e for the full
sizing gate and `contracts/deployment-parameters.md` for the parameter contract.


## Optional Bastion

Per [`specs/00-network-foundation/spec.md`](../../../specs/00-network-foundation/spec.md), Azure
Bastion is **optional and disabled by default** in both greenfield and brownfield modes. When it is
disabled, the deployment must create no `AzureBastionSubnet`, no Bastion host, and no public IP.
When it is explicitly enabled, `AzureBastionSubnet` (`10.0.6.0/26`, `/26` minimum) plus the Bastion
host and its required Standard static public IP are created, and that public IP is the only
permitted public IP in the blueprint.

> **Current deviation**: this module still creates `AzureBastionSubnet` unconditionally, and
> `infra/envs/poc/main.bicep` always deploys the Bastion module. Making Bastion fully conditional
> is tracked by tasks T005 and T059-T063. See
> [`specs/00-network-foundation/RUNBOOK.md`](../../../specs/00-network-foundation/RUNBOOK.md).

## NSG rules for APIM VNet-injected mode (Research Q2)

`apimNsgName` (APIM subnet NSG) includes the minimum baseline rules required for APIM
control-plane connectivity:

- Allow inbound TCP `3443` from service tag `ApiManagement`
- Allow inbound from `AzureLoadBalancer`
- Allow outbound TCP `443` to `Internet`

`hybrid-nsg-agent-blueprint-eastus2-compute` enforces private-by-default egress:

- Allow outbound TCP `443` only to APIM subnet (`hybridsubnet-apim`)
- Allow east-west virtual network traffic
- Deny direct outbound to `Internet`

> When Bastion is enabled, its public IP is the only public IP in this POC and is required by the
> Bastion service. When Bastion is disabled, the deployment contains no public IP at all.

## Inputs

See `main.bicep` parameters:

- `location`
- `vnetName`, `vnetAddressSpace`
- subnet CIDR parameters
- `apimNsgName`, `computeNsgName`
- `privateDnsZoneNames`

## Outputs

- `vnetId`
- `subnetIds` object (`apim`, `foundry`, `compute`, `privateEndpoints`, `cicdAgents`, and `bastion`
  when Bastion is enabled)
- `nsgIds` object (`apim`, `compute`)
- `privateDnsZoneIds` object (all 8 DNS zones)
