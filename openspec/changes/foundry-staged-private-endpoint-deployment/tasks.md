## 1. Split the Foundry module into base and connectivity phases

- [ ] 1.1 Create `infra/modules/foundry/base.bicep`: move the `account`, `project`,
      `keyVaultResources` module call, and the BYO-or-new resolution/creation of Storage
      (`existingStorageAccount`/`newStorageAccount`), AI Search
      (`existingAISearchService`/`newAISearchService`), and Cosmos DB
      (`existingCosmosDBAccount`/`newCosmosDBAccount`) out of `main.bicep` into this new file.
      No private endpoint resources or modules belong here. Output every resource ID, location,
      and endpoint value currently consumed by `privateEndpoints`, `projectConnections`,
      `cosmosDBRbac`, `aiSearchRbac`, or `storageRbac` in the existing `main.bicep` (account ID,
      project ID, project principal ID, workspace GUID, resolved storage/search/cosmos IDs,
      locations, and endpoints, resolved resource/subscription-group names).
- [ ] 1.2 Create `infra/modules/foundry/connectivity.bicep`: move the `privateEndpoints`,
      `projectConnections`, `cosmosDBRbac`, `aiSearchRbac`, `storageRbac`, `capabilityHost`, and
      `modelDeployment` modules here. Replace every reference to `account`/`project`/base-phase
      resource symbols with new input parameters of the same ARM-resource-ID shape already used
      for BYO inputs (reuse the existing `_validate*ResourceId` shape-validation pattern from
      `main.bicep` for each new required-ID parameter).
- [ ] 1.3 Decide the fate of the original `infra/modules/foundry/main.bicep`: if nothing else in
      this repo currently references it directly, replace it with `base.bicep`/`connectivity.bicep`
      and remove it; otherwise keep it only as an explicitly-labeled non-brownfield/low-restriction
      combined path that composes `base.bicep` + `connectivity.bicep` back together for
      environments without the staged-creation requirement.
- [ ] 1.4 Leave `private-endpoint.bicep`, `project-connections.bicep`, `cosmos-rbac.bicep`,
      `ai-search-rbac.bicep`, `storage-rbac.bicep`, `capability-host.bicep`, and
      `model-deployment.bicep` unchanged — only the orchestrating entry point changes.

## 2. Add env-level two-phase entry points

- [ ] 2.1 Create `infra/envs/poc/foundry-base.bicep` wrapping `base.bicep`, and
      `foundry-base.bicepparam.example` with placeholder values, mirroring the existing
      `foundry.bicepparam` example topology.
- [ ] 2.2 Create `infra/envs/poc/foundry-connectivity.bicep` wrapping `connectivity.bicep`, and
      `foundry-connectivity.bicepparam.example`. Its resource-ID parameters must accept either
      `foundry-base.bicep`'s outputs (copy/paste, matching the network module's existing
      output-to-param handoff pattern) or genuinely pre-existing BYO resource IDs.
- [ ] 2.3 Confirm (via `git grep`) whether anything currently references the combined
      `infra/envs/poc/foundry.bicep` / `foundry.bicepparam`; update or retire them per the
      decision made in 1.3.

## 3. Update scripts

- [ ] 3.1 Update `scripts/foundry/deploy.sh` to drive the base phase then the connectivity phase
      as two sequential, separately invokable steps (a `--phase base|connectivity|both` flag, or
      two subcommands — follow the style already used by `scripts/network/`).
- [ ] 3.2 Update `scripts/foundry/preflight.sh` and `scripts/foundry/what-if.sh` to validate each
      phase independently.

## 4. Documentation

- [ ] 4.1 Add or update a Foundry deployment guide under `docs/` documenting the two-phase
      sequence, why it exists (tenant policy requires the base resource to exist, with no private
      endpoint configured, before one is attached — per the customer's documented Key Vault
      creation process), and that connection approval may need manual confirmation between
      phases.
- [ ] 4.2 Cross-link this guide from `docs/deploy-00-network.md` and/or the repo's top-level
      deployment index if one exists, so operators discover the staged sequence before attempting
      a single combined deploy.

## 5. Tests

- [ ] 5.1 Add `tests/foundry/test-foundry-module-contracts.sh` asserting: `base.bicep` compiles
      and declares no private-endpoint resources; `connectivity.bicep` compiles and requires
      resource-ID inputs (shape-validated) rather than referencing base-phase symbols directly;
      every output declared by `base.bicep` has a corresponding input parameter on
      `connectivity.bicep`.
- [ ] 5.2 Add a script-level test for the updated `deploy.sh`/`preflight.sh`/`what-if.sh` phase
      handling, following the pattern of `tests/network/test-generate-brownfield-params.sh`.

## 6. Validation

- [ ] 6.1 Run `az bicep build` on `base.bicep`, `connectivity.bicep`,
      `infra/envs/poc/foundry-base.bicep`, and `infra/envs/poc/foundry-connectivity.bicep` —
      confirm clean compiles.
- [ ] 6.2 Run the new and existing test suites (`tests/foundry/`, plus the full repo test runner
      if one exists) and confirm they pass.
- [ ] 6.3 Run `openspec validate` for this change and confirm it is valid.
- [ ] 6.4 Flag to the user that live validation (an actual `az deployment group validate`/`create`
      run of both phases against a real or mimic brownfield tenant) is still required before
      merging, matching the precedent set by `brownfield-apim-network-policy-compliance` — and
      that this is also the point at which the design's open question about private-endpoint
      approval behavior (manual vs. automatic) should get answered.
