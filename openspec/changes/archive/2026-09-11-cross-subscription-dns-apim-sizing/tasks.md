## 1. `foundry.bicep` — cross-subscription DNS zone support

- [x] 1.1 Add required `dnsIntegrationMode` param (`'vnet-link' | 'zone-group'`) and
      `dnsSubscriptionId` / `dnsResourceGroupName` params (used only in `zone-group` mode);
      update every existing caller and parameter file to pass an explicit mode.
- [x] 1.2 In `zone-group` mode, build each Private DNS zone ID via
      `resourceId(dnsSubscriptionId, dnsResourceGroupName, 'Microsoft.Network/privateDnsZones', zoneName)`
      instead of declaring local `existing` zone resources. This includes the `services.ai.azure.com`
      zone: make the `servicesAiDns` zone resource and `servicesAiDnsLink` VNet-link resource in
      `foundry.bicep` conditional on `dnsIntegrationMode == 'vnet-link'`; in `zone-group` mode,
      reference the DNS-owner-approved existing `privatelink.services.ai.azure.com` zone via
      `resourceId()` and do not manage its VNet link.
- [x] 1.3 In `vnet-link` mode, preserve the current same-subscription `existing` zone
      resource behavior unchanged, including creating the `servicesAiDns` zone and
      `servicesAiDnsLink` VNet link as today.
- [x] 1.4 Verify `az bicep build` succeeds for both modes (no missing param errors, no
      unused-param warnings).

## 2. `brownfield-dns.bicep` — conditional VNet-link creation

- [x] 2.1 Add the same required `dnsIntegrationMode` param; update every existing caller and
      parameter file to pass an explicit mode.
- [x] 2.2 Make VNet-link resource creation conditional (`if (dnsIntegrationMode == 'vnet-link')`)
      so nothing DNS-owner-scoped is deployed in `zone-group` mode.
- [x] 2.3 Verify `az bicep build` succeeds and the compiled template has zero resources in the
      VNet-link resource group when `dnsIntegrationMode == 'zone-group'`.

## 3. `brownfield-network.bicep` — merge compute and CI/CD-agents subnets

- [x] 3.1 Replace the separate `computeSubnetPrefix` / `cicdAgentsSubnetPrefix` params and
      subnet resources with a single merged `computeSubnetPrefix` param and one subnet
      resource (e.g. `compute-cicd`) sized for both workloads, so a single `/28` CIDR is
      deployable without Azure rejecting overlapping subnets.
- [x] 3.2 Update any NSG/route-table associations and outputs that referenced the separate
      `cicdAgentsSubnetPrefix` / CI/CD subnet resource to reference the merged subnet instead.
- [x] 3.3 Verify `az bicep build` succeeds and a `what-if` deployment against the merged
      `/28` allocation produces no overlapping-subnet errors.

## 4. `generate-brownfield-params.sh` — flags and corrected block split

- [x] 4.1 Add required `--dns-integration-mode <vnet-link|zone-group>` flag, validated against
      the allowed values, and fail clearly when it is omitted.
- [x] 4.2 Add `--dns-subscription-id <id>` and require both it and `--dns-resource-group <rg>` when `--dns-integration-mode zone-group` is passed; fail with a clear error if either is omitted in that mode.
- [x] 4.3 Replace the block split with: raise `RECOMMENDED_BLOCK_PREFIX` /
      `MIN_VIABLE_BLOCK_PREFIX` / `MAX_BLOCK_PREFIX` from `/26` to `/25`; split into
      `foundry /27`, `apim /27`, `privateEndpoints /28`, merged `compute+cicdAgents /28`
      (32 addresses spare) targeting the merged subnet from task 3.1; update
      `MINIMUM_PREFIX` from `{"foundry": 27, "apim": 29}` to `{"foundry": 27, "apim": 27}`.
- [x] 4.4 Update the minimum-viable-block help text/error messages to describe the new `/25`
      split and `stv2`-confirmed `/27` APIM minimum (currently says "four /29s" / implies
      `/29` for apim; update throughout, including the `free_blocks()` hint message).
- [x] 4.5 When APIM uses VNet injection, update `brownfield-dns.bicep` and its generated
      parameters to omit the `apim` zone requirement, conditionally skip `apimLink`, and omit
      its link ID from the output.
- [x] 4.6 Thread `dnsIntegrationMode` / `dnsSubscriptionId` through into the generated
      `brownfield-foundry.bicepparam` / `brownfield-dns.bicepparam` output, and set
      `brownfield-foundry.bicepparam` `privateEndpointSubnetName` to the replacement
      private-endpoint subnet name whenever that subnet is allocated.

## 5. Regenerate example params

- [x] 5.1 Regenerate `infra/envs/poc/brownfield-network.bicepparam.example` (and any other
      checked-in example params affected) using the corrected script output, so committed
      examples match the new `/25`-based split rather than the old `/26`-based layouts.

## 6. Documentation

- [x] 6.1 Remove the "Known limitation (2026-09-10)" callout in
      `docs/deploy-00-network.md`.
- [x] 6.2 Document the new `--dns-integration-mode` / `--dns-subscription-id` flags and the corrected `/27 + /27 + /28 + /28` split, replacing the old four-equal-`/29` description.
- [x] 6.3 Document the `zone-group` mode precondition (deploying identity / DNS-owning team
      must already handle zone-group RBAC) as a known precondition, not a limitation.

## 7. Tests

- [x] 7.1 Update `tests/network/test-generate-brownfield-params.sh` so the `/25` block-size
      case asserts the corrected split (`foundry /27`, `apim /27`, `privateEndpoints /28`,
      `compute+cicdAgents /28`) instead of any prior `/26`-based split.
- [x] 7.2 Add a test case for `--dns-integration-mode zone-group` (with
      `--dns-subscription-id`), asserting the generated params reflect cross-subscription
      zone IDs and no VNet-link output.
- [x] 7.3 Add a test case asserting `--dns-integration-mode zone-group` without
      `--dns-subscription-id` fails with a clear error.
- [x] 7.4 Add a test case asserting `privatelink.azure-api.net` is absent from the generated
      zone list when APIM VNet injection is used.
- [x] 7.5 Run `tests/network/run-tests.sh` (full suite) and confirm all existing tests still
      pass alongside the new ones.

## 8. Final validation

- [x] 8.1 Run `az bicep build` across all touched `.bicep` files one more time after all
      edits (regression check).
- [x] 8.2 Run `az deployment group what-if` against the confirmed `/25` free block
      (`10.0.1.128/25` in `<VNET_NAME>`, or the real target block) using the
      regenerated params, per spec FR-008.
