# Chapter 03 — Create Azure API Center

## Objective

Create an **Azure API Center** as the centralized registry for all MCP servers, skills, APIs, and agent tools across the enterprise. API Center complements the AI Gateway (APIM) by providing design-time governance, discovery, and a developer portal.

By the end of this chapter, you will have:
- An Azure API Center instance linked to APIM
- MCP servers registered and discoverable (including the one from Chapter 01)
- Sample skills registered from agentskills.io
- A developer portal for API and tool discovery

---

## Prerequisites

- Chapters 01-02 completed
- Azure CLI authenticated
- APIM instance from Chapter 01 operational

---

## Part 1: Understanding Azure API Center

### What is Azure API Center?

Azure API Center provides a **centralized location** for managing your organization's entire API inventory — regardless of API type, lifecycle stage, or deployment location. It is the **design-time governance** companion to APIM's **runtime governance**.

### How API Center Complements APIM

| Capability | APIM (Runtime) | API Center (Design-time) |
|-----------|----------------|--------------------------|
| API gateway & proxy | ✅ | ❌ |
| Rate limiting & throttling | ✅ | ❌ |
| MCP server exposure | ✅ | ❌ |
| API inventory & catalog | Limited | ✅ Full |
| API governance & linting | ❌ | ✅ |
| MCP server registry (all sources) | APIM-hosted only | ✅ All sources |
| Skill & plugin registry | ❌ | ✅ |
| Developer portal for discovery | ✅ (runtime) | ✅ (catalog) |
| API definition analysis | ❌ | ✅ |
| Cross-platform API tracking | ❌ | ✅ |

### Key Benefits for the Internet of Agents

1. **MCP Server Registry** — Register and discover MCP servers from APIM and external sources in one place
2. **Skill Discovery** — Register skills and plugins for agent consumption
3. **Governance** — Enforce API definition quality through linting and analysis
4. **Developer Self-Service** — Developers find tools and APIs without asking anyone
5. **Synchronized with APIM** — APIs and MCP servers automatically sync between APIM and API Center

---

## Part 2: Create Azure API Center

### Step 1: Create the Instance

```bash
RESOURCE_GROUP="rg-internet-of-agents"
LOCATION="eastus2"
API_CENTER_NAME="apic-agents-platform"

# Create API Center (Standard plan for enterprise features)
az apic create \
  --resource-group $RESOURCE_GROUP \
  --name $API_CENTER_NAME \
  --location $LOCATION
```

> **Cost Tip**: If your API Center is linked to an eligible APIM instance (Standard, Standard v2, Premium, or Premium v2), the Standard plan is available at no extra cost.

### Step 2: Link API Center to APIM

Linking synchronizes APIs and MCP servers between APIM and API Center automatically.

```bash
APIM_RESOURCE_ID=$(az apim show \
  --resource-group $RESOURCE_GROUP \
  --name "apim-agents-gateway" \
  --query id -o tsv)

# Link APIM to API Center
az apic service link create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --link-name "apim-link" \
  --linked-resource-id $APIM_RESOURCE_ID
```

After linking, all APIs and MCP servers from APIM are automatically visible in API Center.

---

## Part 3: Register MCP Servers

### Register the MCP Server from Chapter 01

The MCP server created in Chapter 01 (enterprise-tools) should auto-sync from APIM. Verify in the portal:

1. Navigate to API Center in the [Azure portal](https://portal.azure.com)
2. Go to **MCP Servers**
3. Verify `enterprise-tools` appears with its tools:
   - `lookup-employee`
   - `search-policies`
   - `create-ticket`

### Register an External MCP Server

For MCP servers hosted outside APIM:

```bash
# Register an external MCP server
az apic mcp-server create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --mcp-server-name "external-data-tools" \
  --title "External Data Analytics Tools" \
  --description "MCP server for data analytics operations hosted on Azure Functions" \
  --url "https://func-data-tools.azurewebsites.net/mcp"
```

### MCP Server Discovery for Developers

Developers can discover MCP servers through:

1. **API Center Portal** — Web-based browsing and search
2. **VS Code Extension** — Azure API Center extension for VS Code
3. **CLI** — `az apic mcp-server list`

```bash
# List all registered MCP servers
az apic mcp-server list \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --output table
```

---

## Part 4: Register Skills

Skills are reusable agent capabilities that can be discovered and used by AI agents. They extend agents with specialized functionality.

### Step 1: Browse Available Skills

Visit [agentskills.io](https://agentskills.io/home) to explore available skills. Example skills include:
- **Web Search** — Search the internet for current information
- **Code Execution** — Execute code in a sandboxed environment
- **Document Analysis** — Extract and analyze document content
- **Calendar Management** — Manage calendar events and scheduling

### Step 2: Register Skills in API Center

```bash
# Register a custom skill
az apic skill create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --skill-name "document-analyzer" \
  --title "Document Analyzer" \
  --description "Analyzes documents for key information extraction, summarization, and classification" \
  --version "1.0" \
  --tags "documents,analysis,extraction"

# Register another skill
az apic skill create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --skill-name "expense-processor" \
  --title "Expense Report Processor" \
  --description "Processes expense reports, validates against policy, and submits for approval" \
  --version "1.0" \
  --tags "expenses,finance,approval"
```

### Step 3: Register Skills via Portal

For a richer experience, use the Azure portal:

1. Navigate to API Center → **Skills**
2. Select **+ Register Skill**
3. Provide:
   - **Name**: The skill identifier
   - **Description**: What the skill does (used for agent discovery)
   - **Version**: Semantic version
   - **Endpoint**: The skill's API endpoint
   - **OpenAPI Definition**: Upload the skill's API specification
   - **Tags**: Categories for discovery

---

## Part 5: Register APIs

### Step 1: Register the Travel Agent A2A API

```bash
# Register the A2A agent API from Chapter 02
az apic api create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --api-id "travel-agent-a2a" \
  --title "Enterprise Travel Agent (A2A)" \
  --description "A2A-compliant travel booking and policy compliance agent" \
  --type "a2a" \
  --custom-properties '{"team": "travel-services", "environment": "production"}'

# Add a version
az apic api version create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --api-id "travel-agent-a2a" \
  --version-id "v1" \
  --title "v1.0" \
  --lifecycle-stage "production"
```

### Step 2: Define Custom Metadata

Create custom metadata properties to categorize and govern your APIs:

```bash
# Create metadata for team ownership
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "owning-team" \
  --title "Owning Team" \
  --schema '{"type": "string", "enum": ["travel", "hr", "finance", "engineering"]}'

# Create metadata for data classification
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "data-classification" \
  --title "Data Classification" \
  --schema '{"type": "string", "enum": ["public", "internal", "confidential", "restricted"]}'

# Create metadata for agent compatibility
az apic metadata create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --metadata-name "agent-protocol" \
  --title "Agent Protocol" \
  --schema '{"type": "string", "enum": ["mcp", "a2a", "rest", "graphql"]}'
```

---

## Part 6: Set Up the API Center Portal

Deploy the developer-facing portal for self-service discovery.

### Step 1: Enable the Portal

```bash
# Configure the API Center portal
az apic portal create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --title "Enterprise AI Platform — Tool & Agent Catalog" \
  --description "Discover and consume agents, MCP tools, skills, and APIs"
```

### Step 2: Configure Portal Access

1. In the Azure portal → API Center → **Portal**
2. Configure **Entra ID authentication** for the portal
3. Set up **role-based access**:
   - **API Center Reader** — Can browse and discover
   - **API Center Contributor** — Can register new APIs and tools
   - **API Center Admin** — Full management access

### Step 3: Portal Features

The API Center portal provides:

- **Search & Browse** — Full-text search across all registered assets
- **MCP Server Registry** — Browse MCP servers with connection details
- **Skill Catalog** — Discover skills with descriptions and examples
- **API Details** — View definitions, versions, deployments, and environments
- **Try-It Experience** — Test APIs directly from the portal
- **Connection Snippets** — Copy-paste configuration for MCP clients

---

## Part 7: Enable API Governance

### Step 1: Configure API Linting

Set up automated API definition analysis:

```bash
# Enable managed API analysis (linting)
az apic api-analysis create \
  --resource-group $RESOURCE_GROUP \
  --service-name $API_CENTER_NAME \
  --analysis-name "style-check" \
  --ruleset "microsoft-api-guidelines"
```

### Step 2: API Governance Dashboard

In the Azure portal → API Center → **Governance**:

- View compliance scores across all registered APIs
- Identify APIs missing required metadata
- Track API definition quality over time
- Enforce naming conventions and versioning standards

---

## Part 8: VS Code Integration

### Install the Azure API Center Extension

Developers can discover and use APIs directly from VS Code:

1. Install the **Azure API Center** extension for VS Code
2. Sign in with your Azure account
3. Browse the API Center catalog from the sidebar
4. For MCP servers, the extension can generate `mcp.json` configuration

### Generate MCP Client Configuration

From VS Code, developers can:
1. Browse to an MCP server in the API Center
2. Click **"Copy MCP Configuration"**
3. Paste into their agent's MCP client configuration

```json
{
  "mcpServers": {
    "enterprise-tools": {
      "url": "https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

---

## Summary

| Component | Status |
|-----------|--------|
| Azure API Center created | ✅ |
| Linked to APIM for auto-sync | ✅ |
| MCP servers registered and discoverable | ✅ |
| Skills registered | ✅ |
| APIs registered with custom metadata | ✅ |
| Developer portal deployed | ✅ |
| API governance (linting) configured | ✅ |

---

## References

- [Azure API Center Overview](https://learn.microsoft.com/en-us/azure/api-center/overview)
- [Register and Discover MCP Servers](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server)
- [Register and Discover Skills](https://learn.microsoft.com/en-us/azure/api-center/register-discover-skills)
- [Set Up API Center Portal](https://learn.microsoft.com/en-us/azure/api-center/set-up-api-center-portal)
- [Synchronize APIM and API Center](https://learn.microsoft.com/en-us/azure/api-center/synchronize-api-management-apis)

---

## Next Steps

Proceed to [Chapter 04 — Build a React Discovery UI](./04-react-discovery-ui.md)
