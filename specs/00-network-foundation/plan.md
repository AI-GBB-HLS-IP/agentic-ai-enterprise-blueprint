# Implementation Plan: Network Foundation (Greenfield and Brownfield)

**Branch**: `feat/existing-vnet-network-foundation` | **Date**: 2026-09-03 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/00-network-foundation/spec.md`

## Summary

Preserve the implemented greenfield network foundation while adding a separate brownfield path
that targets an approved existing VNet and creates only new, dedicated blueprint subnets. The
brownfield path is split into network-owner and DNS-owner stages, each with an independent
preflight, scoped `what-if`, approval, deployment, and idempotency check. Existing VNet
configuration, existing subnets, centrally owned DNS zones and records, existing NSGs, route
tables, routes, peerings, and unrelated resources remain outside the deployment ownership
boundary. Bastion is optional in both modes.

The current uncommitted infrastructure edits are an exploratory prototype only. They are not the
approved design and must be reconciled or replaced after `tasks.md` is regenerated from this plan.

## Technical Context

**Language/Version**: Bicep through the repository-supported Azure CLI; Bash and `jq` for
deterministic preflight and confidentiality validation

**Primary Dependencies**: Azure Resource Manager; `Microsoft.Network` virtual networks, subnets,
network security groups, route-table references, private DNS zones, and VNet links; Azure CLI;
Bicep CLI

**Storage**: N/A

**Testing**: `az bicep build`, parameter compilation, read-only Azure CLI preflight,
network-owner-scoped `az deployment group what-if`, DNS-owner resource-group-scoped `what-if`,
post-deployment
resource inspection, private DNS resolution, idempotency comparison, and confidentiality scanning

**Target Platform**: Single-region Azure deployments supporting:

- greenfield mode in a blueprint-owned resource group and VNet;
- brownfield mode where the existing VNet and blueprint resource group can be different resource
  groups in the same subscription, while centrally owned Private DNS zones can reside in other
  approved resource groups or subscriptions within one tenant.

**Project Type**: Infrastructure-as-code modules, environment compositions, validation scripts,
and deployment contracts

**Performance Goals**: Preflight must reject invalid brownfield input before any resource change;
unchanged reruns must produce no unexpected changes; each deployment stage must be independently
retryable

**Constraints**:

- Greenfield retains the fixed VNet and subnet sizes in the specification.
- Brownfield CIDRs are deployment inputs approved by the network/IPAM owner.
- Brownfield creates new dedicated subnets only; existing subnet reuse or reconciliation is
  prohibited.
- Existing VNet address spaces, peerings, DNS servers, DDoS settings, and unrelated subnets are
  immutable.
- Blueprint-owned NSGs are the default; approved existing NSGs can be referenced but not modified.
- Brownfield route tables are approved existing references only.
- Centrally owned Private DNS zones and records are immutable; the blueprint manages approved VNet
  links only.
- Bastion is opt-in and must produce no subnet, host, or public IP when disabled.
- Customer discovery information must not enter committed artifacts.

**Scale/Scope**: One greenfield environment composition and two brownfield deployment stages
(network and DNS). Multi-region topology, hub creation, firewall/route creation, existing subnet
adoption, and customer-specific parameter files are out of scope.

## Constitution Check

*GATE: Evaluated before research and re-evaluated after design.*

| Principle | Check | Pre-design | Post-design |
|---|---|---|---|
| I. Separation of Duties | Network and DNS changes are split into owner-aligned stages; developers receive no infrastructure permissions. | PASS | PASS |
| II. Spec Before Infra | Clarified spec precedes the approved design. Existing uncommitted Bicep is explicitly non-authoritative and cannot be committed until reconciled with generated tasks. | PASS with remediation | PASS with remediation |
| III. Private by Default | No public endpoint is introduced; Bastion is an explicit optional exception with no resources when disabled. | PASS | PASS |
| IV. Incremental, Testable Slices | Preflight, network stage, DNS stage, and optional Bastion are independently previewed and validated. | PASS | PASS |
| V. IaC Validated Before Merge | Every mutating stage requires build, scoped `what-if`, owner approval, deployment evidence, and idempotency validation. | PASS | PASS |

**Required remediation for Principle II**: do not commit the exploratory infrastructure delta as
implemented work. After `speckit.tasks`, compare every prototype file with this plan and either
replace it or update it task-by-task before validation.

No constitution amendment or exception is required. Brownfield support is a reusable deployment
mode; it does not redefine the constitution's original greenfield POC scope.

## Project Structure

### Documentation

```text
specs/00-network-foundation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── deployment-parameters.md
│   ├── network-stage.md
│   └── dns-stage.md
└── tasks.md                 # regenerated after this planning phase
```

### Planned source layout

```text
infra/
├── modules/network/
│   ├── main.bicep                  # greenfield composition; preserves existing defaults
│   ├── subnets.bicep               # new-subnet resources shared by both modes
│   ├── nsg.bicep                   # blueprint-owned NSGs
│   ├── private-dns.bicep           # greenfield zone creation and links
│   ├── private-dns-link.bicep      # brownfield link-only module for an existing zone
│   └── bastion.bicep               # optional Bastion host and public IP
├── envs/poc/
│   ├── main.bicep                  # greenfield environment entry point
│   ├── network.parameters.json     # greenfield parameters
│   ├── brownfield-network.bicep    # network-owner deployment stage
│   ├── brownfield-network.bicepparam.example
│   ├── brownfield-dns.bicep        # DNS-owner deployment stage
│   └── brownfield-dns.bicepparam.example
└── README.md

scripts/network/
├── discover-existing-vnet.sh
├── validate-brownfield-inputs.sh
├── validate-dns-inputs.sh
├── validate-network-what-if.sh
├── validate-dns-what-if.sh
└── scan-confidentiality.sh
```

**Structure Decision**: Keep greenfield and brownfield environment entry points separate. Shared
modules may create new subnets and blueprint-owned NSGs, but brownfield DNS uses a link-only module
so it cannot create or modify centrally owned zones or records. Separate root deployments enforce
owner-aligned permissions and evidence.

## Phase 0: Research

Research decisions are recorded in [research.md](research.md):

1. Separate greenfield and brownfield environment compositions.
2. Validate service-aware brownfield subnet sizing rather than imposing one universal CIDR size.
3. Reject existing subnet names and overlaps before deployment.
4. Support blueprint-owned or approved existing NSGs; support approved existing route tables only.
5. Use existing-zone VNet-link resources for brownfield DNS.
6. Use staged owner-aligned deployment and roll-forward recovery.
7. Make Bastion a fully conditional slice in both modes.
8. Apply arbitrary tags only to blueprint-owned resources.
9. Treat confidentiality validation as a merge gate.

No `NEEDS CLARIFICATION` items remain.

## Phase 1: Design

### Deployment flow

1. **Prepare generic parameters**
   - Select `greenfield` or `brownfield`.
   - Keep real brownfield names, IDs, CIDRs, and policy-required tag values in an untracked
     deployment parameter file or approved secret/configuration system.
   - Accept the policy-input parameters defined by FR-019/FR-020 and fail closed unless
     `publicNetworkAccessDisabled: true`, `localAuthDisabled: true`, and a non-empty
     `allowedModelSkus` array of unique, non-empty, exact SKU strings without wildcards or pattern
     entries are supplied. This spec creates no resource that itself exposes these settings; it
     forwards the validated values unchanged to the Foundry and APIM specs (see Downstream release
     below).

2. **Brownfield discovery**
   - Resolve the selected VNet and inventory its address spaces, existing subnet names/CIDRs,
     delegations, NSG/route-table associations, peerings, DNS configuration, and DDoS settings.
   - Calculate currently unallocated address ranges without proposing changes.
   - Produce a local discovery/capacity result for network/IPAM review. Do not commit raw output.

3. **Brownfield parameter approval**
   - Define new dedicated subnet names and CIDRs only after discovery.
   - Require Foundry `/27` as the current platform minimum and `/26` or larger as the blueprint
     POC recommendation.
   - Require classic Premium APIM `/29` as the technical platform minimum and `/27` or larger as
     the blueprint POC recommendation.
   - Size private endpoint, compute, and CI/CD subnets from expected endpoint/instance counts,
     Azure-reserved addresses, service-specific requirements, and documented growth allowance.
   - Record a generic IPAM approval reference outside committed customer-specific artifacts.

4. **Brownfield read-only preflight**
   - Resolve the selected VNet and confirm the expected tenant, subscription, resource group, and
     location.
   - Read all VNet address spaces and existing subnet names/prefixes.
   - Reject duplicate names, CIDRs outside the VNet, overlaps with existing/requested subnets, and
     service profiles below current minimums or without documented growth headroom.
   - Resolve supplied NSG and route-table IDs and validate read/association permissions without
     changing resources.

5. **Network-owner stage**
   - Deploy the root composition to the blueprint resource group.
   - Create only approved new subnets through a module scoped to the existing VNet resource group.
   - Create blueprint-owned NSGs and optional Bastion resources in the blueprint resource group
     where an approved existing NSG ID is not supplied.
   - Associate approved existing NSGs and route tables without modifying them.
   - Create optional `AzureBastionSubnet` and Bastion resources only when enabled.
   - Build, run a network-scoped `what-if`, reject out-of-bound changes, obtain network-owner
     approval, deploy, and validate.

6. **DNS-owner stage**
   - Accept approved existing Private DNS zone IDs.
   - Validate zone resolution, VNet-link permissions, and existing link-name conflicts without
     changing resources.
   - Create or manage only VNet-link child resources with registration disabled.
   - Group approved zone references by DNS subscription and resource group.
   - Build and run one resource-group-scoped DNS `what-if` per zone-owner scope, using an explicit
     subscription selection; reject zone/record changes, obtain DNS-owner approval, deploy, and
     validate resolution.

7. **Downstream release**
   - Release Foundry and APIM deployment only when required network and DNS states are `ready`
     AND the FR-019/FR-020 policy-input parameters are present and well-formed
     (`policy-compliant`); this spec does not evaluate whether a specific SKU or resource setting
     satisfies policy, only that the required generic inputs passed the schema and posture checks
     for the downstream spec to enforce.
   - If DNS fails after network succeeds, preserve network resources, block progression, correct
     DNS, regenerate and approve the DNS preview, and retry only the DNS stage.

### Module boundaries

- **Shared subnet module**: creates new subnets beneath a supplied VNet name. It must not declare
  or update the VNet parent properties. Subnet child writes must be serialized (for example, a
  resource loop with `@batchSize(1)`) to avoid concurrent VNet update conflicts.
- **NSG module**: creates only blueprint-owned NSGs and rules. Existing NSG IDs bypass creation and
  remain read-only.
- **Brownfield network entry point**: deploys to the blueprint resource group, creates
  blueprint-owned NSGs and optional Bastion there, and invokes a subnet module scoped to the
  existing VNet resource group in the same subscription. It accepts route-table IDs but contains
  no route-table or route resources.
- **Greenfield DNS module**: retains blueprint-owned zone creation and VNet links.
- **Brownfield DNS entry point/link module**: deploys once per DNS-zone resource group and
  subscription, accepts existing zone names/IDs from that scope plus the VNet ID, and creates only
  link child resources.
- **Bastion module**: remains independent and conditional; disabling it removes all Bastion-related
  resources from the compiled deployment.

### Fail-closed validation

The preflight and preview gates must fail when:

- the selected existing VNet cannot be resolved or is in an unapproved scope;
- a requested subnet name already exists;
- an existing requested subnet is not identified by prior deployment outputs as blueprint-managed
  for the same deployment key and is not present in an explicit network-owner-approved adoption
  list whose live properties fully match;
- discovery or network/IPAM capacity approval is missing;
- a requested CIDR is outside every VNet address prefix;
- requested CIDRs overlap each other or any existing subnet;
- a service-specific subnet size/delegation requirement is not met;
- an approved existing NSG, route table, or Private DNS zone cannot be resolved;
- required permissions are missing;
- `what-if` contains a modification/deletion outside the stage contract;
- Bastion resources appear when Bastion is disabled;
- a brownfield DNS preview creates/modifies zones or records;
- a committed artifact contains discovery-derived customer data.

### Validation evidence

Store only redacted, generic evidence:

- preflight result with statuses and generic resource roles;
- discovery and capacity status with customer values removed;
- prior deployment ownership/output status used to distinguish idempotent reruns from adoption of
  customer-managed subnets;
- network and DNS `what-if` change types without customer identifiers;
- subnet purpose, size validation, delegation, and association status;
- DNS-link and private-resolution status;
- idempotency result for each stage;
- confidentiality scan result.

Do not commit raw discovery output, real parameter files, tenant/subscription identifiers, email
addresses, concrete customer resource names, customer CIDRs, or organization-specific policy
names.

## Complexity Tracking

| Complexity | Why required | Simpler alternative rejected |
|---|---|---|
| Separate brownfield network and DNS deployments | Network and DNS resources have different owners and permissions; the specification requires independent approvals and retries. | One cross-scope deployment would require excessive permissions and weaken separation of duties. |
| Read-only preflight script before Bicep | ARM `what-if` alone cannot express every approval, service-minimum, overlap, and confidentiality gate before deployment. | Relying only on deployment failure would discover invalid allocation too late. |
| Separate greenfield zone module and brownfield link-only module | Brownfield must be structurally unable to create or modify central zones and records. | A conditional all-in-one DNS module leaves a broader accidental ownership surface. |
