# Chapter 20 — Observability & Defender Stack

## Objective

Deploy the **mandatory observability infrastructure** that every Foundry project automatically inherits. No agent can operate without telemetry flowing to Azure Monitor, Application Insights, Defender for AI, and the Microsoft Agent 365 registry.

By the end of this lab, you will have:

- A centralized Log Analytics workspace and Application Insights instance
- Diagnostic settings on all AI resources
- APIM gateway metrics flowing to Azure Monitor
- Defender for AI enabled with threat detection
- Microsoft Agent 365 registry sync for unified agent visibility
- Microsoft Purview connected for data governance
- Alert rules for anomaly detection

---

## Why Mandatory Observability

Without observability, you are operating blind:

| Scenario | Without Observability | With Observability |
|----------|----------------------|-------------------|
| Prompt injection attack | Undetected | Alert fires, incident created |
| Token cost spike | Discovered in monthly bill | Real-time alert, auto-throttle |
| Agent quality degradation | Users complain | Evaluation metrics trigger |
| Data exfiltration via tool | Never discovered | Tool call audit trail |
| Model hallucination | Trust erodes | Groundedness score tracked |

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Lab 03 completed | APIM deployed with VNet injection |
| Logged in as | Platform Engineering member |

---

## Part 1: Deploy Log Analytics and Application Insights

### Step 1.1 — Create Log Analytics Workspace

```bash
az monitor log-analytics workspace create \
  --resource-group rg-agent-factory-platform \
  --workspace-name law-agent-factory \
  --location eastus2 \
  --retention-in-days 90 \
  --sku PerGB2018
```

### Step 1.2 — Create Application Insights

```bash
az monitor app-insights component create \
  --app appi-agent-factory \
  --resource-group rg-agent-factory-platform \
  --location eastus2 \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group rg-agent-factory-platform \
    --workspace-name law-agent-factory \
    --query id -o tsv) \
  --kind web \
  --application-type web
```

### Step 1.3 — Store Connection String in Key Vault

Every Foundry project will reference this connection string:

```bash
APPI_CONNECTION=$(az monitor app-insights component show \
  --app appi-agent-factory \
  --resource-group rg-agent-factory-platform \
  --query connectionString -o tsv)

az keyvault secret set \
  --vault-name kv-agent-factory \
  --name "appi-connection-string" \
  --value "$APPI_CONNECTION"
```

---

## Part 2: Configure Diagnostic Settings

### Step 2.1 — APIM Diagnostics

```bash
APIM_ID=$(az apim show \
  --name apim-agent-factory \
  --resource-group rg-agent-factory-platform \
  --query id -o tsv)

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group rg-agent-factory-platform \
  --workspace-name law-agent-factory \
  --query id -o tsv)

az monitor diagnostic-settings create \
  --name "apim-diagnostics" \
  --resource $APIM_ID \
  --workspace $LAW_ID \
  --logs '[
    {"category": "GatewayLogs", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
    {"category": "WebSocketConnectionLogs", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]' \
  --metrics '[
    {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]'
```

### Step 2.2 — AI Services Diagnostics

```bash
AI_SERVICE_ID=$(az cognitiveservices account show \
  --name foundry-agent-factory \
  --resource-group rg-agent-factory-coe \
  --query id -o tsv)

az monitor diagnostic-settings create \
  --name "ai-service-diagnostics" \
  --resource $AI_SERVICE_ID \
  --workspace $LAW_ID \
  --logs '[
    {"category": "Audit", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
    {"category": "RequestResponse", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
    {"category": "Trace", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]' \
  --metrics '[
    {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]'
```

### Step 2.3 — Key Vault Diagnostics

```bash
KV_ID=$(az keyvault show \
  --name kv-agent-factory \
  --resource-group rg-agent-factory-platform \
  --query id -o tsv)

az monitor diagnostic-settings create \
  --name "keyvault-diagnostics" \
  --resource $KV_ID \
  --workspace $LAW_ID \
  --logs '[
    {"category": "AuditEvent", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}},
    {"category": "AzurePolicyEvaluationDetails", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]' \
  --metrics '[
    {"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": true, "days": 90}}
  ]'
```

---

## Part 3: Enable Defender for AI

### Step 3.1 — Enable Defender Plans

```bash
# Enable Defender for AI
az security pricing create \
  --name "AI" \
  --tier "Standard"

# Enable Defender for Key Vault
az security pricing create \
  --name "KeyVaults" \
  --tier "Standard"

# Enable Defender for Resource Manager
az security pricing create \
  --name "Arm" \
  --tier "Standard"
```

### Step 3.2 — Configure Security Contacts

```bash
az security contact create \
  --name "default" \
  --alert-notifications "on" \
  --alerts-admins "on" \
  --email "security-team@contoso.com"
```

### Step 3.3 — Verify Defender Coverage

```bash
az security pricing list \
  --query "[?contains(name, 'AI') || contains(name, 'KeyVault') || contains(name, 'Arm')].{Plan:name, Tier:pricingTier}" \
  -o table

# Expected:
# Plan       Tier
# ---------  --------
# AI         Standard
# KeyVaults  Standard
# Arm        Standard
```

---

## Part 4: Create Alert Rules

### Step 4.1 — High Token Consumption Alert

```bash
az monitor metrics alert create \
  --resource-group rg-agent-factory-platform \
  --name "alert-high-token-usage" \
  --scopes $APIM_ID \
  --description "Alert when total token consumption exceeds threshold" \
  --condition "total ai-gateway-tokens > 100000" \
  --window-size 1h \
  --evaluation-frequency 15m \
  --severity 2 \
  --action-group ag-platform-engineering
```

### Step 4.2 — Gateway Error Rate Alert

```bash
az monitor metrics alert create \
  --resource-group rg-agent-factory-platform \
  --name "alert-gateway-error-rate" \
  --scopes $APIM_ID \
  --description "Alert when APIM error rate exceeds 5%" \
  --condition "avg Requests where ResponseCode >= 500 > 5" \
  --window-size 15m \
  --evaluation-frequency 5m \
  --severity 1 \
  --action-group ag-platform-engineering
```

### Step 4.3 — Unauthorized Access Alert

```kusto
// Create as a Log Analytics alert rule
ApiManagementGatewayLogs
| where TimeGenerated > ago(15m)
| where ResponseCode == 401 or ResponseCode == 403
| summarize FailedAttempts = count() by CallerIpAddress, bin(TimeGenerated, 5m)
| where FailedAttempts > 10
```

```bash
az monitor scheduled-query create \
  --resource-group rg-agent-factory-platform \
  --name "alert-unauthorized-access" \
  --scopes $LAW_ID \
  --condition "count > 0" \
  --condition-query "ApiManagementGatewayLogs | where TimeGenerated > ago(15m) | where ResponseCode == 401 or ResponseCode == 403 | summarize FailedAttempts = count() by CallerIpAddress | where FailedAttempts > 10" \
  --evaluation-frequency 5m \
  --window-size 15m \
  --severity 1 \
  --action-groups ag-platform-engineering \
  --description "High rate of unauthorized access attempts"
```

### Step 4.4 — Anomalous Model Usage Alert

```kusto
// Detect unusual model usage patterns
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h)
| where ApiId == "foundry-models"
| extend AgentId = tostring(parse_json(RequestHeaders)["Authorization"])
| summarize RequestCount = count(), AvgLatency = avg(TotalTime) by AgentId
| join kind=leftouter (
    ApiManagementGatewayLogs
    | where TimeGenerated between(ago(7d) .. ago(1h))
    | extend AgentId = tostring(parse_json(RequestHeaders)["Authorization"])
    | summarize BaselineCount = count() / 168 by AgentId  // hourly average
) on AgentId
| where RequestCount > BaselineCount * 3  // 3x anomaly threshold
```

---

## Part 5: KQL Dashboards for Platform Team

### Step 5.1 — Agent Health Dashboard

```kusto
// Agent Health Overview — Run in Log Analytics
let timeRange = 1h;
ApiManagementGatewayLogs
| where TimeGenerated > ago(timeRange)
| extend AgentId = tostring(parse_json(RequestHeaders)["x-agent-id"])
| summarize
    TotalRequests = count(),
    SuccessRate = round(100.0 * countif(ResponseCode >= 200 and ResponseCode < 300) / count(), 2),
    AvgLatencyMs = round(avg(TotalTime), 0),
    P99LatencyMs = round(percentile(TotalTime, 99), 0),
    ErrorCount = countif(ResponseCode >= 400)
    by AgentId
| order by TotalRequests desc
```

### Step 5.2 — Token Cost Attribution

```kusto
// Token usage by agent and model
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where ApiId == "foundry-models"
| extend AgentId = tostring(parse_json(RequestHeaders)["x-agent-id"])
| extend ResponseBody = parse_json(ResponseBody)
| extend TotalTokens = toint(ResponseBody.usage.total_tokens)
| extend PromptTokens = toint(ResponseBody.usage.prompt_tokens)
| extend CompletionTokens = toint(ResponseBody.usage.completion_tokens)
| summarize
    TotalTokens = sum(TotalTokens),
    PromptTokens = sum(PromptTokens),
    CompletionTokens = sum(CompletionTokens),
    RequestCount = count()
    by AgentId
| extend EstimatedCostUSD = round(TotalTokens * 0.000003, 4)  // Approximate
| order by TotalTokens desc
```

### Step 5.3 — Tool Call Audit Trail

```kusto
// MCP tool call audit
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where ApiId == "mcp-server"
| extend RequestBody = parse_json(RequestBody)
| extend Method = tostring(RequestBody.method)
| extend ToolName = tostring(RequestBody.params.name)
| extend AgentId = tostring(parse_json(RequestHeaders)["x-agent-id"])
| where Method == "tools/call"
| summarize
    CallCount = count(),
    SuccessRate = round(100.0 * countif(ResponseCode == 200) / count(), 2)
    by ToolName, AgentId
| order by CallCount desc
```

### Step 5.4 — Security Events

```kusto
// Security event timeline
union
(ApiManagementGatewayLogs
| where ResponseCode in (401, 403)
| project TimeGenerated, Source = "APIM", Event = strcat("Auth failure: ", ResponseCode), Details = CallerIpAddress),
(AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where ResultType != "Success"
| project TimeGenerated, Source = "KeyVault", Event = OperationName, Details = CallerIpAddress_s),
(SecurityAlert
| where ProviderName == "AI"
| project TimeGenerated, Source = "Defender", Event = AlertType, Details = Description)
| order by TimeGenerated desc
| take 100
```

---

## Part 6: Microsoft Agent 365 — Unified Control Plane

### Step 6.0 — Why Agent 365 Matters for Observability

Microsoft Agent 365 provides the **unified observe/govern/secure experience** that sits above individual Azure monitoring components. While Application Insights gives you traces, and Defender gives you threats, Agent 365 gives the enterprise a **single registry and control plane** for all agents — regardless of where they run.

```
┌─────────────────────────────────────────────────────────────────────┐
│                MICROSOFT AGENT 365 — CONTROL PLANE                   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    AGENT REGISTRY                             │    │
│  │  All agents visible in one place:                            │    │
│  │  • Foundry Prompt Agents    • Azure Functions Agents         │    │
│  │  • Foundry Hosted Agents    • Custom Engine Agents (M365)    │    │
│  │  • Third-Party Agents       • Partner Ecosystem Agents       │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────────┐   │
│  │  OBSERVE     │  │  GOVERN           │  │  SECURE              │   │
│  │             │  │                   │  │                      │   │
│  │  Adoption   │  │  Lifecycle mgmt   │  │  Entra access ctrl   │   │
│  │  Activity   │  │  Access control   │  │  Purview DLP         │   │
│  │  Health     │  │  Compliance       │  │  Defender threats    │   │
│  │  Dashboards │  │  M365 Admin Ctr   │  │  Runtime protection  │   │
│  └─────────────┘  └──────────────────┘  └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

### Step 6.1 — Configure Agent 365 Prerequisites

Microsoft Agent 365 requires Microsoft E5 as a prerequisite. At least one user must be licensed with a qualifying Microsoft Agent 365 license.

1. Navigate to **Microsoft 365 Admin Center** → **Settings** → **Agent 365**
2. Enable the Agent 365 service for your tenant
3. Assign Agent 365 licenses to AI admins and security leaders

### Step 6.2 — Enable Registry Sync

Configure Agent 365 to automatically discover agents from your Azure subscriptions:

```
Agent 365 Registry Sync Sources:
├── Azure Subscriptions (Foundry agents, Functions agents)
├── Microsoft 365 (Copilot agents, Custom Engine agents)
├── Third-Party (pre-integrated partner agents)
└── Manual registration (for agents outside Azure)
```

### Step 6.3 — Configure Observe Dashboards

In the M365 Admin Center Agent 365 section:

| Dashboard | Audience | Key Metrics |
|-----------|----------|-------------|
| **Agent Adoption** | AI Admin | Active agents, usage trends, new registrations |
| **Agent Health** | AI Admin | Performance signals, error rates, availability |
| **Security Overview** | Security Leader | Risk scores, threat detections, compliance status |
| **Business Value** | Business Leader | Agent utilization, ROI indicators, user satisfaction |

### Step 6.4 — Configure Governance Policies

Set lifecycle governance rules that apply to all agents in the registry:

| Policy | Configuration |
|--------|--------------|
| **Agent Activation** | New agents require approval before serving production traffic |
| **Periodic Review** | All production agents must pass quarterly access review |
| **Decommissioning** | Inactive agents (no traffic for 90 days) flagged for retirement |
| **Data Classification** | Agents must declare data sensitivity (Internal/Confidential/HC) |

### Step 6.5 — Connect Security Telemetry to Agent 365

Agent 365 aggregates security signals from the full Microsoft security stack:

- **Microsoft Defender for AI** → Threat alerts, risk scores, attack paths
- **Microsoft Purview** → Data sensitivity labels, DLP violations, insider risk
- **Microsoft Entra** → Identity risk, Conditional Access compliance
- **APIM Gateway** → Traffic anomalies, blocked requests, quota violations
- **Foundry Evaluations** → Quality scores, safety failures, red team results

---

## Part 7: Configure Microsoft Purview

### Step 6.1 — Create Purview Account

```bash
az purview account create \
  --resource-group rg-agent-factory-platform \
  --name purview-agent-factory \
  --location eastus2 \
  --managed-resource-group-name rg-purview-managed
```

### Step 6.2 — Register AI Data Sources

```bash
# Register the AI Services account as a data source in Purview
# This tracks data lineage from AI model inputs/outputs
az purview data-source create \
  --account-name purview-agent-factory \
  --name "foundry-ai-services" \
  --kind "AzureCognitiveService" \
  --data-source-type "AzureCognitiveService"
```

### Step 6.3 — Create Classification Labels

In Purview Studio, create sensitivity labels:

| Label | Purpose | Applied To |
|-------|---------|-----------|
| `AI-Prompt-PII` | Prompts containing PII | Agent prompts |
| `AI-Output-Confidential` | Model outputs with sensitive data | Model responses |
| `AI-Tool-Data` | Data returned by MCP tools | Tool responses |
| `AI-Training-Excluded` | Data opted out of training | All input data |

---

## Part 8: OpenTelemetry Configuration Template

Create the standard OTel configuration that every agent project receives:

### Step 7.1 — Python OTel Configuration

```python
# otel_config.py — Included in every Foundry project blueprint
"""
Standard OpenTelemetry configuration for Secure Agent Factory.
This file is part of the hardened blueprint and should not be modified.
"""

import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter
from opentelemetry.sdk.resources import Resource

def configure_telemetry(agent_name: str, project_name: str):
    """
    Configure OpenTelemetry for a Secure Agent Factory agent.
    Sends traces to both Azure Monitor and the central OTLP collector.
    """
    resource = Resource.create({
        "service.name": agent_name,
        "service.namespace": "secure-agent-factory",
        "deployment.environment": os.getenv("ENVIRONMENT", "dev"),
        "agent.project": project_name,
    })

    provider = TracerProvider(resource=resource)

    # Azure Monitor exporter (mandatory)
    appi_connection = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
    if appi_connection:
        azure_exporter = AzureMonitorTraceExporter(
            connection_string=appi_connection
        )
        provider.add_span_processor(BatchSpanExporter(azure_exporter))

    # OTLP exporter (for central collector)
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if otlp_endpoint:
        otlp_exporter = OTLPSpanExporter(endpoint=otlp_endpoint)
        provider.add_span_processor(BatchSpanExporter(otlp_exporter))

    trace.set_tracer_provider(provider)
    return trace.get_tracer(agent_name)
```

---

## Summary

| Component | Status |
|-----------|--------|
| Log Analytics workspace created | ✅ |
| Application Insights with private link | ✅ |
| Diagnostic settings on APIM, AI Services, Key Vault | ✅ |
| Defender for AI enabled (Standard tier) | ✅ |
| Microsoft Agent 365 registry synced | ✅ |
| Agent 365 observe/govern/secure configured | ✅ |
| Alert rules (tokens, errors, auth, anomalies) | ✅ |
| KQL dashboards (health, cost, audit, security) | ✅ |
| Microsoft Purview connected | ✅ |
| OpenTelemetry configuration template | ✅ |

---

## Next Steps

Proceed to [Chapter 21 — Foundry Project Blueprint & Automated Provisioning](./21-foundry-project-blueprint.md)
