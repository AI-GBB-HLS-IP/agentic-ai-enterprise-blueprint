## 1. Parameter Contracts

- [ ] 1.1 Add optional object parameters for APIM service, Log Analytics workspace, Application Insights, capacity alert, and private DNS zone tags to `infra/envs/poc/apim.bicep`, preserving the existing public IP tag default and mandatory merge; verify `az bicep build --file infra/envs/poc/apim.bicep --stdout` succeeds.
- [ ] 1.2 Add distinct JSON environment-variable inputs for every new tag object to `infra/envs/poc/apim.bicepparam` and `infra/envs/poc/apim.customer.example.bicepparam`; verify the parameter names and defaults are present with targeted assertions in the APIM validation suite.

## 2. Module Tag Propagation

- [ ] 2.1 Add `apimServiceTags` to the APIM service module interface and apply it to `Microsoft.ApiManagement/service`; verify the compiled APIM resource references only the APIM service tag parameter.
- [ ] 2.2 Add separate workspace, Application Insights, and capacity alert tag parameters to the observability module and apply each to its corresponding resource; verify the conditional workspace and unconditional observability resources compile with independent tag expressions.
- [ ] 2.3 Add `privateDnsZoneTags` to the private DNS module and apply it only to the blueprint-created private DNS zone; verify external DNS mode does not introduce an update to any external DNS resource.
- [ ] 2.4 Wire each environment-level tag object to its owning module without shared implicit inheritance; verify compiled module parameters map one-to-one to the intended resource tag inputs.

## 3. Automated Validation

- [ ] 3.1 Extend `specs/02-apim-ai-gateway/validation/validate.sh` to require and validate every new tag environment-variable contract; verify the targeted validation command passes with the repository parameter files.
- [ ] 3.2 Extend `tests/foundry/test-apim-review-regressions.sh` with compiled-template assertions for independent APIM, workspace, Application Insights, capacity alert, private DNS zone, and public IP tags; verify the test fails for a deliberately miswired fixture or assertion and passes after restoration.
- [ ] 3.3 Add regression coverage proving omitted new inputs compile with empty defaults, Azure-valid custom tag keys pass through unchanged, the public IP mandatory `ProjectCode: APIM` override still wins, existing Log Analytics workspaces are not retagged, and external DNS mode creates no tagged DNS zone; verify all APIM foundation regression tests pass using sanitized generic fixtures.

## 4. Documentation

- [ ] 4.1 Update `specs/02-apim-ai-gateway/contracts/apim-bicep-interface.md` with the per-resource tag parameters, environment variables, defaults, ownership boundaries, and public IP mandatory tag behavior; verify every implemented input appears in the contract.
- [ ] 4.2 Update the APIM quickstart and customer deployment guidance with sanitized generic examples of distinct JSON tag objects and an explicit list of resources that do not expose independent Azure resource tags; verify example variable names match the `.bicepparam` files and no live customer tag keys or values are committed.

## 5. End-to-End Verification

- [ ] 5.1 Compile the APIM foundation and parameter artifacts, run the APIM validation and regression suites, and run `openspec validate add-apim-resource-tags --strict`; verify all commands complete successfully.
- [ ] 5.2 Review a deployment preview using distinct tag values for each supported resource and verify the what-if output changes only the intended blueprint-owned resources without modifying external workspace or DNS resources.
