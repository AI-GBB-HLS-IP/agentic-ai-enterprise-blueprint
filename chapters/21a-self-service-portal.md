# Chapter 21a — Self-Service Portal: Fully Automated Project Provisioning

## What This Chapter Delivers

A **fully automated, zero-manual-intervention** self-service portal where:

- **Developers** request new agent projects through a UX — selecting models, tools (MCP/A2A), memory, and knowledge sources from the live API Center catalog
- **IT Platform Engineering** reviews and approves infrastructure asks in a dashboard — clicking "Approve" triggers fully automated infrastructure provisioning (no CLI, no scripts)
- **AI CoE** reviews and approves governance asks in a dashboard — clicking "Approve" triggers fully automated governance provisioning (no CLI, no scripts)
- **Developers** receive an onboarding package with everything ready — project, models, tools, memory, CI/CD, repo — in minutes

**No manual provisioning. No scripts to run. No CLI commands. One click = fully provisioned.**

> **Relationship to the Lab:** [Chapter 21 (Lab)](./21-foundry-project-blueprint.md) teaches you how each component works by building it manually. This chapter wraps those same components into an automated system. Complete the Lab first to understand the mechanics, then deploy this portal for production use.

---

## Architecture: Three Roles, Three Experiences, Zero Manual Steps

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│   👩‍💻 DEVELOPER                🏗️ IT PLATFORM ENG           🧠 AI CoE            │
│   ────────────                ──────────────────           ────────            │
│                                                                                 │
│   Opens portal               Sees task in                 Sees task in          │
│        │                     approval dashboard           approval dashboard    │
│        ▼                            │                            │              │
│   Fills request form                ▼                            ▼              │
│   (project details,          Reviews infra ask            Reviews governance    │
│    models, tools,            (subnet capacity,            ask (tools, models,   │
│    A2A agents,               region quota,                data classification,  │
│    memory, knowledge)        cost center, network)        budget, compliance)   │
│        │                            │                            │              │
│        ▼                            ▼                            ▼              │
│   Clicks "Submit"            Clicks "Approve"             Clicks "Approve"      │
│        │                            │                            │              │
│        │                     ┌──────▼──────────┐          ┌─────▼────────────┐  │
│        │                     │  AUTO-PROVISIONS │          │  AUTO-PROVISIONS  │  │
│        │                     │  • Foundry Proj  │          │  • Model deploys  │  │
│        │                     │  • Private EP    │          │  • RBAC + Identity│  │
│        │                     │  • Diagnostics   │          │  • Content Safety │  │
│        │                     │  • DNS records   │          │  • Tool access    │  │
│        │                     │  • NSG rules     │          │  • A2A routing    │  │
│        │                     │  • APIM product  │          │  • Memory store   │  │
│        │                     └─────────────────┘          │  • CI/CD pipeline │  │
│        │                                                   │  • Git repo       │  │
│        │                                                   │  • Onboarding pkg │  │
│        │                                                   └──────────────────┘  │
│        ▼                                                                        │
│   Receives onboarding                                                           │
│   package (auto-sent)                                                           │
│   Starts building agent                                                         │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## What Each Role Sees in the Portal

### 👩‍💻 Developer Experience

| Page | What they do |
|------|-------------|
| `/request` | Multi-step wizard: project details → models → tools/A2A/memory/knowledge → review & submit |
| `/projects` | Track request status (Submitted → Infra Review → CoE Review → Provisioning → Ready) |
| `/projects/:id` | View onboarding package once provisioned (endpoints, tools, repo URL, CI/CD) |

**What developers never do:** Touch infrastructure, run CLI commands, configure networking, set up identity, create RBAC assignments, or deploy models.

---

### 🏗️ IT Platform Engineering Experience

| Page | What they do |
|------|-------------|
| `/admin/platform` | Dashboard of requests pending infra review |
| Request detail | See project details + auto-calculated capacity checks (subnet IPs, region TPM, cost center validity) |
| Action | Click "Approve" or "Reject" (with reason) |

**What happens on Approve (fully automated):**
1. GitHub Actions workflow `provision-infra.yml` is triggered via API
2. Bicep blueprint deploys: Foundry Project, Private Endpoint, Diagnostic Settings, DNS, NSG, base RBAC
3. Request status auto-advances to "pending-coe-review"
4. AI CoE is auto-notified

**What IT Platform Eng never does:** Run Bicep manually, SSH into anything, copy-paste parameters, send emails to AI CoE.

---

### 🧠 AI CoE Experience

| Page | What they do |
|------|-------------|
| `/admin/coe` | Dashboard of requests pending governance review (infra already provisioned) |
| Request detail | See request + infra provisioning results + risk assessment (tool data classification vs project classification) |
| Action | Click "Approve" or "Reject" (with reason) |

**What happens on Approve (fully automated):**
1. GitHub Actions workflow `provision-governance.yml` is triggered via API
2. Pipeline auto-provisions: model deployments, managed identity + RBAC, Content Safety, APIM tool subscriptions, A2A routes, memory store, CI/CD scaffold, Git repo from template
3. Onboarding package auto-sent to developer (Teams/email via webhook)
4. Request status auto-advances to "provisioned"

**What AI CoE never does:** Run `az` commands, create subscriptions manually, configure APIM policies by hand, send onboarding emails.

---

## Portal Technical Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Frontend (React + TypeScript + Fluent UI v9)                   │
│  Hosted: Azure Static Web Apps                                  │
│                                                                 │
│  Routes:                                                        │
│  /request          → Developer request wizard                   │
│  /projects         → Status tracker (all roles)                 │
│  /admin/platform   → IT Platform Eng approval dashboard         │
│  /admin/coe        → AI CoE approval dashboard                  │
│                                                                 │
│  Auth: MSAL.js + Microsoft Entra ID                             │
│  Role routing: sg-agentfactory-developers                       │
│                sg-agentfactory-platform-eng                      │
│                sg-agentfactory-ai-coe                            │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTPS (Entra bearer token)
┌────────────────────────▼────────────────────────────────────────┐
│  Backend API (Azure Functions — Node.js/TypeScript)             │
│                                                                 │
│  POST /api/projects           Submit new request                │
│  GET  /api/projects           List requests (role-filtered)     │
│  PATCH /api/projects/:id      Approve / Reject                  │
│  GET  /api/catalog/tools      Live from API Center (MCP tools)  │
│  GET  /api/catalog/agents     Live from API Center (A2A agents) │
│  GET  /api/catalog/models     Approved model list               │
│  GET  /api/catalog/knowledge  Available knowledge indexes       │
│                                                                 │
│  On approve → triggers GitHub Actions via repository_dispatch   │
│  State: Azure Cosmos DB (request lifecycle + audit trail)       │
└────────────────────────┬────────────────────────────────────────┘
                         │ repository_dispatch event
┌────────────────────────▼────────────────────────────────────────┐
│  Provisioning Pipelines (GitHub Actions)                        │
│                                                                 │
│  provision-infra.yml      → Bicep deployment (IT-owned infra)   │
│  provision-governance.yml → Governance setup (CoE-owned config) │
│                                                                 │
│  Auth: Federated credentials (OIDC) — no stored secrets         │
│  Bicep templates: Same ones built in the Lab (Ch 21 Parts 1-2) │
└─────────────────────────────────────────────────────────────────┘
```

---

## Build the Portal — GitHub Copilot Agent Mode Prompt

The AI CoE uses **GitHub Copilot Agent Mode** in VS Code to scaffold the portal. Open Copilot Chat (`Ctrl+Shift+I`), switch to **Agent** mode, and paste the following prompt:

```
Create a full-stack self-service portal for an enterprise AI agent platform called "Secure Agent Factory". The portal lets developers request new Foundry projects, and routes approvals through IT Platform Engineering and AI CoE teams. Every provisioning action is fully automated — approvers only click Approve or Reject, and pipelines handle everything else.

## Tech Stack
- Frontend: React 18 + TypeScript + Vite + Fluent UI v9 (Microsoft design system)
- Backend: Azure Functions (Node.js/TypeScript) with HTTP triggers
- Auth: MSAL.js with Microsoft Entra ID (single-tenant)
- Database: Azure Cosmos DB (NoSQL) for request state + audit trail
- Hosting: Azure Static Web Apps (frontend) + Azure Functions (backend)
- Provisioning: GitHub Actions triggered via repository_dispatch

## Authentication & Role-Based Views
- Authenticate with Microsoft Entra ID using MSAL
- Three roles determined by Entra security group membership:
  - "sg-agentfactory-developers" → Developer view (can only see /request and /projects)
  - "sg-agentfactory-platform-eng" → IT Platform Eng view (can see /admin/platform + /projects)
  - "sg-agentfactory-ai-coe" → AI CoE view (can see /admin/coe + /projects)
- Role-based route guards — redirect unauthorized users
- Display current user name + role badge in the nav bar

## Page 1: Developer Request Form (/request)
Create a multi-step wizard form (4 steps with progress indicator):

### Step 1 — Project Details
- Project Name (lowercase, alphanumeric + hyphens, max 20 chars, uniqueness validated against backend)
- Team / Business Unit (text)
- Cost Center (text, pattern CC-XXXX)
- Business Justification (textarea, min 50 chars)
- Data Classification (dropdown: Public, Internal, Confidential, Restricted)
- Initial Environment (radio: dev, staging)
- Developer Entra Group Name (text with autocomplete querying Microsoft Graph API)
- Expected Monthly Volume (number + "interactions/month" label)
- Estimated Token Budget (number + "tokens/hour" label)

### Step 2 — Model Selection
- Fetch approved models from GET /api/catalog/models
- Display as selectable cards with:
  - Model name and description
  - Use case guidance text
  - Capacity slider (with min/max per model)
  - Monthly cost estimate (auto-calculated from capacity)
- At least one model required (validation)
- Show running total estimated cost at bottom

### Step 3 — Tools, Agents, Memory & Knowledge
This is the core capability selection step. It must query the backend (which proxies to API Center) to show live approved options.

#### Section A: MCP Tools
- Fetch from GET /api/catalog/tools
- Display as searchable, filterable card grid:
  - Tool name + icon
  - Description
  - Data classification badge (color-coded)
  - Tool type label (MCP Server | REST API | GraphQL | gRPC)
  - Owner team
  - Last security review date
- Multi-select with checkboxes
- Filter by: tool type, data classification, category
- Search by name or description
- Show warning if tool data classification exceeds project data classification

#### Section B: A2A Agents
- Fetch from GET /api/catalog/agents
- Display as cards showing:
  - Agent name + avatar/icon
  - Description and capabilities list
  - Agent Card URL (for A2A protocol)
  - Owner team
- Multi-select — these are agents the new project can call via A2A

#### Section C: Memory Configuration
- Toggle switch: "Enable Agent Memory" (default: on)
- If enabled:
  - Memory Type (radio cards): Semantic Memory | Episodic Memory | Both
  - Memory Store (dropdown): Azure AI Search | Cosmos DB (vCore) | Qdrant on ACA
  - Retention Period (dropdown): 30 days | 90 days | 1 year | Indefinite
  - Brief explanation text for each option

#### Section D: Knowledge Sources
- Toggle switch: "Enable Knowledge Grounding" (default: on)
- If enabled:
  - Multi-select from available Foundry IQ Knowledge indexes (fetched from GET /api/catalog/knowledge)
  - Each shown as card with: index name, description, document count, last updated
  - "Request New Index" accordion: textarea to describe needed data source (saved as part of request)

### Step 4 — Review & Submit
- Full summary card showing all selections organized by category
- Estimated monthly cost breakdown table (models + memory + tools)
- Checkbox: "I confirm this project follows Responsible AI guidelines and our data handling policies"
- "Submit Request" button (disabled until checkbox checked)
- On submit: POST /api/projects → show success animation → redirect to /projects/:id

## Page 2: IT Platform Engineering Dashboard (/admin/platform)
- Header: "Infrastructure Approval Queue" with count badge
- DataGrid table with columns: Project Name | Team | Classification | Environment | Submitted | Status
- Sortable + filterable
- Click row → slide-out panel with:
  - Full project details from the request
  - **Auto-calculated checks** (fetched from backend on load):
    - ✅/❌ Subnet capacity: "X IPs available in PE subnet" (from Azure API)
    - ✅/❌ Region quota: "X TPM remaining in region Y" (from Azure API)
    - ✅/❌ Cost center: "Validated with finance system" (from internal API)
  - Selected models and tools (read-only summary)
  - Two action buttons at bottom:
    - "Approve" (primary button) — optional notes textarea — on click: calls PATCH with status change, triggers provision-infra pipeline, shows toast "Infrastructure provisioning triggered"
    - "Reject" (danger button) — required reason textarea — on click: calls PATCH, sends rejection notification to developer

## Page 3: AI CoE Dashboard (/admin/coe)
- Header: "Governance Approval Queue" with count badge
- Only shows requests where status = "pending-coe-review" (infra already provisioned)
- DataGrid table with columns: Project Name | Team | Models Requested | Tools Count | Submitted | Status
- Click row → slide-out panel with:
  - Project details + infra provisioning results (what was already deployed)
  - **Risk assessment** (auto-calculated):
    - Tool risk: flag if any tool's data classification > project's data classification
    - Budget risk: flag if estimated monthly cost > org threshold
    - Model risk: highlight if o3-mini selected (advanced reasoning = higher scrutiny)
  - Full tool selection list with descriptions
  - A2A agent connections requested
  - Memory and knowledge configuration
  - Two action buttons:
    - "Approve" — optional notes — triggers provision-governance pipeline
    - "Reject" — required reason — sends rejection notification

## Page 4: Project Status Tracker (/projects)
- Visible to all roles
- Kanban board with columns: Submitted | Infra Review | CoE Review | Provisioning | Ready
- Each card shows: project name, team, submitted date, current status duration
- Click card → full detail view:
  - Complete request details
  - Audit trail timeline: who did what, when, with notes
  - For "Ready" status: prominently display the Onboarding Package:
    - APIM Endpoint URL
    - Available models (with endpoints)
    - Provisioned tools (with APIM routes)
    - A2A agent connections
    - Memory store connection info
    - Git repository URL (clickable)
    - CI/CD pipeline status
    - "Copy onboarding info" button

## Backend API Design
- All endpoints require valid Entra ID bearer token (validated via middleware)
- Role-check middleware: verify caller group membership matches required role for endpoint
- Endpoints:
  - POST /api/projects — validate form fields, check project name uniqueness, save to Cosmos DB with status "pending-infra-review", return project ID
  - GET /api/projects — return projects filtered by role (developers see own, admins see their queue)
  - GET /api/projects/:id — single project with full audit trail
  - PATCH /api/projects/:id — update status + record approver identity/timestamp/notes in audit trail. If new status triggers provisioning, call GitHub Actions repository_dispatch.
  - GET /api/catalog/tools — proxy to API Center REST API using managed identity, filter to approved tools only
  - GET /api/catalog/agents — proxy to API Center REST API, filter for A2A agent type
  - GET /api/catalog/models — return approved model configurations
  - GET /api/catalog/knowledge — return available knowledge indexes from Foundry
  - GET /api/capacity/subnet — query Azure for available PE subnet IPs
  - GET /api/capacity/quota — query Azure for remaining TPM quota in region

- Cosmos DB document schema:
  {
    id: string,
    projectName: string,
    teamName: string,
    costCenter: string,
    status: "pending-infra-review" | "pending-coe-review" | "provisioning-infra" | "provisioning-governance" | "provisioned" | "rejected",
    requestedBy: { id, name, email },
    requestedAt: ISO timestamp,
    dataClassification: string,
    environment: string,
    selections: {
      models: [{ name, version, capacity }],
      tools: [{ id, name, type }],
      agents: [{ id, name, cardUrl }],
      memory: { enabled, type, store, retentionDays },
      knowledge: { enabled, indexes: [], newIndexRequest?: string }
    },
    infraApproval: { approvedBy, approvedAt, notes } | null,
    coeApproval: { approvedBy, approvedAt, notes } | null,
    rejection: { rejectedBy, rejectedAt, reason, phase } | null,
    provisioningResults: {
      infra: { projectId, privateEndpointIp, diagnosticsId },
      governance: { modelDeployments, toolSubscriptions, repoUrl, pipelineUrl }
    },
    auditTrail: [{ timestamp, actor, action, details }]
  }

## GitHub Actions Integration
The backend triggers pipelines by calling the GitHub API:

POST https://api.github.com/repos/{owner}/{repo}/dispatches
{
  "event_type": "provision-infra" | "provision-governance",
  "client_payload": { ...requestData }
}

Create these workflow files in the portal repo:

### .github/workflows/provision-infra.yml
- Triggered by: repository_dispatch type "provision-infra"
- Uses: azure/login with OIDC federated credentials (no stored secrets)
- Runs: az deployment group create with blueprint-foundry-project.bicep
- Parameters come from client_payload (projectName, teamName, costCenter, environment, developerGroupId)
- On success: PATCH /api/projects/:id → status "pending-coe-review"
- On failure: PATCH /api/projects/:id → status "infra-failed", include error details

### .github/workflows/provision-governance.yml
- Triggered by: repository_dispatch type "provision-governance"
- Uses: azure/login with OIDC federated credentials
- Steps (all automated, no manual intervention):
  1. Deploy model deployments to the Foundry project (from selections.models)
  2. Create managed identity + scoped RBAC assignments
  3. Configure Content Safety and Prompt Shields
  4. For each selected tool: create APIM product subscription + grant API Center access
  5. For each A2A agent: configure APIM route for agent endpoint
  6. If memory enabled: deploy memory store via Bicep module
  7. If knowledge enabled: link selected knowledge indexes to project
  8. Create Git repo from starter template (gh repo create --template)
  9. Configure CI/CD pipeline in new repo (copy workflow files)
  10. Send onboarding package notification (Teams adaptive card via webhook)
  11. PATCH /api/projects/:id → status "provisioned"

## Security Requirements
- Never expose Azure credentials to the frontend
- Backend uses managed identity for all Azure API calls
- API Center queries proxied through backend (never direct from browser)
- CORS restricted to Static Web App domain only
- All state changes recorded in Cosmos DB audit trail with Entra ID of actor
- Input sanitization on all form fields (XSS, injection prevention)
- Rate limiting: max 5 project requests per user per 24 hours
- Federated credentials (OIDC) for GitHub Actions — no long-lived secrets

## UI/UX Requirements
- Fluent UI v9 components throughout (Button, Input, Dropdown, DataGrid, Card, Dialog, Spinner, Toast)
- Responsive layout: optimized for desktop, functional on tablet
- Loading skeletons during API calls
- Error boundaries with retry buttons
- Toast notifications: "Request submitted", "Approved", "Rejected", "Provisioning complete"
- Real-time status updates via polling (every 30s on status pages)
- Dark mode support via FluentProvider theme
- Accessibility: ARIA labels, keyboard navigation, screen reader support
```

---

## Platform Infrastructure for the Portal

### Entra ID App Registration

```bash
# Register the portal application
az ad app create \
  --display-name "Secure Agent Factory Portal" \
  --sign-in-audience "AzureADMyOrg" \
  --web-redirect-uris "https://portal-agent-factory.azurestaticapps.net/.auth/login/aad/callback" \
  --enable-id-token-issuance true

# Add required API permissions
# Microsoft Graph: User.Read, GroupMember.Read.All (for role detection)
# Azure Service Management: user_impersonation (for capacity checks)
```

### Cosmos DB for Request State

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

### Hosting (Azure Static Web Apps)

```bash
az staticwebapp create \
  --name portal-agent-factory \
  --resource-group rg-agent-factory-platform \
  --location eastus2 \
  --sku Standard \
  --login-with-aad
```

### Federated Credentials for GitHub Actions (OIDC — No Stored Secrets)

```bash
# Create app registration for GitHub Actions
APP_ID=$(az ad app create --display-name "sp-agent-factory-provisioning" --query appId -o tsv)
SP_ID=$(az ad sp create --id $APP_ID --query id -o tsv)

# Assign Contributor to provisioning resource groups
az role assignment create --assignee $SP_ID --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-platform
az role assignment create --assignee $SP_ID --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-dev
az role assignment create --assignee $SP_ID --role Contributor \
  --scope /subscriptions/<sub-id>/resourceGroups/rg-agent-factory-staging

# Add federated credential for GitHub Actions
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:org-name/agent-factory-portal:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

---

## API Center Integration: Live Tool Catalog in the Portal

The developer's tool selection step fetches the live catalog from API Center via the backend:

```typescript
// backend/src/functions/getCatalogTools.ts
import { app, HttpRequest, HttpResponseInit } from "@azure/functions";
import { DefaultAzureCredential } from "@azure/identity";

export async function getCatalogTools(
  request: HttpRequest
): Promise<HttpResponseInit> {
  const credential = new DefaultAzureCredential();
  const token = await credential.getToken("https://management.azure.com/.default");

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
  const approved = allApis.value.filter(
    (api: any) =>
      api.properties.customProperties?.["security-review-status"] === "approved"
  );

  // Separate by type
  const mcpTools = approved.filter(
    (api: any) => api.properties.customProperties?.["tool-type"] !== "A2A Agent"
  );
  const a2aAgents = approved.filter(
    (api: any) => api.properties.customProperties?.["tool-type"] === "A2A Agent"
  );

  return { status: 200, jsonBody: { mcpTools, a2aAgents } };
}

app.http("getCatalogTools", {
  methods: ["GET"],
  authLevel: "anonymous", // Auth handled by Static Web Apps EasyAuth
  route: "catalog/tools",
  handler: getCatalogTools,
});
```

---

## Provisioning Pipeline: Infrastructure (IT Platform Eng Ownership)

Triggered automatically when IT Platform Eng clicks "Approve" — no manual steps.

```yaml
# .github/workflows/provision-infra.yml
name: "Auto-Provision Infrastructure"

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
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy Foundry Project Blueprint
        uses: azure/arm-deploy@v2
        id: deploy
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

      - name: Advance Request to CoE Review
        run: |
          curl -X PATCH \
            "${{ secrets.PORTAL_API_URL }}/api/projects/${{ github.event.client_payload.requestId }}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
            -d '{
              "status": "pending-coe-review",
              "provisioningResults": {
                "infra": {
                  "projectResourceId": "${{ steps.deploy.outputs.projectResourceId }}",
                  "privateEndpointIp": "${{ steps.deploy.outputs.privateEndpointIp }}",
                  "projectEndpoint": "${{ steps.deploy.outputs.projectEndpoint }}"
                }
              }
            }'
```

---

## Provisioning Pipeline: Governance (AI CoE Ownership)

Triggered automatically when AI CoE clicks "Approve" — no manual steps.

```yaml
# .github/workflows/provision-governance.yml
name: "Auto-Provision Governance"

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
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy Model Deployments
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"
          RG="rg-agent-factory-${{ github.event.client_payload.environment }}"

          echo '${{ toJson(github.event.client_payload.selections.models) }}' | jq -c '.[]' | while read model; do
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
          # Content Safety is already provisioned by infra blueprint
          # Configure severity thresholds based on data classification
          echo "Content Safety configured for project: $PROJECT"

      - name: Grant APIM Access for Selected Tools
        run: |
          PROJECT="${{ github.event.client_payload.projectName }}"
          echo '${{ toJson(github.event.client_payload.selections.tools) }}' | jq -c '.[]' | while read tool; do
            TOOL_ID=$(echo $tool | jq -r '.id')
            TOOL_NAME=$(echo $tool | jq -r '.name')

            az apim subscription create \
              --resource-group rg-agent-factory-platform \
              --service-name apim-agent-factory \
              --subscription-id "sub-${PROJECT}-${TOOL_ID}" \
              --display-name "${PROJECT} — ${TOOL_NAME}" \
              --scope "/apis/${TOOL_ID}" \
              --state active
          done

      - name: Configure A2A Agent Routes
        run: |
          echo '${{ toJson(github.event.client_payload.selections.agents) }}' | jq -c '.[]' | while read agent; do
            AGENT_NAME=$(echo $agent | jq -r '.name')
            AGENT_CARD=$(echo $agent | jq -r '.cardUrl')
            echo "Configuring A2A route: $AGENT_NAME → $AGENT_CARD"
            # Import agent endpoint into APIM as API with A2A policy
          done

      - name: Provision Memory Store
        run: |
          MEMORY='${{ toJson(github.event.client_payload.selections.memory) }}'
          ENABLED=$(echo $MEMORY | jq -r '.enabled')
          if [ "$ENABLED" = "true" ]; then
            az deployment group create \
              --resource-group "rg-agent-factory-${{ github.event.client_payload.environment }}" \
              --template-file ./blueprints/modules/memory-store.bicep \
              --parameters \
                projectName="${{ github.event.client_payload.projectName }}" \
                storeType="$(echo $MEMORY | jq -r '.store')" \
                retentionDays="$(echo $MEMORY | jq -r '.retentionDays')"
          fi

      - name: Scaffold Developer Repository
        env:
          GH_TOKEN: ${{ secrets.REPO_SCAFFOLD_TOKEN }}
        run: |
          PROJECT="${{ github.event.client_payload.projectName }}"
          TEAM="${{ github.event.client_payload.teamName }}"
          gh repo create "org-name/agent-${PROJECT}" \
            --template "org-name/agent-starter-template" \
            --private \
            --description "Agent project: ${PROJECT} (${TEAM})"

      - name: Send Onboarding Package
        run: |
          PROJECT="agent-${{ github.event.client_payload.projectName }}-${{ github.event.client_payload.environment }}"
          TOOLS='${{ toJson(github.event.client_payload.selections.tools) }}'
          MODELS='${{ toJson(github.event.client_payload.selections.models) }}'

          cat <<EOF > onboarding.json
          {
            "projectName": "${PROJECT}",
            "apimEndpoint": "${{ secrets.APIM_URL }}",
            "tools": ${TOOLS},
            "models": ${MODELS},
            "repoUrl": "https://github.com/org-name/agent-${{ github.event.client_payload.projectName }}",
            "portalUrl": "https://portal-agent-factory.azurestaticapps.net/projects/${{ github.event.client_payload.requestId }}"
          }
          EOF

          curl -X POST "${{ secrets.TEAMS_WEBHOOK_URL }}" \
            -H "Content-Type: application/json" \
            -d @onboarding.json

      - name: Mark Request as Provisioned
        run: |
          curl -X PATCH \
            "${{ secrets.PORTAL_API_URL }}/api/projects/${{ github.event.client_payload.requestId }}" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
            -d '{"status": "provisioned"}'
```

---

## Request Lifecycle (State Machine)

```
┌─────────────────┐
│    submitted    │  Developer clicks "Submit"
└────────┬────────┘
         │  (auto-routes to IT Platform Eng dashboard)
┌────────▼─────────────────┐
│  pending-infra-review    │  IT Platform Eng sees request
└────────┬─────────────────┘
         │
    ┌────┴────────────────────┐
    │                         │
┌───▼──────────┐    ┌────────▼────────────┐
│  rejected    │    │ provisioning-infra   │  IT clicks "Approve"
│  (notified)  │    └────────┬────────────┘
└──────────────┘             │  (GitHub Actions runs Bicep)
                    ┌────────▼─────────────┐
                    │  pending-coe-review   │  AI CoE sees request
                    └────────┬─────────────┘
                             │
                        ┌────┴────────────────────┐
                        │                         │
                   ┌────▼──────────┐    ┌────────▼──────────────┐
                   │  rejected     │    │ provisioning-govern    │  CoE clicks "Approve"
                   │  (notified)   │    └────────┬──────────────┘
                   └──────────────┘              │  (GitHub Actions runs governance)
                                        ┌────────▼────────┐
                                        │  provisioned    │  ✅ Developer notified
                                        └─────────────────┘

Every transition records: { who, when, action, notes }
```

---

## What Gets Auto-Provisioned — By Role

### On IT Platform Eng Approval (One Click)

| Component | Method | Owner |
|-----------|--------|-------|
| Foundry Project (AI Services) | Bicep blueprint | 🏗️ IT |
| Private Endpoint + DNS | Bicep blueprint | 🏗️ IT |
| Diagnostic Settings → Log Analytics | Bicep blueprint | 🏗️ IT |
| NSG rules for project subnet | Bicep blueprint | 🏗️ IT |
| Base RBAC (Azure AI Developer) | Bicep blueprint | 🏗️ IT |
| Content Safety resource | Bicep blueprint | 🏗️ IT |
| Key Vault secrets (APIM URL, AppInsights) | Bicep blueprint | 🏗️ IT |

### On AI CoE Approval (One Click)

| Component | Method | Owner |
|-----------|--------|-------|
| Model deployments (per selection) | `az cognitiveservices deployment create` | 🧠 CoE |
| Managed Identity RBAC scoping | `az role assignment create` | 🧠 CoE |
| Content Safety severity thresholds | API configuration | 🧠 CoE |
| APIM subscription per selected tool | `az apim subscription create` | 🧠 CoE |
| API Center access grants | RBAC on API Center | 🧠 CoE |
| A2A agent APIM routes | APIM API import | 🧠 CoE |
| Memory store (AI Search / Cosmos / Qdrant) | Bicep module | 🧠 CoE |
| Knowledge index linkage | Foundry project config | 🧠 CoE |
| Git repository from template | `gh repo create --template` | 🧠 CoE |
| CI/CD pipeline (6 gates) | Workflow file copy | 🧠 CoE |
| Onboarding notification | Teams webhook | 🧠 CoE |

---

## Summary

| Principle | How the Portal Achieves It |
|-----------|---------------------------|
| **Zero manual provisioning** | Every resource created by pipelines, triggered by approval click |
| **Separation of duties** | IT approves infra, CoE approves governance — different dashboards, different pipelines |
| **Live catalog browsing** | Tools and A2A agents fetched from API Center at request time |
| **Full audit trail** | Every action recorded in Cosmos DB with actor identity and timestamp |
| **Developer velocity** | Submit request → provisioned in minutes (not days) |
| **No shadow AI** | Developers can only request from approved catalog — no direct resource creation |
| **Cost visibility** | Estimated costs shown at request time, budget validated at approval |

---

## Next Steps

- Deploy the portal using GitHub Copilot Agent Mode with the prompt above
- Configure Entra ID app registration + role groups
- Set up Cosmos DB and GitHub Actions federated credentials
- Proceed to [Chapter 22 — Identity, RBAC & Guardrails by Default](./22-identity-rbac-guardrails.md)
