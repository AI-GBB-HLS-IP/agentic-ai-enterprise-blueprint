# POC environment deployment (`infra/envs/poc`)

This environment composes the Network Foundation MVP module.

## Prerequisites

- Azure CLI (`az`) with Bicep support
- Active Azure login (`az login`)
- Subscription selected (`az account set --subscription <SUBSCRIPTION_ID>`)
- Subscription permissions: Owner, or Contributor plus User Access Administrator; Network
  Contributor is sufficient when scoped to the target resource group for network resources.
- Entra ID permission to create security groups, or a tenant administrator/group owner who can
  create the `platform-eng`, `ai-coe`, and `developers` groups before downstream RBAC work.

Run the documented preflight checks in `specs/00-network-foundation/spec.md` before deployment.

## Deploy

```bash
RG_NAME="rg-agent-factory-poc"
LOCATION="eastus2"

az group create --name "$RG_NAME" --location "$LOCATION"

az deployment group what-if \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json

az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json
```

## Verify

```bash
az network vnet subnet list \
  --resource-group "$RG_NAME" \
  --vnet-name vnet-agent-factory-poc \
  --query "[].{name:name,prefix:addressPrefix,delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id}" \
  --output table

az network private-dns zone list \
  --resource-group "$RG_NAME" \
  --query "[].name" \
  --output table
```

## Bastion validation

The deployment includes an Azure Bastion Basic host and its required Standard static public IP.
Create a temporary test VM without a public IP in `snet-privateendpoints`, connect through Bastion, and
run `nslookup` for a private endpoint record. Delete the test VM after validation.

- Parameters are in `network.parameters.json`; update `location` and names as needed.
- Azure `what-if` may report platform-generated Bastion `dnsName`/`publicUri` fields as modified;
  these are read-only service properties and are expected false positives.
