# Prerequisite and scope checks (T008-T011)

Status date: 2026-08-23

## Result

| Gate | Purpose | Status | Notes |
|---|---|---|---|
| T008 | Validate existing RG/VNet/subnets/Foundry/model prerequisites | PASS | RG/VNet/subnets/Foundry/model deployment inspected via live Azure CLI |
| T009 | Validate `snet-apim` is unused, undelegated, NSG-preserved-ready | PASS | `delegations=[]`, `ipConfigurations=null`, NSG still bound, prefix `10.0.1.0/24` |
| T010 | Validate `privatelink.azure-api.net` separation from `azure-api.net` | PASS | Existing `privatelink.azure-api.net` confirmed; Chapter 02 creates separate `azure-api.net` |
| T011 | Resolve/record provider+prerequisite gate outcomes | PARTIAL | Provider/policy schema gate T006 remains manual |

## Offline evidence

- APIM module family and POC composition added under:
  - `infra/modules/apim/`
  - `infra/envs/poc/apim.bicep`
  - `infra/envs/poc/apim.bicepparam`
- Validation runner added at:
  - `specs/02-apim-ai-gateway/validation/validate.sh`
- Scope boundaries are encoded in module design:
  - no MCP/A2A resources declared
  - no public fallback endpoint declared
  - no API key backend auth declared
  - no Content Safety/semantic cache/secondary backend declared

## Executed live checks

```bash
./specs/02-apim-ai-gateway/validation/validate.sh
az network vnet subnet show -g rg-agent-factory-poc --vnet-name vnet-agent-factory-poc -n snet-apim --query '{delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id,addressPrefix:addressPrefix,ipConfigurations:ipConfigurations}'
az network private-dns zone list -g rg-agent-factory-poc --query "[?contains(name,'azure-api.net')].{name:name}" -o table
```

Observed outputs:

- `snet-apim`: prefix `10.0.1.0/24`, NSG `nsg-apim`, no delegations, no ip configurations.
- `snet-privateendpoints`: prefix `10.0.4.0/24`.
- Foundry account and `gpt-4.1-mini` deployment found in `eastus2`.
- Existing zone inventory includes `privatelink.azure-api.net`.
