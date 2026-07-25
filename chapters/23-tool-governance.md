# Chapter 23 — Tool Governance & Approved MCP Registry

## Objective

Implement a **governed tool supply chain** where MCP servers and APIs are vetted, cataloged, and published through a controlled workflow. Developers cannot connect to arbitrary tools — they consume only from the approved registry.

By the end of this lab, you will have:

- A tool approval workflow (Request → Review → Catalog → Publish)
- Azure API Center as the governed tool registry
- APIM as the publication and enforcement layer
- MCP tool allowlist policy in the gateway
- Audit trail for all tool governance decisions

---

## The Tool Supply Chain Risk

```
Without Governance:                    With Governance:
Developer finds MCP server            Developer requests tool
        ↓                                     ↓
Connects directly                      AI CoE security review
        ↓                                     ↓
No security review                     Pen test / code scan
No audit trail                                 ↓
No rate limiting                       Register in API Center
Data exfiltration possible                     ↓
        ↓                              Publish through APIM
Shadow tools in production                     ↓
                                       Rate limited, logged, filtered
                                               ↓
                                       Available in Foundry project
```

---

## Prerequisites

| Requirement | Details |
|------------|---------|
| Labs 01-06 completed | APIM and API Center deployed |
| Logged in as | AI CoE member |

---

## Part 1: Create Azure API Center as Tool Registry

### Step 1.1 — Deploy API Center

```bash
az apic create \
  --resource-group rg-agent-factory-platform \
  --name apic-agent-factory \
  --location eastus2 \
  --identity-type SystemAssigned
```

### Step 1.2 — Define Metadata Schema for Tools

```bash
# Register custom metadata for tool governance
az apic metadata create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --metadata-name "security-review-status" \
  --schema '{"type":"string","title":"Security Review Status","enum":["pending","approved","rejected","revoked"]}' \
  --assignments '[{"entity":"api","required":true}]'

az apic metadata create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --metadata-name "data-classification" \
  --schema '{"type":"string","title":"Data Classification","enum":["public","internal","confidential","restricted"]}' \
  --assignments '[{"entity":"api","required":true}]'

az apic metadata create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --metadata-name "tool-owner" \
  --schema '{"type":"string","title":"Tool Owner (Team)"}' \
  --assignments '[{"entity":"api","required":true}]'

az apic metadata create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --metadata-name "last-pen-test" \
  --schema '{"type":"string","title":"Last Penetration Test Date","format":"date"}' \
  --assignments '[{"entity":"api","required":true}]'

az apic metadata create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --metadata-name "max-calls-per-minute" \
  --schema '{"type":"integer","title":"Max Calls Per Minute","minimum":1,"maximum":1000}' \
  --assignments '[{"entity":"api","required":false}]'
```

### Step 1.3 — Create Tool Environments

```bash
# Define environments for tool lifecycle
az apic environment create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --environment-id "dev" \
  --title "Development" \
  --kind "development" \
  --server '{"type":"Azure API Management","managementPortalUri":["https://apim-agent-factory.developer.azure-api.net"]}'

az apic environment create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --environment-id "production" \
  --title "Production" \
  --kind "production" \
  --server '{"type":"Azure API Management","managementPortalUri":["https://apim-agent-factory.developer.azure-api.net"]}'
```

---

## Part 2: Tool Approval Workflow

### Step 2.1 — Define the Workflow Stages

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  1. REQUEST      │ ──→ │  2. REVIEW       │ ──→ │  3. TEST         │
│                  │     │                  │     │                  │
│  Developer       │     │  AI CoE          │     │  Security Team   │
│  submits tool    │     │  evaluates       │     │  pen tests       │
│  request         │     │  business need   │     │  scans code      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                          │
┌─────────────────┐     ┌─────────────────┐              │
│  5. PUBLISH      │ ←── │  4. CATALOG      │ ←───────────┘
│                  │     │                  │
│  APIM imports    │     │  API Center      │
│  with policies   │     │  registration    │
│  Tool available  │     │  with metadata   │
└─────────────────┘     └─────────────────┘
```

### Step 2.2 — Tool Request Template

```yaml
# .github/ISSUE_TEMPLATE/tool-request.yml
name: MCP Tool / API Request
description: Request a new tool be added to the approved registry
title: "[Tool Request] "
labels: ["tool-request", "needs-review"]
assignees: ["ai-coe-team"]

body:
  - type: input
    id: tool-name
    attributes:
      label: Tool Name
      placeholder: "search_documents"
    validations:
      required: true

  - type: dropdown
    id: tool-type
    attributes:
      label: Tool Type
      options:
        - MCP Server (JSON-RPC)
        - REST API
        - GraphQL API
        - gRPC Service
    validations:
      required: true

  - type: textarea
    id: tool-description
    attributes:
      label: What does this tool do?
      placeholder: "Searches the enterprise knowledge base and returns relevant documents"
    validations:
      required: true

  - type: textarea
    id: data-accessed
    attributes:
      label: What data does this tool access?
      placeholder: "Read-only access to knowledge base documents (internal classification)"
    validations:
      required: true

  - type: dropdown
    id: data-classification
    attributes:
      label: Data Classification
      options:
        - Public
        - Internal
        - Confidential
        - Restricted
    validations:
      required: true

  - type: textarea
    id: tool-endpoint
    attributes:
      label: Tool Source / Endpoint
      placeholder: "GitHub repo URL, or internal service endpoint"
    validations:
      required: true

  - type: textarea
    id: authentication
    attributes:
      label: Authentication Method
      placeholder: "Managed Identity, OAuth 2.0, API Key (via Key Vault)"
    validations:
      required: true

  - type: textarea
    id: business-justification
    attributes:
      label: Business Justification
      placeholder: "Required for the customer support agent to answer product questions"
    validations:
      required: true
```

### Step 2.3 — AI CoE Security Review Checklist

```markdown
## Tool Security Review Checklist

- [ ] **Source verified**: Tool comes from a trusted source (internal team, verified vendor)
- [ ] **Code scanned**: Static analysis completed (no known vulnerabilities)
- [ ] **Authentication reviewed**: Uses managed identity or OAuth (no embedded secrets)
- [ ] **Data classification**: Data access matches tool's classification level
- [ ] **Input validation**: Tool validates inputs (no injection vectors)
- [ ] **Output sanitization**: Tool sanitizes outputs (no data leakage)
- [ ] **Rate limiting**: Tool has built-in rate limiting or APIM will enforce
- [ ] **Logging**: Tool produces audit-quality logs
- [ ] **Error handling**: Tool handles errors gracefully (no stack trace leakage)
- [ ] **Network access**: Tool only accesses approved endpoints
- [ ] **Pen test passed**: Penetration test completed and passed
- [ ] **Rollback plan**: Tool can be removed without breaking agents

**Reviewer**: _______________
**Date**: _______________
**Decision**: [ ] Approved [ ] Rejected [ ] Needs changes
```

---

## Part 3: Register Approved Tool in API Center

### Step 3.1 — Register the Tool

```bash
# Register an approved MCP tool
az apic api create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --api-id "search-documents" \
  --title "Search Documents" \
  --type "rest" \
  --description "Searches the enterprise knowledge base. Returns relevant document excerpts. Read-only access." \
  --custom-properties '{
    "security-review-status": "approved",
    "data-classification": "internal",
    "tool-owner": "Knowledge Management Team",
    "last-pen-test": "2025-06-15",
    "max-calls-per-minute": 60
  }'
```

### Step 3.2 — Register Tool Version

```bash
az apic api version create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --api-id "search-documents" \
  --version-id "v1" \
  --title "v1.0.0" \
  --lifecycle-stage "production"
```

### Step 3.3 — Upload Tool Specification

```bash
# Create MCP tool specification
cat > /tmp/search-documents-spec.json << 'EOF'
{
  "name": "search_documents",
  "description": "Search the enterprise knowledge base for relevant documents",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "Search query text",
        "maxLength": 500
      },
      "max_results": {
        "type": "integer",
        "description": "Maximum results to return",
        "minimum": 1,
        "maximum": 10,
        "default": 5
      },
      "filters": {
        "type": "object",
        "properties": {
          "category": { "type": "string", "enum": ["product", "policy", "faq"] },
          "language": { "type": "string", "enum": ["en", "es", "fr", "de"] }
        }
      }
    },
    "required": ["query"]
  }
}
EOF

az apic api definition create \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --api-id "search-documents" \
  --version-id "v1" \
  --definition-id "mcp-spec" \
  --title "MCP Tool Specification" \
  --description "JSON-RPC tool definition for search_documents"
```

---

## Part 4: Publish Tool Through APIM

### Step 4.1 — Import Tool as APIM API

```bash
az apim api create \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "tool-search-documents" \
  --display-name "MCP Tool: search_documents" \
  --path "/tools/search-documents" \
  --protocols https \
  --service-url "https://search-documents.internal.contoso.com/api"
```

### Step 4.2 — Apply Tool-Specific Policies

```xml
<policies>
    <inbound>
        <base />

        <!-- Rate limit per tool -->
        <rate-limit-by-key calls="60" renewal-period="60"
            counter-key="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject ?? "anonymous")" />

        <!-- Input size limit -->
        <set-body>@{
            var body = context.Request.Body.As<JObject>(preserveContent: true);
            var query = body?["params"]?["arguments"]?["query"]?.ToString();
            if (query != null && query.Length > 500) {
                return new JObject(
                    new JProperty("error", "Query exceeds maximum length of 500 characters")
                ).ToString();
            }
            return body.ToString();
        }</set-body>

        <!-- Log tool invocation -->
        <emit-metric name="tool-invocation" value="1" namespace="agent-factory">
            <dimension name="tool-name" value="search_documents" />
            <dimension name="agent-id"
                value="@(context.Request.Headers.GetValueOrDefault("Authorization","").AsJwt()?.Subject ?? "unknown")" />
        </emit-metric>

        <!-- Authenticate to backend -->
        <authentication-managed-identity resource="api://search-documents-backend" />
    </inbound>

    <outbound>
        <base />

        <!-- Sanitize response — remove internal metadata -->
        <set-body>@{
            var body = context.Response.Body.As<JObject>(preserveContent: true);
            body.Remove("_internal");
            body.Remove("_debug");
            return body.ToString();
        }</set-body>
    </outbound>
</policies>
```

### Step 4.3 — Update APIM Tool Allowlist

Add the new tool to the global allowlist in the MCP server policy:

```bash
# The allowlist is maintained in the APIM global policy (Lab 03)
# Add "search_documents" to the allowedTools array
# This is the ONLY way tools become available to agents
```

---

## Part 5: Tool Catalog Discovery for Developers

### Step 5.1 — Grant Developers Read Access to API Center

```bash
DEVELOPER_GROUP=$(az ad group show \
  --group "sg-agentfactory-developers" \
  --query id -o tsv)

# API Center Data Reader — browse catalog only
az role assignment create \
  --assignee-object-id $DEVELOPER_GROUP \
  --assignee-principal-type Group \
  --role "Azure API Center Data Reader" \
  --scope $(az apic show \
    --resource-group rg-agent-factory-platform \
    --name apic-agent-factory \
    --query id -o tsv)
```

### Step 5.2 — Developers Browse Available Tools

```bash
# As a developer: List all approved tools
az apic api list \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --query "[?customProperties.\"security-review-status\"=='approved'].{Name:name, Title:title, Classification:customProperties.\"data-classification\"}" \
  -o table

# Expected:
# Name               Title              Classification
# -----------------  -----------------  ---------------
# search-documents   Search Documents   internal
# get-customer-data  Get Customer Data  confidential
# calculate-pricing  Calculate Pricing  internal
```

---

## Part 6: Tool Revocation Process

### Step 6.1 — Revoke a Compromised Tool

If a tool is found to be compromised:

```bash
# 1. Immediately remove from APIM (stops all traffic)
az apim api delete \
  --resource-group rg-agent-factory-platform \
  --service-name apim-agent-factory \
  --api-id "tool-compromised-tool" \
  --yes

# 2. Update API Center metadata
az apic api update \
  --resource-group rg-agent-factory-platform \
  --service-name apic-agent-factory \
  --api-id "compromised-tool" \
  --custom-properties '{"security-review-status": "revoked"}'

# 3. Remove from APIM allowlist policy
# Update the global MCP policy to remove the tool name

# 4. Alert affected project teams
echo "ALERT: Tool 'compromised-tool' has been revoked. Update your agents immediately."

# 5. Check which agents used this tool (audit trail)
az monitor log-analytics query \
  --workspace $(az monitor log-analytics workspace show \
    --resource-group rg-agent-factory-platform \
    --workspace-name law-agent-factory \
    --query customerId -o tsv) \
  --analytics-query "
    ApiManagementGatewayLogs
    | where ApiId == 'tool-compromised-tool'
    | where TimeGenerated > ago(30d)
    | extend AgentId = tostring(parse_json(RequestHeaders)['x-agent-id'])
    | summarize LastUsed=max(TimeGenerated), CallCount=count() by AgentId
    | order by LastUsed desc
  "
```

---

## Summary

| Component | Status |
|-----------|--------|
| API Center deployed as tool registry | ✅ |
| Custom metadata schema (review status, classification) | ✅ |
| Tool approval workflow defined | ✅ |
| Security review checklist | ✅ |
| Approved tool registered and versioned | ✅ |
| Tool published through APIM with policies | ✅ |
| Tool allowlist enforced in gateway | ✅ |
| Developers can browse catalog (read-only) | ✅ |
| Tool revocation process documented | ✅ |
| Audit trail for tool usage | ✅ |

---

## Next Steps

Proceed to [Chapter 24 — Developer Experience — Build an Agent](./24-developer-build-experience.md)
