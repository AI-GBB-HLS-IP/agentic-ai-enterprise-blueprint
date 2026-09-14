## 1. Spec update

- [x] 1.1 Update `specs/00-network-foundation/spec.md` FR-018 to note route-table association is
      now implemented (not just allowed), and add a new FR for caller-supplied subnet service
      endpoints (default empty except the APIM subnet's VPCx-required default).

## 2. Network module changes

- [x] 2.1 Add optional `routeTableId` property to the subnet object contract in
      `infra/modules/network/subnets.bicep`; when present, associate the referenced route table
      (full ARM resource ID) on that subnet's `routeTable` property. Validate shape only (same
      pattern as `nsgId`), never create/modify the route table.
- [x] 2.2 Add optional `serviceEndpoints` array property to the same subnet object contract; when
      present and non-empty, set the subnet's `serviceEndpoints` to
      `[for e in serviceEndpoints: { service: e }]`.
- [x] 2.3 Add `apimRouteTableId` (default `''`) and `apimServiceEndpoints` (default
      `['Microsoft.AzureActiveDirectory', 'Microsoft.KeyVault', 'Microsoft.Sql', 'Microsoft.Storage']`)
      parameters to `infra/envs/poc/brownfield-network.bicep`; wire both onto the APIM-purpose
      subnet definition only. Validate `apimRouteTableId`'s ARM-resource-ID shape when non-empty,
      mirroring the existing `existingApimNsgId`/`existingComputeNsgId` validation.
- [x] 2.4 Add matching example values (commented out / placeholder) to
      `infra/envs/poc/brownfield-network.bicepparam.example`.

## 3. Generator script

- [x] 3.1 Add `--apim-route-table-id` flag to `scripts/network/generate-brownfield-params.sh`,
      writing `param apimRouteTableId = '<value>'` into the generated brownfield network
      `.bicepparam` when supplied (omit/default to `''` otherwise).

## 4. Docs

- [x] 4.1 Update `docs/deploy-00-network.md` to document `apimRouteTableId`/
      `apimServiceEndpoints`/`--apim-route-table-id`, including the VPCx-required default service
      endpoint list and why it defaults non-empty (see design.md - Decisions #3).
- [x] 4.2 Add a concrete worked example to `docs/deploy-00-network.md` showing a hub DNS
      subscription/resource group used only as `dnsSubscriptionId`/`dnsResourceGroupName` in
      `zone-group` mode (e.g. `dnsSubscriptionId=<hub-subscription-id>`,
      `dnsResourceGroupName=<hub-subscription-name>-<workload-alias>`), explicitly calling out
      that this value must never be used as the workload deployment scope.
- [x] 4.3 Add a migration note for anyone re-running against an already-deployed
      `hybridsubnet-apim` subnet: the new non-empty `apimServiceEndpoints` default will add
      service endpoints on the next apply (see design.md - Migration Plan).

## 5. Tests

- [x] 5.1 Add/update a case in `tests/network/test-network-module-contracts.sh` asserting
      `subnets.bicep` accepts and wires `routeTableId` and `serviceEndpoints` on a subnet object.
- [x] 5.2 Add/update cases in `tests/network/test-generate-brownfield-params.sh` covering
      `--apim-route-table-id` (present and absent) and asserting the compiled brownfield network
      template associates the route table only on the APIM subnet and sets the default service
      endpoints.

## 6. Validation

- [x] 6.1 Run `tests/network/run-tests.sh` (full suite) and confirm all existing + new tests pass.
- [x] 6.2 `az bicep build` (or `az deployment group what-if` if credentials are available) against
      `infra/envs/poc/brownfield-network.bicep` and `infra/envs/poc/brownfield-dns.bicep` to
      confirm no compile regressions.
