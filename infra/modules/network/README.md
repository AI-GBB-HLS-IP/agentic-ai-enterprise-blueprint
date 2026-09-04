# Network module (`infra/modules/network`)

This module provisions the Network Foundation MVP for the POC:

- VNet `vnet-agent-factory-poc` (`10.0.0.0/16` by default)
- 5 fixed workload subnets:
  - `snet-apim` (`10.0.1.0/24`)
  - `snet-foundry` (`10.0.2.0/24`, delegated to `Microsoft.App/environments`)
  - `snet-compute` (`10.0.3.0/24`)
  - `snet-privateendpoints` (`10.0.4.0/24`, private endpoint network policies disabled)
  - `snet-cicd-agents` (`10.0.5.0/24`)
- NSGs for APIM and compute subnets
- Private DNS zones + VNet links for:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.azure-api.net`
  - `privatelink.vaultcore.azure.net`
  - `privatelink.blob.core.windows.net`
  - `privatelink.database.windows.net`

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

`nsg-apim` includes the minimum baseline rules required for APIM control-plane connectivity:

- Allow inbound TCP `3443` from service tag `ApiManagement`
- Allow inbound from `AzureLoadBalancer`
- Allow outbound TCP `443` to `Internet`

`nsg-compute` enforces private-by-default egress:

- Allow outbound TCP `443` only to APIM subnet (`snet-apim`)
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
- `privateDnsZoneIds` object (all 6 DNS zones)
