## Context

See `proposal.md` for motivation. The current Chapter 02 environment entry point
(`infra/envs/poc/apim.bicep`) composes the APIM service, private DNS, observability, Foundry role
assignment, Foundry backend, model allowlist, and governed API in one deployment. Its parameter
file and validation script consequently require Foundry before APIM itself can be previewed or
validated.

The module family is already close to the desired boundary: private DNS, observability, backend,
API, and Foundry role assignment are separate modules. The principal coupling is that
`infra/modules/apim/main.bicep` references Foundry and deploys the role assignment, while the
environment entry point and validator treat every module as one readiness unit.

The customer VPCx Azure 2.0 guidance independently defines APIM and Foundry. APIM requires
internal VNet mode, an approved subnet with customer network controls, a public IP for classic
internal-mode platform operation, TLS restrictions, diagnostics, and capacity monitoring.
Foundry has its own GenAI approval and account-enablement workflow, approved regions and models,
private endpoints, and policy enforcement; its guidance contains no APIM prerequisite.
The customer baseline reviewed for this change is the `cloudx-patterns` snapshot at commit
`a23fe3be99e`, under `docs/azure_2_0/services/azure-api-management-v2/` and
`docs/azure_2_0/services/azure-aifoundry-2.0/`.

## Goals / Non-Goals

**Goals:**

- Make the existing `infra/envs/poc/apim.bicep` entry point the Foundry-independent foundation
  deployment to preserve the familiar primary APIM path.
- Add an explicit integration entry point that consumes an existing APIM service and approved
  Foundry inputs.
- Give each stage its own parameter contract, preview, deployment, outputs, validation command,
  evidence, and readiness result.
- Keep Stage 2 additive so it cannot replace the APIM service or mutate foundation-owned DNS,
  networking, or monitoring.

**Non-Goals:**

- Changing the selected APIM Premium tier, internal VNet posture, model policy behavior, or
  managed-identity authentication.
- Making Foundry depend on APIM or changing Chapter 01 Foundry infrastructure.
- Adding MCP, A2A, Content Safety, semantic caching, secondary backends, or public access.
- Automatically deploying Stage 2 when Stage 1 completes.

## Decisions

### 1. Use two resource-group deployment entry points

`infra/envs/poc/apim.bicep` will become the foundation entry point and will compose only the APIM
service, private DNS, and observability modules. A new
`infra/envs/poc/apim-foundry-integration.bicep` entry point will reference the existing APIM
service and compose the Foundry role assignment, backend, model mapping, and governed API.

The corresponding parameter files will be `apim.bicepparam` for foundation inputs and
`apim-foundry-integration.bicepparam` for Foundry and governed API inputs.

This preserves the current primary APIM deployment path while removing its Foundry requirement.
The alternative of one template with an `enableFoundryIntegration` condition was rejected because
the template would still expose mixed prerequisites, permissions, outputs, and validation states,
making the operational boundary easy to bypass accidentally.

### 2. Move Foundry authorization out of the APIM service module

`infra/modules/apim/main.bicep` will own only the APIM service and its system-assigned identity.
The existing `foundry-role-assignment.bicep` module will be invoked only by the integration entry
point, using the principal ID of an existing APIM service.

This makes the dependency direction explicit: integration depends on the APIM identity, while the
APIM identity never depends on Foundry. Keeping the role assignment in `main.bicep` with
conditional parameters was rejected because it preserves cross-stage permissions and schema
coupling in the foundation module.

### 3. Reference foundation resources from Stage 2 instead of redeploying them

The integration entry point will declare the APIM service as an existing resource scoped to `resourceGroup(apimResourceGroupName)` and pass its name, ID, and principal ID to the integration modules. It will deploy the backend/API modules at that scope and invoke the role-assignment module at `resourceGroup(foundryResourceGroupName)`; it will not invoke the APIM service, private DNS, or observability modules.

This ARM boundary ensures an integration deployment cannot unintentionally replace the APIM service or alter its VNet configuration. It also allows Foundry and APIM to reside in separate resource groups while retaining account-scoped role assignment.

### 4. Split parameters and outputs by ownership

Foundation parameters will include location, APIM service and publisher settings, network
references, private DNS settings, SKU/capacity, public-network policy handoff, and observability
settings. They will contain no `foundry*`, `approvedModels`, backend, product, token limit, or
governed API parameters.

Integration parameters will include the existing APIM service name/resource group, Foundry
account name/resource ID/resource group, approved model mappings, backend/API/product names,
token limits, and Foundry API version. Integration outputs will report role assignment, backend,
API, product, and model-mapping readiness; foundation outputs will report APIM, identity, network,
DNS, and observability readiness.

### 5. Validate stages independently, then provide an aggregate mode

The validation runner will accept an explicit `foundation`, `integration`, or `all` mode.
Foundation mode will compile and preview only foundation templates and perform no
`Microsoft.CognitiveServices` lookup. Integration mode will first validate the existing APIM
identity, then validate Foundry prerequisites and the integration template. `all` will run both
in order for environments where Foundry is already available.

Separate evidence files will establish the two acceptance gates. Existing evidence that combines
identity/DNS or end-to-end results will be reorganized or relabeled so foundation readiness
remains true when integration is intentionally pending.

### 6. Present Chapter 02 as a resumable two-stage workflow

The chapter, legacy feature spec, plan, quickstart, contract, and tasks will use the same stage
names and resource ownership. Stage 1 instructions end with a usable foundation checkpoint.
Stage 2 begins with Foundry approval, account, model, and permissions as its own prerequisites.

This avoids implying either Azure service requires the other while retaining the blueprint's
governed AI API as the final integrated outcome.

### 7. Model customer APIM controls as foundation prerequisites

Foundation preflight will validate the customer policy profile before provisioning:

- `apimsubnet-*` naming from the customer guidance, or a documented tenant-approved naming
  exception;
- the approved hybrid NSG;
- the APIM route table or a documented tenant-specific exception;
- no subnet delegation;
- the four required service endpoints;
- a customer-approved public IP resource for classic internal APIM;
- a corporate administrator email;
- Premium tier, internal VNet mode, HTTPS backends, TLS 1.2-or-stronger settings, and disabled
  weak protocols/ciphers.

The existing brownfield network templates already support an NSG resource ID, route-table
resource ID, and service endpoints. The generic customer document requires
`apim-routetable-<location>`, while the repository records an observed landing-zone policy that
denies a route table when the shared hybrid NSG is attached. The implementation will not silently
choose between these conflicting controls: validation must require either the documented customer
profile or explicit evidence of the active tenant-approved exception.

The required public IP is treated as an APIM platform/control-plane dependency, not evidence of a
public gateway. Exposure validation will use internal VNet mode and endpoint reachability rather
than asserting that no public IP resource exists.

### 8. Expand foundation monitoring to the customer baseline

The observability module will retain Application Insights and Log Analytics for blueprint
telemetry and add or verify the policy-required APIM diagnostic destination for AllLogs and
AllMetrics. It will also add or verify the customer capacity alert at an average capacity
threshold greater than 60 percent.

Where customer Azure Policy deploys or locks diagnostic settings, the template will reference and
validate the enforced configuration rather than fighting policy ownership.

### 9. Keep enterprise custom DNS conditional

The existing `azure-api.net` private DNS zone remains the VNet-local foundation mechanism.
Customer guidance states that default APIM domains are not globally resolvable across the
enterprise network in internal mode. Chapter 02 will therefore document approved custom domains,
approved CA certificates, and internal DNS A records to the private VIP as an optional extension
when consumers require broader internal reachability. This does not gate foundation validation
for VNet-local consumers.

### 10. Make customer Foundry governance a Stage 2 gate

Integration validation will require evidence that the GenAI Review Board case and Foundry account
enablement are complete, that the existing Foundry deployment is in an approved region with
private access, and that every mapped model is on the customer-approved model list. These checks
belong only to Stage 2 and must never run during foundation preview or deployment.
The referenced customer guidance currently identifies East US, East US 2, and West Europe as the
allowed Foundry regions; validation should consume the maintained customer policy source rather
than permanently duplicating a list that can change.

## Risks / Trade-offs

- **[Existing automation invokes the combined parameter contract]** -> Update all repository
  scripts and docs together; make removed Foundry parameters fail visibly rather than being
  silently ignored.
- **[Stage 2 targets the wrong APIM identity]** -> Require the APIM resource ID/name explicitly,
  derive the principal ID from the existing resource, and validate it before role assignment.
- **[Readiness is reported as complete after Stage 1]** -> Use separate `foundationReadiness` and
  `integrationReadiness` outputs and label the full governed API outcome as requiring both.
- **[Integration deployment could drift from foundation configuration]** -> Treat APIM, DNS, and
  observability as existing/read-only in Stage 2 and verify their required posture before adding
  integration resources.
- **[Two entry points increase operator steps]** -> Provide an `all` validation mode and a concise
  handoff showing exactly which foundation outputs become Stage 2 inputs, without recombining the
  deployments.
- **[Generic APIM guidance and active tenant policy disagree on route-table attachment]** ->
  Validate the active policy assignment and require documented exception evidence rather than
  hardcoding a configuration that Azure Policy will deny.
- **[A required public IP is mistaken for public gateway exposure]** -> Document its
  platform-management purpose and test internal endpoint reachability separately.
- **[Azure Policy owns diagnostic settings]** -> Detect policy-created settings and validate
  required categories/destinations instead of attempting an unauthorized replacement.

## Migration Plan

1. Refactor `infra/modules/apim/main.bicep` to remove Foundry parameters, references, role
   assignment, and Foundry readiness outputs.
2. Reduce `infra/envs/poc/apim.bicep` and `apim.bicepparam` to foundation-owned modules and inputs,
   including the customer-approved APIM public IP and network-policy profile.
3. Add the integration entry point and parameter file using the existing APIM service plus the
   existing role-assignment, backend, and API modules.
4. Extend foundation observability with policy-compatible diagnostics and capacity-alert
   validation.
5. Split validation modes and evidence, then update Chapter 02 and all legacy Chapter 02 planning
   artifacts to describe stage-specific prerequisites, customer controls, and checkpoints.
6. Compile and preview Stage 1 without Foundry inputs; verify its live foundation posture where
   Azure access is available.
7. Preview Stage 2 against an existing APIM foundation and approved Foundry environment; verify
   the preview contains only integration-owned changes.
8. Reapply each stage unchanged to verify idempotency and run the full end-to-end request test
   after integration.

Rollback is stage-specific. Removing or rolling back Stage 2 deletes only integration-owned API,
backend, model mapping, and role assignment resources; the APIM foundation remains deployed.
Rolling back Stage 1 follows the existing APIM infrastructure rollback procedure and is not
required to remove Foundry resources.
