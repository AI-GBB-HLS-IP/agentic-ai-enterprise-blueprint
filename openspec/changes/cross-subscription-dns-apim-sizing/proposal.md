# Change: Cross-subscription DNS zone-group mode + real APIM subnet sizing

## Status
In review. Once the spec changes are merged, this change is ready to implement.

## Problem
Live discovery against a real brownfield target (`<SUBSCRIPTION_ALIAS>` / `<VNET_NAME>`) found two gaps
between the spec's original assumptions and reality:

1. Centrally owned Private DNS zones live in a **different subscription** than the target VNet,
   and the DNS owner uses **per-private-endpoint DNS zone groups**, not VNet-level links. Zero
   VNet links exist on any zone we checked. The blueprint's Bicep only supports same-subscription
   `existing` zone references today.
2. APIM VNet injection (already correctly implemented in `apim/main.bicep`) needs a realistic
   `/28` subnet, not the `/29` the generator script and docs assume — confirmed against a real
   production instance using 9 addresses (more than a `/29`'s 8 total).

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
  - change the `/26` block split: `foundry /27` + `apim /28` + `privateEndpoints /29` +
    `compute+cicdAgents /29` (merged), replacing the current four-equal-`/29` split
  - drop `privatelink.azure-api.net` from the required-zone list when APIM uses VNet injection
- `docs/deploy-00-network.md`: replace the "Known limitation" callout with the actual new
  behavior once implemented; document the new CLI flags.
- `tests/network/test-generate-brownfield-params.sh`: update/add regression tests for the new
  split and flags.

## Out of scope (do not do in this change)
- Re-scoping/rewriting T048-T057 in `tasks.md` wholesale (only the two touched scripts above).
- `vnet-link` mode changes — it already works; only add the `zone-group` branch.
- stv2 APIM support — classic tier (Developer/Premium) only, per the confirmed POC profile.
- Requesting more address space from the network team — POC proceeds within the confirmed `/26`.

## Reference (read before starting)
- `specs/00-network-foundation/spec.md` — Session 2026-09-10 clarifications, FR-016/FR-016a/FR-016b
- `docs/deploy-00-network.md` — "Minimum viable block: /26" section + its Known limitation callout
- Confirmed target CIDR plan (see below)

## Pre-implementation check (do this first, before writing any code)

Confirm the APIM platform version, not just SKU name — `/28` sizing was observed on
`<apim-example-instance>` (Developer tier), but classic vs. stv2 platform depends on
`platformVersion`, not the SKU name alone. If the POC's target instance resolves to stv2, it
needs `/27` minimum and the entire `/26` plan in this proposal collapses (see spec.md's
Session 2026-09-10 clarification on stv2). Run:

```
az account set --subscription "AZR-HJI"
az apim show -n azr-hji-mtaxon-apim-dev -g AZR-HJI-MT-Axon-dev \
  --query "{sku:sku.name, platformVersion:platformVersion}" -o table
```

If `platformVersion` is `stv1`, the `/28` plan below holds. If `stv2`, stop and revisit sizing
with the network team before proceeding.

## Acceptance criteria
- [ ] `generate-brownfield-params.sh --block-size 26` against the real discovery file produces
      exactly: `foundry /27`, `apim /28`, `privateEndpoints /29`, `compute+cicdAgents /29`
      (merged), with zero remaining address space.
- [ ] Generated `foundry.bicepparam`/`brownfield-dns.bicepparam` support a cross-subscription
      `dnsSubscriptionId` distinct from the workload subscription.
- [ ] `privatelink.azure-api.net` is no longer requested/required when APIM uses VNet injection.
- [ ] All existing tests in `tests/network/` still pass; new tests cover the above.
- [ ] `docs/deploy-00-network.md` no longer contains the "Known limitation" callout — it
      describes actual behavior.

## Example target CIDR plan (<region>, free block 10.0.1.192/26)

| Purpose | CIDR | Total | Usable |
|---|---|---|---|
| `foundry` | `10.0.1.192/27` | 32 | 27 |
| `apim` | `10.0.1.224/28` | 16 | 11 |
| `privateEndpoints` | `10.0.1.240/29` | 8 | 3 |
| `compute+cicdAgents` (merged) | `10.0.1.248/29` | 8 | 3 |
