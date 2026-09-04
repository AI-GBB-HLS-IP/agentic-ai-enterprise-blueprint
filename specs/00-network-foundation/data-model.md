# Data Model: Network Foundation Deployment

## Input and ownership entities

| Entity | Key fields | Validation and ownership rules |
|---|---|---|
| Deployment mode | `greenfield` or `brownfield` | Explicit; greenfield remains the default. |
| Existing VNet reference | subscription, resource group, name, resource ID, location, address prefixes | Brownfield prerequisite; read-only. It shares a subscription with blueprint workloads for the approved APIM profile. Address spaces, peerings, DNS servers, DDoS settings, and customer-managed subnets are immutable. |
| VNet discovery result | address spaces, existing subnet names/CIDRs, delegations, NSG/route-table associations, peerings, DNS configuration, DDoS settings, unallocated ranges | Local read-only evidence produced before parameter approval; raw customer values are not committed. |
| Capacity plan | subnet purpose, technical minimum, recommended size, requested size, expected consumers, reserved addresses, growth allowance, approval state | Foundry: `/27` minimum and `/26` recommended for POC; classic Premium APIM: `/29` minimum and `/27` recommended for POC; other subnet sizes require workload calculations. |
| Subnet request | purpose, name, CIDR, service profile, delegation, private-endpoint policy, NSG mode/ID, route-table ID | Brownfield requests always create new subnets. Name and CIDR must not conflict; CIDR must be contained, service-compatible, approved, and include documented headroom. |
| NSG selection | `blueprint-managed` or `existing`, resource ID, required rule profile | Blueprint-managed NSGs may be created/updated. Existing NSGs are referenced and validated but never modified. |
| Route-table selection | optional existing resource ID | Brownfield reference only. The feature can associate it with a new subnet but cannot create or modify route tables or routes. |
| Private DNS zone reference | service role, zone resource ID, zone name, owner scope | Brownfield prerequisite; zone and records are read-only. |
| VNet-link request | zone resource ID, VNet resource ID, link name, registration flag | Blueprint-managed child resource; registration must be disabled. |
| Bastion selection | enabled, subnet CIDR, host name, public IP name, tags | Optional. Disabled means no Bastion-related resources. |
| Policy inputs | `publicNetworkAccessDisabled`, `localAuthDisabled`, `allowedModelSkus` | Required deployment-time object. Both booleans must be present and `true`; `allowedModelSkus` must be a non-empty array of unique, non-empty, case-sensitive SKU strings with no wildcards or patterns. This spec creates no resource exposing public-network-access or local-auth settings and no model/serving resource; it validates schema/posture, then forwards the values unchanged to Foundry/APIM, which enforce applicability. |
| Approval evidence | stage, owner role, what-if digest, decision, timestamp, redaction status | Required before each mutating stage; committed evidence contains no customer identifiers. |
| Deployment ownership record | deployment key, prior deployment name, managed subnet IDs, expected properties | Local/live ARM deployment output used to permit idempotent reruns without adopting customer-managed subnets. |
| Ownership adoption approval | deployment key, approved subnet names, live-property comparison, network-owner approval | Exceptional fallback when deployment history is unavailable; accepted only for exact property matches and never implicit. |

## Managed resource states

| State | Meaning |
|---|---|
| `unvalidated` | Input exists but live preflight has not completed. |
| `discovered` | Required VNet state was inventoried and available capacity was calculated locally. |
| `capacity-approved` | Network/IPAM owner approved requested CIDRs and documented sizing rationale. |
| `blocked` | A conflict, capacity issue, missing permission, policy incompatibility, or confidentiality issue prevents preview/deployment. |
| `validated` | Read-only preflight passed for the stage. |
| `previewed` | Scoped `what-if` completed and stayed within the stage contract. |
| `approved` | The responsible owner approved the redacted preview. |
| `deployed` | The stage deployment completed successfully. |
| `ready` | Post-deployment and idempotency checks passed. |
| `failed` | The stage failed and downstream deployment is blocked pending roll-forward remediation. |

## Relationships

```text
Deployment mode
  ├─ greenfield -> blueprint VNet -> fixed subnets -> blueprint DNS zones/links
  └─ brownfield -> existing VNet reference
                    -> subnet requests
                       -> blueprint or existing NSG
                       -> optional existing route table
                    -> existing DNS zone references
                       -> blueprint-managed VNet links
                    -> optional Bastion
```

## Stage transitions

### Network stage

```text
unvalidated -> discovered -> capacity-approved -> validated -> previewed -> approved -> deployed -> ready
      |              |                 |              |           |           |          |
      +------------> blocked <---------+--------------+-----------+-----------+----------+
```

### DNS stage

The DNS stage starts only after the network stage is `ready`. If DNS becomes `failed`, the network
stage remains `ready`; downstream Foundry/APIM work remains blocked until DNS is corrected,
re-previewed, reapproved, redeployed, and returned to `ready`.

Any stage whose approved parameters change transitions from `ready` back to `previewed` and
requires renewed owner approval before deployment.

## Global readiness

Network Foundation readiness is true only when:

- the selected mode's required network stage is `ready`;
- required Private DNS integration is `ready`;
- optional Bastion is either disabled or independently `ready`;
- no out-of-bound modification is present;
- the FR-019/FR-020 generic policy-input parameters are present and well-formed
  (`policy-compliant`), so downstream Foundry/APIM specs can enforce them;
- the confidentiality gate passes.
