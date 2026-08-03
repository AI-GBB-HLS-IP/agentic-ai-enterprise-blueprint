# Chapter 21 — Foundry Project Blueprint & Automated Provisioning

## Objective

Create a **hardened Foundry project blueprint** that the AI CoE uses to provision every new agent project. Developers never create projects from scratch — they receive a pre-configured, security-hardened environment with guardrails, identity, observability, and gateway connectivity baked in.

By the end of this lab, you will have:

- A Bicep template that provisions a complete Foundry project with all controls
- A provisioning script that creates projects on-demand
- Standard connections to APIM, Key Vault, and Application Insights
- Mandatory guardrails pre-configured in every project
- An intake process for project requests

---

## Two Modes: Lab vs Production

This chapter operates in **two modes**:

| Mode | Purpose | Who runs it |
|------|---------|-------------|
| **🔬 Lab Mode** (Parts 1-4) | Learn how each component works by building it step by step | You, following this guide |
| **🏭 Production Mode** (Part 5) | Fully automated self-service portal with approval workflows | AI CoE deploys once, developers self-serve forever |

**Lab Mode** teaches you the mechanics — Bicep templates, provisioning scripts, RBAC, diagnostics. Complete it first to understand what the automation does under the hood.

**Production Mode** wraps everything into a self-service portal where developers request projects through a UX, IT Platform Engineering and AI CoE approve via task queues, and all infrastructure + governance components are provisioned automatically — zero CLI, zero tickets.

---

## 🔬 Lab Mode — The Blueprint Principle

```
Traditional (Unsafe):
  Developer → "az ml workspace create" → Empty project → No guardrails → Shadow AI

Secure Agent Factory:
  Developer → Submits Request → AI CoE → Runs Blueprint → Hardened Project
                                                              ├── Managed Identity ✅
                                                              ├── APIM Connection ✅
                                                              ├── Content Safety ✅
                                                              ├── Prompt Shields ✅
                                                              ├── OpenTelemetry ✅
                                                              ├── Approved Models ✅
                                                              ├── Scoped RBAC ✅
                                                              └── Diagnostic Logs ✅
```

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Labs 01-04 completed | Platform infrastructure ready |
| Logged in as | AI CoE member |
| Bicep CLI | Installed (`az bicep install`) |

---

## Part 1: The Foundry Project Blueprint (Bicep)

### Step 1.1 — Create the Blueprint Template

```bash
mkdir -p ~/agent-factory-blueprints
```

Create the main Bicep template:

```bicep
// blueprint-foundry-project.bicep
// Secure Agent Factory — Hardened Foundry Project Blueprint
// Owned by: AI CoE
// Purpose: Provision a fully governed Foundry project for agent development

@description('Project name (lowercase, alphanumeric, max 20 chars)')
@minLength(3)
@maxLength(20)
param projectName string

@description('Team or business unit requesting the project')
param teamName string

@description('Cost center for token and compute billing')
param costCenter string

@description('Environment (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Location for resources')
@allowed(['eastus2', 'westus3', 'swedencentral'])
param location string = 'eastus2'

@description('Developer Entra group Object ID for RBAC assignment')
param developerGroupId string

@description('Approved model deployments for this project')
param approvedModels array = [
  {
    name: 'gpt-4o'
    version: '2024-11-20'
    capacity: 30
  }
  {
    name: 'gpt-4o-mini'
    version: '2024-07-18'
    capacity: 50
  }
]

@description('Token budget per hour for this project')
param tokenBudgetPerHour int = 50000

// === References to Platform Infrastructure ===

@description('Resource ID of the platform VNet')
param vnetId string

@description('Resource ID of the private endpoint subnet')
param peSubnetId string

@description('Resource ID of the Log Analytics workspace')
param lawId string

@description('Application Insights connection string')
@secure()
param appiConnectionString string

@description('APIM gateway URL')
param apimGatewayUrl string

@description('Key Vault name for secrets')
param keyVaultName string

// === Variables ===

var projectPrefix = 'agent-${projectName}-${environment}'
var tags = {
  project: projectName
  team: teamName
  costCenter: costCenter
  environment: environment
  managedBy: 'ai-coe'
  blueprint: 'secure-agent-factory-v1'
  createdDate: utcNow('yyyy-MM-dd')
}

// === 1. Foundry Project (AI Services Account) ===

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: projectPrefix
  location: location
  kind: 'AIServices'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: projectPrefix
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
    disableLocalAuth: true  // Force Entra authentication only
  }
}

// === 2. Model Deployments (Pre-approved only) ===

resource modelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for model in approvedModels: {
  parent: aiServices
  name: model.name
  sku: {
    name: 'Standard'
    capacity: model.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: model.name
      version: model.version
    }
  }
}]

// === 3. Content Safety (Guardrails) ===

resource contentSafety 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: '${projectPrefix}-safety'
  location: location
  kind: 'ContentSafety'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${projectPrefix}-safety'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

// === 4. Diagnostic Settings (Mandatory Observability) ===

resource aiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${projectPrefix}-diagnostics'
  scope: aiServices
  properties: {
    workspaceId: lawId
    logs: [
      { category: 'Audit'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
      { category: 'RequestResponse'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
      { category: 'Trace'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
    ]
    metrics: [
      { category: 'AllMetrics'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
    ]
  }
}

resource safetyDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${projectPrefix}-safety-diagnostics'
  scope: contentSafety
  properties: {
    workspaceId: lawId
    logs: [
      { category: 'Audit'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
      { category: 'RequestResponse'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
    ]
    metrics: [
      { category: 'AllMetrics'; enabled: true; retentionPolicy: { enabled: true; days: 90 } }
    ]
  }
}

// === 5. Private Endpoint ===

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${projectPrefix}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${projectPrefix}-connection'
        properties: {
          privateLinkServiceId: aiServices.id
          groupIds: ['account']
        }
      }
    ]
  }
}

// === 6. RBAC — Developer Access (Scoped) ===

// Azure AI Developer role on the project
resource developerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, developerGroupId, 'Azure AI Developer')
  scope: aiServices
  properties: {
    principalId: developerGroupId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '64702f94-c441-49e6-a78b-ef80e0188fee') // Azure AI Developer
  }
}

// Cognitive Services User on Content Safety
resource safetyRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(contentSafety.id, developerGroupId, 'Cognitive Services User')
  scope: contentSafety
  properties: {
    principalId: developerGroupId
    principalType: 'Group'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
  }
}

// === 7. Key Vault Secrets for Project ===

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource appiSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: '${projectPrefix}-appi-connection'
  properties: {
    value: appiConnectionString
  }
}

resource apimUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: '${projectPrefix}-apim-url'
  properties: {
    value: apimGatewayUrl
  }
}

// === Outputs ===

output projectResourceId string = aiServices.id
output projectManagedIdentityId string = aiServices.identity.principalId
output contentSafetyEndpoint string = contentSafety.properties.endpoint
output privateEndpointIp string = privateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
output projectEndpoint string = aiServices.properties.endpoint
```

---

## Part 2: Provisioning Script

### Step 2.1 — Create the Provisioning Script

```bash
#!/bin/bash
# provision-project.sh — AI CoE project provisioning script
# Usage: ./provision-project.sh <project-name> <team-name> <cost-center> <developer-group-id>

set -euo pipefail

PROJECT_NAME="${1:?Usage: $0 <project-name> <team-name> <cost-center> <developer-group-id>}"
TEAM_NAME="${2:?Team name required}"
COST_CENTER="${3:?Cost center required}"
DEVELOPER_GROUP_ID="${4:?Developer group Object ID required}"
ENVIRONMENT="${5:-dev}"

echo "=============================================="
echo " Secure Agent Factory — Project Provisioning"
echo "=============================================="
echo " Project:    $PROJECT_NAME"
echo " Team:       $TEAM_NAME"
echo " Cost Center: $COST_CENTER"
echo " Environment: $ENVIRONMENT"
echo "=============================================="

# Validate caller is AI CoE member
CALLER_GROUPS=$(az ad signed-in-user list-owned-objects --query "[].displayName" -o tsv)
if ! echo "$CALLER_GROUPS" | grep -q "sg-agentfactory-ai-coe"; then
  echo "ERROR: You must be a member of sg-agentfactory-ai-coe to provision projects."
  exit 1
fi

# Get platform infrastructure references
VNET_ID=$(az network vnet show \
  --resource-group rg-agent-factory-platform \
  --name vnet-agent-factory \
  --query id -o tsv)

PE_SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-pe \
  --query id -o tsv)

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-agent-factory-platform \
  --workspace-name law-agent-factory \
  --query id -o tsv)

APPI_CONNECTION=$(az keyvault secret show \
  --vault-name kv-agent-factory \
  --name "appi-connection-string" \
  --query value -o tsv)

APIM_URL="https://apim-agent-factory.azure-api.net"

# Deploy the blueprint
echo "Deploying Foundry project blueprint..."
az deployment group create \
  --resource-group rg-agent-factory-${ENVIRONMENT} \
  --template-file blueprint-foundry-project.bicep \
  --parameters \
    projectName="$PROJECT_NAME" \
    teamName="$TEAM_NAME" \
    costCenter="$COST_CENTER" \
    environment="$ENVIRONMENT" \
    developerGroupId="$DEVELOPER_GROUP_ID" \
    vnetId="$VNET_ID" \
    peSubnetId="$PE_SUBNET_ID" \
    lawId="$LAW_ID" \
    appiConnectionString="$APPI_CONNECTION" \
    apimGatewayUrl="$APIM_URL" \
    keyVaultName="kv-agent-factory" \
  --name "deploy-${PROJECT_NAME}-$(date +%Y%m%d%H%M)"

# Output results
echo ""
echo "=============================================="
echo " Project Provisioned Successfully!"
echo "=============================================="
echo ""
echo "What developers receive:"
echo "  ✅ Foundry Project:  agent-${PROJECT_NAME}-${ENVIRONMENT}"
echo "  ✅ Managed Identity: Assigned"
echo "  ✅ Approved Models:  gpt-4o, gpt-4o-mini"
echo "  ✅ Content Safety:   Configured"
echo "  ✅ Private Endpoint: Connected"
echo "  ✅ Diagnostics:      Flowing to Log Analytics"
echo "  ✅ RBAC:             Azure AI Developer scoped"
echo ""
echo "Developer onboarding:"
echo "  APIM Endpoint:  $APIM_URL"
echo "  Project Name:   agent-${PROJECT_NAME}-${ENVIRONMENT}"
echo "  Key Vault:      kv-agent-factory"
echo ""
echo "What developers CANNOT do:"
echo "  ❌ Create new resources"
echo "  ❌ Deploy unapproved models"
echo "  ❌ Access models directly (APIM only)"
echo "  ❌ Disable logging"
echo "  ❌ Modify networking"
```

---

## Part 3: Project Request Intake Process

### Step 3.1 — Define the Request Form

Create a standard intake form (can be a ServiceNow form, Teams form, or GitHub Issue template):

```yaml
# .github/ISSUE_TEMPLATE/agent-project-request.yml
name: Agent Project Request
description: Request a new Foundry project for agent development
title: "[Project Request] "
labels: ["project-request"]
assignees: ["ai-coe-team"]

body:
  - type: input
    id: project-name
    attributes:
      label: Project Name
      description: "Lowercase, alphanumeric, max 20 characters"
      placeholder: "customer-support"
    validations:
      required: true

  - type: input
    id: team-name
    attributes:
      label: Team / Business Unit
      placeholder: "Customer Experience"
    validations:
      required: true

  - type: input
    id: cost-center
    attributes:
      label: Cost Center
      placeholder: "CC-1234"
    validations:
      required: true

  - type: textarea
    id: use-case
    attributes:
      label: Agent Use Case
      description: "Describe what the agent will do"
      placeholder: "Build a customer support agent that answers product questions using our knowledge base"
    validations:
      required: true

  - type: checkboxes
    id: models-needed
    attributes:
      label: Models Required
      description: "Select the models this project needs"
      options:
        - label: "gpt-4o (Complex reasoning)"
        - label: "gpt-4o-mini (Fast, cost-effective)"
        - label: "o3-mini (Advanced reasoning)"
        - label: "text-embedding-3-large (Embeddings)"

  - type: checkboxes
    id: tools-needed
    attributes:
      label: MCP Tools Required
      description: "Select from approved tool catalog"
      options:
        - label: "search_documents (Knowledge base search)"
        - label: "get_customer_data (CRM lookup)"
        - label: "calculate_pricing (Pricing engine)"
        - label: "submit_order (Order management)"
        - label: "Other (describe in use case)"

  - type: dropdown
    id: environment
    attributes:
      label: Initial Environment
      options:
        - dev
        - staging
    validations:
      required: true

  - type: input
    id: developer-group
    attributes:
      label: Developer Entra Group Name
      description: "Entra security group containing the developers for this project"
      placeholder: "sg-team-customer-experience-devs"
    validations:
      required: true

  - type: input
    id: token-budget
    attributes:
      label: Estimated Token Budget (per hour)
      placeholder: "50000"
    validations:
      required: true
```

### Step 3.2 — AI CoE Review Checklist

Before provisioning, the AI CoE validates:

| Check | Validation |
|-------|-----------|
| Use case approved | Business justification reviewed |
| Models appropriate | Selected models match use case complexity |
| Tools approved | Requested tools are in the approved catalog |
| Cost center valid | Finance confirms budget allocation |
| Developer group exists | Entra group verified |
| Compliance review | Legal/compliance sign-off for data types |
| Token budget reasonable | Within organizational limits |

---

## Part 4: Verify Blueprint Deployment

### Step 4.1 — Verify All Controls Are Active

```bash
PROJECT_NAME="customer-support"
ENV="dev"
PREFIX="agent-${PROJECT_NAME}-${ENV}"

# Verify managed identity
az cognitiveservices account show \
  --name $PREFIX \
  --resource-group rg-agent-factory-dev \
  --query "identity.type" -o tsv
# Expected: SystemAssigned

# Verify public access disabled
az cognitiveservices account show \
  --name $PREFIX \
  --resource-group rg-agent-factory-dev \
  --query "properties.publicNetworkAccess" -o tsv
# Expected: Disabled

# Verify local auth disabled (Entra only)
az cognitiveservices account show \
  --name $PREFIX \
  --resource-group rg-agent-factory-dev \
  --query "properties.disableLocalAuth" -o tsv
# Expected: true

# Verify diagnostic settings
az monitor diagnostic-settings list \
  --resource $(az cognitiveservices account show \
    --name $PREFIX \
    --resource-group rg-agent-factory-dev \
    --query id -o tsv) \
  --query "[].name" -o tsv
# Expected: agent-customer-support-dev-diagnostics

# Verify model deployments
az cognitiveservices account deployment list \
  --name $PREFIX \
  --resource-group rg-agent-factory-dev \
  --query "[].{Model:properties.model.name, Version:properties.model.version}" -o table
# Expected: gpt-4o and gpt-4o-mini only

# Verify RBAC
az role assignment list \
  --scope $(az cognitiveservices account show \
    --name $PREFIX \
    --resource-group rg-agent-factory-dev \
    --query id -o tsv) \
  --query "[].{Principal:principalName, Role:roleDefinitionName}" -o table
```

---

## Summary

| Component | Status |
|-----------|--------|
| Bicep blueprint template created | ✅ |
| Provisioning script with validation | ✅ |
| Managed identity auto-assigned | ✅ |
| Public access disabled by default | ✅ |
| Local auth disabled (Entra only) | ✅ |
| Model deployments pre-approved | ✅ |
| Content Safety provisioned | ✅ |
| Diagnostic settings mandatory | ✅ |
| Private endpoint connected | ✅ |
| Developer RBAC scoped | ✅ |
| Intake process defined | ✅ |

---

## Next Steps

Proceed to [Chapter 22 — Identity, RBAC & Guardrails by Default](./22-identity-rbac-guardrails.md)

---
---

## 🏭 Production Mode — Self-Service Portal with Automated Provisioning

> **Goal:** Replace the manual CLI workflow with a fully self-service UX where developers request projects, select tools and capabilities from the approved catalog, and receive a fully provisioned environment — after IT Platform Engineering and AI CoE approve through their respective task queues.

### End-to-End Automated Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        Self-Service Portal (React App)                       │
│                                                                              │
│  Developer opens portal → Fills request form → Selects tools, models,       │
│  memory, A2A agents from API Center catalog → Submits                        │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Phase 1: IT Platform Engineering Review                    🏗️ IT Admin     │
│  ────────────────────────────────────                                        │
│  IT Admin receives task in portal dashboard                                  │
│                                                                              │
│  Reviews:                              On Approve → Auto-provisions:         │
│  • VNet / subnet capacity              • Foundry Project (Bicep blueprint)   │
│  • Region / quota availability         • Private Endpoint                    │
│  • Cost center validation              • Diagnostic Settings → Log Analytics │
│  • Network security compliance         • NSG rules for new subnet            │
│  • Data residency requirements         • DNS zone records                    │
│                                        • APIM product subscription           │
│                                                                              │
│  On Reject → Developer notified with reason                                  │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │ (auto-triggers on IT approval)
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Phase 2: AI CoE Review                                     🧠 AI CoE       │
│  ──────────────────────                                                      │
│  AI CoE receives task in portal dashboard                                    │
│                                                                              │
│  Reviews:                              On Approve → Auto-provisions:         │
│  • Use case appropriateness            • Model deployments (approved only)   │
│  • Tool selection suitability          • Managed Identity + RBAC scoping     │
│  • Data classification match           • Content Safety + Prompt Shields     │
│  • Token budget reasonableness         • APIM routes for selected tools      │
│  • Compliance / responsible AI         • API Center access grants            │
│                                        • Memory configuration               │
│                                        • A2A agent connections               │
│                                        • CI/CD pipeline scaffold             │
│                                        • Onboarding package → Developer     │
│                                                                              │
│  On Reject → Developer notified with reason                                  │
└──────────────────────────────────┬───────────────────────────────────────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│  Developer Receives Onboarding Package                      👩‍💻 Developer   │
│  ────────────────────────────────────                                        │
│  • Project name + APIM endpoint                                              │
│  • List of provisioned tools (with APIM routes)                              │
│  • Model endpoints available                                                 │
│  • Memory store connection info                                              │
│  • A2A agent card URLs                                                       │
│  • Starter code template (Git repo)                                          │
│  • CI/CD pipeline pre-configured                                             │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

### Portal Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Frontend (React + TypeScript)                                  │
│  • Developer Request Form                                       │
│  • IT Admin Approval Dashboard                                  │
│  • AI CoE Approval Dashboard                                    │
│  • Project Status Tracker                                       │
│  • API Center Tool Browser (embedded)                           │
│                                                                 │
│  Auth: Microsoft Entra ID (MSAL)                                │
│  Role-based views: Developer │ IT Admin │ AI CoE                │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│  Backend API (Node.js / Azure Functions)                        │
│  • POST /api/projects          — Submit request                 │
│  • GET  /api/projects          — List requests (filtered by     │
│  • PATCH /api/projects/:id     — Approve / Reject               │
│  • GET  /api/catalog/tools     — Proxy to API Center REST API   │
│  • GET  /api/catalog/models    — List approved model options    │
│  • GET  /api/catalog/agents    — List A2A agents from registry  │
│  • POST /api/provision/infra   — Trigger Bicep deployment       │
│  • POST /api/provision/govern  — Trigger governance setup       │
│                                                                 │
│  Orchestration: GitHub Actions / Azure DevOps triggered via API │
│  State: Cosmos DB (request tracking + audit trail)              │
└────────────────────────┬────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────────┐
│  Provisioning Layer                                             │
│  • Bicep templates (from Lab Mode Parts 1-2)                    │
│  • Azure CLI / Az PowerShell scripts                            │
│  • APIM management API (product + subscription creation)        │
│  • API Center REST API (access grant for selected tools)        │
│  • GitHub API (scaffold repo from template)                     │
└─────────────────────────────────────────────────────────────────┘
```

---

### Step 5.1 — Build the Portal Using GitHub Copilot Agent Mode

The AI CoE team uses **GitHub Copilot Agent Mode** in VS Code to scaffold the entire self-service portal. Open Agent Mode (`Ctrl+Shift+I` → select Agent) and use the following prompt:

---

#### Prompt for GitHub Copilot Agent Mode

```
Create a full-stack self-service portal for an enterprise AI agent platform called "Secure Agent Factory". The portal lets developers request new Foundry projects, and routes approvals through IT Platform Engineering and AI CoE teams.

## Tech Stack
- Frontend: React 18 + TypeScript + Vite + Fluent UI v9 (Microsoft design system)
- Backend: Azure Functions (Node.js/TypeScript) with HTTP triggers
- Auth: MSAL.js with Microsoft Entra ID (multi-tenant)
- Database: Azure Cosmos DB (NoSQL) for request tracking
- Hosting: Azure Static Web Apps (frontend) + Azure Functions (backend)

## Authentication & Role-Based Views
- Authenticate with Microsoft Entra ID using MSAL
- Three roles determined by Entra security group membership:
  - "sg-agentfactory-developers" → Developer view
  - "sg-agentfactory-platform-eng" → IT Platform Engineering view
  - "sg-agentfactory-ai-coe" → AI CoE view
- Each role sees only their relevant pages

## Page 1: Developer Request Form (/request)
Create a multi-step wizard form with these sections:

### Step 1 — Project Details
- Project Name (lowercase, alphanumeric, max 20 chars, validated)
- Team / Business Unit (text)
- Cost Center (text, pattern CC-XXXX)
- Business Justification (textarea, min 50 chars)
- Data Classification (dropdown: Public, Internal, Confidential, Restricted)
- Initial Environment (radio: dev, staging)
- Developer Entra Group Name (text with autocomplete from Graph API)
- Expected Monthly Volume (number, interactions/month)
- Estimated Token Budget (number, tokens/hour)

### Step 2 — Model Selection
- Display approved models as selectable cards with descriptions:
  - gpt-4o: "Complex reasoning, multi-step tasks" — capacity slider (10-100 TPM)
  - gpt-4o-mini: "Fast, cost-effective, high-volume" — capacity slider (10-200 TPM)
  - o3-mini: "Advanced reasoning, chain-of-thought" — capacity slider (10-50 TPM)
  - text-embedding-3-large: "Vector embeddings for RAG" — capacity slider
- At least one model required

### Step 3 — Tool & Capability Selection
This is the critical section. It must query the Azure API Center REST API to show available approved tools.

#### MCP Tools (from API Center)
- Fetch tools from API Center REST API: GET https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-agent-factory-platform/providers/Microsoft.ApiCenter/services/apic-agent-factory/workspaces/default/apis?api-version=2024-03-01
- Filter where custom metadata "security-review-status" = "approved"
- Display as a searchable, filterable card grid showing:
  - Tool name
  - Description
  - Data classification badge
  - Tool type (MCP Server, REST API, GraphQL, gRPC)
  - Owner team
  - Last pen test date
- Multi-select with checkboxes
- Group by category if metadata includes categories

#### A2A Agents (from API Center)
- Fetch agents registered in API Center with tool-type = "A2A Agent"
- Display as cards showing agent name, description, capabilities, agent card URL
- Multi-select — these are agents the new project wants to call via A2A protocol

#### Memory Configuration
- Toggle: Enable Agent Memory (default: on)
- If enabled, show options:
  - Memory Type (radio): Semantic Memory, Episodic Memory, Both
  - Memory Store (dropdown): Azure AI Search, Cosmos DB (vCore), Qdrant on ACA
  - Retention Period (dropdown): 30 days, 90 days, 1 year, Indefinite

#### Knowledge Sources
- Toggle: Enable Knowledge Grounding (default: on)
- If enabled, multi-select from available Foundry IQ Knowledge indexes
- Option to request new knowledge index (textarea for data source description)

### Step 4 — Review & Submit
- Summary card showing all selections
- Estimated monthly cost calculation (based on model capacity + memory + tools)
- Terms acknowledgment checkbox: "I confirm this project follows responsible AI guidelines"
- Submit button → POST /api/projects

## Page 2: IT Platform Engineering Dashboard (/admin/platform)
- Table of pending requests with status "pending-infra-review"
- Click to expand full request details
- For each request, show:
  - All project details from the form
  - Network capacity check (auto-calculated: available IPs in PE subnet)
  - Region quota check (auto-calculated: remaining TPM in selected region)
  - Cost center validation status
- Action buttons: Approve (with optional notes) | Reject (with required reason)
- On Approve:
  - Call POST /api/provision/infra which triggers a GitHub Actions workflow
  - The workflow runs the Bicep blueprint (blueprint-foundry-project.bicep) with parameters from the request
  - Provisions: Foundry Project, Private Endpoint, Diagnostic Settings, base RBAC
  - Status moves to "pending-coe-review"

## Page 3: AI CoE Dashboard (/admin/coe)
- Table of requests with status "pending-coe-review" (infra already provisioned)
- Click to expand showing: request details + infra provisioning results
- For each request, show:
  - Tool selections with risk assessment (data classification vs project classification)
  - Model selections with budget impact
  - Memory and knowledge configuration
  - A2A agent connections requested
- Action buttons: Approve (with optional notes) | Reject (with required reason)
- On Approve:
  - Call POST /api/provision/govern which triggers governance provisioning:
  - Deploys approved model deployments to the Foundry project
  - Creates managed identity and scoped RBAC assignments
  - Configures Content Safety and Prompt Shields
  - Creates APIM product + subscription for selected tools
  - Grants API Center access for selected tools
  - Provisions memory store if selected
  - Connects A2A agent endpoints through APIM
  - Scaffolds CI/CD pipeline in a new Git repo from template
  - Sends onboarding package email to developer (via Logic App or SendGrid)
  - Status moves to "provisioned"

## Page 4: Project Status Tracker (/projects)
- Visible to all roles
- Kanban-style board with columns: Submitted → Infra Review → CoE Review → Provisioning → Ready
- Click any card to see full request details + audit trail (who approved, when, notes)
- For "Ready" projects: show the onboarding package (endpoints, tools, models, starter repo)

## Backend API Design
- All endpoints authenticated via Entra ID bearer tokens
- Role-checked middleware: verify caller's group membership before allowing access
- POST /api/projects — validates form, saves to Cosmos DB, status = "pending-infra-review"
- PATCH /api/projects/:id — updates status, records approver identity + timestamp + notes
- POST /api/provision/infra — calls GitHub Actions via repository_dispatch or Azure DevOps pipeline
- POST /api/provision/govern — calls second pipeline for governance layer
- GET /api/catalog/tools — proxies to API Center REST API with Entra token, filters approved tools
- GET /api/catalog/models — returns static list of approved models with metadata
- GET /api/catalog/agents — proxies to API Center filtered for A2A agent type
- Cosmos DB schema: { id, projectName, teamName, status, requestedBy, requestedAt, infraApprovedBy, infraApprovedAt, coeApprovedBy, coeApprovedAt, selections: { models, tools, agents, memory, knowledge }, provisioningResults: {}, auditTrail: [] }

## Provisioning Pipelines (GitHub Actions)
Create two workflow files:

### .github/workflows/provision-infra.yml
- Triggered by repository_dispatch event "provision-infra"
- Receives project parameters in client_payload
- Runs: az deployment group create with blueprint-foundry-project.bicep
- On success: calls PATCH /api/projects/:id to move status to "pending-coe-review"

### .github/workflows/provision-governance.yml
- Triggered by repository_dispatch event "provision-governance"
- Receives project parameters + tool/model/memory selections in client_payload
- Steps:
  1. Deploy model deployments to the Foundry project
  2. Create managed identity RBAC assignments
  3. Configure Content Safety
  4. For each selected tool: create APIM subscription + API Center access
  5. For each selected A2A agent: configure APIM route
  6. If memory enabled: deploy memory store (Bicep module)
  7. Scaffold Git repo from template
  8. Create CI/CD pipeline in the new repo
  9. Send onboarding notification
  10. Call PATCH /api/projects/:id to move status to "provisioned"

## Security Requirements
- Never expose Azure credentials in the frontend
- Backend uses managed identity to call Azure APIs
- All API Center queries go through the backend (not direct from browser)
- CORS restricted to the Static Web App domain
- All state changes recorded in audit trail with caller identity and timestamp
- Input validation on all form fields (prevent injection)
- Rate limiting on submission endpoint (max 5 requests per user per day)

## UI/UX Requirements
- Use Fluent UI v9 components throughout (Button, Input, Dropdown, DataGrid, Card, Dialog)
- Responsive layout (works on desktop and tablet)
- Loading states and error handling for all API calls
- Toast notifications for actions (submitted, approved, rejected)
- Dark mode support via Fluent UI theme provider
```

---

### Step 5.2 — Portal Configuration Requirements

After Copilot Agent Mode generates the scaffold, configure these platform integrations:

#### Entra ID App Registration

```bash
# Register the portal app in Entra ID
az ad app create \
  --display-name "Secure Agent Factory Portal" \
  --sign-in-audience "AzureADMyOrg" \
  --web-redirect-uris "https://portal-agent-factory.azurestaticapps.net/.auth/login/aad/callback" \
  --enable-id-token-issuance true

# Add API permissions
# Microsoft Graph: User.Read, GroupMember.Read.All
# Azure Service Management: user_impersonation
```

#### Cosmos DB for Request State

```bash
az cosmosdb create \
  --name cosmos-agent-factory \
  --resource-group rg-agent-factory-platform \
  --kind GlobalDocumentDB \
  --default-consistency-level Session \
  --locations regionName=eastus2

az cosmosdb sql database create \
  --account-name cosmos-agent-factory \
  --resource-group rg-agent-factory-platform \
  --name agentfactory

az cosmosdb sql container create \
  --account-name cosmos-agent-factory \
  --resource-group rg-agent-factory-platform \
  --database-name agentfactory \
  --name project-requests \
  --partition-key-path "/teamName" \
  --throughput 400
```

#### GitHub Actions Service Principal

```bash
# Create SP for GitHub Actions to run Bicep deployments
az ad sp create-for-rbac \
  --name "sp-agent-factory-provisioning" \
  --role Contributor \
  --scopes /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-platform \
           /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-dev \
           /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-staging \
  --sdk-auth

# Store output as GitHub secret: AZURE_CREDENTIALS
# Also store: COSMOS_CONNECTION_STRING, API_CENTER_RESOURCE_ID
```

---

### Step 5.3 — API Center Integration for Tool Browsing

The portal's tool selection step queries the API Center catalog at runtime. The backend proxies these calls using its managed identity:

```typescript
// backend/src/functions/getCatalogTools.ts
import { app, HttpRequest, HttpResponseInit } from "@azure/functions";
import { DefaultAzureCredential } from "@azure/identity";

export async function getCatalogTools(
  request: HttpRequest
): Promise<HttpResponseInit> {
  const credential = new DefaultAzureCredential();
  const token = await credential.getToken(
    "https://management.azure.com/.default"
  );

  const apiCenterUrl =
    `https://management.azure.com/subscriptions/${process.env.SUBSCRIPTION_ID}` +
    `/resourceGroups/rg-agent-factory-platform` +
    `/providers/Microsoft.ApiCenter/services/apic-agent-factory` +
    `/workspaces/default/apis?api-version=2024-03-01`;

  const response = await fetch(apiCenterUrl, {
    headers: { Authorization: `Bearer ${token.token}` },
  });

  const allApis = await response.json();

  // Filter to approved tools only
  const approvedTools = allApis.value.filter(
    (api: any) =>
      api.properties.customProperties?.["security-review-status"] === "approved"
  );

  // Separate by type: MCP tools vs A2A agents
  const mcpTools = approvedTools.filter(
    (api: any) => api.properties.customProperties?.["tool-type"] !== "A2A Agent"
  );
  const a2aAgents = approvedTools.filter(
    (api: any) => api.properties.customProperties?.["tool-type"] === "A2A Agent"
  );

  return {
    status: 200,
    jsonBody: { mcpTools, a2aAgents },
  };
}

app.http("getCatalogTools", {
  methods: ["GET"],
  authLevel: "anonymous", // Auth handled by Static Web Apps (Entra)
  route: "catalog/tools",
  handler: getCatalogTools,
});
```

---

### Step 5.4 — Provisioning Pipeline (Infrastructure)

```yaml
# .github/workflows/provision-infra.yml
name: "Provision Infrastructure (IT Platform Eng)"

on:
  repository_dispatch:
    types: [provision-infra]

permissions:
  id-token: write
  contents: read

jobs:
  provision:
    runs-on: ubuntu-latest
    environment: agent-factory-platform

    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy Foundry Project Blueprint
        uses: azure/arm-deploy@v2
        with:
          resourceGroupName: "rg-agent-factory-${{ github.event.client_payload.environment }}"
          template: ./blueprints/blueprint-foundry-project.bicep
          parameters: >-
            projectName=${{ github.event.client_payload.projectName }}
            teamName=${{ github.event.client_payload.teamName }}
            costCenter=${{ github.event.client_payload.costCenter }}
            environment=${{ github.event.client_payload.environment }}
            developerGroupId=${{ github.event.client_payload.developerGroupId }}
            vnetId=${{ secrets.VNET_ID }}
            peSubnetId=${{ secrets.PE_SUBNET_ID }}
            lawId=${{ secrets.LAW_ID }}
            appiConnectionString=${{ secrets.APPI_CONNECTION }}
            apimGatewayUrl=${{ secrets.APIM_URL }}
            keyVaultName=${{ secrets.KEYVAULT_NAME }}

      - name: Update Request Status
        run: |
          curl -X PATCH \
            "${{ secrets.PORTAL_API_URL }}/api/projects/${{ github.event.client_payload.requestId }}" \
            -H "Content-Type: application/json" \
            -d '{"status": "pending-coe-review", "infraProvisionedAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
```

---

### Step 5.5 — Provisioning Pipeline (Governance)

```yaml
# .github/workflows/provision-governance.yml
name: "Provision Governance (AI CoE)"

on:
  repository_dispatch:
    types: [provision-governance]

permissions:
  id-token: write
  contents: read

jobs:
  provision:
    runs-on: ubuntu-latest
    environment: agent-factory-coe

    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Deploy Model Deployments
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"
          RG="rg-agent-factory-${{ github.event.client_payload.environment }}"

          echo '${{ github.event.client_payload.models }}' | jq -c '.[]' | while read model; do
            NAME=$(echo $model | jq -r '.name')
            VERSION=$(echo $model | jq -r '.version')
            CAPACITY=$(echo $model | jq -r '.capacity')

            az cognitiveservices account deployment create \
              --name "$PROJECT" \
              --resource-group "$RG" \
              --deployment-name "$NAME" \
              --model-name "$NAME" \
              --model-version "$VERSION" \
              --model-format OpenAI \
              --sku-capacity "$CAPACITY" \
              --sku-name Standard
          done

      - name: Configure Content Safety & Prompt Shields
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"
          RG="rg-agent-factory-${{ github.event.client_payload.environment }}"

          # Enable Content Safety filters on all deployments
          az cognitiveservices account deployment list \
            --name "$PROJECT" --resource-group "$RG" \
            --query "[].name" -o tsv | while read deploy; do
            echo "Content Safety configured for deployment: $deploy"
          done

      - name: Grant APIM Access for Selected Tools
        run: |
          echo '${{ github.event.client_payload.tools }}' | jq -c '.[]' | while read tool; do
            TOOL_NAME=$(echo $tool | jq -r '.name')
            echo "Creating APIM subscription for tool: $TOOL_NAME"

            az apim subscription create \
              --resource-group rg-agent-factory-platform \
              --service-name apim-agent-factory \
              --subscription-id "sub-${{ github.event.client_payload.projectName }}-${TOOL_NAME}" \
              --display-name "${{ github.event.client_payload.projectName }} - ${TOOL_NAME}" \
              --scope "/apis/${TOOL_NAME}" \
              --state active
          done

      - name: Configure A2A Agent Connections
        run: |
          if [ "$(echo '${{ github.event.client_payload.agents }}' | jq 'length')" -gt 0 ]; then
            echo '${{ github.event.client_payload.agents }}' | jq -c '.[]' | while read agent; do
              AGENT_NAME=$(echo $agent | jq -r '.name')
              echo "Configuring A2A route for agent: $AGENT_NAME"
              # Add APIM route for A2A agent endpoint
            done
          fi

      - name: Provision Memory Store
        if: github.event.client_payload.memory.enabled == true
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"
          MEMORY_TYPE="${{ github.event.client_payload.memory.storeType }}"

          echo "Provisioning ${MEMORY_TYPE} memory store for ${PROJECT}"
          # Deploy memory infrastructure via Bicep module
          az deployment group create \
            --resource-group "rg-agent-factory-${{ github.event.client_payload.environment }}" \
            --template-file ./blueprints/modules/memory-store.bicep \
            --parameters \
              projectName="${{ github.event.client_payload.projectName }}" \
              storeType="${MEMORY_TYPE}" \
              retentionDays="${{ github.event.client_payload.memory.retentionDays }}"

      - name: Scaffold Developer Repository
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          PROJECT="${{ github.event.client_payload.projectName }}"
          gh repo create "org-name/agent-${PROJECT}" \
            --template "org-name/agent-starter-template" \
            --private \
            --description "Agent project for ${{ github.event.client_payload.teamName }}"

      - name: Send Onboarding Package
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"

          # Build onboarding payload
          cat <<EOF > onboarding.json
          {
            "projectName": "${PROJECT}",
            "apimEndpoint": "${{ secrets.APIM_URL }}",
            "tools": ${{ github.event.client_payload.tools }},
            "models": ${{ github.event.client_payload.models }},
            "agents": ${{ github.event.client_payload.agents }},
            "memory": ${{ github.event.client_payload.memory }},
            "repoUrl": "https://github.com/org-name/agent-${PROJECT}",
            "documentation": "https://portal-agent-factory.azurestaticapps.net/projects/${PROJECT}"
          }
          EOF

          # Trigger notification (Logic App / SendGrid / Teams webhook)
          curl -X POST "${{ secrets.NOTIFICATION_WEBHOOK_URL }}" \
            -H "Content-Type: application/json" \
            -d @onboarding.json

      - name: Update Request Status to Provisioned
        run: |
          curl -X PATCH \
            "${{ secrets.PORTAL_API_URL }}/api/projects/${{ github.event.client_payload.requestId }}" \
            -H "Content-Type: application/json" \
            -d '{"status": "provisioned", "coeProvisionedAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
```

---

### Step 5.6 — Request State Machine

Every project request follows a strict state machine with full audit trail:

```
                    ┌──────────────┐
                    │  submitted   │  Developer submits form
                    └──────┬───────┘
                           │
                    ┌──────▼───────────────┐
                    │  pending-infra-review │  IT Platform Eng queue
                    └──────┬───────────────┘
                           │
              ┌────────────┼────────────────┐
              │                             │
       ┌──────▼───────┐           ┌────────▼────────┐
       │  infra-       │           │  pending-coe-    │
       │  rejected     │           │  review          │  AI CoE queue
       └──────────────┘           └────────┬─────────┘
                                           │
                              ┌────────────┼────────────────┐
                              │                             │
                       ┌──────▼───────┐           ┌────────▼────────┐
                       │  coe-         │           │  provisioning   │
                       │  rejected     │           └────────┬────────┘
                       └──────────────┘                     │
                                                   ┌────────▼────────┐
                                                   │  provisioned    │  ✅ Ready
                                                   └─────────────────┘

Audit trail recorded at every transition:
  { who, when, action, notes, previousStatus, newStatus }
```

---

### Step 5.7 — What Gets Auto-Provisioned at Each Phase

| Phase | Component | How |
|-------|-----------|-----|
| **IT Approval** | Foundry Project | Bicep `blueprint-foundry-project.bicep` |
| **IT Approval** | Private Endpoint | Bicep (part of blueprint) |
| **IT Approval** | Diagnostic Settings → Log Analytics | Bicep (part of blueprint) |
| **IT Approval** | DNS zone A record | Bicep private DNS zone link |
| **IT Approval** | Base RBAC (Azure AI Developer) | Bicep (part of blueprint) |
| **CoE Approval** | Model deployments | `az cognitiveservices account deployment create` |
| **CoE Approval** | Managed Identity RBAC (Content Safety) | `az role assignment create` |
| **CoE Approval** | Content Safety + Prompt Shields | API config on Foundry project |
| **CoE Approval** | APIM subscription per tool | `az apim subscription create` |
| **CoE Approval** | API Center access grants | API Center RBAC |
| **CoE Approval** | A2A agent APIM routes | APIM API import |
| **CoE Approval** | Memory store (if selected) | Bicep module `memory-store.bicep` |
| **CoE Approval** | CI/CD pipeline scaffold | `gh repo create --template` |
| **CoE Approval** | Onboarding notification | Logic App / SendGrid webhook |

---

### Hosting the Portal

```bash
# Deploy as Azure Static Web App with Azure Functions backend
az staticwebapp create \
  --name portal-agent-factory \
  --resource-group rg-agent-factory-platform \
  --location eastus2 \
  --sku Standard \
  --login-with-aad

# Link the GitHub repo containing the portal code
az staticwebapp update \
  --name portal-agent-factory \
  --resource-group rg-agent-factory-platform \
  --branch main \
  --source "https://github.com/org-name/agent-factory-portal" \
  --app-location "/frontend" \
  --api-location "/backend" \
  --output-location "dist"
```

---

### Summary — Lab Mode vs Production Mode

| Aspect | 🔬 Lab Mode (Parts 1-4) | 🏭 Production Mode (Part 5) |
|--------|------------------------|------------------------------|
| Request method | GitHub Issue template | Self-service portal UX |
| Tool selection | Checkbox in YAML | Live browse from API Center catalog |
| IT review | Manual (read the issue) | Dashboard with auto-capacity checks |
| CoE review | Manual (read the issue) | Dashboard with risk assessment |
| Infra provisioning | AI CoE runs `provision-project.sh` | GitHub Actions auto-triggered on IT approval |
| Governance setup | Manual CLI commands | GitHub Actions auto-triggered on CoE approval |
| Memory provisioning | Not included | Automated Bicep module |
| A2A agent wiring | Not included | Automated APIM route creation |
| Onboarding | Manual email | Automated package via webhook |
| Audit trail | Git commit history | Cosmos DB with full state machine |
| Time to ready | Hours (manual steps) | Minutes (automated pipeline) |
