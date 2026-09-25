## 1. Resource Inventory and Contracts

- [ ] 1.1 Inventory every resource declaration under `infra/envs/poc/` and `infra/modules/`,
  classifying it as blueprint-created taggable, blueprint-created unsupported, existing/external,
  or conditional create-or-reference; verify the reviewed inventory covers every compiled resource
  type from all environment entry points.
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
  mandatory tag precedence, and Stage 2 ownership boundaries.

## 5. Automated Validation

- [ ] 5.1 Extend `tests/network/run-tests.sh` coverage with compiled-template assertions for
  greenfield and brownfield tag mappings, `{}` defaults, repeated-family keys, optional Bastion,
  unknown-key rejection, and external-resource immutability; verify the suite fails for a
  deliberately miswired assertion and passes after restoration.
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
- [ ] 5.6 Define and generate a deployment-specific ownership manifest after resolving the exact
  template, effective parameters, DNS mode, optional resources, and cross-scope targets. Require a
  schema version, Azure cloud, deployment scope, template and effective-parameter digests, and one
  entry for every planned tagged declaration containing its logical name, type, subscription,
  resource group, name, and canonical resource ID.
- [ ] 5.7 Define the versioned JSON evidence schema and the `--accept-existing` and
  `--prior-evidence <path>` CLI contract. Require a creation timestamp, manifest digest, and an
  `absent` or `accepted-existing` outcome with canonical ID for every entry; allow prior evidence
  only for the same logical declaration and scope.
- [ ] 5.8 Add `scripts/tags/preflight-owned-names.sh` to consume the manifest and evidence contract,
  query each canonical ID, and reject malformed inputs, duplicate or unknown attestations,
  prior-evidence logical-declaration or scope mismatches, manifest-digest mismatches, and all other
  existing resources with a non-zero exit. Enforce the design's non-overrideable
  `OWNERSHIP_EVIDENCE_TTL_SECONDS` freshness invariant; an initial run with an existing name fails,
  while a partial initial deployment can use the evidence that recorded the name as absent.
- [ ] 5.9 Add preflight fixtures proving absent and eligible re-deployment cases pass, while
  non-attested, malformed, duplicate, stale, and mismatched evidence cases fail.
- [ ] 5.10 Add `scripts/tags/deploy-with-ownership-preflight.sh` to generate the manifest, invoke
  the preflight, and verify fresh evidence immediately before every tagged deployment:
  `infra/envs/poc/main.bicep` (including private DNS and optional Bastion),
  `infra/envs/poc/brownfield-network.bicep`, `infra/envs/poc/brownfield-dns.bicep`,
  `infra/envs/poc/foundry.bicep`, and `infra/envs/poc/foundry-dns.bicep`. Wire the first three
  through their commands in `docs/deploy-00-network.md` and the final two through
  `scripts/foundry/deploy.sh`; that script must invoke `scripts/foundry/preflight.sh` before the
  common gate. Provide the same required sequence in every documented direct
  `az deployment group create` procedure. Fail closed for missing, stale, or manifest-mismatched
  evidence, and verify a failing gate emits no deployment on each path.
- [ ] 5.11 Add in-template validation that fails when an existing-ID or reuse parameter resolves to
  a name another input still forces the same deployment to create; in brownfield NSG coverage,
  exercise `existingApimNsgId` and `existingComputeNsgId` with `reuseExistingNsgs=false`, while
  confirming `sharedHybridNsgId` remains valid because it suppresses creation. Verify the
  contradictory-input fixture fails template validation and the non-contradictory equivalents still
  compile.

## 6. Documentation and Completion

- [ ] 6.1 Add one blueprint-wide resource-tag inventory and contract table listing each logical
  resource, ownership mode, input name or map key, default, merge behavior, and unsupported reason;
  verify every reviewed inventory row appears exactly once.
- [ ] 6.2 Update network, Foundry, APIM, and customer deployment guidance with sanitized examples,
  ownership boundaries, legacy Foundry compatibility, repeated-family map usage, and the mandatory
  ownership preflight prerequisite for deployments that create resources with deterministic
  blueprint-owned names; verify all documented names match the implemented
  `.bicepparam` interfaces.
- [ ] 6.3 Record offline validation results and mark approval-dependent Foundry what-if/runtime
  evidence `BLOCKED` without changing the separate Stage 1 evidence-file reconciliation; verify no
  document claims unexecuted live validation passed.
- [ ] 6.4 Run `openspec validate add-blueprint-resource-tags --strict`, update #81 with final
  evidence links and completion status, and verify the implementation pull request references the
  issue and all acceptance criteria.
