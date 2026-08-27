# US1 gateway posture evidence (T018)

Status: **PASS**

Validation date: 2026-08-27

## Live result

```text
APIM SKU: Premium, capacity 1
Virtual network type: Internal
Subnet: vnet-agent-factory-poc/snet-apim
Subnet address prefix: 10.0.1.0/24
Subnet delegation: none
Subnet NSG: nsg-apim
Public gateway IP addresses: none
```

The deployed gateway uses classic Premium internal VNet injection and preserves the dedicated
subnet and NSG. No public gateway IP address is published.

## Reproduction commands

```bash
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-apim \
  --query '{delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id,addressPrefix:addressPrefix}'

az apim show -g rg-agent-factory-poc -n apim-agent-factory-private-poc \
  --query '{sku:sku.name,capacity:sku.capacity,virtualNetworkType:virtualNetworkType,publicIpAddresses:publicIPAddresses,subnetId:virtualNetworkConfiguration.subnetResourceId}'
```

## Pass criteria

- APIM SKU is classic Premium (`Premium`)
- No v2-specific subnet delegation is configured
- APIM `virtualNetworkType` is `Internal`
- Public endpoint IP list is empty
- Subnet ID equals `snet-apim`
