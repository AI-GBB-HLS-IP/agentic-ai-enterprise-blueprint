# Feature Specification: Network Foundation (Greenfield and Brownfield)

**Feature Branch**: `feat/existing-vnet-network-foundation`

**Created**: 2026-08-13

**Status**: Greenfield mode implemented; brownfield adjustment in specification

**Input**: Issue #1 — initial Network Foundation; Issue #33 — customer-managed VNet support.

**Blueprint reference**: Chapters [01-foundry-byo-networking](../../chapters/01-foundry-byo-networking.md)
and [19-network-and-gateway](../../chapters/19-network-and-gateway.md).

## Scope Deviation from Blueprint (documented per Constitution Principle II)

The blueprint (Ch. 19) assumes a **hub-and-spoke** topology: a pre-existing hub VNet with Azure
Firewall, optional Bastion, ExpressRoute/VPN, and centralized Private DNS zones, with this platform
deployed as a spoke. The original greenfield implementation started without a hub; brownfield mode
must instead preserve the target environment's established network ownership boundaries.

**Greenfield POC decision**: deploy a **single, self-contained VNet**
(`vnet-agent-factory-poc`) that holds the required workload subnets, with optional Bastion, in
place of a hub-spoke peering. Azure Firewall and ExpressRoute are **out of scope** for greenfield
POC mode; NSGs provide traffic control instead of a hub firewall.

**Future migration path**: when moving beyond POC, this VNet becomes the spoke; peer it to a new
hub VNet, move Bastion/Firewall to the hub, and update UDRs to route egress through the hub
firewall. This is documented here so the deviation is never silently permanent.

## Clarifications

### Session 2026-09-03

- Q: How does brownfield deployment decide whether to create or reuse each required subnet?
  A: Brownfield mode targets a specific existing VNet but creates new, dedicated blueprint
  subnets. Reuse or reconciliation of existing subnets is out of scope. Deployment fails if a
  requested subnet name or CIDR conflicts with an existing subnet.
- Q: Who owns NSGs and route tables associated with newly created brownfield subnets?
  A: The blueprint creates dedicated NSGs unless an approved existing NSG is referenced. Route
  tables remain customer-managed: the blueprint may associate an approved existing route table
  but does not create or modify route tables or routes in brownfield mode.
- Q: Who creates and manages VNet links to centrally owned Private DNS zones in brownfield mode?
  A: The central DNS team owns the zones and DNS records. The blueprint creates and manages only
  the approved VNet links using supplied zone resource IDs.
- Q: How are subnet address sizes determined?
  A: Greenfield mode retains the fixed blueprint sizes for predictable deployment. Brownfield
  subnet sizes are configurable but must meet current Azure service minimums, include documented
  growth headroom, and receive customer network/IPAM approval.
- Q: How are brownfield changes applied when network and DNS resources have different owners?
  A: Use staged, owner-aligned deployments. The network owner applies subnet and approved
  association changes after a network-scoped what-if; the DNS owner applies approved VNet links
  after a DNS-scoped what-if.
- Q: What happens if the network stage succeeds but the DNS stage fails?
  A: Use roll-forward recovery. Keep the approved network changes, stop downstream progression,
  correct the DNS issue, rerun and approve the DNS-scoped what-if, and retry the DNS stage
  idempotently. Do not automatically remove approved resources across ownership boundaries.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Platform Engineer provisions the network from zero (Priority: P1)

As an IT Platform Engineer starting from an empty subscription, I need to stand up a VNet with
purpose-built subnets, NSGs, and Private DNS zones so that Foundry, APIM, and compute workloads
have a private, segmented network to deploy into — with no public exposure.

**Why this priority**: Nothing else in the blueprint (Foundry, APIM, agents) can be deployed
without this network existing first. It is the literal foundation.

**Independent Test**: Deploy the Bicep module to a fresh resource group; verify via `az network
vnet subnet list` that all 5 required subnets in FR-002 exist with correct address prefixes,
delegations, and NSG associations; verify Private DNS zones are linked to the VNet.

**Acceptance Scenarios**:

1. **Given** an empty resource group, **When** the network Bicep module is deployed, **Then** a
   VNet with address space `10.0.0.0/16` and the 5 required workload subnets (`snet-apim`,
   `snet-foundry`, `snet-compute`, `snet-privateendpoints`, and `snet-cicd-agents`) exists,
   matching the FR-002 table.
2. **Given** the VNet exists, **When** an NSG is inspected on the compute subnet, **Then** direct
   internet egress to AI services is denied except through the APIM subnet.
3. **Given** the VNet exists, **When** Private DNS zones for Foundry/OpenAI/APIM/Key
   Vault/Storage/SQL are queried, **Then** all zones exist and are linked to the VNet.

---

### User Story 2 - Platform Engineer optionally enables admin connectivity (Priority: P2)

As an IT Platform Engineer, I may enable an approved private administration method when the
environment does not already provide one, so that I can troubleshoot private connectivity without
making Bastion part of the required platform baseline.

**Why this priority**: Administrative connectivity is useful for interactive troubleshooting but
is not required when equivalent centrally managed access or non-interactive validation is
available.

**Independent Test**: With Bastion enabled, deploy it into `AzureBastionSubnet`, connect to a test
VM without a public IP, and resolve a private DNS name. With Bastion disabled, verify the what-if
contains no Bastion subnet, host, or public IP.

**Acceptance Scenarios**:

1. **Given** Bastion is explicitly enabled, **When** a platform engineer connects via the Azure Portal,
   **Then** they reach a test VM with no public IP assigned.
2. **Given** a private endpoint and its DNS zone exist, **When** `nslookup` is run from the test
   VM, **Then** it resolves to the private IP, not a public one.
3. **Given** Bastion is disabled, **When** the deployment is previewed or executed, **Then** no
   Bastion subnet, host, or public IP is created.

---

### User Story 3 - Team confirms quota/region before deployment (Priority: P1)

As the team planning this POC, I need to confirm Azure OpenAI/Foundry model quota (TPM) is
available in the target region before deploying network + Foundry, so that the network isn't
built in a region that later blocks model deployment.

**Why this priority**: Rework cost of re-deploying an entire VNet in a different region is high;
this must be resolved before infra work (see Issue #4, dependency of this spec).

**Independent Test**: Query current quota via `az cognitiveservices usage list` / Azure AI Foundry
quota page for the candidate region(s); confirm sufficient TPM for planned POC agent traffic.

**Acceptance Scenarios**:

1. **Given** a candidate region, **When** quota is queried, **Then** available TPM for the chosen
   model(s) meets or exceeds the POC traffic estimate, or a quota increase request has been filed
   and approved before proceeding.

---

### User Story 4 - Platform Engineer integrates with a customer-managed VNet (Priority: P1)

As an IT Platform Engineer deploying into an established Azure environment, I need to add only
the approved blueprint subnets to an existing VNet so that the platform uses customer-managed
network governance without taking ownership of the surrounding network.

**Why this priority**: Enterprise environments commonly provide centrally managed VNets,
peerings, DNS, routing, and security controls that the blueprint must preserve.

**Independent Test**: Select brownfield mode and provide generic references for the existing VNet,
configurable subnet names, and approved non-overlapping CIDRs. Verify with deployment what-if that
only the approved subnets and explicitly enabled supporting resources are proposed.

**Acceptance Scenarios**:

1. **Given** an existing VNet identified by `<subscription-id>`,
   `<existing-vnet-resource-group>`, and `<existing-vnet-name>`, **When** brownfield mode is
   selected, **Then** only approved blueprint subnets and explicitly enabled supporting resources
   are proposed.
2. **Given** the existing VNet has address spaces, peerings, custom DNS servers, DDoS settings,
   and unrelated subnets, **When** the deployment completes, **Then** those existing properties
   and resources remain unchanged.
3. **Given** a requested CIDR is outside the VNet address space or overlaps an existing or
   concurrently requested subnet, **When** validation runs, **Then** deployment is blocked before
   any network change.
4. **Given** private DNS and private administrative access are centrally provided, **When**
   brownfield mode is deployed, **Then** no blueprint-owned DNS zones, Bastion subnet, Bastion
   host, or public IP are created.
5. **Given** the VNet and blueprint resources are in different resource groups in the same
   subscription, or the DNS zones are in another permitted resource group or subscription,
   **When** permissions are validated, **Then** deployment proceeds only when the executing
   identity has the required access at every affected scope.
6. **Given** a discovery artifact contains customer-specific identifiers, **When** specification,
   planning, task, parameter, or validation artifacts are produced, **Then** only generic
   placeholders are committed and the source discovery artifact remains local.
7. **Given** a brownfield VNet is selected, **When** discovery runs, **Then** its address spaces,
   existing subnets, peerings, DNS configuration, DDoS settings, and relevant associations are
   inventoried before any subnet parameters or deployment previews are approved.

### Edge Cases

- What happens if the delegated Foundry subnet runs out of IPs during POC scaling? → Ch. 01
  recommends /24 sizing with 80% max utilization; POC uses /24 per subnet to leave headroom
- The existing VNet has insufficient unallocated address space for the requested subnets.
- A requested subnet name already exists with a different CIDR, delegation, NSG, or route table.
- The deployment identity can read the platform resource group but cannot modify the existing
  VNet or centrally managed private DNS resources.
- A management policy requires tags whose names and values are supplied only at deployment time.
- Customer-managed NSG or route-table associations are required for the new subnets.
  (see Requirements below).
- How does the system handle a region with insufficient OpenAI/Foundry quota? → Story 3 above
  blocks deployment until resolved; do not proceed with network deployment in an unconfirmed
  region.
- What happens when NSG rules conflict with Foundry/APIM's own required outbound rules (e.g.,
  Azure Front Door dependencies for APIM VNet-injected mode)? → Document required allow-rules
  from Microsoft's published service tags in `plan.md` before implementation.

## Prerequisites

Complete these checks before deploying the POC network or starting the Foundry/APIM epics.

### Subscription and Azure RBAC

- The executing identity must be a subscription **Owner**, or have **Contributor** plus
  **User Access Administrator**. For this spec's deployment via `az deployment group create`,
  **Contributor** (or **Owner**) at the target subscription or resource group scope is sufficient;
  it already includes the required `Microsoft.Network/*` permissions.
- User Access Administrator is required for later managed identity, service principal, and
  group-based role assignments. It is not needed to create the VNet resources in this spec,
  but must be available before downstream Foundry/APIM and governance work begins.
- The target subscription must be active, have a registered `Microsoft.Network` resource
  provider, and have sufficient regional quota for the selected POC location.

### Microsoft Entra ID

- The team must be able to create or request creation of Entra security groups for the three
  operating roles (for example: `sg-agentfactory-platform-engineering`, `sg-agentfactory-ai-coe`,
  and `sg-agentfactory-developers`).
- Group creation may be restricted by tenant policy. If the executing identity cannot create
  groups, an Entra Global Administrator / Groups Administrator (or other directory role permitted
  by tenant policy) must create them and can delegate ownership/membership management before
  role-assignment work starts.
- Do not grant developers direct Contributor, Owner, or User Access Administrator access to
  the POC subscription. Developers consume approved endpoints and contribute agent code through
  the PR workflow.

### Preflight checks

Run these checks after `az login` and `az account set`:

```bash
az account show --query "{subscription:id,name:name,tenant:tenantId,state:state}"
az role assignment list --assignee "$(az account show --query user.name -o tsv)" \
  --scope "/subscriptions/$(az account show --query id -o tsv)" \
  --include-inherited --query "[].{role:roleDefinitionName,scope:scope}" -o table
az provider show --namespace Microsoft.Network \
  --query "{namespace:namespace,registrationState:registrationState}" -o table
az group exists --name rg-agent-factory-poc
```

The output must show the intended subscription and tenant, an effective Contributor/Owner
assignment for the deployer, `Microsoft.Network` in `Registered` state, and a confirmed region
quota decision before deployment proceeds. Entra group creation is a tenant-level check and
must be confirmed with the tenant administrator when self-service group creation is disabled.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: In greenfield mode, the network MUST provide a single VNet
  (`vnet-agent-factory-poc`) with address space `10.0.0.0/16`, deployed via Bicep.
- **FR-002**: In greenfield mode, the VNet MUST contain the following workload subnets, matching
  Ch. 19's design (sizes increased to /24 per Ch. 01's 80%-utilization guidance where the
  blueprint used smaller ranges):

  | Subnet | Purpose | CIDR |
  |---|---|---|
  | `snet-apim` | APIM VNet injection | 10.0.1.0/24 |
  | `snet-foundry` | Foundry delegated subnet (Microsoft.App/environments) | 10.0.2.0/24 |
  | `snet-compute` | ACA / App Service compute | 10.0.3.0/24 |
  | `snet-privateendpoints` | Private endpoints (Storage, Key Vault, SQL, Foundry, OpenAI) | 10.0.4.0/24 |
  | `snet-cicd-agents` | Self-hosted CI/CD agents (if used) | 10.0.5.0/24 |
  When optional Bastion is enabled, the VNet MUST also contain `AzureBastionSubnet` using an
  approved `/26` or larger prefix; the greenfield default remains `10.0.6.0/26`.
- **FR-002a**: Both modes MUST implement the following purpose-keyed subnet contract. Brownfield
  names and CIDRs are configurable, but the purpose keys and service behaviors are stable:

  | Purpose key | Delegation | Private endpoint network policy | NSG profile |
  |---|---|---|---|
  | `apim` | None for classic Premium | Enabled | Required APIM control-plane profile |
  | `foundry` | `Microsoft.App/environments` | Enabled | Optional approved profile |
  | `compute` | Selected compute service requirement | Enabled | Required private-compute profile |
  | `privateEndpoints` | None | Disabled | Optional approved profile |
  | `cicdAgents` | None unless selected agent service requires it | Enabled | Optional approved profile |
  | `bastion` | None; optional fixed `AzureBastionSubnet` name | Enabled | Service-managed requirements |

- **FR-003**: The Foundry-purpose subnet MUST be delegated to `Microsoft.App/environments`.
- **FR-004**: NSGs MUST be applied to the APIM-purpose and compute-purpose subnets at minimum,
  denying direct internet egress from compute to AI services except through the approved gateway
  path.
- **FR-005**: In greenfield mode, Private DNS zones MUST be created and VNet-linked for:
  Foundry/Cognitive Services (`privatelink.cognitiveservices.azure.com`), Azure OpenAI
  (`privatelink.openai.azure.com`), APIM (`privatelink.azure-api.net`), Key Vault
  (`privatelink.vaultcore.azure.net`), Storage Blob (`privatelink.blob.core.windows.net`), and SQL
  (`privatelink.database.windows.net`) if used. Brownfield DNS ownership follows FR-016.
- **FR-006**: No subnet or resource in this spec MAY have a public IP assigned. When Bastion is
  explicitly enabled, its required public IP is the sole permitted exception.
- **FR-007**: Greenfield resources MUST remain deployable/re-deployable idempotently via
  `az deployment group create`. Brownfield network and DNS resources MUST be deployable through
  their owner-aligned scoped deployments and independently idempotent.
- **FR-008**: The deployment MUST be validated with `az deployment group what-if` prior to merge,
  with output attached to the PR (per Constitution Principle V).
- **FR-009**: The feature MUST support explicit `greenfield` and `brownfield` deployment modes;
  `greenfield` remains the default and retains the behavior in FR-001 through FR-008.
- **FR-010**: Brownfield mode MUST reference an existing VNet using separately configurable
  `<subscription-id>`, `<existing-vnet-resource-group>`, and `<existing-vnet-name>` values.
- **FR-011**: Brownfield mode MUST create only explicitly requested blueprint subnets and
  supporting resources and MUST NOT assume ownership of the existing VNet.
- **FR-011a**: Brownfield mode MUST create new, dedicated blueprint subnets in the selected
  existing VNet. Reuse, reconciliation, resizing, or repurposing of existing subnets is out of
  scope. Deployment MUST fail when a requested subnet name or CIDR conflicts with an existing
  customer-managed subnet. On rerun, an existing requested subnet is allowed only when a prior
  deployment output identifies it as blueprint-managed and its properties still match. If that
  ownership record is unavailable, an explicit network-owner-approved adoption list MAY restore
  ownership only when every live subnet property matches the request and associated
  blueprint-owned resources are verified; implicit adoption is prohibited.
- **FR-012**: Brownfield mode MUST NOT add, remove, or modify existing VNet address spaces,
  peerings, DNS-server settings, DDoS settings, or unrelated subnets.
- **FR-013**: Every requested brownfield subnet CIDR MUST be customer-approved, contained within
  the existing VNet address space, and non-overlapping with existing and concurrently requested
  subnets. Invalid allocation MUST block deployment before changes occur.
- **FR-013a**: Greenfield mode MUST retain the fixed subnet sizes in FR-002. Brownfield subnet
  sizes MUST be configurable and MUST pass validation against current service minimums and
  documented growth headroom before deployment.
- **FR-013b**: Brownfield planning MUST begin with a read-only discovery stage that inventories
  the selected VNet address spaces, existing subnet names and CIDRs, peerings, DNS configuration,
  DDoS settings, NSG and route-table associations, delegations, and available address capacity.
  Discovery MUST complete before subnet parameters are approved.
- **FR-013c**: The sizing gate MUST distinguish technical minimums from blueprint recommendations.
  For the currently approved service profiles, Foundry VNet injection MUST use `/27` or larger and
  SHOULD use `/26` or larger for POC growth headroom; classic Premium APIM MUST use `/29` or larger
  and SHOULD use `/27` or larger for POC growth headroom. Private endpoint, compute, and CI/CD
  subnet sizes MUST be derived from documented endpoint/instance counts, Azure-reserved addresses,
  service-specific requirements, and an approved growth allowance.
- **FR-013d**: Brownfield capacity approval MUST include a generic IPAM approval reference so
  automation does not claim authority over unallocated-but-reserved or externally routed ranges
  that are not visible from the VNet resource itself.
- **FR-014**: Blueprint subnet names MUST be configurable in brownfield mode. A fixed Azure
  service subnet name MAY be enforced only when that optional service is enabled.
- **FR-015**: Brownfield deployment MUST validate access to every affected resource group and
  subscription and fail safely when required read, subnet-management, association, or DNS-link
  permissions are absent. The existing VNet and blueprint workload resources MUST be in the same
  subscription for the approved classic Premium APIM profile; centrally owned Private DNS zones
  MAY be in other approved subscriptions within the same tenant.
- **FR-015a**: Brownfield changes MUST be separated into owner-aligned deployment stages. The
  network stage MUST contain only subnet, blueprint-managed NSG, and approved association changes.
  The DNS stage MUST contain only approved VNet-link changes. Each owner MUST review and approve a
  scoped what-if before applying its stage.
- **FR-015b**: A failed later stage MUST block downstream deployment but MUST NOT automatically
  roll back a successfully applied earlier owner-approved stage. Recovery MUST correct the failed
  stage, regenerate and reapprove its scoped what-if, and retry it idempotently.
- **FR-016**: Brownfield mode MUST support centrally owned private DNS zones without creating,
  replacing, or taking ownership of those zones or their records. The blueprint MUST accept
  approved zone resource IDs and create and manage only the VNet links to the selected existing
  VNet. DNS links MUST be deployed once per DNS-zone resource group and subscription so each
  deployment has one explicit owner scope.
- **FR-016a**: Brownfield DNS inputs MUST provide approved existing zones for active
  Cognitive Services/Foundry, Azure OpenAI, APIM, Key Vault, and Storage Blob roles. Optional
  service roles, including SQL, are required only when the corresponding downstream service is
  enabled.
- **FR-017**: Azure Bastion MUST be optional in both greenfield and brownfield modes. When
  disabled, no Bastion subnet, host, or public IP may be proposed.
- **FR-018**: NSG and route-table integration MUST be explicit and limited to approved new
  subnets. The blueprint MUST create a dedicated NSG unless an approved existing NSG resource ID
  is supplied. In brownfield mode, route tables MUST remain customer-managed: the blueprint MAY
  associate an approved existing route table but MUST NOT create or modify route tables or routes.
  It MUST NOT alter unrelated NSGs, route tables, or routes.
- **FR-019**: Blueprint-owned resources MUST declaratively align with applicable policies that
  disable public network access or local authentication where those settings are supported. No
  resource created directly by this spec (VNet, subnet, NSG, Private DNS zone, VNet link,
  Bastion) currently exposes a public-network-access or local-authentication toggle; this
  requirement governs the required boolean `publicNetworkAccessDisabled` and
  `localAuthDisabled` policy-input parameters (see the `Policy inputs` entity in
  `data-model.md`). Both values MUST be explicitly present and `true`; `false`, null, omitted,
  or non-boolean values fail validation because they would weaken the private-by-default
  baseline. This spec accepts the validated inputs and forwards them unchanged to the Foundry
  ([01-foundry-byo-networking](../01-foundry-byo-networking/spec.md)) and APIM
  ([02-apim-ai-gateway](../02-apim-ai-gateway/spec.md)) specs, which own the PaaS resources where
  these settings apply. A downstream service that does not expose one of the settings MUST treat
  the corresponding input as satisfied by design and MUST NOT introduce a public endpoint or
  local-authentication bypass.
- **FR-020**: Downstream model deployment parameters MUST reject serving SKUs prohibited by
  applicable policy before resource creation. This spec does not create model or serving
  resources; it MUST accept `allowedModelSkus` as a non-empty array of unique, non-empty,
  case-sensitive SKU strings with no wildcard or pattern entries, pass it through unchanged as
  part of the readiness output described in `plan.md`'s Downstream release step, and MUST NOT
  release network/DNS readiness to the Foundry spec until the list is present and well-formed.
  Enforcing that the selected deployment SKU is an exact member of this allowlist at
  resource-creation time is owned by the Foundry spec.
- **FR-021**: The deployment MUST accept arbitrary policy-required tags without assuming specific
  names or values and MUST apply them only to blueprint-owned resources.
- **FR-022**: Brownfield deployment MUST require review of `az deployment group what-if`; any
  proposed modification or deletion outside the approved boundary MUST block deployment.
- **FR-023**: Customer discovery output MUST remain local evidence only. It MUST NOT be committed,
  copied into repository artifacts, linked using an absolute path, or represented through
  customer-specific identifiers, names, email addresses, naming examples, or policy names.
- **FR-024**: Specifications, plans, tasks, examples, committed parameters, and validation
  evidence MUST use generic placeholders and MUST pass a confidentiality scan showing zero
  customer-specific identifiers derived from discovery.

### Key Entities

- **VNet**: `vnet-agent-factory-poc` — top-level container, address space `10.0.0.0/16`.
- **Subnet**: one per workload purpose (see FR-002 table); each has an address prefix, optional
  delegation, optional NSG association.
- **NSG**: security rule set attached to `snet-apim` and `snet-compute`.
- **Private DNS Zone**: one per Azure PaaS service requiring private endpoint resolution; each
  linked to the VNet.
- **Subnet purpose contract**: mode-independent mapping of purpose key to delegation,
  private-endpoint network policy, NSG profile, and sizing rule.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A platform engineer can deploy the required network from an empty resource group to
  fully provisioned (VNet + 5 required subnets + NSGs + DNS zones) in under 15 minutes via one
  `az deployment group create` command.
- **SC-002**: Zero public IPs exist when Bastion is disabled; when Bastion is enabled, its required
  public IP is the sole exception.
- **SC-003**: `az deployment group what-if` produces no unexpected changes when re-run against an
  already-deployed environment (idempotency).
- **SC-004**: DNS resolution for a private endpoint resource resolves to a private address from an
  approved in-network validation method; Bastion is one optional method.
- **SC-005**: Every approved brownfield what-if confines 100% of proposed changes to approved new
  subnets, associations, DNS links, and explicitly enabled supporting resources.
- **SC-006**: Brownfield deployment causes zero changes to existing VNet address spaces, peerings,
  DNS-server settings, DDoS settings, and unrelated subnets.
- **SC-007**: 100% of requested subnet CIDRs pass approval, containment, and non-overlap
  validation before deployment.
- **SC-007a**: 100% of brownfield deployments have a completed, reviewed discovery and capacity
  result before subnet parameter approval or `what-if`.
- **SC-008**: Disabling optional Bastion results in zero Bastion-related resources in the
  deployment preview.
- **SC-009**: Confidentiality review finds zero discovery-derived customer identifiers, names,
  naming samples, or organization-specific policy names in committed repository artifacts.
- **SC-010**: 100% of Network Foundation deployment previews are blocked before resource creation
  unless `policyInputs` is present and valid: `publicNetworkAccessDisabled` and `localAuthDisabled`
  are explicit `true` booleans, and `allowedModelSkus` is a non-empty array of unique, non-empty,
  exact SKU strings with no wildcard or pattern entries. Every accepted preview reports
  `policy-compliant: true`, and the policy-input values forwarded to Foundry/APIM are semantically
  identical to the validated inputs without defaults, filtering, case normalization, or
  substitution.

## Assumptions

- Greenfield POC region and model quota were validated during the original implementation.
  Reconfirm current regional availability and compare live quota with the final traffic estimate
  before every new deployment; do not copy subscription-specific quota output into reusable
  artifacts.
- No pre-existing hub VNet, ExpressRoute, or ExpressRoute/VPN Gateway is available — confirmed
  greenfield subscription per user's original request.
- Azure Firewall is deferred; NSGs are sufficient traffic control for POC scope. This will be
  revisited if/when this environment is promoted beyond POC (see Scope Deviation above).
- When Bastion is enabled, its subnet uses Azure's required fixed name, `AzureBastionSubnet`.
  Bastion remains disabled when centrally managed access or another approved validation method is
  available.
- Subscription-level permissions (Contributor + Network Contributor at minimum) are available to
  the platform engineer executing this spec; broader Entra ID prerequisites are tracked separately
  in Issue #5.
- Team size is 2–3 people (per constitution); this spec does not need multi-region or
  multi-environment (dev/staging/prod) network topology yet — POC is single-environment.
