# Brownfield Network Stage Contract

## Owner and scope

The customer network owner reviews and applies the root deployment to the approved blueprint
resource group. A nested module creates subnet children in the existing VNet resource group in the
same subscription. The
deployment identity requires only the permissions needed to read the VNet, create the approved new
subnets, create blueprint-owned NSGs when selected, and associate approved existing NSGs or route
tables.

## Allowed changes

- Create approved new dedicated workload subnets.
- Apply the required service delegation and private-endpoint network-policy setting to those new
  subnets.
- Create/update blueprint-owned NSGs and their approved rule profiles.
- Associate an approved existing NSG with a new subnet without modifying the NSG.
- Associate an approved existing route table with a new subnet without modifying the route table
  or routes.
- When enabled, create `AzureBastionSubnet` through the VNet-resource-group-scoped subnet module,
  and create the Bastion host and required public IP in the blueprint resource group.

## Forbidden changes

- Create, delete, resize, or update the existing VNet.
- Change VNet address spaces, peerings, DNS servers, DDoS settings, or tags.
- Reuse, resize, reconcile, delete, or modify any customer-managed subnet.
- Modify an existing NSG or its rules.
- Create or modify route tables or routes.
- Create Private DNS zones, records, or VNet links.
- Create Bastion-related resources when Bastion is disabled.

## Required preview assertions

The stage is blocked unless:

- every change is a create/update of a blueprint-owned resource or an approved association on a
  newly created subnet;
- there are no deletes;
- the VNet appears only as an existing parent/reference;
- every requested subnet name and CIDR passed preflight, or a prior deployment output identifies
  the matching subnet as blueprint-managed for an idempotent rerun, or an explicit
  network-owner-approved adoption record exists and live properties match;
- no existing NSG or route-table resource is modified;
- Bastion resources match the explicit enablement choice.

## Outputs

- Existing VNet resource ID
- New subnet IDs keyed by workload purpose
- Blueprint-owned NSG IDs and approved existing NSG associations
- Approved route-table associations
- Optional Bastion resource IDs
- Structured stage status
