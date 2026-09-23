## Why

Azure may generate an untagged `Application Insights Smart Detection` Action Group when the APIM foundation creates Application Insights, even though the blueprint does not declare or automatically reference that resource. Operators need explicit guidance because organizational cleanup may delete untagged resources, while the separate APIM capacity alert has no notification actions unless customer-approved Action Group IDs are supplied.

## What Changes

- Document the Azure-generated Smart Detection Action Group as a platform side effect outside the blueprint ownership and tagging contract.
- Explain how operators verify that no alert rule references the generated Action Group before deleting it.
- Clarify that the APIM capacity alert is independent and sends notifications only when `APIM_CAPACITY_ALERT_ACTION_GROUP_IDS` contains customer-approved Action Group resource IDs.
- Surface the standalone-deployment design gap for reviewer feedback without changing infrastructure behavior or claiming that the blueprint creates an Action Group.
- Link the documentation change to tracking issue #79.

## Capabilities

### New Capabilities

None. This is a documentation-only clarification of current Azure and blueprint behavior.

### Modified Capabilities

None. No deployment or runtime requirements change.

## Impact

- Updates APIM operator guidance and the staged APIM Bicep interface contract.
- May add a focused validation note or checklist entry covering generated-resource reference checks.
- Does not change Bicep templates, parameter contracts, deployed resources, APIs, or dependencies.
