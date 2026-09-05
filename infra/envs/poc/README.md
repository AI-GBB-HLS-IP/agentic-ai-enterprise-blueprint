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

For the full ordered sequence, including validation gates, known deviations, and which steps are
not yet automated, follow
[`specs/00-network-foundation/RUNBOOK.md`](../../../specs/00-network-foundation/RUNBOOK.md).

## Validate before deploying

```bash
# FR-019/FR-020 policy inputs (keep the input file untracked)
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json

# Repository confidentiality gate
./scripts/network/scan-confidentiality.sh

# Deterministic validation suite
./tests/network/run-tests.sh
```

## Deploy

Resource-group topology is fully configurable, not fixed at three. Each template independently
accepts the resource group name(s) of the resources it depends on
(`networkResourceGroupName` on `foundry.bicep`/`apim.bicep`, `foundryResourceGroupName` on
`apim.bicep`), each defaulting to `resourceGroup().name` — i.e. "the RG I'm being deployed into."
That means the same three templates support any of these topologies (and combinations in between)
by choosing which RG name(s) you pass to `az group create`/`az deployment group create` and which
override params you set:

| Topology | RGs | How |
|---|---|---|
| Single RG | 1 | Deploy `main.bicep`, `foundry.bicep`, `apim.bicep` all into the same RG. Leave `networkResourceGroupName`/`foundryResourceGroupName` at their defaults. |
| Network isolated | 2 | Network in its own RG; Foundry + APIM share a second RG. Set `networkResourceGroupName` on both `foundry.bicepparam` and `apim.bicepparam` to the network RG name; deploy `foundry.bicep` and `apim.bicep` into the shared second RG (`foundryResourceGroupName` on apim defaults correctly since it equals apim's own RG). |
| Foundry isolated | 2 | Network + APIM share one RG; Foundry gets its own. Deploy `main.bicep` and `apim.bicep` into the shared RG (network default works); set `foundryResourceGroupName` on `apim.bicepparam` to the Foundry RG name, and `networkResourceGroupName` on `foundry.bicepparam` to the shared RG name. |
| Fully separated | 3 | Network, Foundry, and APIM each in their own RG (example below). Set both override params on `foundry.bicepparam`/`apim.bicepparam`. |

None of this requires touching the module code — only which RG name(s) you deploy each template
into and which of the two override params you set in the `.bicepparam` files. The example below
uses the fully-separated (3 RG) topology; adapt the RG names/count per the table above.

```bash
LOCATION="eastus2"
NETWORK_RG="rg-agent-blueprint-poc-network"
FOUNDRY_RG="rg-agent-blueprint-poc-foundry"
APIM_RG="rg-agent-blueprint-poc-apim"

az group create --name "$NETWORK_RG" --location "$LOCATION"
az group create --name "$FOUNDRY_RG" --location "$LOCATION"
az group create --name "$APIM_RG" --location "$LOCATION"

# 1. Network foundation
az deployment group what-if \
  --resource-group "$NETWORK_RG" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json

az deployment group create \
  --resource-group "$NETWORK_RG" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json

# 2. Foundry (references the network RG's vnet/subnets/DNS zones)
az deployment group what-if \
  --resource-group "$FOUNDRY_RG" \
  --template-file infra/envs/poc/foundry.bicep \
  --parameters infra/envs/poc/foundry.bicepparam

az deployment group create \
  --resource-group "$FOUNDRY_RG" \
  --template-file infra/envs/poc/foundry.bicep \
  --parameters infra/envs/poc/foundry.bicepparam

# 3. APIM (references the network RG's vnet/subnet and the Foundry RG's account)
az deployment group what-if \
  --resource-group "$APIM_RG" \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam

az deployment group create \
  --resource-group "$APIM_RG" \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

## Verify

```bash
az network vnet subnet list \
  --resource-group "$NETWORK_RG" \
  --vnet-name vnet-agent-factory-poc \
  --query "[].{name:name,prefix:addressPrefix,delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id}" \
  --output table

az network private-dns zone list \
  --resource-group "$NETWORK_RG" \
  --query "[].name" \
  --output table

# Private-by-default check: expect no public IP unless Bastion is intentionally enabled
az network public-ip list --resource-group "$NETWORK_RG" --query "[].name" --output table
```

## Bastion validation

Azure Bastion is **optional and disabled by default** in the approved design. When it is disabled,
the deployment must contain no `AzureBastionSubnet`, no Bastion host, and no public IP, and this
section does not apply.

> **Current deviation**: `main.bicep` still deploys Bastion unconditionally and exposes no
> `deployBastion` parameter. Making Bastion conditional is tracked by tasks T025 and T059-T063.

When Bastion is intentionally enabled, the deployment includes an Azure Bastion Basic host and its
required Standard static public IP.
For a full interactive Bastion validation, create a temporary test VM without a public IP in
`hybridsubnet-privateendpoints`, connect through the Azure Portal, and run `nslookup` for a private
endpoint record. Delete the test VM and its NIC/disk after validation.

The Basic SKU supports portal-based Bastion access but does not support the Azure CLI native-client
or tunnel commands. Use Standard or Premium if CLI/SSH tunnel validation is required. For a
non-interactive DNS-only check, Azure Run Command can execute `nslookup` inside the private VM:

```bash
az vm run-command invoke \
  --resource-group "$NETWORK_RG" \
  --name vm-dns-test \
  --command-id RunShellScript \
  --scripts 'nslookup validation-endpoint.privatelink.openai.azure.com'
```

The validation record is temporary and must be removed with:

```bash
az network private-dns record-set a delete \
  --resource-group "$NETWORK_RG" \
  --zone-name privatelink.openai.azure.com \
  --name validation-endpoint \
  --yes
```

Remove the temporary VM and attached resources after validation:

```bash
VM_NAME="vm-dns-test"
NIC_ID="$(az vm show --resource-group "$NETWORK_RG" --name "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv)"
NIC_NAME="${NIC_ID##*/}"
DISK_NAME="$(az vm show --resource-group "$NETWORK_RG" --name "$VM_NAME" \
  --query 'storageProfile.osDisk.name' -o tsv)"

az vm delete --resource-group "$NETWORK_RG" --name "$VM_NAME" --yes
az network nic delete --resource-group "$NETWORK_RG" --name "$NIC_NAME"
az disk delete --resource-group "$NETWORK_RG" --name "$DISK_NAME" --yes
```

- Parameters are in `network.parameters.json`; update `location` and names as needed.
- Azure `what-if` may report platform-generated Bastion `dnsName`/`publicUri` fields as modified;
  these are read-only service properties and are expected false positives.
