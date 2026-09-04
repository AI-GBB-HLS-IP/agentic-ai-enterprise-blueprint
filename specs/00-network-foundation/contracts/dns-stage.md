# Brownfield DNS Stage Contract

## Owner and scope

The central DNS owner reviews and applies this resource-group-scoped stage after the network stage
is ready. Run it once per DNS-zone resource group and subscription with explicit scope selection.
The
deployment identity requires permission to read the approved existing zones and create/manage only
their VNet-link child resources.

## Allowed changes

- Create or update an approved VNet link beneath an approved existing Private DNS zone.
- Set the link to the approved existing VNet resource ID.
- Keep registration disabled.

## Forbidden changes

- Create, delete, or modify Private DNS zones.
- Create, delete, or modify DNS record sets.
- Link an unapproved VNet or zone.
- Enable automatic registration.
- Modify network-stage resources.

## Required preview assertions

The stage is blocked unless every proposed change is a VNet-link child resource under an approved
existing zone. Zone or record changes, deletes, or unrelated resource changes fail the gate.

## Recovery

If the DNS stage fails after the network stage succeeds:

1. Keep the approved network-stage resources.
2. Block downstream deployment.
3. Correct the DNS input or permission issue.
4. Regenerate and reapprove the DNS-scoped `what-if`.
5. Retry the DNS stage idempotently.

## Outputs

- VNet-link IDs keyed by service role
- Zone-reference validation status
- Private-resolution validation status
- Structured stage status
