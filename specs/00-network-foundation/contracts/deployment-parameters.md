# Deployment Parameter Contract

This contract defines the intended input shape. It is a design contract, not Bicep code.

## Common metadata

- Mode is selected by choosing the greenfield or brownfield entry point; it is not a Bicep mode
  switch.
- `location`
- `tags`: arbitrary object applied only to blueprint-owned resources
- `deployBastion`: boolean, default `false` for brownfield
- `policyInputs` (FR-019/FR-020), validated by `scripts/network/validate-policy-inputs.sh` and
  forwarded unchanged to the Foundry/APIM specs:
  - `publicNetworkAccessDisabled`: required boolean; MUST be `true`. `false`, null, omitted, and
    non-boolean values are rejected.
  - `localAuthDisabled`: required boolean; MUST be `true`. `false`, null, omitted, and
    non-boolean values are rejected.
  - `allowedModelSkus`: required non-empty array of exact, case-sensitive SKU strings. Each entry
    MUST be non-empty after trimming, unique, and free of wildcard or pattern characters. The
    network feature validates only this shape; the Foundry feature rejects a selected SKU that is
    not an exact member before model creation.

The policy-input object is required in both greenfield and brownfield modes. It is a posture and
allowlist contract, not a copy of live policy assignments; organization-specific policy names,
values, and discovery output remain outside committed artifacts. A downstream service that lacks a
corresponding setting must preserve the private-by-default posture rather than interpret `false`
as permission to enable public access or local authentication.

### Policy-input example

```json
{
  "policyInputs": {
    "publicNetworkAccessDisabled": true,
    "localAuthDisabled": true,
    "allowedModelSkus": [
      "generic-model-sku-a",
      "generic-model-sku-b"
    ]
  }
}
```

The validator MUST reject the following cases:

- `policyInputs` is missing, null, or not an object.
- Either boolean is missing, null, not a JSON boolean, or `false`.
- `allowedModelSkus` is missing, null, not an array, or empty.
- An SKU entry is not a string, is empty after trimming, is duplicated, or contains wildcard or
  pattern syntax.

The validator MUST preserve the original accepted string values when forwarding the object; it
must not normalize case, substitute defaults, or silently remove entries.

## Greenfield parameters

- VNet name and fixed address space
- Fixed workload subnet names and CIDRs from the specification
- Blueprint-owned NSG names
- Blueprint-owned Private DNS zone names
- Optional Bastion names and CIDR

Existing greenfield defaults remain backward compatible.

## Brownfield network parameters

- Existing VNet reference:
  - `<subscription-id>`
  - `<existing-vnet-resource-group>`
  - `<existing-vnet-name>`
- `<blueprint-resource-group>` in the same subscription as the existing VNet
- `deploymentKey` used to resolve prior blueprint-managed subnet outputs on rerun
- optional `adoptBlueprintManagedSubnets` list, requiring explicit network-owner approval and exact
  live-property validation when prior deployment history is unavailable
- New subnet request per workload purpose:
  - configurable `name`
  - approved `prefix`
  - selected `serviceProfile`
  - optional approved existing `networkSecurityGroupResourceId`
  - optional approved existing `routeTableResourceId`
- Blueprint-owned NSG names used only when an existing NSG ID is absent
- Optional Bastion subnet request and resource names

## Brownfield DNS parameters

- `dnsIntegrationMode`: `vnet-link` or `zone-group`, explicit and required; never inferred
- `dnsSubscriptionId`: subscription ID hosting the approved existing DNS zones; MAY differ from
  the workload/VNet subscription only in `zone-group` mode
- `dnsResourceGroupName`: resource group hosting the approved existing DNS zones; in `vnet-link`
  mode it MUST match the VNet resource group
- Per-service-role approved existing zone resource IDs (built from `dnsSubscriptionId` +
  `dnsResourceGroupName` + zone name), required only for roles deployed behind a private endpoint
  (see FR-016a)
- In `vnet-link` mode only: VNet-link request inputs (link name, registration flag, always
  disabled) for zones in the workload subscription and VNet resource group
- In `zone-group` mode only: no additional DNS-owner-scoped inputs; zone resource IDs are passed
  straight to the workload modules that build `privateDnsZoneConfigs`
- APIM is excluded from the per-service-role zone list when it uses VNet injection; it uses its
  own self-owned `azure-api.net` zone (blueprint-created, not centrally owned) instead

Parameters are not approved until discovery confirms address containment and available capacity.

## Sizing profile

Each subnet request records:

- `technicalMinimumPrefix`
- `recommendedPrefix`
- `requestedPrefix`
- expected endpoint/instance count
- Azure-reserved address count
- growth allowance and rationale

For the currently approved profiles:

- Foundry injection: technical minimum `/27`, blueprint POC recommendation `/26`, Microsoft
  production recommendation `/24` (see `spec.md` FR-013e). A `/26` caps concurrent agent sessions
  at ~50 under the default 1:1 IP-to-session ratio and MUST be recorded as an explicit capacity
  trade-off when the admin-allocated VNet cannot fit `/24`.
- Premium SKU on the confirmed `stv2` platform: technical minimum `/27`; SKU tier and platform
  version are separate properties, so this does not select Premium v2.
- Private endpoint and merged compute/CI/CD values are calculated from their expected consumers
  and current service requirements.
- See `spec.md` FR-013e for the POC `/25` example: Foundry `/27`, APIM `/27`, private endpoints
  `/28`, merged compute/CI/CD `/28`, and one `/27` spare.

## Brownfield DNS parameters

- Existing VNet resource ID
- One DNS owner scope per deployment invocation:
  - `<dns-subscription-id>`
  - `<dns-zone-resource-group>`
- Approved existing zone references in that owner scope:
  - generic zone resource ID
  - generic link name
- `registrationEnabled` is fixed to `false`

## Validation invariants

- Real customer values are supplied only through untracked deployment parameters or an approved
  external configuration system.
- Committed examples use placeholders and non-routable illustrative values only.
- Brownfield subnet names must not already exist.
- An existing requested subnet is accepted on rerun only when prior deployment outputs for the
  same `deploymentKey` identify it as blueprint-managed and properties match, or when it appears
  in the explicitly approved adoption list and every live property matches.
- Discovery and network/IPAM capacity approval must exist before parameter approval.
- Brownfield prefixes must be contained within the VNet and non-overlapping.
- Existing NSG, route-table, and zone references must resolve and remain read-only.
- No Bastion-specific value is required when Bastion is disabled.
- No organization-specific policy or tag name is embedded in the contract.
