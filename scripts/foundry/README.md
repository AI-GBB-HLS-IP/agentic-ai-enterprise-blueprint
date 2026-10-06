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
cp infra/envs/poc/foundry.bicepparam.example \
   infra/envs/poc/foundry.customer.bicepparam

RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.customer.bicepparam \
./scripts/foundry/what-if.sh
```

What-if is read-only and must pass before deployment.

## Deployment

Deployment requires the explicit `--execute` flag:

```bash
cp infra/envs/poc/foundry.bicepparam.example \
   infra/envs/poc/foundry.customer.bicepparam

RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.customer.bicepparam \
./scripts/foundry/deploy.sh --execute
```

Authentication, approval, and environment protection are owned by the caller. These scripts
never contain credentials and do not infer a subscription; Azure CLI's active subscription must
be selected by the caller.

### Account/project only, no model deployment

`enableModelDeployment` defaults to `false` in `foundry.bicep` itself, but
`foundry.customer.bicepparam` reads it from `FOUNDRY_ENABLE_MODEL_DEPLOYMENT`, which defaults to
`'true'`. To deploy only the account, project, dependent resources, and bare private endpoints
(no model deployment), set it explicitly:

```bash
FOUNDRY_ENABLE_MODEL_DEPLOYMENT=false \
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.customer.bicepparam \
./scripts/foundry/deploy.sh --execute
```

## Purge leftovers

If a prior deployment failed partway (or was deleted) and a retry with the same account/Key
Vault name fails, there are two kinds of leftovers that can block recreation:

- A **live** Cognitive Services account in the terminal `Failed` provisioning state from a
  partial create. With `--execute`, only this state is eligible for deletion; transient states
  such as `Creating`, `Updating`, or `Deleting`, and unknown states, are reported and left in place.
- A **soft-deleted** copy of the account and/or Key Vault, which Azure creates on delete
  (including the delete step below) and which blocks recreation with the same name until purged.

`purge.sh` checks both, in order (live account first, then soft-deleted account, then
soft-deleted Key Vault), lists/reports findings by default, and only deletes/purges with
`--execute`:

```bash
# Dry run (list/report only)
LOCATION=eastus \
RG_NAME=rg-agent-factory-poc \
FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc \
FOUNDRY_KEY_VAULT_NAME=kv-agent-factory-poc \
./scripts/foundry/purge.sh

# Delete/purge after reviewing the findings above
LOCATION=eastus \
RG_NAME=rg-agent-factory-poc \
FOUNDRY_ACCOUNT_NAME=foundry-agent-factory-poc \
FOUNDRY_KEY_VAULT_NAME=kv-agent-factory-poc \
./scripts/foundry/purge.sh --execute
```

Deleting a live Failed-state account typically soft-deletes it; re-run the script (or run it
again with `--execute`) to purge that soft-deleted copy as well. Before purging, review any
governance/retention tags (e.g. an extended-delete-by tag) on the reported resource — a purge may
be denied by policy, which is a separate remediation path (request a retention exception) rather
than a script issue.

`FOUNDRY_KEY_VAULT_NAME` is optional; omit it to only check/purge the Cognitive Services account.
`LOCATION` must match the region the failed resources were created in, and `RG_NAME` must match
their original resource group (Cognitive Services purge is resource-group-scoped even though the
soft-deleted resource no longer appears in that group).

### Staged deployment (tenant Phase 2, then Phase 3)

Tenant Phase 2 runs `foundry.bicep`, which creates the account, project, dependent resources, and
bare private endpoints without private DNS zone groups. Tenant Phase 3 is the separate,
subsequent `foundry-dns.bicep` deployment, run only after Phase 2 succeeds (mirroring the
approved reference process's manual DNS-association step; see
`openspec/changes/foundry-staged-private-endpoint-deployment/design.md`). Run what-if and deploy
for each phase in order, reusing the same generic scripts:

```bash
# Tenant Phase 2: account/project/dependent resources/bare private endpoints
cp infra/envs/poc/foundry.bicepparam.example \
   infra/envs/poc/foundry.customer.bicepparam

RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.customer.bicepparam \
./scripts/foundry/what-if.sh
RG_NAME=rg-agent-factory-poc \
TEMPLATE_FILE=infra/envs/poc/foundry.bicep \
PARAMETER_FILE=infra/envs/poc/foundry.customer.bicepparam \
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

## BYO deployment audit

`audit-byo-deployment.sh` is a **read-only** diagnostic for an already-deployed, network-injected
(BYO-VNet) Foundry account/project. It does not apply to greenfield deployments created
end-to-end by `foundry.bicep` in this repo (those already satisfy every check by construction);
it targets customer environments deployed by hand, by a different tool, or partially remediated
out-of-band, where drift from the approved pattern is possible.

It checks every AIServices account/project it finds against the approved reference pattern in
`infra/modules/foundry/*.bicep` -- required connections, Capability Host state, the five required
RBAC grants on the project's managed identity (Cosmos DB Operator, Cosmos DB Data Contributor on
`enterprise_memory`, AI Search Index Data Contributor + Search Service Contributor, Storage Blob
Data Contributor + scoped Data Owner), and private DNS zone links -- and prints a `PASS`/`WARN`/
`FAIL` verdict per check with a pointer to the bicep module that encodes the expected state.

Private DNS zones commonly live in a separate hub subscription/resource group rather than the
Foundry account's own RG. With the `resource-graph` az extension installed
(`az extension add --name resource-graph`), the script searches every subscription you have
access to for each required zone and verifies it's actually linked to the account's injected
VNet, giving a definitive `PASS`/`FAIL` regardless of which subscription the zone lives in.
Without that extension, zone checks are limited to the account's own RG and report `WARN`
instead of `FAIL` when a zone isn't found there (since that doesn't prove it's missing elsewhere).

```bash
# SUBSCRIPTION_ID accepts either a subscription GUID or display name.
SUBSCRIPTION_ID=<sub-id-or-name> ./scripts/foundry/audit-byo-deployment.sh

# Narrow to resource groups whose name contains a substring:
SUBSCRIPTION_ID=<sub-id-or-name> RG_FILTER=<resource-group-substring> ./scripts/foundry/audit-byo-deployment.sh
```

Exits non-zero if any check reports `FAIL`. `WARN` findings (e.g. DNS zone checks running
without the `resource-graph` extension) need human judgement and do not fail the run.

## Bitbucket adapter

Bitbucket can call the same scripts after `az login` or workload-identity setup:

```yaml
script:
  - ./scripts/foundry/preflight.sh
  - ./scripts/foundry/what-if.sh
```

The GitHub Actions workflow is another thin adapter around this contract.
