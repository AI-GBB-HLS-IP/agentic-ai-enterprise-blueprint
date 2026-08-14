# Chapter 01 — Create Microsoft Foundry with BYO Networking

## Objective

Create a **Microsoft Foundry** instance with **Bring-Your-Own VNet (BYO networking)** to ensure all agent traffic stays within your enterprise network boundary. This chapter covers the networking deep-dive, subnet sizing, and configuration.

---

## Architecture Context: Why Foundry Comes First

### Where This Fits

Microsoft Foundry is the **AI application platform** where agents are built, trained, evaluated, and deployed. By establishing Foundry as the first piece of infrastructure, you create the foundation that all subsequent chapters build upon:

```
┌─────────────────────────────────────────────┐
│         Microsoft Foundry (This Chapter)     │
│                                             │
│  ┌─────────┐ ┌─────────┐ ┌──────────────┐  │
│  │ Prompt  │ │ Hosted  │ │  Knowledge   │  │
│  │ Agents  │ │ Agents  │ │  Indexes     │  │
│  └─────────┘ └─────────┘ └──────────────┘  │
│  ┌─────────┐ ┌─────────┐ ┌──────────────┐  │
│  │ Model   │ │ Evalua- │ │  Tracing &   │  │
│  │ Deploy  │ │ tions   │ │  Monitoring  │  │
│  └─────────┘ └─────────┘ └──────────────┘  │
│                    │                         │
│         ┌──────────▼──────────┐             │
│         │  Delegated Subnet   │             │
│         │  (Your VNet)        │             │
│         └─────────────────────┘             │
└─────────────────────────────────────────────┘
```

### What You Will Achieve

By the end of this chapter, you will have:
- A fully private Foundry instance with no public internet exposure
- A delegated subnet properly sized for agent workloads
- Private endpoints for all dependent services (Storage, SQL, Key Vault)
- DNS resolution configured for private connectivity
- The networking foundation that enables Chapters 06-08 (knowledge bases, prompt agents, hosted agents)

### Benefits of This Approach

| Benefit | Description |
|---------|-------------|
| **Zero Public Exposure** | All agent traffic stays within your VNet — no data traverses the public internet |
| **Regulatory Compliance** | Meets requirements for HIPAA, SOC 2, PCI-DSS, and industry-specific regulations |
| **Network Segmentation** | Foundry workloads are isolated in their own subnet with NSG controls |
| **Private Data Access** | Agents can reach on-premises data sources through ExpressRoute/VPN without exposure |
| **Foundation for Everything** | Every subsequent agent deployment (prompt agents, hosted agents, knowledge indexes) inherits this security posture |

---

## Prerequisites

- Azure subscription with Owner access
- Azure CLI installed (`az --version` ≥ 2.60)
- The completed network foundation resource group: `rg-agent-factory-poc`
- A virtual network planned for the platform

---

## Part 1: Understanding Foundry Networking

### Network Architecture

When you run Foundry Agent Service with BYO VNet, two zones are involved:

1. **Microsoft-managed Foundry platform network** — Contains the Foundry endpoint, Micro VM host layer, Tools Service, and Data Proxy host layer
2. **Your customer VNet** — Contains the delegated subnet (for Micro VMs and Data Proxy) and private endpoint subnet (for storage, SQL Database, Key Vault)

### Two Agent Types, Two Traffic Flows

| Agent Type | Compute | Traffic Path |
|-----------|---------|-------------|
| **Hosted Agent** | Your container image on Azure Container Apps (Micro VM) | Client → Foundry endpoint → Micro VM → Tools Service → Data Proxy → customer resources (via private endpoints) |
| **Prompt Agent** | Fully managed by Microsoft | Client → Foundry endpoint → Tools Service → Data Proxy → customer resources (via private endpoints) |

### Key Concepts

| Term | Description |
|------|-------------|
| **Single-tenant data proxy** | Platform-managed networking component dedicated to your Foundry project. Handles all outbound connectivity. Each project gets its own isolated instance. |
| **Delegated subnet** | Your VNet subnet delegated to Foundry Agent Service. All agent infrastructure deploys into this subnet. |
| **Micro VM** | Lightweight VM that runs a Hosted Agent. Has a dedicated NIC in the delegated subnet. |
| **Tool server** | Backend service registered at project level. All tool calls route through the data proxy. |

### Subnet Sizing

| Subnet | Total IPs | Usable IPs | Approximate Concurrent Sessions |
|--------|-----------|------------|--------------------------------|
| /27 | 32 | ~27 | ~17 |
| /26 | 64 | ~59 | ~50 (maximum supported) |
| **/24 (recommended)** | 256 | ~251 | 50+ with headroom for upgrades |

> **Critical**: Target maximum **80% subnet utilization** to absorb spikes from platform upgrades and scaling events. A /24 subnet is recommended for production.

### IP Consumption

- **Hosted agent revisions** consume IPs from the delegated subnet
- **Prompt agent revisions** do NOT consume IPs
- IPs are reserved at approximately **1 IP per 10 pods** ratio
- Platform upgrades run old and new infrastructure in parallel, temporarily increasing IP consumption

---

## Part 2: Create the Foundry Instance

### Step 1: Prepare the Delegated Subnet

The subnet from the Network Foundation (`snet-foundry`, 10.0.2.0/24) is already created. Verify it:

```bash
# Verify the Foundry subnet exists
az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-foundry \
  --query '{addressPrefix: addressPrefix, delegations: delegations[].serviceName}' \
  -o json
```

If the delegation needs to be updated for Foundry:
```bash
az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name snet-foundry \
  --delegations Microsoft.App/environments
```

### Step 2: Create the Foundry Account

```bash
FOUNDRY_NAME="foundry-agents-platform"

# Create the Foundry account (AI Services resource)
az cognitiveservices account create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --kind AIServices \
  --sku S0 \
  --location $LOCATION \
  --custom-domain $FOUNDRY_NAME \
  --properties '{
    "networkAcls": {
      "defaultAction": "Deny",
      "virtualNetworkRules": [],
      "ipRules": []
    },
    "publicNetworkAccess": "Disabled"
  }'
```

### Step 3: Create Private Endpoints

```bash
FOUNDRY_ID=$(az cognitiveservices account show \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --query id -o tsv)

# Create private endpoint for Foundry
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --name "pe-foundry" \
  --vnet-name $VNET_NAME \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $FOUNDRY_ID \
  --group-id account \
  --connection-name "foundry-connection"

# Create private DNS zone
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "privatelink.cognitiveservices.azure.com"

az network private-dns zone vnet-link create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "privatelink.cognitiveservices.azure.com" \
  --name "link-foundry" \
  --virtual-network $VNET_NAME \
  --registration-enabled false

# Create DNS record
az network private-endpoint dns-zone-group create \
  --resource-group $RESOURCE_GROUP \
  --endpoint-name "pe-foundry" \
  --name "foundry-dns-group" \
  --private-dns-zone "privatelink.cognitiveservices.azure.com" \
  --zone-name "cognitiveservices"
```

### Step 4: Create Supporting Resources with Private Endpoints

Foundry requires storage, Key Vault, and optionally SQL Database:

```bash
# Create Storage Account
STORAGE_NAME="stagentsplatform"
az storage account create \
  --resource-group $RESOURCE_GROUP \
  --name $STORAGE_NAME \
  --location $LOCATION \
  --sku Standard_LRS \
  --public-network-access Disabled

# Create private endpoint for storage
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --name "pe-storage" \
  --vnet-name $VNET_NAME \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $(az storage account show -g $RESOURCE_GROUP -n $STORAGE_NAME --query id -o tsv) \
  --group-id blob \
  --connection-name "storage-blob-connection"

# Create Key Vault
KV_NAME="kv-agents-platform"
az keyvault create \
  --resource-group $RESOURCE_GROUP \
  --name $KV_NAME \
  --location $LOCATION \
  --public-network-access Disabled \
  --enable-rbac-authorization

# Create private endpoint for Key Vault
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --name "pe-keyvault" \
  --vnet-name $VNET_NAME \
  --subnet snet-privateendpoints \
  --private-connection-resource-id $(az keyvault show -g $RESOURCE_GROUP -n $KV_NAME --query id -o tsv) \
  --group-id vault \
  --connection-name "keyvault-connection"
```

### Step 5: Create Private DNS Zones for All Services

```bash
# Storage blob DNS
az network private-dns zone create -g $RESOURCE_GROUP -n "privatelink.blob.core.windows.net"
az network private-dns zone vnet-link create -g $RESOURCE_GROUP \
  --zone-name "privatelink.blob.core.windows.net" --name "link-blob" \
  --virtual-network $VNET_NAME --registration-enabled false

# Key Vault DNS
az network private-dns zone create -g $RESOURCE_GROUP -n "privatelink.vaultcore.azure.net"
az network private-dns zone vnet-link create -g $RESOURCE_GROUP \
  --zone-name "privatelink.vaultcore.azure.net" --name "link-kv" \
  --virtual-network $VNET_NAME --registration-enabled false
```

### Step 6: Create the Foundry Project

```bash
# Create a Foundry project
az cognitiveservices account deployment create \
  --resource-group $RESOURCE_GROUP \
  --name $FOUNDRY_NAME \
  --deployment-name "gpt-4o" \
  --model-name "gpt-4o" \
  --model-version "2024-11-20" \
  --model-format OpenAI \
  --sku-name GlobalStandard \
  --sku-capacity 30
```

---

## Part 3: Configure BYO Network in Foundry Portal

Some network configurations are best done in the Foundry portal:

1. Navigate to [Microsoft Foundry Portal](https://ai.azure.com)
2. Select your Foundry resource
3. Go to **Settings** → **Networking**
4. Select **Bring your own virtual network**
5. Configure:
   - **Virtual Network**: `vnet-agent-factory-poc`
   - **Delegated Subnet**: `snet-foundry` (10.0.2.0/24)
   - **Private Endpoint Subnet**: `snet-privateendpoints` (10.0.4.0/24)

> **Important**: BYO VNet configuration must be set before creating agents. It cannot be changed after agents are deployed.

---

## Part 4: Monitoring IP Usage

The Azure portal doesn't expose IP utilization for delegated subnets directly. Monitor these signals:

| Signal | Indicates |
|--------|-----------|
| HTTP 5xx from data proxy | IP exhaustion — data proxy can't scale |
| 4xx on hosted agent session creation | IP exhaustion — can't allocate Micro VM |
| New project provisioning failures | Subnet capacity exceeded |

**Recommendation**: Deploy a new Foundry instance with a fresh subnet when these signals appear.

---

## Part 5: VNet Peering Considerations

If you need to peer with other VNets:

- All peered VNets must use **unique, non-overlapping IP ranges**
- Only **RFC 1918 private IPv4 ranges** are supported:
  - `10.0.0.0/8`
  - `172.16.0.0/12`
  - `192.168.0.0/16`
- CGNAT ranges (`100.64.0.0/10`) are **not supported**
- If IP overlap is unavoidable, use **Managed virtual network** instead of BYO VNet

---

## Summary

| Component | Status |
|-----------|--------|
| Foundry account created with network restrictions | ✅ |
| Private endpoints for Foundry, Storage, Key Vault | ✅ |
| Private DNS zones configured | ✅ |
| Delegated subnet (/24) for Foundry agents | ✅ |
| Model deployed (gpt-4o) | ✅ |
| BYO VNet configured in Foundry portal | ✅ |

---

## References

- [Foundry Agent Service Networking Deep-Dive](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive)
- [Securing Foundry with BYO VNet](https://nirmalt.com/posts/securingmicrosoftfoundrywithbyovnet/)
- [Quickstart: Create Foundry Resources](https://learn.microsoft.com/en-us/azure/foundry/tutorials/quickstart-create-foundry-resources)
- [Set Up Private Networking for Foundry](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks)

---

## Next Steps

Proceed to [Chapter 02 — Build the AI Gateway](./02-ai-gateway.md)
