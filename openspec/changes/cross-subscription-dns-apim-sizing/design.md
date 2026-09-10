## Context

See proposal.md - Problem/What changes for motivation and scope. Current state:

- `infra/envs/poc/foundry.bicep` only supports same-subscription Private DNS zones via
  `existing` resource references — it cannot target a zone that lives in a different
  subscription than the workload VNet.
- `infra/envs/poc/brownfield-dns.bicep` unconditionally creates VNet-link resources against
  the DNS-owner subscription. Real discovery (`<SUBSCRIPTION_ALIAS>` / `<VNET_NAME>`) shows the DNS
  owner uses **per-private-endpoint DNS zone groups** instead — zero VNet links exist on any
  zone checked.
- `scripts/network/generate-brownfield-params.sh` splits any block into a foundry half plus
  four equal quarters (currently `/27` foundry + `/29` × 4 for a `/26` input). This under-sizes
  APIM.
- APIM platform version is confirmed **`stv2`**, checked directly against two separate,
  independently owned Premium-tier instances (`platformVersion: stv2` on both). "Classic
  Premium" tier name and `stv1`/`stv2` platform version are independent axes; an earlier,
  never-actually-verified assumption that the target was `stv1` (based on
  `<apim-example-instance>`, Developer tier) is superseded by this direct evidence.
  `stv2`'s subnet minimum is `/27` (ARM-enforced, not a soft guideline) — same as Foundry's
  agent-subnet minimum. Both together consume a full `/26`, so the workable block is `/25`, not
  `/26`. Per user direction: this `/25` constraint is POC-only — production will request a
  larger address allocation separately and is out of scope here.

## Goals / Non-Goals

**Goals:**
- Support a `dnsIntegrationMode` of `zone-group` in addition to today's implicit `vnet-link`
  behavior, without changing default behavior for existing callers.
- Correct the block-splitting math to real-world, `stv2`-verified minimums: `foundry /27`,
  `apim /27`, `privateEndpoints /28`, merged `compute+cicdAgents /28` — fits exactly in a `/25`
  with 32 addresses spare.
- Stop requesting `privatelink.azure-api.net` when APIM uses VNet injection (not needed in
  that mode).

**Non-Goals:**
- No changes to `vnet-link` mode's existing behavior — it already works correctly.
- No request for additional POC address space — the `/25` the customer already handed over is
  the fixed constraint for this change; a larger production allocation is a separate, later
  request and out of scope here.

## Decisions

1. **Cross-subscription zone reference via 4-arg `resourceId()`, not `subscriptionResourceId()`.**
   `subscriptionResourceId(subId, type, name)` omits the resource-group segment, which Private
   DNS zones require as part of their resource ID. The 4-arg form
   `resourceId(dnsSubscriptionId, dnsResourceGroupName, 'Microsoft.Network/privateDnsZones', zoneName)`
   is the only built-in function that produces a valid cross-subscription, cross-resource-group
   ID without needing a linked/cross-scope module deployment.
   - Alternative considered: deploy a nested module scoped to the DNS subscription to look up
     the zone via `existing`. Rejected — adds a second deployment scope and requires the
     deploying identity to have at least Reader on the DNS subscription just to resolve the
     module, with no benefit over a plain `resourceId()` string (Bicep does not validate
     cross-subscription `existing` references at compile time either way).

2. **New param `dnsIntegrationMode: 'vnet-link' | 'zone-group'`, default `'vnet-link'`.**
   Preserves current behavior for all existing callers/params files. In `zone-group` mode:
   - `foundry.bicep` builds zone IDs via decision 1 instead of declaring `existing` zone
     resources in the local subscription.
   - `brownfield-dns.bicep` skips VNet-link resource creation entirely (`if` condition on the
     mode), since zone-group association happens per-PE, not per-VNet, and is expected to
     already exist (owned by the DNS team) or be created by the PE's own
     `Microsoft.Network/privateEndpoints/privateDnsZoneGroups` sub-resource.
   - Alternative considered: two entirely separate Bicep files instead of a mode switch.
     Rejected — the two modes share >90% of their logic (subnet/PE creation); a single param
     keeps the diff small and avoids drift between duplicated templates.

3. **Corrected subnet split: `foundry /27 + apim /27 + privateEndpoints /28 + (compute+cicdAgents) /28`.**
   Replaces both the old four-equal-`/29` split and the intermediate `/26`-based
   `/27+/28+/29+/29` split (both assumed `stv1`). With `stv2` confirmed, APIM's ARM-enforced
   minimum is `/27` — identical to Foundry's `Microsoft.App/environments` delegation minimum.
   Together those two `/27`s consume a full `/26`, so the workable block for this POC is `/25`:
   two `/27`s for foundry+apim, then two `/28`s (`privateEndpoints`, merged
   `compute+cicdAgents`) from the remaining `/26`, leaving 32 addresses spare.
   - Alternative considered: request a larger block to keep four separate, more generously
     sized subnets. Rejected for the **POC** per explicit user direction — the POC proceeds
     within the `/25` the customer already handed over; a larger allocation is deferred to
     production and out of scope for this change.

4. **Drop `privatelink.azure-api.net` from the required zone list when APIM uses VNet
   injection.** That zone is for API Management's own public/gateway hostname resolution,
   which is not needed when APIM is injected into the VNet (internal mode resolves via the
   VNet-injected private IP, not the public zone).
   - Alternative considered: always request it regardless of injection mode. Rejected —
     unnecessary coordination with the DNS-owning team for a zone the internal-mode
     deployment never uses.

## Risks / Trade-offs

- [Risk] Merging `compute` and `cicdAgents` into one `/28` (11 usable IPs) removes any
  per-purpose network isolation between the two. → Mitigation: explicitly documented as a
  POC-only trade-off in docs/deploy-00-network.md; production deployments (once a larger
  address allocation is requested, per user direction) should use a full four-subnet split.
- [Risk] `zone-group` mode assumes the DNS-owning team already manages zone-group
  associations out-of-band (or the PE's own zone-group sub-resource handles it); if the
  deploying identity lacks any RBAC on the cross-subscription DNS zone, PE creation may still
  fail at the zone-group step. → Mitigation: document this precondition in
  docs/deploy-00-network.md; fail with a clear error rather than a silent partial deployment.
- [Risk] Changing the default block split affects any already-generated `.bicepparam` files
  that assumed the old four-equal-`/29` layout. → Mitigation: default `dnsIntegrationMode`
  stays `vnet-link`; the corrected split only applies to newly generated params, and existing
  checked-in example params are regenerated as part of this change, not silently reinterpreted.

## Migration Plan

1. Update `foundry.bicep` with the new param and cross-subscription zone-ID logic (decision 1-2).
2. Update `brownfield-dns.bicep` to make VNet-link creation conditional on `dnsIntegrationMode`.
3. Update `generate-brownfield-params.sh`: add `--dns-integration-mode` / `--dns-subscription-id`
   flags, correct the block-split math (decision 3), drop the APIM zone in VNet-injection mode
   (decision 4).
4. Update `docs/deploy-00-network.md` to remove the "Known limitation" callout and document the
   new flags/behavior.
5. Update/add tests in `tests/network/test-generate-brownfield-params.sh` for the new split and
   flags.

Rollback: revert the commits for this change; `dnsIntegrationMode` defaulting to `vnet-link`
means no rollback migration is needed for existing deployments (they never opted into
`zone-group` mode).

## Open Questions

None — the one blocking unknown (APIM stv1 vs stv2) was resolved before finalizing this design
(confirmed `stv2` against two real instances; block re-derived from `/26` to `/25`
accordingly). Production sizing (a larger, separately requested allocation) is explicitly
deferred and out of scope for this POC change, per user direction.
