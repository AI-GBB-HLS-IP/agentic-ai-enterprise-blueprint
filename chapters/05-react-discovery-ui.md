# Chapter 05 — Build a React Discovery UI

## Objective

Build a custom **React UI** that enables developers and business users to discover Agents (via A2A), MCP tools, and skills across the enterprise. Deploy it securely to an **App Service Environment (ASE)** with network isolation.

---

## Architecture Context: The Developer Self-Service Portal

### Where This Fits

The Discovery UI is the **human interface** to the enterprise catalog. While agents discover each other programmatically via A2A and API Center, humans need a rich visual experience to browse, search, and understand available capabilities.

```
┌─────────────────────────────────────────────────────┐
│            React Discovery UI (This Chapter)         │
│                                                     │
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐   │
│  │  Agent    │  │   MCP     │  │    Skill      │   │
│  │  Browser  │  │  Browser  │  │   Browser     │   │
│  └───────────┘  └───────────┘  └───────────────┘   │
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐   │
│  │  Try It   │  │  Usage    │  │   Agent       │   │
│  │  Panel    │  │  Metrics  │  │   Compose     │   │
│  └───────────┘  └───────────┘  └───────────────┘   │
└──────────────────────┬──────────────────────────────┘
                       │ Queries
┌──────────────────────▼──────────────────────────────┐
│  API Center (Chapter 04) + APIM (Chapter 02)        │
└─────────────────────────────────────────────────────┘
```

### What You Will Achieve

- A production-grade **React application** with TypeScript and modern component patterns
- **Agent browsing** with capability search, filtering, and "try it" functionality
- **MCP tool browsing** with schema visualization and usage examples
- Secure deployment on **App Service Environment** (VNet-injected, no public access)

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Developer Productivity** | Find existing tools in seconds instead of asking around or searching wikis |
| **Reduce Shadow AI** | When discovery is easy, developers use governed tools instead of building their own |
| **Business User Access** | Non-developers can browse agent capabilities and request new ones |
| **Composability** | Visual tool for composing multi-agent workflows using discovered capabilities |
| **Adoption Metrics** | Track which tools are most popular, which are underused, and where gaps exist |

---

## Prerequisites

- Chapters 01-03 completed
- Node.js 20+ installed
- GitHub Copilot extension in VS Code (for Agent Mode)

---

## Part 1: Build the React App Using GitHub Copilot Agent Mode

> **Approach**: We will use VS Code **GitHub Copilot Agent Mode** to generate the React application. This demonstrates how developers in your organization can rapidly build applications using AI-assisted development.

### Step 1: Open VS Code Agent Mode

1. Open VS Code
2. Open the Copilot Chat panel (`Ctrl+Shift+I`)
3. Switch to **Agent Mode** (click the mode selector or use `@workspace`)

### Step 2: Prompt for the Application

Use the following prompt in GitHub Copilot Agent Mode:

```
Create a React application using TypeScript and Vite for an "Enterprise AI Platform Discovery Portal" with the following features:

1. **Dashboard Page**: Overview showing counts of registered agents, MCP tools, and skills with recent activity

2. **Agent Discovery Page**:
   - Fetch and display A2A agent cards from a configurable API endpoint
   - Show agent name, description, version, skills, and capabilities
   - Filter by skill tags, status, and protocol
   - Click to view agent details and test with sample messages
   - Display the agent card JSON for developers

3. **MCP Tools Page**:
   - List MCP servers registered in Azure API Center
   - Show each server's tools with descriptions and parameters
   - Provide MCP client configuration snippets (copy-to-clipboard)
   - Filter by category and tags

4. **Skills Catalog Page**:
   - Browse registered skills with descriptions and examples
   - Filter by category and search by keyword
   - Show skill connection details and usage examples

5. **Shared Features**:
   - Responsive Material UI design with dark/light theme
   - Search bar with full-text search across all asset types
   - Authentication via MSAL (Microsoft Entra ID)
   - Environment-based API endpoint configuration
   - Loading states and error handling

Use React Router for navigation, React Query for data fetching,
and Material UI for components. Structure the project with
/src/pages, /src/components, /src/services, /src/hooks folders.
```

### Step 3: Expected Project Structure

Copilot should generate a project with this structure:

```
discovery-portal/
├── src/
│   ├── components/
│   │   ├── Layout/
│   │   │   ├── AppBar.tsx
│   │   │   ├── Sidebar.tsx
│   │   │   └── Layout.tsx
│   │   ├── AgentCard.tsx
│   │   ├── McpServerCard.tsx
│   │   ├── SkillCard.tsx
│   │   └── SearchBar.tsx
│   ├── pages/
│   │   ├── Dashboard.tsx
│   │   ├── AgentDiscovery.tsx
│   │   ├── McpTools.tsx
│   │   └── SkillsCatalog.tsx
│   ├── services/
│   │   ├── agentService.ts
│   │   ├── mcpService.ts
│   │   ├── skillService.ts
│   │   └── apiClient.ts
│   ├── hooks/
│   │   ├── useAgents.ts
│   │   ├── useMcpServers.ts
│   │   └── useSkills.ts
│   ├── auth/
│   │   └── msalConfig.ts
│   ├── App.tsx
│   └── main.tsx
├── package.json
├── vite.config.ts
└── .env.example
```

### Step 4: Key Service Implementations

**Agent Discovery Service** (`src/services/agentService.ts`):
```typescript
import { apiClient } from './apiClient';

export interface AgentCard {
  name: string;
  description: string;
  version: string;
  skills: AgentSkill[];
  capabilities: { streaming: boolean };
  supported_interfaces: { url: string; protocol_binding: string }[];
}

export interface AgentSkill {
  id: string;
  name: string;
  description: string;
  tags: string[];
  examples: string[];
}

export const agentService = {
  // Discover agents via A2A protocol
  async discoverAgents(registryUrl: string): Promise<AgentCard[]> {
    const response = await apiClient.get(`${registryUrl}/agents`);
    return response.data;
  },

  // Get agent card from a specific A2A endpoint
  async getAgentCard(agentUrl: string): Promise<AgentCard> {
    const response = await apiClient.get(`${agentUrl}/.well-known/agent.json`);
    return response.data;
  },

  // Send test message to an A2A agent
  async testAgent(agentUrl: string, message: string, contextId?: string) {
    const response = await apiClient.post(`${agentUrl}/v1/message:stream`, {
      message: {
        kind: 'message',
        role: 'user',
        parts: [{ kind: 'text', text: message }],
        messageId: null,
        contextId: contextId || crypto.randomUUID(),
      },
    });
    return response.data;
  },
};
```

**MCP Server Service** (`src/services/mcpService.ts`):
```typescript
import { apiClient } from './apiClient';

export interface McpServer {
  name: string;
  title: string;
  description: string;
  url: string;
  tools: McpTool[];
}

export interface McpTool {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export const mcpService = {
  // List MCP servers from API Center
  async listServers(): Promise<McpServer[]> {
    const response = await apiClient.get('/api/mcp-servers');
    return response.data;
  },

  // Generate MCP client configuration
  generateConfig(server: McpServer): string {
    return JSON.stringify({
      mcpServers: {
        [server.name]: {
          url: server.url,
          headers: {
            Authorization: 'Bearer <your-token>',
          },
        },
      },
    }, null, 2);
  },
};
```

### Step 5: Build and Test Locally

```bash
cd discovery-portal
npm install
npm run dev
```

---

## Part 2: Deploy to App Service Environment (ASE)

An **App Service Environment (ASE)** provides a fully isolated and dedicated environment for running App Service apps at high scale with full network isolation.

### Understanding ASE Networking

ASE v3 provides:
- **VNet injection** — All apps run inside your VNet
- **Internal or external** endpoint configuration
- **Private DNS** integration
- **No public inbound** access (internal mode)
- **Outbound through VNet** — All traffic controlled by your network rules

### Step 1: Create the App Service Environment

```bash
ASE_NAME="ase-agents-portal"
ASE_SUBNET="snet-ase"

# Create a dedicated subnet for ASE (requires /24 minimum)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name $ASE_SUBNET \
  --address-prefix 10.0.6.0/24 \
  --delegations Microsoft.Web/hostingEnvironments

# Create ASE v3 (internal mode for network isolation)
# Note: This takes 1-2 hours
az appservice ase create \
  --resource-group $RESOURCE_GROUP \
  --name $ASE_NAME \
  --vnet-name $VNET_NAME \
  --subnet $ASE_SUBNET \
  --kind ASEv3 \
  --virtual-ip-type Internal
```

### Step 2: Configure Network Settings

```bash
# Configure custom DNS for ASE
az appservice ase update \
  --resource-group $RESOURCE_GROUP \
  --name $ASE_NAME \
  --front-end-scale-factor 15

# Create private DNS zone for ASE
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "${ASE_NAME}.appserviceenvironment.net"

az network private-dns zone vnet-link create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "${ASE_NAME}.appserviceenvironment.net" \
  --name "link-ase" \
  --virtual-network $VNET_NAME \
  --registration-enabled false
```

### Step 3: Deploy the React App to ASE

```bash
# Create App Service Plan in the ASE
az appservice plan create \
  --resource-group $RESOURCE_GROUP \
  --name "asp-portal" \
  --app-service-environment $ASE_NAME \
  --sku I1v2 \
  --is-linux

# Create the web app
az webapp create \
  --resource-group $RESOURCE_GROUP \
  --plan "asp-portal" \
  --name "app-discovery-portal" \
  --runtime "NODE:20-lts"

# Build the React app
cd discovery-portal
npm run build

# Deploy the built app
cd dist
zip -r ../portal.zip .
cd ..

az webapp deploy \
  --resource-group $RESOURCE_GROUP \
  --name "app-discovery-portal" \
  --src-path portal.zip \
  --type zip

# Configure environment variables
az webapp config appsettings set \
  --resource-group $RESOURCE_GROUP \
  --name "app-discovery-portal" \
  --settings \
    VITE_API_CENTER_URL="https://apic-agents-platform.azure-api.net" \
    VITE_APIM_URL="https://apim-agents-gateway.azure-api.net" \
    VITE_ENTRA_CLIENT_ID="<your-app-registration-client-id>" \
    VITE_ENTRA_TENANT_ID="<your-tenant-id>"
```

### Step 4: Configure Authentication

```bash
# Enable Entra ID authentication
az webapp auth microsoft update \
  --resource-group $RESOURCE_GROUP \
  --name "app-discovery-portal" \
  --client-id "<app-registration-client-id>" \
  --issuer "https://login.microsoftonline.com/<tenant-id>/v2.0" \
  --allowed-audiences "api://app-discovery-portal"
```

---

## Part 3: Optional — Deploy to Azure Container Apps

```bash
# Build container
docker build -t discovery-portal:v1 .
az acr build --registry acragentsplatform --image discovery-portal:v1 .

# Deploy to Container Apps
az containerapp create \
  --resource-group $RESOURCE_GROUP \
  --name "ca-discovery-portal" \
  --environment "cae-agents" \
  --image "acragentsplatform.azurecr.io/discovery-portal:v1" \
  --target-port 80 \
  --ingress internal \
  --env-vars \
    VITE_API_CENTER_URL="https://apic-agents-platform.azure-api.net" \
    VITE_APIM_URL="https://apim-agents-gateway.azure-api.net"
```

---

## Summary

| Component | Status |
|-----------|--------|
| React Discovery UI built with Copilot Agent Mode | ✅ |
| Agent Discovery page (A2A protocol) | ✅ |
| MCP Tools browser | ✅ |
| Skills Catalog | ✅ |
| Deployed to ASE with network isolation | ✅ |
| Entra ID authentication configured | ✅ |

---

## References

- [App Service Environment Overview](https://learn.microsoft.com/en-us/azure/app-service/environment/overview)
- [ASE Network Configuration](https://learn.microsoft.com/en-us/azure/app-service/environment/configure-network-settings)
- [A2A Protocol Specification](https://a2a-protocol.org/latest/)

---

## Next Steps

Proceed to [Chapter 06 — Create a Foundry IQ Knowledge Base](./06-foundry-iq-knowledge.md)
