## 1. Template

- [x] 1.1 Add `hostnameMode`, existing/declared hostname parameters and secure `hostnameCertificates` with merge logic to `infra/modules/apim/main.bicep`; verify `az bicep build --file infra/envs/poc/apim.bicep` has no errors or warnings
- [x] 1.2 Plumb the parameters through `infra/envs/poc/apim.bicep`; verify the build succeeds
- [x] 1.3 Verify `az bicep snapshot` for preserve, merge and replace parameter files shows the selected expression and that preserve emits the captured entries

## 2. Capture script, parameters, docs

- [x] 2.1 Add `scripts/apim/get-existing-hostnames.sh`; verify `bash -n` passes and a fake `az` run prints only Key Vault-backed entries with a PFX warning on stderr
- [x] 2.2 Add `hostnameMode` and `APIM_EXISTING_HOSTNAMES_JSON` to `apim.bicepparam`, and gateway/developer/management PFX examples to `apim.customer.example.bicepparam`; verify `az bicep build-params` succeeds for both
- [x] 2.3 Document the mandatory capture step, modes, PFX handling and DNS caveat in `infra/envs/poc/README.md`
- [x] 2.4 Verify `tests/foundry/test-apim-review-regressions.sh` and `tests/foundry/test-apim-staged-contracts.sh` pass

## 3. Review follow-ups

- [x] 3.1 Make `preserve`/`merge` fail when the captured list is unset (`existingHostnamesJson`, `fail()` in `apim.bicep`); verify with `bicep test` assertions that unset fails and `[]`, a list, and `replace` pass
- [x] 3.2 Demote retained `Proxy` `defaultSslBinding` when a declared `Proxy` claims it and fail on more than one; verify with `bicep test` assertions across preserve, replace, merge (case-insensitive replace, Management replace, default demotion) and two declared defaults
- [x] 3.3 Use portable base64 in the example (`base64 < file | tr -d '\n'`); verify no `base64 -w0` remains
- [x] 3.4 Add `tests/foundry/test-apim-hostname-capture.sh` (mocked `az`) and verify it passes, fails when `az` errors are swallowed, and runs in `tests/foundry/run-tests.sh`

## 4. Live validation (BLOCKED until a non-production APIM is available)

- [ ] 4.1 With a Key Vault-backed domain, run the script and deploy a SKU change; verify the domain remains
- [ ] 4.2 In `merge` mode add a gateway PFX domain; verify captured and declared domains are both configured, and that a declared Management domain replaces the captured one
- [ ] 4.3 In `replace` mode with an empty list; verify all custom domains are removed
- [ ] 4.4 Run the script against a missing service; verify it prints `[]` and exits 0
