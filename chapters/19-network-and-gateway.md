# Chapter 19 — Network Foundation & APIM AI Gateway

## Objective

Build the **network isolation layer** and deploy the **APIM AI Gateway** — the single chokepoint through which all AI traffic must flow. No developer, agent, or tool can reach models or backends without passing through this gateway.

By the end of this lab, you will have:

- A VNet with purpose-built subnets for every workload
- Private endpoints for all AI services
- APIM deployed with VNet injection
- Gateway policies enforcing auth, rate limiting, content filtering, and logging
- All direct model access blocked

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          VNet: vnet-agent-factory                    │
│                          Address Space: 10.0.0.0/16                 │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ snet-apim        │  │ snet-foundry     │  │ snet-compute     │  │
│  │ 10.0.1.0/24      │  │ 10.0.2.0/24      │  │ 10.0.3.0/24      │  │
│  │                  │  │                  │  │                  │  │
│  │ APIM Gateway     │  │ Foundry Projects │  │ Agent Hosting    │  │
│  │ (VNet-injected)  │  │ (Delegated)      │  │ (ACA / App Svc)  │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ snet-pe          │  │ snet-devops      │  │ snet-mgmt        │  │
│  │ 10.0.4.0/24      │  │ 10.0.5.0/24      │  │ 10.0.6.0/24      │  │
│  │                  │  │                  │  │                  │  │
│  │ Private          │  │ CI/CD Agents     │  │ Jump Box /       │  │
│  │ Endpoints        │  │ (Self-hosted)    │  │ Bastion          │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

**Traffic flow (enforced)**:
```
Developer Agent → APIM (snet-apim) → Private Endpoint (snet-pe) → Foundry Model
                                    ↓
                          Policies enforced:
                          • JWT validation
                          • Rate limiting
                          • Content filtering
                          • Token budget
                          • Logging to App Insights
```

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Lab 01 completed | Platform Engineering RBAC assigned |
| Lab 02 completed | Azure Policy initiative active |
| Logged in as | Platform Engineering member |

---

## Part 1: Create the Virtual Network

### Step 1.1 — Create VNet and Subnets

```bash
# Create VNet
az network vnet create \
  --resource-group rg-agent-factory-platform \
  --name vnet-agent-factory \
  --address-prefix 10.0.0.0/16 \
  --location eastus2

# APIM subnet (VNet injection)
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-apim \
  --address-prefixes 10.0.1.0/24

# Foundry subnet (delegated)
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-foundry \
  --address-prefixes 10.0.2.0/24

# Compute subnet (ACA / App Service)
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-compute \
  --address-prefixes 10.0.3.0/24

# Private Endpoints subnet
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-pe \
  --address-prefixes 10.0.4.0/24

# CI/CD Agents subnet
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-devops \
  --address-prefixes 10.0.5.0/24

# Management subnet (Bastion)
az network vnet subnet create \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name AzureBastionSubnet \
  --address-prefixes 10.0.6.0/24
```

### Step 1.2 — Create Network Security Groups

```bash
# NSG for APIM subnet
az network nsg create \
  --resource-group rg-agent-factory-platform \
  --name nsg-apim

# Allow inbound HTTPS to APIM
az network nsg rule create \
  --resource-group rg-agent-factory-platform \
  --nsg-name nsg-apim \
  --name AllowHTTPS \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes VirtualNetwork \
  --destination-port-ranges 443

# Allow APIM management endpoint
az network nsg rule create \
  --resource-group rg-agent-factory-platform \
  --nsg-name nsg-apim \
  --name AllowAPIMManagement \
  --priority 110 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes ApiManagement \
  --destination-port-ranges 3443

# Associate NSG with APIM subnet
az network vnet subnet update \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-apim \
  --network-security-group nsg-apim

# NSG for compute subnet — deny direct internet egress to AI services
az network nsg create \
  --resource-group rg-agent-factory-platform \
  --name nsg-compute

# Allow outbound to APIM only (not to AI services directly)
az network nsg rule create \
  --resource-group rg-agent-factory-platform \
  --nsg-name nsg-compute \
  --name AllowToApim \
  --priority 100 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes 10.0.1.0/24 \
  --destination-port-ranges 443

# Deny direct outbound to CognitiveServices service tag
az network nsg rule create \
  --resource-group rg-agent-factory-platform \
  --nsg-name nsg-compute \
  --name DenyDirectAI \
  --priority 200 \
  --direction Outbound \
  --access Deny \
  --protocol Tcp \
  --destination-address-prefixes CognitiveServicesManagement \
  --destination-port-ranges 443

az network vnet subnet update \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-compute \
  --network-security-group nsg-compute
```

> **Key Point**: The NSG on `snet-compute` blocks direct traffic to AI services. Developers' agents can only reach models through APIM in `snet-apim`.

---

## Part 2: Deploy APIM AI Gateway

### Step 2.1 — Create APIM Instance

```bash
az apim create \
  --name apim-agent-factory \
  --resource-group rg-agent-factory-platform \
  --publisher-name "Platform Engineering" \
  --publisher-email platform-eng@contoso.com \
  --sku-name Premiumv2 \
  --sku-capacity 1 \
  --location eastus2 \
  --virtual-network Internal \
  --virtual-network-type Internal
```

> **Note**: `Internal` VNet mode means APIM is only accessible from within the VNet. No public internet access.

### Step 2.2 — Configure APIM Subnet

```bash
APIM_SUBNET_ID=$(az network vnet subnet show \
  --resource-group rg-agent-factory-platform \
  --vnet-name vnet-agent-factory \
  --name snet-apim \
  --query id -o tsv)

az apim update \
  --name apim-agent-factory \
  --resource-group rg-agent-factory-platform \
  --set virtualNetworkConfiguration.subnetResourceId=$APIM_SUBNET_ID
```

### Step 2.3 — Enable System-Assigned Managed Identity

```bash
az apim update \
  --name apim-agent-factory \
  --resource-group rg-agent-factory-platform \
  --enable-managed-identity true
```

---

## Part 3: Create Private Endpoints for AI Services

### Step 3.1 — Private Endpoint for Foundry / Azure AI Services

```bash
# Create private endpoint for the AI Services account
az network private-endpoint create \
  --resource-group rg-agent-factory-platform \
  --name pe-foundry-ai \
  --vnet-name vnet-agent-factory \
  --subnet snet-pe \
  --private-connection-resource-id $(az cognitiveservices account show \
    --name foundry-agent-factory \
    --resource-group rg-agent-factory-coe \
    --query id -o tsv) \
  --group-id account \
  --connection-name foundry-ai-connection
```

### Step 3.2 — Private DNS Zones

```bash
# DNS zone for Cognitive Services
az network private-dns zone create \
  --resource-group rg-agent-factory-platform \
  --name "privatelink.cognitiveservices.azure.com"

az network private-dns zone vnet-link create \
  --resource-group rg-agent-factory-platform \
  --zone-name "privatelink.cognitiveservices.azure.com" \
  --name foundry-dns-link \
  --virtual-network vnet-agent-factory \
  --registration-enabled false

az network private-endpoint dns-zone-group create \
  --resource-group rg-agent-factory-platform \
  --endpoint-name pe-foundry-ai \
  --name foundry-dns-group \
  --private-dns-zone "privatelink.cognitiveservices.azure.com" \
  --zone-name cognitiveservices

# DNS zone for OpenAI
az network private-dns zone create \
  --resource-group rg-agent-factory-platform \
  --name "privatelink.openai.azure.com"

az network private-dns zone vnet-link create \
  --resource-group rg-agent-factory-platform \
  --zone-name "privatelink.openai.azure.com" \
  --name openai-dns-link \
  --virtual-network vnet-agent-factory \
  --registration-enabled false
```

### Step 3.3 — Private Endpoint for Key Vault

```bash
az network private-endpoint create \
  --resource-group rg-agent-factory-platform \
  --name pe-keyvault \
  --vnet-name vnet-agent-factory \
  --subnet snet-pe \
  --private-connection-resource-id $(az keyvault show \
    --name kv-agent-factory \
    --resource-group rg-agent-factory-platform \
    --query id -o tsv) \
  --group-id vault \
  --connection-name keyvault-connection

az network private-dns zone create \
  --resource-group rg-agent-factory-platform \
  --name "privatelink.vaultcore.azure.net"

az network private-dns zone vnet-link create \
  --resource-group rg-agent-factory-platform \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name kv-dns-link \
  --virtual-network vnet-agent-factory \
  --registration-enabled false

az network private-endpoint dns-zone-group create \
  --resource-group rg-agent-factory-platform \
  --endpoint-name pe-keyvault \
  --name kv-dns-group \
  --private-dns-zone "privatelink.vaultcore.azure.net" \
  --zone-name keyvault
```

---

## Part 4: Configure APIM as AI Gateway

### Step 4.1 — Import Foundry Model API as Backend

```bash
# Create a backend pointing to the Foundry model endpoint via private endpoint
az apim api create \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "foundry-models" \
  --display-name "Foundry Models API" \
  --path "/models" \
  --protocols https \
  --service-url "https://foundry-agent-factory.cognitiveservices.azure.com/openai"
```

### Step 4.2 — Apply Mandatory Gateway Policies

Create the **global policy** that applies to every API call:

```xml
<!-- All-APIs Policy — Applied globally -->
<policies>
    <inbound>
        <base />

        <!-- 1. Authentication: Require valid JWT -->
        <validate-jwt header-name="Authorization" require-scheme="Bearer"
                      failed-validation-httpcode="401"
                      failed-validation-error-message="Unauthorized. Valid JWT required.">
            <openid-config url="https://login.microsoftonline.com/{tenant-id}/v2.0/.well-known/openid-configuration" />
            <required-claims>
                <claim name="aud">
                    <value>api://apim-agent-factory</value>
                </claim>
            </required-claims>
        </validate-jwt>

        <!-- 2. Rate Limiting: Per-agent identity -->
        <rate-limit-by-key calls="100" renewal-period="60"
            counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject ?? "anonymous")"
            increment-condition="@(context.Response.StatusCode >= 200 && context.Response.StatusCode < 300)" />

        <!-- 3. Token Budget: Max tokens per request -->
        <set-header name="x-max-tokens" exists-action="skip">
            <value>4096</value>
        </set-header>

        <!-- 4. Emit metrics for observability -->
        <emit-metric name="ai-gateway-request"
                     value="1"
                     namespace="agent-factory">
            <dimension name="agent-id"
                       value="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject ?? "unknown")" />
            <dimension name="api-id" value="@(context.Api.Id)" />
            <dimension name="operation-id" value="@(context.Operation.Id)" />
        </emit-metric>

        <!-- 5. Authenticate to backend using APIM managed identity -->
        <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
    </inbound>

    <backend>
        <base />
    </backend>

    <outbound>
        <base />

        <!-- 6. Remove backend headers that leak internal info -->
        <set-header name="x-ms-region" exists-action="delete" />
        <set-header name="x-envoy-upstream-service-time" exists-action="delete" />

        <!-- 7. Log token usage -->
        <emit-metric name="ai-gateway-tokens"
                     value="@{
                        var body = context.Response.Body.As<JObject>(preserveContent: true);
                        return body?["usage"]?["total_tokens"]?.ToString() ?? "0";
                     }"
                     namespace="agent-factory">
            <dimension name="agent-id"
                       value="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject ?? "unknown")" />
        </emit-metric>
    </outbound>

    <on-error>
        <base />
        <emit-metric name="ai-gateway-error" value="1" namespace="agent-factory">
            <dimension name="error-reason" value="@(context.LastError.Reason)" />
            <dimension name="status-code" value="@(context.Response.StatusCode.ToString())" />
        </emit-metric>
    </on-error>
</policies>
```

### Step 4.3 — Apply the Policy via CLI

```bash
az apim api policy create \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "foundry-models" \
  --xml-content @/tmp/apim-global-policy.xml
```

### Step 4.4 — Create MCP Server API in APIM

```bash
# Import MCP server as an API
az apim api create \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "mcp-server" \
  --display-name "MCP Server — Governed Tools" \
  --path "/mcp" \
  --protocols https \
  --service-url "https://foundry-agent-factory.cognitiveservices.azure.com/mcp"
```

### Step 4.5 — MCP Tool Allowlist Policy

Only allow calls to approved MCP tools:

```xml
<policies>
    <inbound>
        <base />
        <!-- Tool Allowlist: Block unapproved tool calls -->
        <choose>
            <when condition="@{
                var body = context.Request.Body.As<JObject>(preserveContent: true);
                var method = body?["method"]?.ToString();
                if (method == "tools/call") {
                    var toolName = body?["params"]?["name"]?.ToString();
                    var allowedTools = new[] {
                        "search_documents",
                        "get_customer_data",
                        "calculate_pricing",
                        "submit_order"
                    };
                    return !allowedTools.Contains(toolName);
                }
                return false;
            }">
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>{"error": "Tool not in approved allowlist"}</set-body>
                </return-response>
            </when>
        </choose>
    </inbound>
</policies>
```

---

## Part 5: Disable Direct Access to AI Services

### Step 5.1 — Disable Public Network Access

```bash
# Disable public access on the Foundry AI Services account
az cognitiveservices account update \
  --name foundry-agent-factory \
  --resource-group rg-agent-factory-coe \
  --public-network-access Disabled

# Set default network ACL to Deny
az cognitiveservices account network-rule update \
  --name foundry-agent-factory \
  --resource-group rg-agent-factory-coe \
  --default-action Deny
```

### Step 5.2 — Verify APIM Can Still Reach Backend

```bash
# Test from APIM (should succeed via private endpoint + managed identity)
az apim api test \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "foundry-models"

# Test direct access from outside VNet (should fail)
curl -s -o /dev/null -w "%{http_code}" \
  "https://foundry-agent-factory.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01" \
  -H "api-key: test"
# Expected: Connection refused or 403
```

---

## Part 6: Network Verification

### Step 6.1 — Validate Traffic Flow

```bash
# List all private endpoints
az network private-endpoint list \
  --resource-group rg-agent-factory-platform \
  --query "[].{Name:name, Subnet:subnet.id, Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  -o table

# Verify DNS resolution
az network private-dns record-set list \
  --resource-group rg-agent-factory-platform \
  --zone-name "privatelink.cognitiveservices.azure.com" \
  -o table
```

### Step 6.2 — Verify NSG Enforcement

```bash
# Check effective NSG rules on compute subnet
az network nic list-effective-nsg \
  --resource-group rg-agent-factory-platform \
  --network-interface-name <compute-nic-name> \
  --query "value[].effectiveSecurityRules[?direction=='Outbound'].{Rule:name, Access:access, DestAddr:destinationAddressPrefix, DestPort:destinationPortRange}" \
  -o table
```

---

## Summary

| Component | Status |
|-----------|--------|
| VNet with 6 subnets created | ✅ |
| NSGs enforcing traffic rules | ✅ |
| APIM deployed with VNet injection (Internal) | ✅ |
| Private endpoints for AI Services, Key Vault | ✅ |
| Private DNS zones configured | ✅ |
| Global gateway policies (JWT, rate limit, metrics) | ✅ |
| MCP tool allowlist enforced | ✅ |
| Direct model access blocked (public access disabled) | ✅ |
| NSG blocks direct AI service calls from compute | ✅ |

---

## Next Steps

Proceed to [Chapter 20 — Observability & Defender Stack](./20-observability-and-defender.md)
