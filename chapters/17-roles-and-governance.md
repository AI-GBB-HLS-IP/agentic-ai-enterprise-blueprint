# Chapter 17 — Governance Model, Roles & Separation of Duties

## Objective

Define the **three-role governance model** that underpins the Secure Agent Factory. By the end of this lab, you will have:

- Three Entra ID security groups with clearly defined responsibilities
- RBAC role assignments that enforce separation of duties
- A responsibility matrix that prevents any single role from bypassing controls
- Conditional Access policies for privileged operations

---

## Why Roles Matter

Without explicit role boundaries, enterprises encounter:

```
Developer creates Foundry project → No guardrails → No observability → No audit trail
                                         ↓
                            Shadow AI in production
```

The Secure Agent Factory enforces:

```
Developer requests project → AI CoE provisions from blueprint → Platform Eng infrastructure enforces
                                         ↓
                            Every agent born secure by default
```

---

## Part 1: Define the Three Roles

### Role 1: Platform Engineering

**Mission**: Own the infrastructure foundation. Ensure every AI workload runs on compliant, observable, secure infrastructure.

| Responsibility | Description |
|---------------|-------------|
| Azure Policy | Define and enforce compliance policies |
| Networking | VNet, private endpoints, DNS, NSGs |
| APIM AI Gateway | Central chokepoint for all AI traffic |
| Defender for AI | Threat detection and response |
| Microsoft Agent 365 | Enterprise control plane — registry sync, security telemetry, infrastructure health signals |
| Azure Monitor | Observability infrastructure |
| Purview | Data governance and classification |
| Key Vault | Secrets infrastructure (not individual secrets) |
| Audit | Azure Activity Log, diagnostic settings |

**Does NOT**:
- Create Foundry projects
- Build agents
- Approve tools
- Manage developer access

### Role 2: AI Center of Excellence (AI CoE)

**Mission**: Own the platform product. Provide a self-service, governed experience for developers to build agents safely.

| Responsibility | Description |
|---------------|-------------|
| Foundry Projects | Provision from hardened blueprints |
| Identity | Create and assign managed identities per agent |
| Guardrails | Configure Content Safety, Prompt Shields per project |
| Tool Governance | Review, approve, and publish MCP tools |
| Model Governance | Select approved models per project |
| Agent 365 Governance | Manage agent lifecycle, activation, and compliance in Agent 365 registry |
| Developer Onboarding | Grant access, provide documentation |
| Production Promotion | Approve agents for production deployment |
| Evaluations | Define evaluation criteria and thresholds |

**Does NOT**:
- Manage infrastructure
- Configure networking
- Build agents
- Modify Azure Policy

### Role 3: Developers

**Mission**: Build agent logic within the provided sandbox. Focus on business value, not infrastructure.

| Responsibility | Description |
|---------------|-------------|
| Agent Logic | Prompts, orchestration, tool usage |
| Local Testing | Test within the provided environment |
| Code Quality | Unit tests, integration tests |
| Documentation | Agent documentation, runbooks |
| CI/CD Submission | Submit for promotion through pipeline |

**Cannot**:
- Create Foundry resources
- Deploy models
- Create networking
- Access models directly (must go through APIM)
- Register MCP tools
- Bypass guardrails
- Skip observability
- Promote to production directly

---

## Part 2: Create Entra ID Security Groups

### Step 2.1 — Create the Security Groups

```bash
# Platform Engineering group
az ad group create \
  --display-name "sg-agentfactory-platform-engineering" \
  --mail-nickname "sg-agentfactory-platform-eng" \
  --description "Secure Agent Factory — Platform Engineering team. Owns infrastructure, policy, networking, and observability."

# AI CoE group
az ad group create \
  --display-name "sg-agentfactory-ai-coe" \
  --mail-nickname "sg-agentfactory-ai-coe" \
  --description "Secure Agent Factory — AI Center of Excellence. Owns Foundry projects, identity, guardrails, and tool governance."

# Developer group
az ad group create \
  --display-name "sg-agentfactory-developers" \
  --mail-nickname "sg-agentfactory-developers" \
  --description "Secure Agent Factory — Developers. Build agents within governed sandboxes. No infrastructure access."
```

### Step 2.2 — Capture Group Object IDs

```bash
# Store group IDs for later use
PLATFORM_ENG_GROUP=$(az ad group show \
  --group "sg-agentfactory-platform-engineering" \
  --query id -o tsv)

AI_COE_GROUP=$(az ad group show \
  --group "sg-agentfactory-ai-coe" \
  --query id -o tsv)

DEVELOPER_GROUP=$(az ad group show \
  --group "sg-agentfactory-developers" \
  --query id -o tsv)

echo "Platform Engineering: $PLATFORM_ENG_GROUP"
echo "AI CoE:               $AI_COE_GROUP"
echo "Developers:           $DEVELOPER_GROUP"
```

### Step 2.3 — Add Members

```bash
# Add platform engineers
az ad group member add \
  --group "sg-agentfactory-platform-engineering" \
  --member-id $(az ad user show --id platform-admin@contoso.com --query id -o tsv)

# Add AI CoE members
az ad group member add \
  --group "sg-agentfactory-ai-coe" \
  --member-id $(az ad user show --id ai-coe-lead@contoso.com --query id -o tsv)

# Add developers
az ad group member add \
  --group "sg-agentfactory-developers" \
  --member-id $(az ad user show --id developer1@contoso.com --query id -o tsv)
```

---

## Part 3: Create the Resource Group Structure

### Step 3.1 — Resource Group Hierarchy

```bash
# Shared infrastructure (Platform Engineering owns)
az group create \
  --name rg-agent-factory-platform \
  --location eastus2 \
  --tags \
    "owner=platform-engineering" \
    "purpose=shared-infrastructure" \
    "cost-center=platform"

# AI CoE management plane (AI CoE owns)
az group create \
  --name rg-agent-factory-coe \
  --location eastus2 \
  --tags \
    "owner=ai-coe" \
    "purpose=foundry-projects-and-governance" \
    "cost-center=ai-coe"

# Developer sandbox (AI CoE provisions, developers use)
az group create \
  --name rg-agent-factory-dev \
  --location eastus2 \
  --tags \
    "owner=ai-coe" \
    "purpose=developer-sandboxes" \
    "cost-center=development"

# Production (AI CoE promotes, Platform Eng monitors)
az group create \
  --name rg-agent-factory-prod \
  --location eastus2 \
  --tags \
    "owner=ai-coe" \
    "purpose=production-agents" \
    "cost-center=production"
```

---

## Part 4: Assign RBAC Roles

### Step 4.1 — Platform Engineering RBAC

Platform Engineering gets **infrastructure control** but **no Foundry project access**:

```bash
RG_PLATFORM="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-platform"

# Owner on platform resource group (networking, APIM, monitoring)
az role assignment create \
  --assignee-object-id $PLATFORM_ENG_GROUP \
  --assignee-principal-type Group \
  --role "Owner" \
  --scope $RG_PLATFORM

# Network Contributor across all RGs (manage VNet, NSGs, private endpoints)
for rg in rg-agent-factory-platform rg-agent-factory-coe rg-agent-factory-dev rg-agent-factory-prod; do
  az role assignment create \
    --assignee-object-id $PLATFORM_ENG_GROUP \
    --assignee-principal-type Group \
    --role "Network Contributor" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg"
done

# Monitoring Contributor across all RGs
for rg in rg-agent-factory-platform rg-agent-factory-coe rg-agent-factory-dev rg-agent-factory-prod; do
  az role assignment create \
    --assignee-object-id $PLATFORM_ENG_GROUP \
    --assignee-principal-type Group \
    --role "Monitoring Contributor" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg"
done

# Resource Policy Contributor at subscription level
az role assignment create \
  --assignee-object-id $PLATFORM_ENG_GROUP \
  --assignee-principal-type Group \
  --role "Resource Policy Contributor" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"

# Security Admin (for Defender)
az role assignment create \
  --assignee-object-id $PLATFORM_ENG_GROUP \
  --assignee-principal-type Group \
  --role "Security Admin" \
  --scope "/subscriptions/$(az account show --query id -o tsv)"
```

### Step 4.2 — AI CoE RBAC

AI CoE gets **Foundry project control** and **developer access management**:

```bash
# Owner on CoE resource group
az role assignment create \
  --assignee-object-id $AI_COE_GROUP \
  --assignee-principal-type Group \
  --role "Owner" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-coe"

# Contributor on dev and prod RGs (provision Foundry projects)
for rg in rg-agent-factory-dev rg-agent-factory-prod; do
  az role assignment create \
    --assignee-object-id $AI_COE_GROUP \
    --assignee-principal-type Group \
    --role "Contributor" \
    --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg"
done

# User Access Administrator on dev RG (assign developer permissions)
az role assignment create \
  --assignee-object-id $AI_COE_GROUP \
  --assignee-principal-type Group \
  --role "User Access Administrator" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-dev"

# Reader on platform RG (see but not modify infrastructure)
az role assignment create \
  --assignee-object-id $AI_COE_GROUP \
  --assignee-principal-type Group \
  --role "Reader" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-platform"
```

### Step 4.3 — Developer RBAC (Minimal Access)

Developers get the **minimum permissions** to build agents:

```bash
# Azure AI Developer on dev RG only (build agents, not manage infrastructure)
az role assignment create \
  --assignee-object-id $DEVELOPER_GROUP \
  --assignee-principal-type Group \
  --role "Azure AI Developer" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-dev"

# Reader on platform RG (see APIM endpoints, App Insights connection strings)
az role assignment create \
  --assignee-object-id $DEVELOPER_GROUP \
  --assignee-principal-type Group \
  --role "Reader" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-platform"

# NO access to prod RG — promotion happens through CI/CD only
# NO Owner or Contributor anywhere
# NO User Access Administrator anywhere
```

### Step 4.4 — Foundry-Specific RBAC

```bash
# AI CoE: Azure AI Administrator on Foundry (manage projects, connections, deployments)
az role assignment create \
  --assignee-object-id $AI_COE_GROUP \
  --assignee-principal-type Group \
  --role "Azure AI Administrator" \
  --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-agent-factory-coe"

# Developers: Azure AI Developer on their project scope only
# (This is assigned per-project by AI CoE during provisioning — see Lab 05)
```

---

## Part 5: Conditional Access Policies

### Step 5.1 — Require MFA for Privileged Operations

Create a Conditional Access policy in Entra ID that requires MFA for Platform Engineering and AI CoE groups when accessing Azure Management:

| Setting | Value |
|---------|-------|
| **Name** | `CA-AgentFactory-PrivilegedMFA` |
| **Users** | `sg-agentfactory-platform-engineering`, `sg-agentfactory-ai-coe` |
| **Cloud Apps** | Microsoft Azure Management |
| **Grant** | Require MFA |
| **Session** | Sign-in frequency: 4 hours |

### Step 5.2 — Block Developer Access to Azure Portal for Infrastructure

| Setting | Value |
|---------|-------|
| **Name** | `CA-AgentFactory-DevBlockInfra` |
| **Users** | `sg-agentfactory-developers` |
| **Cloud Apps** | Microsoft Azure Management |
| **Conditions** | Device platform: Any; Location: Any |
| **Grant** | Allow (MFA required, compliant device required) |

> **Note**: Developers can still access Azure Portal as Reader, but with stricter controls. The real enforcement is RBAC — they cannot modify infrastructure even if they reach the portal.

---

## Part 6: Responsibility Matrix (RACI)

| Activity | Platform Eng | AI CoE | Developer |
|----------|:----------:|:------:|:---------:|
| Define compliance policies | **R/A** | C | I |
| Deploy APIM Gateway | **R/A** | I | I |
| Configure VNet/networking | **R/A** | C | I |
| Set up Defender for AI | **R/A** | I | I |
| Configure Azure Monitor | **R/A** | C | I |
| Create Foundry Project | I | **R/A** | C |
| Provision Managed Identity | I | **R/A** | I |
| Configure Guardrails | C | **R/A** | I |
| Approve MCP Tools | C | **R/A** | C |
| Select Approved Models | C | **R/A** | C |
| Build Agent Logic | I | C | **R/A** |
| Write Agent Prompts | I | C | **R/A** |
| Test Agent Locally | I | I | **R/A** |
| Submit for Production | I | C | **R/A** |
| Approve for Production | I | **R/A** | I |
| Monitor Production Agents | **R** | **A** | I |
| Respond to Security Incidents | **R/A** | C | I |

*R = Responsible, A = Accountable, C = Consulted, I = Informed*

---

## Part 7: Verify Separation of Duties

### Step 7.1 — Test Platform Engineering Boundaries

```bash
# Login as platform engineer
az login --username platform-admin@contoso.com

# ✅ Should succeed: Create policy definition
az policy definition create --name "test-policy" --rules '{}' --mode All

# ❌ Should fail: Create Foundry project (no Contributor on CoE RG)
az ml workspace create --name "test-project" --resource-group rg-agent-factory-coe
# Expected: AuthorizationFailed

# ❌ Should fail: Assign developer RBAC (no User Access Administrator)
az role assignment create --assignee developer1@contoso.com --role "Contributor" \
  --scope "/subscriptions/.../resourceGroups/rg-agent-factory-dev"
# Expected: AuthorizationFailed
```

### Step 7.2 — Test AI CoE Boundaries

```bash
# Login as AI CoE lead
az login --username ai-coe-lead@contoso.com

# ✅ Should succeed: Create Foundry project
az ml workspace create --name "agent-project-001" --resource-group rg-agent-factory-dev

# ✅ Should succeed: Assign developer to project
az role assignment create --assignee developer1@contoso.com --role "Azure AI Developer" \
  --scope "/subscriptions/.../resourceGroups/rg-agent-factory-dev/providers/..."

# ❌ Should fail: Create Azure Policy (no Resource Policy Contributor)
az policy definition create --name "test-policy" --rules '{}' --mode All
# Expected: AuthorizationFailed

# ❌ Should fail: Modify APIM (no Contributor on platform RG)
az apim update --name apim-agent-factory --resource-group rg-agent-factory-platform
# Expected: AuthorizationFailed
```

### Step 7.3 — Test Developer Boundaries

```bash
# Login as developer
az login --username developer1@contoso.com

# ✅ Should succeed: Create agent within assigned project
# (Demonstrated in Lab 08)

# ❌ Should fail: Create Foundry project
az ml workspace create --name "my-rogue-project" --resource-group rg-agent-factory-dev
# Expected: AuthorizationFailed

# ❌ Should fail: Deploy a model
az ml model create --name "my-model" --resource-group rg-agent-factory-dev
# Expected: AuthorizationFailed

# ❌ Should fail: Access production
az resource list --resource-group rg-agent-factory-prod
# Expected: AuthorizationFailed

# ❌ Should fail: Modify networking
az network vnet subnet create --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory --name my-subnet --address-prefixes 10.0.99.0/24
# Expected: AuthorizationFailed
```

---

## Anti-Patterns to Avoid

| Anti-Pattern | Risk | Correct Approach |
|-------------|------|------------------|
| Giving developers Contributor on subscription | Can create any resource, bypass all controls | Azure AI Developer on specific project scope |
| Single "AI Team" group | No separation of duties | Three distinct groups with scoped permissions |
| Shared service principal for agents | Cannot attribute, audit, or revoke per agent | Managed Identity per agent |
| Platform team builds agents | Conflicts of interest, no audit separation | Platform provides infrastructure, CoE provisions, developers build |
| Developers self-service Foundry projects | Inconsistent security, missing guardrails | AI CoE provisions from blueprint |

---

## Summary

| Component | Status |
|-----------|--------|
| Three Entra ID security groups created | ✅ |
| Resource group hierarchy established | ✅ |
| RBAC assignments scoped per role | ✅ |
| Conditional Access policies configured | ✅ |
| RACI matrix documented | ✅ |
| Separation of duties verified | ✅ |

---

## Next Steps

Proceed to [Chapter 18 — Azure Policy — Block Non-Compliant Deployments](./18-azure-policy-enforcement.md)
