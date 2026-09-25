## 1. Resource Inventory and Contracts

Scope: tagging under declared ownership, including normal redeployment. Automatic ownership
discovery, attestation/evidence gates, and concurrency enforcement are excluded, not pending
dependencies. Existing unrelated deployment prerequisites remain unchanged.

- [ ] 1.1 Inventory every resource declaration under `infra/envs/poc/` and `infra/modules/`,
  classifying it as declared blueprint-managed taggable, managed unsupported, existing/BYO
  reference, or conditional create/update-or-reference. Record entry point, full resource
  identity/scope, active branch condition, tag input/default/precedence or unsupported reason,
  implementation task, and acceptance scenario in one matrix. Cover `main.bicep` (including
  private DNS and optional Bastion), `brownfield-network.bicep`, `brownfield-dns.bicep`,
  `foundry.bicep`, `foundry-dns.bicep`, `apim.bicep`, and `apim-foundry-integration.bicep`;
  verify every compiled resource type and applicable ownership branch is represented.
- [ ] 1.2 Verify Azure tag support for each parent, child, extension, and preview API resource type
  in the inventory; verify no tag parameter is planned for a resource whose selected API does not
  expose Azure resource tags.
- [ ] 1.3 Define consistent singular parameter names and purpose-keyed map keys for network, DNS,
  Bastion, Foundry, supporting-service, and private-endpoint resources; verify every
  blueprint-created taggable inventory row maps to exactly one documented input and every
  repeated-family map rejects unknown keys with a resource-specific error.
- [ ] 1.4 Define the compatibility and merge contract for the existing Foundry `tags` object,
  resource-specific overrides, and mandatory APIM tags; verify examples demonstrate
  base-to-specific-to-mandatory precedence with generic values.

## 2. Network, DNS, and Bastion Tagging

- [ ] 2.1 Add independent tag inputs for the greenfield VNet and blueprint-created APIM and compute
  NSGs, wiring them through `infra/envs/poc/main.bicep` and the network modules; verify compiled
  output maps each input only to its intended resource.
- [ ] 2.2 Add purpose-keyed tag maps for blueprint-created private DNS zones and virtual network
  links; verify every supported zone and link can receive a distinct tag object and missing keys
  resolve to `{}`, while unknown keys are rejected.
- [ ] 2.3 After optional Bastion tasks T025 and T059-T063 in
  `specs/00-network-foundation/tasks.md` are complete, add independent tag inputs for the Bastion
  public IP and Bastion host without implementing a second conditional-deployment contract here;
  verify enabled deployments emit the correct tags and disabled deployments emit neither resource.
  If those dependencies remain incomplete, keep this task blocked and do not claim this tagging
  change complete.
- [ ] 2.4 Add independent tag inputs to brownfield network paths only for blueprint-created NSGs;
  verify existing VNets, route tables, shared NSGs, reusable per-purpose NSGs, and subnet children
  receive no tag update.
- [ ] 2.5 Add tag inputs to brownfield DNS only for blueprint-created virtual network links and
  other confirmed taggable resources; verify existing zones, record sets, private endpoints, and
  DNS zone groups are not retagged.
- [ ] 2.6 Update the greenfield `infra/envs/poc/network.parameters.json`, brownfield `.bicepparam`
  examples and generated files, and the brownfield parameter generator with sanitized tag inputs
  and `{}` defaults; verify `tests/network/test-generate-brownfield-params.sh` covers every
  generated tag contract.
- [ ] 2.7 Implement input-consistency validation for determinable contradictions between supplied
  external IDs and active create/update targets identified by task 1.1, including relevant Foundry
  paths if that inventory identifies any. Compare full ARM IDs case-insensitively, not bare names.
  For brownfield NSGs, check both existing per-purpose IDs against both active NSG targets only
  when `sharedHybridNsgId` is empty and `reuseExistingNsgs=false`. Wire guards into evaluated
  expressions so they cannot be discarded as unused; do not add Azure ownership discovery.

## 3. Foundry Resource Tagging

- [ ] 3.1 Add resource-specific Foundry account and project tag inputs while retaining the existing
  shared `tags` object as the compatibility base; verify conflicting-key compiled output uses the
  resource-specific value.
- [ ] 3.2 Add independent tag inputs for blueprint-created Key Vault, Storage, AI Search, and
  Cosmos DB resources; verify each create branch receives its effective tags and each existing/BYO
  branch remains tag-free.
- [ ] 3.3 Add purpose-keyed private-endpoint tag inputs for Foundry, Storage, Key Vault, Cosmos DB,
  and AI Search endpoints on the Foundry creation path (`infra/envs/poc/foundry.bicep` ->
  `infra/modules/foundry/main.bicep` -> `infra/modules/foundry/private-endpoint.bicep`), not on
  `foundry-dns.bicep`; verify each created endpoint can receive distinct tags and skipped or
  externally supplied endpoints are not updated.
- [ ] 3.4 Add independent tags for the services.ai private DNS zone and virtual network link created
  by `foundry-dns.bicep`, using the existing shared `tags` object as the compatibility base and
  resource-specific values as overrides; verify `zone-group` mode creates neither resource and
  applies no corresponding tags.
- [ ] 3.5 Update Foundry `.bicepparam` files and customer examples with separate JSON
  environment-variable inputs while preserving the legacy shared input; verify omitted new inputs
  compile and sanitized custom keys pass through unchanged.
- [ ] 3.6 Document and regression-test Foundry child resources that do not support independent
  Azure tags, including applicable connections, capability hosts, model deployments, RBAC
  assignments, and DNS zone groups; verify no misleading tag inputs are exposed.

## 4. APIM Contract Preservation

- [ ] 4.1 Reconcile the APIM Stage 1 resource inventory with the archived
  `apim-resource-tagging` contract; verify all existing per-resource inputs and the mandatory public
  IP `ProjectCode: APIM` precedence remain unchanged.
- [ ] 4.2 Inventory APIM Stage 2 role assignments and APIM child resources, documenting unsupported
  independent tag surfaces for backends, named values, APIs, operations, products, bindings, and
  policies; verify `apim-foundry-integration.bicep` gains no unsupported tag parameters.
- [ ] 4.3 Extend APIM regression coverage only where needed to protect blueprint-wide invariants;
  verify `tests/foundry/test-apim-review-regressions.sh` still proves independent Stage 1 mappings,
  mandatory tag precedence, declared Stage 1 create/update-versus-reference behavior, and Stage 2
  unsupported tag surfaces.

## 5. Automated Validation

- [ ] 5.1 Extend `tests/network/run-tests.sh` coverage with compiled-template assertions for
  greenfield and brownfield tag mappings, `{}` defaults, repeated-family keys, optional Bastion,
  unknown-key rejection, and exclusion of referenced existing/BYO resources from tag assignments;
  verify the suite fails for a deliberately miswired assertion and passes after restoration.
- [ ] 5.2 Extend `tests/foundry/run-tests.sh` coverage for Foundry shared-base compatibility,
  resource-specific precedence, conditional create-or-reference behavior, private-endpoint maps,
  services.ai DNS mode behavior, unknown-key rejection, and unsupported child resources; verify the
  suite fails for a deliberately miswired assertion and passes after restoration.
- [ ] 5.3 Compile every affected Bicep entry point and parameter file, including greenfield network,
  brownfield network and DNS, Foundry and Foundry DNS, APIM foundation, and APIM Foundry
  integration; verify all builds succeed without introducing required tag parameters.
- [ ] 5.4 Run the repository confidentiality scan against all new examples, fixtures, and evidence;
  verify committed tag keys and values contain only sanitized generic data.
- [ ] 5.5 Run `OFFLINE_ONLY=true specs/02-apim-ai-gateway/validation/validate.sh all` and all
  affected network and Foundry regression suites; verify offline checks pass while unavailable
  Foundry live gates remain explicitly `BLOCKED`.
- [ ] 5.6 Add evaluated-input regression fixtures for task 2.7: same-identity contradictions
  (including case variants and cross-purpose NSG matches) must fail with an ownership-input error;
  different-scope same-name IDs and valid shared/reused NSG branches must not fail that check.
  Exercise other inventory-identified contradictions and their valid counterparts. Verify actual
  guard evaluation, including when new tag inputs are omitted, not merely successful Bicep
  compilation or the presence of `fail()` in output.
- [ ] 5.7 Verify create/update tag payloads retain documented defaults and merge precedence for
  redeployment of previously blueprint-created resources, including APIM Stage 1 and Foundry.
  Assert no new ownership manifest, attestation, or evidence input is required. Record these as
  offline payload/contract checks, not proof of live resource ownership or collision prevention.

## 6. Documentation and Completion

- [ ] 6.1 Publish the reviewed task 1.1 resource-tag matrix as the single inventory, completing its
  input names/map keys, defaults, merge behavior, branch conditions, unsupported reasons, task
  links, and acceptance-scenario links; verify every reviewed row appears exactly once and no
  in-scope entry point, including APIM Stage 1, is omitted.
- [ ] 6.2 Update network, Foundry, APIM, and customer deployment guidance with sanitized examples,
  declared-ownership boundaries, normal redeployment, legacy Foundry compatibility, and
  repeated-family map usage. Cover every task 1.1 create/update entry point in scripted and direct
  procedures, including `docs/deploy-00-network.md`, Foundry deployment guidance, and
  `specs/02-apim-ai-gateway/quickstart.md`. Require operator verification that targets are absent or
  already blueprint-owned, stopping or using supported BYO paths otherwise, and prevention of
  conflicting concurrent deployments. Explicitly document the accepted undeclared-collision/race
  risk without promising automated detection or adding a new ownership gate. Verify names match
  implemented JSON and `.bicepparam` interfaces and existing unrelated preflights remain intact.
  Document the intentional rejection of previously tolerated contradictory ownership inputs and
  how callers correct their create/reuse selection.
- [ ] 6.3 Record offline validation results and mark approval-dependent Foundry what-if/runtime
  evidence `BLOCKED` without changing the separate Stage 1 evidence-file reconciliation; verify no
  document claims unexecuted live validation passed.
- [ ] 6.4 Run `openspec validate add-blueprint-resource-tags --strict`, update #81 with final
  evidence links and completion status, and verify the implementation pull request references the
  issue and all acceptance criteria.
