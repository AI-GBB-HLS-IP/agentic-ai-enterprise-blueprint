# US1 gateway posture evidence (T018)

Status: **BLOCKED (live Azure gate unresolved)**

## Live checks to capture

```bash
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-apim \
  --query '{delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id,addressPrefix:addressPrefix}'

az apim show -g rg-agent-factory-poc -n apim-agent-factory-poc \
  --query '{sku:sku.name,capacity:sku.capacity,virtualNetworkType:virtualNetworkType,publicIpAddresses:publicIPAddresses,subnetId:virtualNetworkConfiguration.subnetResourceId}'
```

## Pass criteria

- Delegation includes `Microsoft.Web/serverFarms`
- APIM SKU is Premium v2 (`PremiumV2`)
- APIM `virtualNetworkType` is `Internal`
- Public endpoint IP list is empty
- Subnet ID equals `snet-apim`
