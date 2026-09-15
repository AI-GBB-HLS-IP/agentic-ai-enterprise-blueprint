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

### Staged deployment (tenant Phase 2, then Phase 3)

Tenant Phase 2 runs `foundry.bicep`, which creates the account, project, dependent resources, and
bare private endpoints without private DNS zone groups. Tenant Phase 3 is the separate,
subsequent `foundry-dns.bicep` deployment, run only after Phase 2 succeeds (mirroring the
approved reference process's manual DNS-association step; see
`openspec/changes/foundry-staged-private-endpoint-deployment/design.md`). Run what-if and deploy
for each phase in order, reusing the same generic scripts:

```bash
# Tenant Phase 2: account/project/dependent resources/bare private endpoints
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/what-if.sh
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.bicepparam \
./scripts/foundry/deploy.sh --execute

# Tenant Phase 3: private DNS zone group association
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
`foundry-dns.bicepparam`, populate it with full private endpoint ARM resource IDs, and run Phase 3.
All five endpoint IDs may be empty to skip their associations; populate each ID that should receive a DNS zone group. The IDs may identify endpoints in other resource groups or subscriptions.

The `RG_NAME` value is the top-level deployment scope, not a constraint on endpoint location.
Phase 3 creates nested deployments at each endpoint resource group parsed from the supplied ID.
The deploying identity therefore needs deployment and private-endpoint child-resource write
permissions at every endpoint resource group. In cross-subscription `zone-group` mode it also
needs the separately granted central DNS-zone read/join permission; DNS RBAC and endpoint-scope
RBAC are distinct.

## Bitbucket adapter

Bitbucket can call the same scripts after `az login` or workload-identity setup:

```yaml
script:
  - ./scripts/foundry/preflight.sh
  - ./scripts/foundry/what-if.sh
```

The GitHub Actions workflow is another thin adapter around this contract.
