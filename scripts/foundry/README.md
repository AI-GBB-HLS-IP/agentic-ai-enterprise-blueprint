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

`audit-byo-deployment.sh` is a **read-only**, fully standalone diagnostic for an already-deployed
BYO-VNet Foundry account/project -- it only runs `az`/`jq` commands against the live environment
and does not require a checkout of this repo (bicep paths in its hints are informational
references to the approved pattern, not files it reads). It does not apply to greenfield
deployments created end-to-end by `foundry.bicep` in this repo (those already satisfy every check
by construction); it targets customer environments deployed by hand, by a different tool, or
partially remediated out-of-band, where drift from the approved pattern is possible. This repo's
approved reference pattern always configures subnet delegation (`networkInjections` --
`infra/modules/foundry/main.bicep:146-153`); there is no supported private-endpoint-only
alternative topology, so the script fails an account that lacks it. Private endpoints are an
additional DNS/private-access mechanism that complements the required network-injected delegated
subnet, not a substitute for it -- the script still checks for them (and their DNS zone group
association) alongside the network-injection check, and uses the private endpoint's VNet purely
as a diagnostic fallback for the zone-link comparisons below when no subnet was found.

It checks every AIServices account/project it finds against the approved reference pattern in
`infra/modules/foundry/*.bicep` -- required connections, Capability Host state, the required RBAC
grants on the project's managed identity: Cosmos DB Operator (control-plane) on the Cosmos
account, Cosmos DB Built-in Data Contributor (data-plane) scoped separately to each of the three
project-workspace-prefixed containers (`thread-message-store`, `system-thread-message-store`,
`agent-entity-store`), AI Search Index Data Contributor + Search Service Contributor on the AI
Search service, and Storage Blob Data Contributor + scoped Storage Blob Data Owner on the storage
account -- plus private DNS zone VNet links, and -- for the Foundry
account itself plus each project's Cosmos DB/Storage/AI Search connections -- that each
resource's own private endpoint has a `privateDnsZoneGroups` association for the correct zone
(`infra/modules/foundry/private-endpoint-dns.bicep`). It prints a `PASS`/`WARN`/`FAIL` verdict
per check (with ✅/⚠️/❌ icons) and a pointer to the bicep module that encodes the expected state.

A zone being linked to the VNet only enables DNS *queries* from that VNet; the zone-group
association on each resource's private endpoint is what actually creates that resource's A
record. A missing zone-group association is a common root cause of the Agents-tab
"customer-managed downstream dependency returned an error" failure even when the zone itself is
present and correctly linked -- which is why both are checked separately.

Private DNS zones and private endpoints commonly live in a separate hub subscription/resource
group rather than the Foundry account's own RG. The script attempts to install and probe the
`resource-graph` az extension itself (a local CLI config change only -- it touches nothing in the
customer's Azure environment) so it can search every subscription you have access to for each
required zone and private endpoint, giving a definitive `PASS`/`FAIL` regardless of which
subscription they live in. If the extension can't be installed or used (including when an
organization's policy denies installing CLI extensions), the script prints the exact reason `az`
reported and continues in a degraded mode: those specific zone/private-endpoint checks report
`WARN` (manual verification needed) instead of `PASS`/`FAIL`, while every other check (RBAC,
connections, Capability Host) is unaffected.

Set `SKIP_EXTENSION_INSTALL=1` to opt out of the automatic `az extension add --name
resource-graph` attempt entirely -- useful behind restricted egress, in locked-down CI runners,
or anywhere auto-installing CLI extensions is undesirable. The script then goes straight to the
same degraded `WARN` mode described above instead of attempting the install, with a clear message
pointing to `az extension add --name resource-graph` if you want the stronger checks later.

```bash
# SUBSCRIPTION_ID accepts either a subscription GUID or display name.
SUBSCRIPTION_ID=<sub-id-or-name> ./scripts/foundry/audit-byo-deployment.sh

# Narrow to resource groups whose name contains a substring:
SUBSCRIPTION_ID=<sub-id-or-name> RG_FILTER=<resource-group-substring> ./scripts/foundry/audit-byo-deployment.sh

# Assert the hub/spoke VNet this deployment is supposed to be private-linked into. [1] then
# FAILs loudly if the account's actual VNet doesn't match, and [3]'s zone-link checks fall back
# to it when no VNet could be auto-detected at all (instead of defaulting every zone to WARN).
SUBSCRIPTION_ID=<sub-id-or-name> EXPECTED_VNET_ID=<vnet-resource-id> ./scripts/foundry/audit-byo-deployment.sh

# Skip the automatic "resource-graph" extension install (e.g. restricted egress or CI runners):
SUBSCRIPTION_ID=<sub-id-or-name> SKIP_EXTENSION_INSTALL=1 ./scripts/foundry/audit-byo-deployment.sh
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
