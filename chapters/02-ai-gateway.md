# Chapter 02 — Build the AI Gateway

## Objective

In this chapter, you will create the **AI Gateway** — the central control plane for all LLM interactions, MCP server governance, and A2A agent routing. This is the foundational layer of the Secure Internet of Agents platform.

By the end of this chapter, you will have:
- An Azure API Management instance with VNet injection for network isolation
- A GenAI gateway configured for LLM traffic management
- A unified model API exposing multiple LLM backends through a single endpoint
- A REST API exposed as an MCP server through APIM
- An A2A agent API imported into the gateway

---

## Architecture Context: The Heart of the Platform

### Where This Fits

The AI Gateway is the **single chokepoint** through which all AI traffic flows. Every LLM call, every MCP tool invocation, every A2A agent delegation passes through this layer — giving you centralized control over security, cost, and quality.

```
┌──────────────────────────────────────────────────────────────┐
│                    All AI Consumers                            │
│  Agents │ Apps │ Copilot │ Developers │ Partner Systems       │
└──────────────────────┬───────────────────────────────────────┘
                       │ Single Entry Point
┌──────────────────────▼───────────────────────────────────────┐
│              AI Gateway (APIM) — This Chapter                 │
│                                                              │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │ GenAI    │ │ MCP      │ │ A2A      │ │ Content      │   │
│  │ Policies │ │ Gateway  │ │ Broker   │ │ Safety       │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘   │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐   │
│  │ Rate     │ │ Semantic │ │ Load     │ │ Token        │   │
│  │ Limiting │ │ Cache    │ │ Balance  │ │ Accounting   │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────────┘   │
└──────────────────────┬───────────────────────────────────────┘
                       │ Managed Identity Auth (no API keys)
┌──────────────────────▼───────────────────────────────────────┐
│  Azure OpenAI │ Foundry Models │ Claude │ Bedrock │ Gemini   │
└──────────────────────────────────────────────────────────────┘
```

### What You Will Achieve

A fully operational AI Gateway that:
- Provides **one endpoint** for all LLM interactions across the organization
- Transforms any REST API into an **MCP server** instantly (existing APIs become agent tools)
- Governs all **A2A agent communication** with auth, rate limiting, and monitoring
- Applies **Content Safety** (Prompt Shields, Task Adherence) inline on every request
- Tracks **token consumption** per team/app/agent for cost attribution
- Eliminates API key sprawl with **managed identity authentication**

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Unified Access** | Developers get one endpoint — no need to manage multiple API keys, endpoints, or SDKs |
| **Cost Control** | Token quotas and rate limits prevent cost explosions; dashboards show exactly who's spending what |
| **Instant Tool Creation** | Any existing REST API becomes an MCP tool with zero code changes — just import into APIM |
| **Security by Default** | Content Safety, JWT validation, and managed identities are enforced for every request |
| **Multi-Model Freedom** | Switch between Azure OpenAI, Claude, Bedrock, or Gemini without changing client code |
| **Observability** | Every request is traced with Application Insights — full visibility into latency, errors, and patterns |

---

## Prerequisites

- Chapter 01 completed (Foundry with BYO VNet operational)
- Azure subscription with Owner access
- Azure CLI installed (`az --version` ≥ 2.60)
- A resource group for the lab: `rg-internet-of-agents`
- VNet from Chapter 01 available

---

## Part 1: Understanding APIM Networking Options

Azure API Management offers several networking models. Understanding these is critical for a secure deployment.

### Networking Model Comparison

| Model | Tiers | Traffic | Use Case |
|-------|-------|---------|----------|
| **VNet Injection (Classic)** — External | Developer, Premium | Inbound + outbound via internet | External access to private backends |
| **VNet Injection (Classic)** — Internal | Developer, Premium | Inbound + outbound via VNet only | Fully internal access |
| **VNet Injection (Premium v2)** | Premium v2 | Inbound + outbound via delegated subnet | **Recommended** — full isolation with modern architecture |
| **VNet Integration (v2)** | Standard v2, Premium v2 | Outbound only | External gateway, private backends |
| **Inbound Private Endpoint** | Most tiers | Inbound only | Secure client connections |

### Our Choice: VNet Injection (Premium v2 Tier)

We will use **VNet injection in the Premium v2 tier** because it provides:

- The API Management gateway endpoint is accessible through the VNet at a **private IP address**
- APIM can make outbound requests to API backends that are **isolated in the network** or any peered network
- Network connectivity to most service dependencies is **automatically managed**
- Both inbound and outbound traffic can be allowed to the **delegated subnet**, peered VNets, ExpressRoute, and S2S VPN connections
- The Premium v2 tier supports all AI gateway capabilities including MCP servers and A2A

> **Note**: VNet injection in Premium v2 is configured at creation time. You cannot add it after the instance is created.

### Advanced: Web Application Firewall

For scenarios requiring both secure external and internal access, deploy an **Azure Application Gateway with WAF** in front of an internal APIM instance. This provides:
- DDoS protection
- SSL offloading
- OWASP rule sets for API protection
- Path-based routing

---

## Part 2: Create the Virtual Network

First, create the virtual network that will host all platform components.

```bash
# Set variables
RESOURCE_GROUP="rg-internet-of-agents"
LOCATION="eastus2"
VNET_NAME="vnet-agents-platform"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create VNet with address space for all platform subnets
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --location $LOCATION

# Create subnet for APIM (delegated) — /24 recommended
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-apim \
  --address-prefix 10.0.1.0/24 \
  --delegations Microsoft.ApiManagement/service

# Create subnet for App Services / ASE
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-appservice \
  --address-prefix 10.0.2.0/24

# Create subnet for Foundry (delegated) — /24 recommended for production
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-foundry \
  --address-prefix 10.0.3.0/24

# Create subnet for private endpoints
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-privateendpoints \
  --address-prefix 10.0.4.0/24

# Create subnet for Azure Container Apps
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-aca \
  --address-prefix 10.0.5.0/24
```

---

## Part 3: Create API Management with VNet Injection

### Step 1: Create the APIM Instance

```bash
APIM_NAME="apim-agents-gateway"

# Create APIM with Premium v2 tier and VNet injection
# Note: This takes 30-45 minutes
az apim create \
  --resource-group $RESOURCE_GROUP \
  --name $APIM_NAME \
  --publisher-name "Enterprise AI Platform" \
  --publisher-email "ai-platform@contoso.com" \
  --sku-name Premiumv2 \
  --location $LOCATION \
  --virtual-network-type Internal \
  --virtual-network "{\"subnetResourceId\": \"/subscriptions/<SUB_ID>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/snet-apim\"}"
```

> **Important**: Replace `<SUB_ID>` with your Azure subscription ID. You can get it with `az account show --query id -o tsv`.

### Step 2: Configure Private DNS Zone

Since APIM is deployed in internal mode, configure a private DNS zone for name resolution.

```bash
# Create private DNS zone for APIM
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "azure-api.net"

# Link DNS zone to VNet
az network private-dns zone vnet-link create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "azure-api.net" \
  --name "link-apim" \
  --virtual-network $VNET_NAME \
  --registration-enabled false

# Get APIM private IP and create A record
APIM_PRIVATE_IP=$(az apim show \
  --resource-group $RESOURCE_GROUP \
  --name $APIM_NAME \
  --query "privateIpAddresses[0]" -o tsv)

az network private-dns record-set a create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "azure-api.net" \
  --name $APIM_NAME

az network private-dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name "azure-api.net" \
  --record-set-name $APIM_NAME \
  --ipv4-address $APIM_PRIVATE_IP
```

### Step 3: Enable System-Assigned Managed Identity

```bash
# Enable managed identity for APIM
az apim update \
  --resource-group $RESOURCE_GROUP \
  --name $APIM_NAME \
  --enable-managed-identity true
```

---

## Part 4: Configure the GenAI Gateway

The AI Gateway in APIM provides a comprehensive set of capabilities for managing AI backends. Here's what we'll configure:

### Step 1: Import a Microsoft Foundry API

First, deploy an Azure OpenAI resource and import it into APIM.

```bash
# Create Azure OpenAI resource
OPENAI_NAME="oai-agents-platform"

az cognitiveservices account create \
  --resource-group $RESOURCE_GROUP \
  --name $OPENAI_NAME \
  --kind OpenAI \
  --sku S0 \
  --location $LOCATION \
  --custom-domain $OPENAI_NAME

# Deploy a model
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $OPENAI_NAME \
  --deployment-name "gpt-4o" \
  --model-name "gpt-4o" \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-name Standard \
  --sku-capacity 30

# Create private endpoint for OpenAI
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --name "pe-openai" \
  --vnet-name $VNET_NAME \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $(az cognitiveservices account show --resource-group $RESOURCE_GROUP --name $OPENAI_NAME --query id -o tsv) \
  --group-id account \
  --connection-name "openai-connection"
```

Now import the Foundry API in the Azure portal:

1. Navigate to your APIM instance in the [Azure portal](https://portal.azure.com)
2. Go to **APIs** → **+ Add API** → **Azure AI Foundry**
3. Select your Azure OpenAI resource and model deployment
4. APIM will auto-configure:
   - The API schema based on the OpenAI specification
   - Backend authentication using managed identity
   - Base policies for the AI gateway

### Step 2: Grant APIM Access to OpenAI

```bash
# Get APIM managed identity principal ID
APIM_PRINCIPAL_ID=$(az apim show \
  --resource-group $RESOURCE_GROUP \
  --name $APIM_NAME \
  --query "identity.principalId" -o tsv)

# Assign Cognitive Services OpenAI User role
OPENAI_RESOURCE_ID=$(az cognitiveservices account show \
  --resource-group $RESOURCE_GROUP \
  --name $OPENAI_NAME \
  --query id -o tsv)

az role assignment create \
  --assignee $APIM_PRINCIPAL_ID \
  --role "Cognitive Services OpenAI User" \
  --scope $OPENAI_RESOURCE_ID
```

### Step 3: Configure AI Gateway Policies

Apply policies for token management, caching, and content safety. Place both token-limit and
token-metric policies in the inbound pipeline:

```xml
<!-- Token rate limiting per subscription and token metrics for monitoring -->
<inbound>
    <base />
    <llm-token-limit
        counter-key="@(context.Subscription.Id)"
        tokens-per-minute="10000"
        estimate-prompt-tokens="true"
        remaining-tokens-variable-name="remainingTokens">
    </llm-token-limit>
    <llm-emit-token-metric namespace="ai-gateway-metrics">
        <dimension name="Subscription" value="@(context.Subscription.Id)" />
        <dimension name="API" value="@(context.Api.Id)" />
        <dimension name="Team" value="@(context.Request.Headers.GetValueOrDefault("x-team-id", "unknown"))" />
    </llm-emit-token-metric>
</inbound>
```

### Step 4: Configure Backend Load Balancing

Set up load balancing across multiple OpenAI deployments:

1. In the Azure portal, go to APIM → **Backends**
2. Create a **backend pool** with multiple OpenAI endpoints
3. Configure:
   - **Priority-based** routing (PTU instances first, then pay-as-you-go)
   - **Circuit breaker** with dynamic trip duration using Retry-After headers
   - **Session affinity** for multi-turn conversations

---

## Part 5: Create the Unified Model API

The unified model API exposes multiple LLM backends through a **single client-facing endpoint** using the OpenAI Chat Completions format.

### Step 1: Create via Azure Portal

1. In APIM → **APIs** → **Models** → **+ Add** → **Unified model API**
2. Configure:
   - **Display name**: `Enterprise LLM API`
   - **API path**: `/llm/v1` (results in endpoint at `/llm/v1/chat/completions`)
3. Add models:
   - **Model 1**: `gpt-4o` → Azure OpenAI endpoint → Managed Identity auth
   - **Model 2**: `claude-sonnet` → Anthropic endpoint → API key header auth
4. Configure **model aliases**:
   - `gpt` → routes to `gpt-4o`
   - `claude` → routes to `claude-sonnet-4-5`
5. Set up token management and content safety policies

### Step 2: Test from a Client Application

```python
from openai import OpenAI

# All requests go through the AI Gateway — one endpoint for all models
client = OpenAI(
    base_url="https://apim-agents-gateway.azure-api.net/llm/v1",
    api_key="<apim-subscription-key>",  # APIM subscription key, NOT an LLM API key
)

# Use the model alias — APIM routes to the right backend
response = client.chat.completions.create(
    model="gpt",  # Alias for gpt-4o
    messages=[{"role": "user", "content": "What can you do?"}],
)
print(response.choices[0].message.content)

# Switch model by changing only the alias — no code changes needed
response = client.chat.completions.create(
    model="claude",  # Alias for claude-sonnet
    messages=[{"role": "user", "content": "What can you do?"}],
)
print(response.choices[0].message.content)
```

### Step 3: Discover Available Models

Developers can discover available models via the `/models` endpoint:

```bash
curl https://apim-agents-gateway.azure-api.net/llm/v1/models \
  -H "Ocp-Apim-Subscription-Key: <key>"
```

---

## Part 6: Create a Web API and Expose as MCP Server

### Step 1: Create a Sample REST API

Create a simple Web API using Azure App Service that we'll expose as an MCP server.

```bash
# Create App Service Plan
az appservice plan create \
  --resource-group $RESOURCE_GROUP \
  --name "asp-agents-api" \
  --sku P1v3 \
  --is-linux

# Create Web App
az webapp create \
  --resource-group $RESOURCE_GROUP \
  --plan "asp-agents-api" \
  --name "app-enterprise-tools" \
  --runtime "PYTHON:3.11"
```

Create a sample Flask API (`app.py`):

```python
from flask import Flask, jsonify, request

app = Flask(__name__)

@app.route("/api/lookup-employee", methods=["GET"])
def lookup_employee():
    """Look up employee details by name or ID."""
    query = request.args.get("query", "")
    # In production, this would query your HR system
    return jsonify({
        "name": "Jane Doe",
        "department": "Engineering",
        "title": "Senior Developer",
        "email": "jane.doe@contoso.com"
    })

@app.route("/api/search-policies", methods=["GET"])
def search_policies():
    """Search company policies by keyword."""
    keyword = request.args.get("keyword", "")
    return jsonify({
        "results": [
            {"title": "Remote Work Policy", "summary": "..."},
            {"title": "Data Classification Policy", "summary": "..."}
        ]
    })

@app.route("/api/create-ticket", methods=["POST"])
def create_ticket():
    """Create a support ticket."""
    data = request.get_json()
    return jsonify({
        "ticket_id": "TKT-2024-001",
        "status": "created",
        "title": data.get("title", ""),
        "priority": data.get("priority", "medium")
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

### Step 2: Import the API into APIM

1. In APIM → **APIs** → **+ Add API** → **OpenAPI**
2. Import the OpenAPI specification for your Web API
3. Configure the backend to point to your App Service
4. Set up authentication (managed identity or subscription key)

### Step 3: Expose as MCP Server

This is the key step — turning your REST API into an MCP server that AI agents can discover and call:

1. In APIM → navigate to your imported API
2. Select **Export as MCP Server**
3. Configure:
   - **MCP Server name**: `enterprise-tools`
   - **Description**: `Enterprise HR and IT tools for AI agents`
   - Each API operation becomes an **MCP tool**:
     - `lookup-employee` → MCP tool for employee lookup
     - `search-policies` → MCP tool for policy search
     - `create-ticket` → MCP tool for ticket creation

4. The MCP server is now accessible at:
   ```
   https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp
   ```

### Step 4: Apply Governance Policies to MCP Tools

```xml
<!-- Apply to all MCP tool operations -->
<inbound>
    <base />
    <!-- Rate limiting -->
    <rate-limit calls="100" renewal-period="60" />

    <!-- JWT validation for Entra ID tokens -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401">
        <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
        <audiences>
            <audience>api://apim-agents-gateway</audience>
        </audiences>
    </validate-jwt>

    <!-- IP filtering -->
    <ip-filter action="allow">
        <address-range from="10.0.0.0" to="10.0.255.255" />
    </ip-filter>
</inbound>

<!-- Cache responses -->
<outbound>
    <base />
    <cache-store duration="300" />
</outbound>
```

### Step 5: Test the MCP Server

From any MCP client (e.g., GitHub Copilot in VS Code, Claude Desktop):

```json
{
  "mcpServers": {
    "enterprise-tools": {
      "url": "https://apim-agents-gateway.azure-api.net/mcp/enterprise-tools/mcp",
      "headers": {
        "Ocp-Apim-Subscription-Key": "<subscription-key>"
      }
    }
  }
}
```

---

## Part 7: Import an A2A Agent API

A2A (Agent-to-Agent) APIs allow agents to communicate using the standardized A2A protocol. Import them into APIM for governance.

1. In APIM → **APIs** → **+ Add API** → **A2A Agent API**
2. Provide the A2A agent card URL (we'll create the agent in Chapter 02)
3. APIM imports the agent card and creates the API definition
4. Apply governance policies (rate limiting, authentication, monitoring)

---

## Part 8: Enable Monitoring

### Configure Application Insights

```bash
# Create Application Insights
az monitor app-insights component create \
  --resource-group $RESOURCE_GROUP \
  --app "ai-gateway-insights" \
  --location $LOCATION \
  --kind web

# Link to APIM
APPINSIGHTS_KEY=$(az monitor app-insights component show \
  --resource-group $RESOURCE_GROUP \
  --app "ai-gateway-insights" \
  --query instrumentationKey -o tsv)

az apim update \
  --resource-group $RESOURCE_GROUP \
  --name $APIM_NAME \
  --set properties.customProperties.'Microsoft.WindowsAzure.ApiManagement.Gateway.Reporting.Telemetry'=true
```

### Enable LLM Logging

In the Azure portal, enable logging for your LLM APIs to track:
- Token usage per consumer
- Prompts and completions (for auditing)
- Latency and error rates
- Cost attribution by team/application

The built-in analytics dashboard in APIM provides a visual overview of all AI gateway metrics.

---

## Summary

You now have:

| Component | Status |
|-----------|--------|
| VNet with subnets for all platform components | ✅ Created |
| APIM with VNet injection (internal mode) | ✅ Created |
| Private DNS zone for internal resolution | ✅ Configured |
| Azure OpenAI with private endpoint | ✅ Created |
| GenAI gateway with token limiting and metrics | ✅ Configured |
| Unified model API with multiple backends | ✅ Created |
| REST API exposed as MCP server | ✅ Created |
| Governance policies on MCP tools | ✅ Applied |
| Application Insights monitoring | ✅ Enabled |

---

## Key Takeaways

1. **AI Gateway is the central choke point** — All LLM and agent traffic flows through APIM, enabling consistent governance
2. **VNet injection provides full isolation** — No public endpoints; all traffic stays within the enterprise network
3. **Managed identities eliminate API keys** — APIM authenticates to backends using its managed identity
4. **MCP server exposure is declarative** — Existing REST APIs become agent tools with zero code changes
5. **Unified model API decouples clients from providers** — Switch models without changing application code

---

## References

- [AI Gateway Capabilities in APIM](https://learn.microsoft.com/en-us/azure/api-management/genai-gateway-capabilities)
- [Unified Model API](https://learn.microsoft.com/en-us/azure/api-management/unified-model-api)
- [MCP Servers in APIM](https://learn.microsoft.com/en-us/azure/api-management/mcp-server-overview)
- [Export REST API as MCP Server](https://learn.microsoft.com/en-us/azure/api-management/export-rest-mcp-server)
- [APIM VNet Concepts](https://learn.microsoft.com/en-us/azure/api-management/virtual-network-concepts)
- [VNet Injection Premium v2](https://learn.microsoft.com/en-us/azure/api-management/inject-vnet-v2)
- [Import A2A Agent API](https://learn.microsoft.com/en-us/azure/api-management/agent-to-agent-api)
- [Import Foundry API](https://learn.microsoft.com/en-us/azure/api-management/azure-ai-foundry-api)

---

## Next Steps

Proceed to [Chapter 03 — Build an Agent with Microsoft Agent Framework](./03-agent-framework.md)
