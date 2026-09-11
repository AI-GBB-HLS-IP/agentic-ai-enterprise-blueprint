# Change: Cross-subscription DNS zone-group mode + real APIM subnet sizing

## Status
Ready to implement. Spec approved in PR #62 (merged into `specs/00-network-foundation/spec.md`,
`data-model.md`, `contracts/deployment-parameters.md`, `tasks.md`). **Re-sized 2026-09-10** after
confirming the real APIM platform version is `stv2` (see below) — the block moved from `/26` to
`/25` and APIM's subnet minimum moved from `/29` to `/27`.

## Problem
Live discovery against a real brownfield target (`<SUBSCRIPTION_ALIAS>` / `<VNET_NAME>`) found two gaps
between the spec's original assumptions and reality:

1. Centrally owned Private DNS zones live in a **different subscription** than the target VNet,
   and the DNS owner uses **per-private-endpoint DNS zone groups**, not VNet-level links. Zero
   VNet links exist on any zone we checked. The blueprint's Bicep only supports same-subscription
   `existing` zone references today.
2. APIM VNet injection (already correctly implemented in `apim/main.bicep`) needs a realistic
   `/27` subnet, not the `/28`/`/29` the generator script and docs assume. Confirmed via
   `az apim show --query platformVersion` against **two separate, independently checked
   Premium-tier instances** (one in the customer's environment, one in a private validation
   environment): both run on the **`stv2`** compute platform, whose hard, ARM-enforced subnet
   minimum is `/27` — not the `/29` a prior, never-actually-verified assumption about
   `<apim-example-instance>` (Developer tier) had implied. "Classic Premium" tier name and
   `stv1`/`stv2` platform version are independent axes; a classic-tier instance can (and, per
   both checked instances, does) run on `stv2` infrastructure.

## What changes

- `infra/envs/poc/foundry.bicep`: replace same-subscription-only `existing` Private DNS zone
  declarations with zone IDs built via `resourceId(dnsSubscriptionId, dnsResourceGroupName,
  'Microsoft.Network/privateDnsZones', zoneName)` (four-arg cross-subscription form —
  `subscriptionResourceId()` does NOT work here, it omits the resource-group segment that
  private DNS zones require), gated by a new `dnsIntegrationMode` param
  (`vnet-link` | `zone-group`). No `existing` zone resource needed in `zone-group` mode.
- `infra/envs/poc/brownfield-dns.bicep`: make this template's VNet-link creation conditional /
  skippable entirely when `dnsIntegrationMode == 'zone-group'` (no DNS-owner-scoped resource is
  created in that mode).
- `scripts/network/generate-brownfield-params.sh`:
  - add `--dns-integration-mode`, `--dns-subscription-id` flags
  - raise `RECOMMENDED_BLOCK_PREFIX`/`MIN_VIABLE_BLOCK_PREFIX`/`MAX_BLOCK_PREFIX` from `/26` to
    `/25` and change the split to: `foundry /27` + `apim /27` + `privateEndpoints /28` +
    `compute+cicdAgents /28` (merged), replacing both the old four-equal-`/29` split and the
    intermediate `/26`-based `/27+/28+/29+/29` split (both assumed `stv1`; the real, verified
    platform is `stv2`, which needs `/27` for APIM, not `/28`/`/29`)
  - update `MINIMUM_PREFIX = {"foundry": 27, "apim": 29}` to `{"foundry": 27, "apim": 27}`
  - drop `privatelink.azure-api.net` from the required-zone list when APIM uses VNet injection
  - when allocating a replacement private-endpoint subnet, emit the matching
    `privateEndpointSubnetName` in the git-ignored `brownfield-foundry.bicepparam` so Foundry
    uses the new subnet without overwriting the tracked greenfield example
- `docs/deploy-00-network.md`: replace the "Known limitation" callout with the actual new
  behavior once implemented; document the new CLI flags.
- `tests/network/test-generate-brownfield-params.sh`: update/add regression tests for the new
  split and flags.

## Out of scope (do not do in this change)
- Re-scoping/rewriting T048-T057 in `tasks.md` wholesale (only the two touched scripts above).
- `vnet-link` mode changes — it already works; only add the `zone-group` branch.
- Requesting more address space from the network team **for the POC** — POC proceeds within the
  confirmed `/25` that the customer already handed over. (Production is a separate, later
  request for a larger allocation and is explicitly out of scope for this POC-sizing change.)

## Reference (read before starting)
- `specs/00-network-foundation/spec.md` — Session 2026-09-10 clarifications, FR-016/FR-016a/FR-016b
- `docs/deploy-00-network.md` — "Minimum viable block" section + its Known limitation callout
- Confirmed target CIDR plan (see below)

## Pre-implementation check — RESOLVED 2026-09-10

APIM platform version is confirmed **`stv2`**, checked directly (not inferred):

```
az apim show -n <apim-example-instance> -g <resource-group> \
  --query "{sku:sku.name, platformVersion:platformVersion}" -o table
# -> Premium, stv2
```

Checked against two separate, independently owned Premium-tier instances (the customer's real
environment and a private validation environment); both returned `stv2`.

The earlier `/28`/`/29` sizing was based on an unverified assumption about
`<apim-example-instance>` (Developer tier) that was never actually queried. With `stv2`
confirmed, APIM's hard subnet minimum is `/27` (ARM-enforced — deployment fails below this, per
Microsoft Learn's virtual-network-concepts subnet-size-requirements). Foundry's agent subnet
minimum is also `/27`. Both minimums together consume exactly `/26` of address space, which is
why the block moved from `/26` to `/25` (see target CIDR plan below).

## Acceptance criteria
- [ ] `generate-brownfield-params.sh --block-size 25` against the real discovery file produces
      exactly: `foundry /27`, `apim /27`, `privateEndpoints /28`, `compute+cicdAgents /28`
      (merged), with 32 addresses spare.
- [ ] Generated `brownfield-foundry.bicepparam` sets `privateEndpointSubnetName` to the replacement
      private-endpoint subnet name whenever that subnet is allocated.
- [ ] Generated `brownfield-foundry.bicepparam`/`brownfield-dns.bicepparam` support a cross-subscription
      `dnsSubscriptionId` distinct from the workload subscription.
- [ ] `privatelink.azure-api.net` is no longer requested/required when APIM uses VNet injection.
- [ ] All existing tests in `tests/network/` still pass; new tests cover the above.
- [ ] `docs/deploy-00-network.md` no longer contains the "Known limitation" callout — it
      describes actual behavior.

## Example target CIDR plan (<VNET_NAME>, free `/25` = `10.0.2.128/25`)

Existing `hybridsubnet-privateendpoints` (`10.0.1.136/29`) already hosts Key Vault + Storage
private endpoints and is left untouched outside the target block. Subnet names follow the
`hybridsubnet-<purpose>` convention already used in the reference environment.

| Purpose | Subnet name | CIDR | Total | Usable |
|---|---|---|---|---|
| Foundry agent | `hybridsubnet-foundry` | `10.0.2.128/27` | 32 | 27 |
| APIM VNet injection | `hybridsubnet-apim` | `10.0.2.160/27` | 32 | 27 |
| Private endpoints (new, if needed beyond `hybridsubnet-privateendpoints`) | `hybridsubnet-privateendpoints-2` | `10.0.2.192/28` | 16 | 11 |
| Compute + CI/CD agents (merged) | `hybridsubnet-compute` | `10.0.2.208/28` | 16 | 11 |
| spare/reserved | — | `10.0.2.224/27` | 32 | — |
