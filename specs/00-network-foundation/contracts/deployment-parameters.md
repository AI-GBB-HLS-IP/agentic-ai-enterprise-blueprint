# Deployment Parameter Contract

This contract defines the intended input shape. It is a design contract, not Bicep code.

## Common metadata

- Mode is selected by choosing the greenfield or brownfield entry point; it is not a Bicep mode
  switch.
- `location`
- `tags`: arbitrary object applied only to blueprint-owned resources
- `deployBastion`: boolean, default `false` for brownfield

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

- Foundry injection: technical minimum `/27`, blueprint POC recommendation `/26`.
- Classic Premium APIM: technical minimum `/29`, blueprint POC recommendation `/27`.
- Private endpoint, compute, and CI/CD values are calculated from their expected consumers and
  current service requirements.

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
