# Chapter 14 — Connect Copilot Studio to APIM MCP Server via VNet

## Objective

In this chapter, you will connect **Microsoft Copilot Studio** to the **APIM MCP server** (built in Chapter 02) using **VNet integration** and **private endpoints** — ensuring all traffic between Copilot Studio and your AI Gateway stays on the Microsoft backbone network without traversing the public internet.

By the end of this chapter, you will have:
- VNet support enabled for your Power Platform environment
- A private endpoint exposing APIM to the Power Platform delegated subnet
- A Copilot Studio agent that invokes MCP tools through the private APIM endpoint
- End-to-end private connectivity validated with no public internet exposure

---

## Architecture Context: Extending Zero-Trust to Low-Code AI

### Where This Fits

Copilot Studio is a **low-code agent builder** that empowers citizen developers to create conversational AI agents. However, enterprise security teams require that these agents access backend services — like your MCP server and LLM gateway — through private network paths, not public endpoints.

```
┌───────────────────────────────────────────────────────────────────┐
│                    Microsoft Copilot Studio                         │
│        (Power Platform Managed Environment + VNet Support)         │
└──────────────────────────────┬────────────────────────────────────┘
                               │ Private traffic via delegated subnet
┌──────────────────────────────▼────────────────────────────────────┐
│              Power Platform VNet (Delegated Subnet)                 │
│                    snet-powerplatform (10.0.7.0/24)                │
└──────────────────────────────┬────────────────────────────────────┘
                               │ Private Endpoint
┌──────────────────────────────▼────────────────────────────────────┐
│              AI Gateway (APIM) — Chapter 02                        │
│    MCP Server │ GenAI Gateway │ A2A Routing │ Rate Limiting        │
└──────────────────────────────┬────────────────────────────────────┘
                               │ VNet-injected (snet-apim)
┌──────────────────────────────▼────────────────────────────────────┐
│         Backend Services (Foundry, Models, Tools, Data)            │
└───────────────────────────────────────────────────────────────────┘
```

### What You Will Achieve

- **Zero public internet exposure** — Copilot Studio connects to APIM entirely over private networking
- **Enterprise governance** — All MCP tool calls from Copilot Studio go through APIM policies (rate limiting, JWT validation, content filtering)
- **Citizen developer enablement** — Low-code builders get full access to MCP tools without managing network infrastructure
- **Compliance posture** — Traffic never leaves the Microsoft backbone, satisfying data residency and sovereignty requirements

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Network Isolation** | Copilot Studio traffic to APIM stays within your VNet |
| **Centralized Governance** | Same APIM policies apply whether the caller is code-first or low-code |
| **No Public Endpoint Required** | APIM can disable public access entirely |
| **Auditability** | All Copilot Studio → MCP calls appear in APIM analytics and App Insights |

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Chapter 02 completed | APIM deployed with VNet injection and MCP server configured |
| Chapter 01 completed | VNet infrastructure with available subnet space |
| Power Platform environment | With **Managed Environment** enabled |
| Copilot Studio license | Per-user or per-tenant license |
| Azure subscription | Same subscription as APIM for VNet peering |
| Roles | Power Platform Environment Admin + Azure Network Contributor |

---

## Part 1: Enable VNet Support for Power Platform

### Step 1.1 — Understand the Requirements

VNet support for Power Platform requires:
- A **Managed Environment** (not a default environment)
- A **delegated subnet** with the `Microsoft.PowerPlatform/vnetaccesslinks` delegation
- The subnet must have at least a **/24** CIDR block
- Enterprise policies configured via ARM template

### Step 1.2 — Create the Delegated Subnet

Add a subnet for Power Platform to the existing VNet:

```bash
# Add Power Platform delegated subnet
az network vnet subnet create \
  --resource-group rg-internet-of-agents \
  --vnet-name vnet-agents \
  --name snet-powerplatform \
  --address-prefixes 10.0.7.0/24 \
  --delegations Microsoft.PowerPlatform/vnetaccesslinks
```

### Step 1.3 — Deploy Enterprise Policy for VNet Support

Use the ARM template from Microsoft's CopilotStudioSamples repository:

```powershell
# Clone the sample infrastructure templates
git clone https://github.com/microsoft/CopilotStudioSamples.git
cd CopilotStudioSamples/infrastructure/vnet-support

# Deploy the enterprise policy
New-AzSubscriptionDeployment `
  -Name "powerplatform-vnet-policy" `
  -TemplateFile "./enterprisePolicy.json" `
  -Location "eastus2" `
  -Verbose
```

Alternatively, create the enterprise policy manually:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "enterprisePolicyName": {
      "type": "string",
      "defaultValue": "ep-copilot-studio-vnet"
    },
    "location": {
      "type": "string",
      "defaultValue": "eastus2"
    },
    "subnetId": {
      "type": "string",
      "metadata": {
        "description": "Resource ID of the delegated subnet"
      }
    }
  },
  "resources": [
    {
      "type": "Microsoft.PowerPlatform/enterprisePolicies",
      "apiVersion": "2020-10-01",
      "name": "[parameters('enterprisePolicyName')]",
      "location": "[parameters('location')]",
      "kind": "NetworkInjection",
      "properties": {
        "networkInjection": {
          "virtualNetworks": [
            {
              "id": "[parameters('subnetId')]"
            }
          ]
        }
      }
    }
  ]
}
```

Deploy with:

```bash
SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-internet-of-agents \
  --vnet-name vnet-agents \
  --name snet-powerplatform \
  --query id -o tsv)

az deployment group create \
  --resource-group rg-internet-of-agents \
  --template-file enterprise-policy.json \
  --parameters subnetId=$SUBNET_ID
```

### Step 1.4 — Link the Enterprise Policy to Your Environment

```powershell
# Connect to Power Platform
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force
Connect-PowerAppsAdministration

# Get your environment ID
$env = Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq "Agents-Production" }

# Link the enterprise policy to the environment
# This is done via the Power Platform Admin Center or ARM API
# Navigate to: admin.powerplatform.microsoft.com → Environments → Your Env → Settings → Networking
```

> **Note**: After enabling VNet support, the environment may take 15-30 minutes to fully configure the network path.

---

## Part 2: Configure Private Endpoint for APIM

### Step 2.1 — Create a Private Endpoint for APIM Gateway

Since your APIM is already VNet-injected (Chapter 02), you need a **private endpoint** so that the Power Platform delegated subnet can reach it:

```bash
# Create private endpoint for APIM in the private endpoints subnet
az network private-endpoint create \
  --resource-group rg-internet-of-agents \
  --name pe-apim-powerplatform \
  --vnet-name vnet-agents \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $(az apim show \
    --name apim-agents-gateway \
    --resource-group rg-internet-of-agents \
    --query id -o tsv) \
  --group-id Gateway \
  --connection-name apim-powerplatform-connection
```

### Step 2.2 — Configure Private DNS Zone

Create a private DNS zone so Copilot Studio resolves APIM's hostname to the private IP:

```bash
# Create private DNS zone for APIM
az network private-dns zone create \
  --resource-group rg-internet-of-agents \
  --name "privatelink.azure-api.net"

# Link DNS zone to the VNet
az network private-dns zone vnet-link create \
  --resource-group rg-internet-of-agents \
  --zone-name "privatelink.azure-api.net" \
  --name apim-dns-link \
  --virtual-network vnet-agents \
  --registration-enabled false

# Create DNS zone group for automatic record management
az network private-endpoint dns-zone-group create \
  --resource-group rg-internet-of-agents \
  --endpoint-name pe-apim-powerplatform \
  --name apim-dns-group \
  --private-dns-zone "privatelink.azure-api.net" \
  --zone-name apim
```

### Step 2.3 — Verify Private Endpoint Connectivity

```bash
# Verify the private endpoint has an IP assigned
az network private-endpoint show \
  --resource-group rg-internet-of-agents \
  --name pe-apim-powerplatform \
  --query "customDnsConfigs[].{FQDN:fqdn, IP:ipAddresses[0]}" -o table

# Expected output:
# FQDN                                          IP
# -------------------------------------------- -----------
# apim-agents-gateway.azure-api.net             10.0.4.x
```

### Step 2.4 — (Optional) Disable Public Access on APIM

Once all consumers use private endpoints, lock down public access:

```bash
# Disable public network access (only do this if all consumers are private)
az apim update \
  --name apim-agents-gateway \
  --resource-group rg-internet-of-agents \
  --public-network-access false
```

> **Warning**: Only disable public access after confirming all agents (Foundry, App Service, Copilot Studio) connect via private endpoints.

---

## Part 3: Create the Copilot Studio Agent

### Step 3.1 — Create a New Agent in Copilot Studio

1. Navigate to [https://copilotstudio.microsoft.com](https://copilotstudio.microsoft.com)
2. Select your **Managed Environment** (the one with VNet support enabled)
3. Click **Create** → **New agent**
4. Name: `MCP Tools Agent`
5. Description: `Enterprise agent that invokes MCP tools through the private AI Gateway`

### Step 3.2 — Configure Authentication

Set up authentication so the agent can acquire tokens for APIM:

1. In your agent → **Settings** → **Security** → **Authentication**
2. Select **Authenticate with Microsoft**
3. Configure the service principal:

| Setting | Value |
|---------|-------|
| Client ID | `<your-app-registration-client-id>` |
| Client Secret | Stored in Key Vault (accessible via VNet) |
| Token Endpoint | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token` |
| Scopes | `api://apim-agents-gateway/.default` |

### Step 3.3 — Register the App in Entra ID

```bash
# Create app registration for Copilot Studio → APIM authentication
az ad app create \
  --display-name "Copilot Studio MCP Client" \
  --sign-in-audience AzureADMyOrg

# Note the Application (client) ID from output
APP_ID=$(az ad app list --display-name "Copilot Studio MCP Client" --query "[0].appId" -o tsv)

# Create a client secret
az ad app credential reset \
  --id $APP_ID \
  --display-name "copilot-studio-secret" \
  --query password -o tsv

# Store the secret in Key Vault (accessible via private endpoint)
az keyvault secret set \
  --vault-name kv-agents-platform \
  --name "copilot-studio-client-secret" \
  --value "<secret-from-above>"
```

---

## Part 4: Configure HTTP Request Nodes for MCP Tools

### Step 4.1 — Create a Topic for MCP Tool Invocation

In Copilot Studio, create a topic that calls the APIM MCP server:

1. Go to **Topics** → **+ New topic** → **From blank**
2. Name: `Invoke MCP Tool`
3. Add trigger phrases:
   - "Use a tool"
   - "Call MCP"
   - "Execute tool"

### Step 4.2 — Add HTTP Request Node

Add an **HTTP Request** action node to call APIM's MCP endpoint:

1. Add node → **Call an action** → **HTTP Request**
2. Configure:

| Property | Value |
|----------|-------|
| **URL** | `https://apim-agents-gateway.azure-api.net/mcp/tools/list` |
| **Method** | POST |
| **Headers** | `Content-Type: application/json` |
| **Headers** | `Ocp-Apim-Subscription-Key: <subscription-key>` |
| **Headers** | `Authorization: Bearer {System.Activity.Authentication.Token}` |

> **Key Point**: Because VNet support is enabled, this HTTPS call routes through the Power Platform delegated subnet → private endpoint → APIM. No public internet involved.

### Step 4.3 — Create Tool Discovery Topic

Build a topic that lists available MCP tools:

```yaml
# Topic: List Available Tools
# Trigger: "What tools are available?", "Show me tools", "List MCP tools"

HTTP Request:
  URL: https://apim-agents-gateway.azure-api.net/mcp/tools/list
  Method: POST
  Body: |
    {
      "jsonrpc": "2.0",
      "method": "tools/list",
      "id": 1
    }
  Headers:
    Content-Type: application/json
    Authorization: Bearer {Token}
    Ocp-Apim-Subscription-Key: {SubscriptionKey}
```

### Step 4.4 — Create Tool Execution Topic

Build a topic that executes an MCP tool:

```yaml
# Topic: Execute MCP Tool
# Trigger: "Run tool", "Execute {ToolName}"

# Step 1: Ask for tool name (if not provided)
Question: Which tool would you like to run?
  Variable: Topic.ToolName

# Step 2: Ask for parameters
Question: What parameters should I pass?
  Variable: Topic.ToolParams

# Step 3: HTTP Request to execute
HTTP Request:
  URL: https://apim-agents-gateway.azure-api.net/mcp/tools/call
  Method: POST
  Body: |
    {
      "jsonrpc": "2.0",
      "method": "tools/call",
      "params": {
        "name": "{Topic.ToolName}",
        "arguments": {Topic.ToolParams}
      },
      "id": 2
    }
  Headers:
    Content-Type: application/json
    Authorization: Bearer {Token}
    Ocp-Apim-Subscription-Key: {SubscriptionKey}
```

### Step 4.5 — Use Power Automate Cloud Flow (Alternative)

For more complex orchestration, use a Power Automate cloud flow as an intermediary:

1. Create a new **Instant cloud flow** triggered from Copilot Studio
2. Add an **HTTP** action (Premium connector):

```json
{
  "method": "POST",
  "uri": "https://apim-agents-gateway.azure-api.net/mcp/tools/call",
  "headers": {
    "Content-Type": "application/json",
    "Ocp-Apim-Subscription-Key": "@{parameters('ApimSubscriptionKey')}",
    "Authorization": "Bearer @{body('Get_Token')?['access_token']}"
  },
  "body": {
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "@{triggerBody()?['toolName']}",
      "arguments": "@{triggerBody()?['toolArguments']}"
    },
    "id": 1
  }
}
```

> **Note**: The HTTP connector in Power Automate also routes through the VNet when VNet-supported connectors are enabled.

---

## Part 5: Validate Private Connectivity

### Step 5.1 — Verify Network Path

Confirm that traffic flows through the private endpoint:

1. In **Azure Portal** → **APIM** → **Monitoring** → **Metrics**
2. Filter by `Client IP Address`
3. Verify calls from Copilot Studio show a **private IP** (10.0.7.x range), not a public IP

### Step 5.2 — Test from Copilot Studio

1. Open your agent in Copilot Studio
2. Use the **Test** pane
3. Type: "What tools are available?"
4. Verify the response lists your MCP tools from APIM

### Step 5.3 — Check APIM Diagnostics

```kusto
// In Application Insights — Verify private connectivity
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| where ApiId == "mcp-server-api"
| where CallerIpAddress startswith "10.0.7."
| project TimeGenerated, CallerIpAddress, ResponseCode, Method, Url
| order by TimeGenerated desc
| take 20
```

### Step 5.4 — Verify No Public Internet Exposure

```bash
# Attempt to call APIM from outside the VNet (should fail if public access is disabled)
curl -s -o /dev/null -w "%{http_code}" \
  https://apim-agents-gateway.azure-api.net/mcp/tools/list

# Expected: 403 or connection timeout (if public access disabled)
```

---

## Part 6: Configure Telemetry to Private Application Insights

### Step 6.1 — Create Private Link Scope for Application Insights

```bash
# Create Azure Monitor Private Link Scope (AMPLS)
az monitor private-link-scope create \
  --resource-group rg-internet-of-agents \
  --name ampls-agents-platform \
  --query-access Open \
  --ingestion-access PrivateOnly

# Connect Application Insights to the Private Link Scope
az monitor private-link-scope scoped-resource create \
  --resource-group rg-internet-of-agents \
  --scope-name ampls-agents-platform \
  --name appi-connection \
  --linked-resource $(az monitor app-insights component show \
    --app appi-agents-platform \
    --resource-group rg-internet-of-agents \
    --query id -o tsv)

# Create private endpoint for AMPLS
az network private-endpoint create \
  --resource-group rg-internet-of-agents \
  --name pe-ampls-powerplatform \
  --vnet-name vnet-agents \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $(az monitor private-link-scope show \
    --resource-group rg-internet-of-agents \
    --name ampls-agents-platform \
    --query id -o tsv) \
  --group-id azuremonitor \
  --connection-name ampls-connection
```

### Step 6.2 — Configure Copilot Studio Telemetry

In your Copilot Studio agent settings:

1. **Settings** → **Advanced** → **Application Insights**
2. Enter the **Connection String** for your private Application Insights instance
3. Telemetry will flow through the VNet to the private AMPLS endpoint

---

## Security Considerations

### Network Security Groups (NSGs)

Apply NSGs to the Power Platform delegated subnet:

```bash
# Create NSG for Power Platform subnet
az network nsg create \
  --resource-group rg-internet-of-agents \
  --name nsg-powerplatform

# Allow outbound to APIM private endpoint subnet only
az network nsg rule create \
  --resource-group rg-internet-of-agents \
  --nsg-name nsg-powerplatform \
  --name AllowApimPrivateEndpoint \
  --priority 100 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes 10.0.4.0/24 \
  --destination-port-ranges 443

# Deny all other outbound internet traffic
az network nsg rule create \
  --resource-group rg-internet-of-agents \
  --nsg-name nsg-powerplatform \
  --name DenyInternet \
  --priority 4096 \
  --direction Outbound \
  --access Deny \
  --protocol "*" \
  --destination-address-prefixes Internet \
  --destination-port-ranges "*"

# Associate NSG with subnet
az network vnet subnet update \
  --resource-group rg-internet-of-agents \
  --vnet-name vnet-agents \
  --name snet-powerplatform \
  --network-security-group nsg-powerplatform
```

### APIM Policy for Copilot Studio Validation

Add an inbound policy to validate Copilot Studio caller identity:

```xml
<inbound>
    <base />
    <!-- Validate JWT from Copilot Studio service principal -->
    <validate-jwt header-name="Authorization" require-scheme="Bearer">
        <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
        <required-claims>
            <claim name="appid" match="all">
                <value>{copilot-studio-app-client-id}</value>
            </claim>
        </required-claims>
    </validate-jwt>
    <!-- Rate limit Copilot Studio calls -->
    <rate-limit-by-key calls="100" renewal-period="60"
        counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization",""))" />
</inbound>
```

---

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| HTTP Request returns timeout | VNet not properly linked | Verify enterprise policy is linked to environment |
| 403 from APIM | JWT validation failed | Check app registration and scopes |
| DNS resolution fails | Private DNS zone not linked | Verify DNS zone is linked to VNet |
| "VNet not supported" error | Environment not Managed | Convert to Managed Environment in Admin Center |
| Intermittent connectivity | Subnet exhaustion | Ensure /24 subnet has available IPs |

---

## Summary

| Component | Status |
|-----------|--------|
| Power Platform Managed Environment | ✅ |
| VNet support enabled (enterprise policy) | ✅ |
| Delegated subnet (snet-powerplatform) | ✅ |
| Private endpoint for APIM | ✅ |
| Private DNS resolution | ✅ |
| Copilot Studio agent created | ✅ |
| HTTP Request nodes calling MCP via private endpoint | ✅ |
| JWT authentication configured | ✅ |
| Private telemetry (AMPLS) | ✅ |
| End-to-end private connectivity validated | ✅ |

---

## References

- [VNet Support for Power Platform — Overview](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-network-isolation-vnet)
- [Power Platform VNet Support Setup](https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview)
- [CopilotStudioSamples — VNet Infrastructure Templates](https://github.com/microsoft/CopilotStudioSamples/tree/main/infrastructure/vnet-support)
- [APIM Private Endpoints](https://learn.microsoft.com/en-us/azure/api-management/private-endpoint)
- [Azure Monitor Private Link Scope](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/private-link-security)
- [Copilot Studio HTTP Request Node](https://learn.microsoft.com/en-us/microsoft-copilot-studio/authoring-http-node)

---

## Next Steps

Proceed to [Chapter 15 — Set Up Observability, Evaluation, and Guardrails](./15-observability.md)
