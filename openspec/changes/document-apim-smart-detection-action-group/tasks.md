## 1. Operator Guidance

- [ ] 1.1 Update `specs/02-apim-ai-gateway/quickstart.md` to identify the possible Azure-generated `Application Insights Smart Detection` Action Group, distinguish it from blueprint-owned APIM capacity monitoring, and verify the guidance uses conditional platform-behavior wording.
- [ ] 1.2 Add a safe operator verification sequence before cleanup of the generated Action Group, including checking alert-rule references and confirming that organizational tag cleanup must not delete a referenced notification target; verify the guidance does not recommend unconditional deletion.
- [ ] 1.3 Document that `APIM_CAPACITY_ALERT_ACTION_GROUP_IDS` defaults to `[]`, so the capacity alert detects conditions without sending notifications until customer-approved Action Group IDs are supplied; verify the parameter name and behavior match the current Bicep parameter files.

## 2. Ownership Contract

- [ ] 2.1 Update `specs/02-apim-ai-gateway/contracts/apim-bicep-interface.md` to state that the blueprint does not create, name, tag, reference, or lifecycle-manage the Azure-generated Smart Detection Action Group; verify it is excluded from the blueprint-owned resource and tag surfaces.
- [ ] 2.2 Record the standalone-deployment limitation that the blueprint references existing Action Groups but does not create one, without defining future receiver or ownership behavior; verify the text remains a documented limitation rather than a new infrastructure requirement.

## 3. Validation and Review

- [ ] 3.1 Add or update the relevant APIM deployment checklist or validation guidance so reviewers confirm capacity-alert actions separately from the presence of an Azure-generated Smart Detection Action Group; verify no validation artifact treats the generated group as deployment success evidence.
- [ ] 3.2 Review all changed examples for generic placeholders and confirm no subscription IDs, resource-group names, customer identifiers, email addresses, or live Action Group IDs are committed.
- [ ] 3.3 Run documentation link checks if available, run `openspec validate document-apim-smart-detection-action-group --strict`, and verify `git diff --check` succeeds.
