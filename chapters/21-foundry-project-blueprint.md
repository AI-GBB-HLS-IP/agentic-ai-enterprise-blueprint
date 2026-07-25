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

## The Blueprint Principle

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
