## 1. Split private-endpoint creation from DNS zone group association

- [x] 1.1 Update `infra/modules/foundry/private-endpoint.bicep`: remove the `privateDnsZoneGroups`
      child resources (`foundryDnsGroup`, `storageDnsGroup`, `keyVaultDnsGroup`,
      `cosmosDBDnsGroup`, `aiSearchDnsGroup`) and their now-unused DNS-zone-ID parameters
      (`cognitiveServicesDnsZoneId`, `openAiDnsZoneId`, `servicesAiDnsZoneId`, `blobDnsZoneId`,
      `keyVaultDnsZoneId`, `cosmosDBDnsZoneId`, `aiSearchDnsZoneId`). Keep the bare private
      endpoint resources unchanged. Preserve outputs for every private endpoint's full resource
      ID (empty string when the conditional PE was not created).
- [x] 1.2 Create `infra/modules/foundry/private-endpoint-dns.bicep`: takes each dependency's
      already-created private endpoint's full resource ID (empty string to skip that resource)
      plus its DNS zone resource ID, and creates the corresponding
      `Microsoft.Network/privateEndpoints/privateDnsZoneGroups` child resource by referencing the
      PE as an `existing` resource at the scope encoded in the ID. Mirror the DNS zone config
      shape (`cognitive-services`, `openai`, `services-ai` for the Foundry account; `blob` for
      Storage; `keyvault` for Key Vault; `cosmosdb` for Cosmos DB; `aisearch` for AI Search) from
      the removed resources in 1.1.
- [x] 1.3 Update `infra/modules/foundry/main.bicep`: stop passing DNS-zone-ID parameters into the
      `privateEndpoints` module call and remove the `privateDnsZoneIds` parameter entirely. Add
      outputs passing through the PE resource-ID outputs from `private-endpoint.bicep`.

## 2. Add the DNS-association env-level entry point

- [x] 2.1 Update `infra/envs/poc/foundry.bicep`: remove `dnsIntegrationMode`, `dnsSubscriptionId`,
      `dnsResourceGroupName`, the private DNS zone `existing`/creation resources, the
      `servicesAiDns`/`servicesAiDnsLink` VNet-link creation, and the `privateDnsZoneIds` variable
      and module parameter — none of that belongs to the main deployment anymore. Add outputs for
      the PE resource IDs surfaced by `main.bicep` in 1.3.
- [x] 2.2 Create `infra/envs/poc/foundry-dns.bicep`: reintroduce the `dnsIntegrationMode`/
      `dnsSubscriptionId`/`dnsResourceGroupName` parameters and DNS zone resolution logic removed
      from `foundry.bicep` in 2.1 (same `vnet-link`/`zone-group` ternary and fail-closed
      validation), plus parameters for each dependency's full private endpoint resource ID
      (defaulting to empty to allow skipping). Wire these into `private-endpoint-dns.bicep` via a
      module call. Create `foundry-dns.bicepparam.example` with placeholder values.
- [x] 2.3 Confirmed (via `git grep`) references to the DNS-related params removed from
      `infra/envs/poc/foundry.bicep`; updated `foundry.bicepparam`/`foundry.customer.bicepparam`
      to drop them. Also found and fixed a deeper reference:
      `scripts/network/generate-brownfield-params.sh` generated a single combined
      `brownfield-foundry.bicepparam` targeting the old `foundry.bicep` with DNS params inline.
      Split it into `brownfield-foundry.bicepparam` (no DNS params) and a new
      `brownfield-foundry-dns.bicepparam` (DNS params + placeholder PE resource IDs) targeting
      `foundry-dns.bicep`; updated `tests/network/test-generate-brownfield-params.sh` and
      `docs/deploy-00-network.md` accordingly.

## 3. Update scripts

- [x] 3.1 `scripts/foundry/deploy.sh`/`what-if.sh` are already generic over `TEMPLATE_FILE`/
      `PARAMETER_FILE`, so no script code changes are required to drive the two phases
      sequentially; documented the two-phase invocation (main, then DNS) in
      `scripts/foundry/README.md`.
- [x] 3.2 `what-if.sh` validates the template and parameter file selected through
      `TEMPLATE_FILE`/`PARAMETER_FILE`, so it can preview each phase independently.
      `preflight.sh` is a shared prerequisite check and does not consume those overrides; run it
      before the staged deployments (see README).

## 4. Documentation

- [x] 4.1 Updated `docs/deploy-00-network.md` section 5.6 ("Foundry owner stage") — the existing
      Foundry deployment guide — to document the two-phase sequence, why it exists (the approved
      reference ARM template creates private endpoints without DNS association in one deployment;
      DNS zone group attachment is a distinct, later step — manual in the reference process and
      templated here for repeatability), and that the main deployment succeeding does not mean
      Foundry is functionally complete until the DNS phase also runs.
- [x] 4.2 No separate cross-link needed: the two-phase sequence lives in the same
      `docs/deploy-00-network.md` guide operators already follow end-to-end, immediately after the
      network-owner and DNS-integration stages it depends on.

## 5. Tests

- [x] 5.1 Added `tests/foundry/test-foundry-module-contracts.sh` asserting: `private-endpoint.bicep`
      compiles and declares no `privateDnsZoneGroups` resources; `private-endpoint-dns.bicep`
      compiles and declares every expected `privateDnsZoneGroups` resource referencing an
      `existing` private endpoint by full resource ID; `main.bicep` no longer declares a
      `privateDnsZoneIds` parameter.
- [x] 5.2 Updated `tests/network/test-brownfield-poc-smoke.sh`'s "zone-group DNS scope fails
      closed" assertions to build and check `infra/envs/poc/foundry-dns.bicep` instead of
      `foundry.bicep` (the DNS resolution logic moved there in task 2.2).
- [x] 5.3 No script-level test needed: `scripts/foundry/deploy.sh`/`what-if.sh` required no code
      changes because they already support `TEMPLATE_FILE`/`PARAMETER_FILE`; `preflight.sh`
      remains the unchanged shared prerequisite check. There is no new phase-handling logic to
      test.
- [x] 5.4 (Out-of-scope addition, requested mid-implementation) Added an overridable `tags`
      object param (default `{ 'foundry-poc': 'true' }`) threaded from `foundry.bicep`/
      `foundry-dns.bicep` through `main.bicep` into every taggable resource it creates directly or
      via `storage.bicep`/`ai-search.bicep`/`cosmos-db.bicep`/`supporting-resources.bicep`/
      `private-endpoint.bicep`, plus the `servicesAiDns`/`servicesAiDnsLink` resources in
      `foundry-dns.bicep`. Role assignments, project connections, capability hosts, model
      deployments, and DNS zone groups do not support tags and were left unchanged. Verified via
      `az bicep build` on every touched file plus `tests/foundry/`/`tests/network/` smoke tests.

## 6. Validation

- [x] 6.1 Ran `az bicep build` on `private-endpoint.bicep`, `private-endpoint-dns.bicep`,
      `main.bicep`, `storage.bicep`, `ai-search.bicep`, `cosmos-db.bicep`,
      `supporting-resources.bicep`, `infra/envs/poc/foundry.bicep`, and
      `infra/envs/poc/foundry-dns.bicep` — all compile clean (only pre-existing, unrelated
      `capabilityHostKind`/`internalId` warnings).
- [x] 6.2 Ran `tests/foundry/test-foundry-module-contracts.sh` and the full
      `tests/network/run-tests.sh` suite (including `test-generate-brownfield-params.sh` and the
      confidentiality/policy-input scans) — all pass.
- [x] 6.3 Ran `openspec validate foundry-staged-private-endpoint-deployment` — valid.
- [ ] 6.4 Flag to the user that live validation (an actual `az deployment group validate`/`create`
      run of both phases against a representative brownfield environment) is still required before
      merging, matching the precedent set by `brownfield-apim-network-policy-compliance` — and
      that this is also the point at which the design's open question about private-endpoint
      connection approval (independent of DNS zone group timing) should get answered.
