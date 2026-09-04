# Research: Greenfield and Brownfield Network Foundation

## R1: Deployment-mode structure

**Decision**: Preserve the existing greenfield entry point and add separate brownfield network and
DNS entry points.

**Rationale**: Greenfield owns the VNet and Private DNS zones, while brownfield owns only approved
new subnets, optional blueprint NSGs, optional Bastion resources, and approved VNet links. Separate
entry points make those ownership differences visible in compiled templates and scoped previews.

**Alternatives considered**:

- One root template with a mode switch: rejected because conditional resources retain a broad
  ownership surface and complicate owner-aligned approvals.
- Replace greenfield with brownfield-only composition: rejected because it would break the
  implemented POC path.

## R2: Brownfield subnet sizing

**Decision**: Keep greenfield CIDRs fixed. Make brownfield CIDRs configurable and validate them
against the selected Azure service profile, current published minimums, expected instance/endpoint
count, Azure-reserved addresses, and documented growth headroom.

**Rationale**: Existing enterprise VNets have different address constraints, and service minimums
vary by service tier and deployment model. A universal brownfield `/24` rule is unnecessarily
restrictive, while accepting any syntactically valid CIDR risks immediate exhaustion.

**Alternatives considered**:

- Fixed sizes in both modes: rejected because it prevents deployment into valid constrained VNets.
- Service minimum only: rejected because it provides no operational growth margin.
- A single minimum for every subnet: rejected because APIM, delegated compute, private endpoints,
  CI/CD agents, and optional Bastion consume addresses differently.

**Implementation note**: Minimums must be maintained as named validation rules with documentation
references, not scattered hard-coded assumptions. The deployment owner must reconfirm them when
Azure service tiers or APIs change.

For the currently approved profiles:

- Foundry Agent Service VNet injection requires a subnet delegated to
  `Microsoft.App/environments` with `/27` or larger. The blueprint recommends `/26` or larger for a
  POC unless a documented capacity calculation supports a smaller allocation.
- Classic Developer/Premium APIM supports `/29` as its technical minimum. The blueprint recommends
  `/27` or larger for a POC to allow scaling beyond one unit.
- Private endpoint, compute, and CI/CD subnet sizes are workload calculations, not universal
  constants. Each calculation must include Azure-reserved addresses, expected resource count,
  service-specific consumption, and growth allowance.

References:

- [Foundry Agent Service private networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [API Management VNet injection resources](https://learn.microsoft.com/azure/api-management/virtual-network-injection-resources)

## R2a: Brownfield discovery before allocation

**Decision**: Add a distinct read-only discovery stage before brownfield parameter approval and
preflight.

**Rationale**: Safe subnet allocation requires the complete VNet address spaces, existing subnet
prefixes, peerings, DNS configuration, DDoS settings, delegations, and NSG/route-table
associations. Parameterizing CIDRs before collecting that state can produce overlaps or violate
central network controls.

**Alternatives considered**:

- Use only user-supplied VNet and CIDR parameters: rejected because the deployment would not
  independently validate available capacity.
- Discover during deployment: rejected because discovery must inform network/IPAM approval before
  a mutating preview.

## R3: Existing subnet handling

**Decision**: Brownfield creates new dedicated subnets and rejects any requested name that already
exists unless prior deployment outputs identify that exact subnet as blueprint-managed by the same
deployment.

**Rationale**: Updating a customer-managed subnet declaration can unintentionally replace delegation,
NSG, route-table, service-endpoint, or private-endpoint-policy settings. Rejecting name and CIDR
conflicts provides a deterministic no-modification boundary, while deployment outputs preserve
idempotent reruns of blueprint-managed subnets without treating them as adopted resources.

**Alternatives considered**:

- Reuse compatible existing subnets: rejected for this increment because compatibility and
  ownership rules would be customer-specific.
- Reconcile existing subnets: rejected because it violates the clarified specification.

## R4: NSG and route-table ownership

**Decision**: Create dedicated blueprint NSGs by default, allow approved existing NSG resource IDs,
and allow only approved existing route-table resource IDs in brownfield mode.

**Rationale**: The blueprint can provide secure defaults without taking ownership of centralized
routing. Existing NSGs and route tables are references only; their rules and routes are immutable
to this feature.

**Alternatives considered**:

- Customer-managed controls only: rejected because it makes a reusable secure baseline harder to
  deploy.
- Blueprint-created route tables: rejected because routing is commonly governed by the VNet owner
  and can affect traffic beyond the blueprint.

## R5: Central Private DNS integration

**Decision**: Brownfield accepts approved existing Private DNS zone IDs and creates/manages only
VNet links with registration disabled.

**Rationale**: This preserves central ownership of zones and records while making the required VNet
integration declarative and testable.

**Alternatives considered**:

- Blueprint creates duplicate zones: rejected because duplicate zone ownership fragments name
  resolution.
- DNS owner performs links manually: rejected because tracked infrastructure must remain IaC.
- One module that can create zones or links: rejected for brownfield because it broadens the
  accidental modification boundary.

## R6: Cross-scope deployment and failure recovery

**Decision**: Use separate network-owner and DNS-owner stages with independent preflight,
`what-if`, approval, deployment, and idempotency checks. Use roll-forward recovery.

The network root deploys to the blueprint resource group and scopes subnet child deployment to the
existing VNet resource group in the same subscription. DNS is executed once per approved DNS-zone
resource group and subscription. This follows the classic Premium APIM requirement that APIM and
its VNet remain in the same subscription while still supporting centrally owned DNS elsewhere.

**Rationale**: Separate stages follow least privilege and separation of duties. If a later DNS
stage fails, approved network resources remain valid; automatically deleting them would cross
ownership boundaries and could create additional risk.

**Alternatives considered**:

- One identity deploys every scope: rejected because it requires broad cross-scope permissions.
- Automatic rollback: rejected because rollback can remove already approved shared-network
  changes.
- Manual portal integration: rejected by the IaC constitution.

## R7: Optional Bastion

**Decision**: Bastion is disabled by default for brownfield and optional in greenfield. When
disabled, no Bastion subnet, host, or public IP is compiled into the deployment.

**Rationale**: Enterprise environments may already provide private administration. Avoiding
unneeded Bastion resources preserves address space and eliminates an unnecessary public IP.

**Alternatives considered**:

- Always deploy Bastion: rejected by the clarified specification.
- Always omit Bastion: rejected because greenfield environments may require an approved
  administration path.

## R8: Policy-compatible parameters

**Decision**: Accept arbitrary tags and apply them only to blueprint-owned resources. Expose
supported public-network and local-authentication controls declaratively in downstream modules,
and validate downstream model SKU choices against applicable policy before deployment.

**Rationale**: Policy assignments vary by environment. Generic parameters keep the blueprint
portable without embedding organization-specific policy names or values.

**Alternatives considered**:

- Hard-code observed tag names or policy behavior: rejected as non-portable and confidential.
- Depend on policy remediation after deployment: rejected because the desired state should align
  before resource creation.

## R9: Confidentiality gate

**Decision**: Treat discovery output and real brownfield parameter values as local deployment
inputs. Commit only generic placeholders and redacted validation evidence.

**Rationale**: Discovery can contain identities, IDs, names, CIDRs, peer details, and policy names
that do not belong in a reusable public blueprint.

**Alternatives considered**:

- Commit sanitized discovery output: rejected because sanitization can miss identifying
  combinations.
- Commit customer parameter files in a private folder: rejected because repository history still
  retains the data.
