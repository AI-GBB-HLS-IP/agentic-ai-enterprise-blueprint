# Provider-neutral Foundry automation

These scripts contain the shared Azure deployment contract. They do not depend on GitHub,
Bitbucket, or a specific portal. CI systems should authenticate to Azure and invoke these scripts.

## Preflight

```bash
RG_NAME=rg-agent-factory-poc \
VNET_NAME=vnet-agent-factory-poc \
LOCATION=eastus2 \
MODEL_FORMAT=OpenAI \
MODEL_NAME=gpt-4.1-mini \
DEPLOYMENT_SKU=Standard \
REQUESTED_CAPACITY=10 \
./scripts/foundry/preflight.sh
```

Preflight is read-only. It validates the existing network foundation and model quota.

## What-if

```bash
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/what-if.sh
```

What-if is read-only and must pass before deployment.

## Deployment

Deployment requires the explicit `--execute` flag:

```bash
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/deploy.sh --execute
```

Authentication, approval, and environment protection are owned by the caller. These scripts
never contain credentials and do not infer a subscription; Azure CLI's active subscription must
be selected by the caller.

### Two-phase deployment (private endpoints, then DNS zone groups)

`foundry.bicep` creates the account, project, dependent resources, and bare private endpoints in
one deployment. Private DNS zone group association is a separate, subsequent deployment against
`foundry-dns.bicep`, run after the first deployment succeeds (mirroring the approved reference
template's own manual DNS-association step; see
`openspec/changes/foundry-staged-private-endpoint-deployment/design.md`). Run what-if and deploy
for each phase in order, reusing the same generic scripts:

```bash
# Phase 1: account/project/dependent-resources/private-endpoints
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/what-if.sh
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/deploy.sh --execute

# Phase 2: private DNS zone group association (same resource group)
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry-dns.bicep \
PARAMETER_FILE=infra/envs/poc/foundry-dns.bicepparam \
./scripts/foundry/what-if.sh
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry-dns.bicep \
PARAMETER_FILE=infra/envs/poc/foundry-dns.bicepparam \
./scripts/foundry/deploy.sh --execute
```

Copy `infra/envs/poc/foundry-dns.bicepparam.example` to a local, untracked
`foundry-dns.bicepparam` and fill in the private endpoint names output by phase 1 before running
phase 2.

## Bitbucket adapter

Bitbucket can call the same scripts after `az login` or workload-identity setup:

```yaml
script:
  - ./scripts/foundry/preflight.sh
  - ./scripts/foundry/what-if.sh
```

The GitHub Actions workflow is another thin adapter around this contract.
