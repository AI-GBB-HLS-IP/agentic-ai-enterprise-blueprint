# POC environment deployment (`infra/envs/poc`)

This environment composes the Network Foundation MVP module.

## Prerequisites

- Azure CLI (`az`) with Bicep support
- Active Azure login (`az login`)
- Subscription selected (`az account set --subscription <SUBSCRIPTION_ID>`)
- Subscription permissions: Owner, or Contributor plus User Access Administrator (UAA is needed for
  role assignments, not for creating the network resources themselves). For deployment via
  `az deployment group create`, the deploying identity must have `Microsoft.Resources/deployments/*`
  permissions (included in Contributor/Owner).
- Entra ID permission to create security groups, or a tenant administrator (e.g., Global/Groups/User
  Administrator, per tenant policy) who can create the `platform-eng`, `ai-coe`, and `developers`
  groups before downstream RBAC work.

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
For a full interactive Bastion validation, create a temporary test VM without a public IP in
`snet-privateendpoints`, connect through the Azure Portal, and run `nslookup` for a private
endpoint record. Delete the test VM and its NIC/disk after validation.

The Basic SKU supports portal-based Bastion access but does not support the Azure CLI native-client
or tunnel commands. Use Standard or Premium if CLI/SSH tunnel validation is required. For a
non-interactive DNS-only check, Azure Run Command can execute `nslookup` inside the private VM:

```bash
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name vm-dns-test \
  --command-id RunShellScript \
  --scripts 'nslookup validation-endpoint.privatelink.openai.azure.com'
```

The validation record is temporary and must be removed with:

```bash
az network private-dns record-set a delete \
  --resource-group "$RG_NAME" \
  --zone-name privatelink.openai.azure.com \
  --name validation-endpoint \
  --yes
```

Remove the temporary VM and attached resources after validation:

```bash
VM_NAME="vm-dns-test"
NIC_ID="$(az vm show --resource-group "$RG_NAME" --name "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv)"
NIC_NAME="${NIC_ID##*/}"
DISK_NAME="$(az vm show --resource-group "$RG_NAME" --name "$VM_NAME" \
  --query 'storageProfile.osDisk.name' -o tsv)"

az vm delete --resource-group "$RG_NAME" --name "$VM_NAME" --yes
az network nic delete --resource-group "$RG_NAME" --name "$NIC_NAME"
az disk delete --resource-group "$RG_NAME" --name "$DISK_NAME" --yes
```

- Parameters are in `network.parameters.json`; update `location` and names as needed.
- Azure `what-if` may report platform-generated Bastion `dnsName`/`publicUri` fields as modified;
  these are read-only service properties and are expected false positives.
