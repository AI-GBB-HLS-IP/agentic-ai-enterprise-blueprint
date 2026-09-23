## Context

See `proposal.md` for motivation. The APIM foundation declares Application Insights and a separate APIM capacity metric alert, but it declares no `Microsoft.Insights/actionGroups` resource. Azure may still generate an untagged Action Group named `Application Insights Smart Detection` during Application Insights provisioning. The generated resource can be mistaken for a blueprint-owned notification path even when no alert rule references it.

The customer parameter contract already exposes `APIM_CAPACITY_ALERT_ACTION_GROUP_IDS`, defaulting to an empty array. Therefore, the capacity alert can exist without any notification action. Documentation must preserve that current contract while making the operational consequence explicit.

## Goals / Non-Goals

**Goals:**

- Establish a clear ownership boundary between blueprint-declared observability resources and Azure-generated artifacts.
- Give operators a safe verification sequence before organizational tag-cleanup processes delete the generated Action Group.
- Distinguish Application Insights Smart Detection notifications from the APIM capacity alert notification contract.
- Surface the standalone notification gap for review without pre-deciding future infrastructure ownership.

**Non-Goals:**

- Create, tag, adopt, rename, or delete an Action Group through Bicep.
- Change capacity-alert defaults, receivers, readiness logic, or validation behavior.
- Guarantee that Azure always creates, or never recreates, the generated Action Group.
- Define the future receiver model for a blueprint-owned Action Group.

## Decisions

### Document the resource as a possible Azure-generated side effect

Guidance will use conditional language because the resource is not declared by the blueprint and Azure platform behavior may vary over time. The documentation will identify the observed default name while avoiding a guarantee that every deployment creates it.

Alternative considered: list it as a blueprint-created resource. Rejected because the compiled template contains no Action Group resource and the blueprint cannot control its name, tags, receivers, or lifecycle.

### Keep generated Smart Detection and APIM capacity alert guidance separate

The interface contract will state that the generated Action Group is not automatically connected to the APIM capacity alert. The quickstart will explain that capacity notifications require explicit `APIM_CAPACITY_ALERT_ACTION_GROUP_IDS` values.

Alternative considered: recommend reusing the generated Action Group for APIM capacity notifications. Rejected because it is untagged, platform-named, outside the ownership contract, and may contain broad role-based receivers.

### Require reference verification before deletion

Operator guidance will require checking Azure Monitor alert rules or resource references before deletion. An empty reference result supports cleanup, but documentation will not present deletion as universally safe.

Alternative considered: recommend unconditional deletion whenever the resource is untagged. Rejected because a customer or future Azure operation could attach an alert rule after deployment.

### Record standalone Action Group ownership as a future design decision

The documentation will state that the current blueprint references existing Action Group IDs but does not create an Action Group. Whether a standalone deployment should create a named, tagged Action Group with required receivers remains outside this documentation-only change.

Alternative considered: add Action Group infrastructure in the same change. Rejected because receiver ownership, notification destinations, deployment modes, and readiness behavior require separate requirements and customer review.

## Risks / Trade-offs

- [Azure platform behavior changes] → Use conditional wording and describe the authoritative blueprint ownership boundary rather than relying on the generated resource's continued presence.
- [Operators delete a referenced Action Group] → Require reference checks before deletion and avoid unconditional cleanup commands.
- [Documentation implies the capacity alert is operationally complete] → Explicitly state that an empty Action Group ID array produces detection without notifications.
- [The known standalone gap remains unresolved] → Link the limitation to #79 and identify future Action Group ownership as a separate decision.
