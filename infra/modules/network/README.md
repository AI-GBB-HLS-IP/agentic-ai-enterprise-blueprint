# Network module (`infra/modules/network`)

This module provisions the Network Foundation MVP for the POC:

- VNet `vnet-agent-factory-poc` (`10.0.0.0/16` by default)
- 6 subnets:
  - `snet-apim` (`10.0.1.0/24`)
  - `snet-foundry` (`10.0.2.0/24`, delegated to `Microsoft.App/environments`)
  - `snet-compute` (`10.0.3.0/24`)
  - `snet-privateendpoints` (`10.0.4.0/24`)
  - `snet-cicd-agents` (`10.0.5.0/24`)
  - `AzureBastionSubnet` (`10.0.6.0/26`)
- NSGs for APIM and compute subnets
- Azure Bastion Basic host with the required Standard static public IP
- Private DNS zones + VNet links for:
  - `privatelink.cognitiveservices.azure.com`
  - `privatelink.openai.azure.com`
  - `privatelink.azure-api.net`
  - `privatelink.vaultcore.azure.net`
  - `privatelink.blob.core.windows.net`
  - `privatelink.database.windows.net`

## NSG rules for APIM VNet-injected mode (Research Q2)

`nsg-apim` includes the minimum baseline rules required for APIM control-plane connectivity:

- Allow inbound TCP `3443` from service tag `ApiManagement`
- Allow inbound from `AzureLoadBalancer`
- Allow outbound TCP `443` to `Internet`

`nsg-compute` enforces private-by-default egress:

- Allow outbound TCP `443` only to APIM subnet (`snet-apim`)
- Allow east-west virtual network traffic
- Deny direct outbound to `Internet`

> The Bastion public IP is the only public IP in this POC and is required by the Bastion service.

## Inputs

See `main.bicep` parameters:

- `location`
- `vnetName`, `vnetAddressSpace`
- subnet CIDR parameters
- `apimNsgName`, `computeNsgName`
- `privateDnsZoneNames`

## Outputs

- `vnetId`
- `subnetIds` object (`apim`, `foundry`, `compute`, `privateEndpoints`, `cicdAgents`, `bastion`)
- `nsgIds` object (`apim`, `compute`)
- `privateDnsZoneIds` object (all 6 DNS zones)
