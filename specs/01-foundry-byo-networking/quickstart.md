# Quickstart Validation Guide

This guide validates the design after implementation without prescribing implementation
bodies. It assumes Azure CLI, Bicep CLI, subscription access, and a private test host in
`vnet-agent-factory-poc`.

## Prerequisites

1. Confirm the existing resource group, VNet, both named subnets, and required private DNS
   zones are present.
2. Obtain AI CoE approval for `modelName`, `modelVersion`, `modelFormat`, `deploymentSku`,
   and `deploymentCapacity`.
3. Confirm the selected region and model quota using the provider's live model/quota APIs.

## Validate the deployment preview

```bash
az bicep build --file infra/modules/foundry/main.bicep
az deployment group what-if \
  --resource-group rg-agent-factory-poc \
  --template-file infra/envs/poc/foundry.bicepparam
```

Expected: only declared Chapter 01 resources are created/updated; existing network and DNS
zones are read as prerequisites, with no public IPs or duplicate zones.

## Validate placement and network posture

Inspect the account, project, storage, Key Vault, optional SQL, and private endpoints:

```bash
az resource list -g rg-agent-factory-poc -o table
az cognitiveservices account show -g rg-agent-factory-poc -n <account> \
  --query '{location:location,publicNetworkAccess:properties.publicNetworkAccess,networkAcls:properties.networkAcls}'
az network private-endpoint-connection list -g rg-agent-factory-poc \
  --id <target-resource-id>
```

Expected: same region/resource group, account and dependencies deny public access, every
required connection is `Approved`, and every endpoint is in `snet-privateendpoints`.

## Validate subnet and DNS

```bash
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-foundry
az network vnet subnet show -g rg-agent-factory-poc \
  --vnet-name vnet-agent-factory-poc -n snet-privateendpoints
az network private-dns link vnet list -g rg-agent-factory-poc \
  -z <zone-name> -o table
```

From a private VNet host, resolve each service FQDN and confirm private addresses. Run the
implementation's utilization check and require less than 80% delegated-subnet utilization.

## Validate the model smoke test

Send one controlled request through the private Foundry endpoint using the approved deployment.
Record deployment name/model/version/SKU/capacity and response status. Repeat ten times when
the service is available; readiness requires at least 9 successful responses and no public route.

## Failure cases

The validation must fail with an affected resource and remediation hint for pending/rejected
PEs, missing DNS zone groups/links, public access enabled, placement mismatch, subnet
delegation/range mismatch, unavailable model/quota, or post-agent BYO VNet configuration.

