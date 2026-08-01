# Chapter 29 — Day in the Life: IT Platform Engineering

## Objective

Walk through a **typical day for an IT Platform Engineer** operating the Secure Agent Factory infrastructure. Demonstrate how the platform transforms IT's role from reactive firefighting and per-team provisioning into **proactive platform management** — where policy enforces itself, monitoring is automatic, and the platform scales without linear headcount growth.

---

## The IT Platform Engineering Role

### What IT Platform Engineering Owns

IT Platform Engineering owns the **foundation layer** — everything below the application that makes the platform secure, reliable, and compliant. They build it once and everyone benefits forever.

### What Changes With This Platform

| Traditional IT for AI | IT on This Platform |
|----------------------|---------------------|
| Provision infrastructure per team, per project | Build platform once; teams self-serve within guardrails |
| Manually audit for compliance gaps | Azure Policy prevents non-compliance at creation time |
| No visibility into agent fleet | Microsoft Agent 365 provides centralized registry with observe/govern/secure |
| Respond to security incidents with no context | Defender detects + alerts with full correlation; Agent 365 provides risk dashboards |
| Set up monitoring per application | Application Insights enabled by default for everything |
| Chase teams for logging compliance | Logging is non-optional — built into the architecture |
| Manage VPN/VNet requests one by one | VNet pre-built; Private Link for all services |
| Spend 80% of time on tickets | Spend 80% of time on platform improvement |

---

## Meet Raj — Senior Platform Engineer

> **Raj** is a Senior Platform Engineer on a 4-person infrastructure team. His team manages the underlying platform that supports 12 development teams, 40+ agents, and the entire AI CoE. Here's his Wednesday.

---

## 7:00 AM — Platform Health Check

Raj starts his day with the **Platform Health Dashboard** — a unified view of all infrastructure components.

### What He Checks

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PLATFORM HEALTH DASHBOARD                         │
│                                                                     │
│  INFRASTRUCTURE STATUS                                              │
│  ┌─────────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  APIM Gateway        │  │  Foundry          │  │  Networking   │ │
│  │  Status: ✅ Healthy   │  │  Status: ✅ Active │  │  VNet: ✅     │ │
│  │  Requests/hr: 12,400 │  │  Models: 6 online │  │  NSG: ✅      │ │
│  │  Avg latency: 145ms  │  │  Capacity: 62%    │  │  DNS: ✅      │ │
│  │  Error rate: 0.02%   │  │  PTU used: 58%    │  │  Firewall: ✅ │ │
│  └─────────────────────┘  └──────────────────┘  └───────────────┘ │
│                                                                     │
│  ┌─────────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  Key Vault           │  │  Defender for AI  │  │  Log          │ │
│  │  Status: ✅ Healthy   │  │  Threats: 0 🟢    │  │  Analytics    │ │
│  │  Secrets accessed: 89│  │  Agents scanned:  │  │  Ingestion:   │ │
│  │  Rotation due: 3     │  │  42/42 (100%)     │  │  2.3 GB/day   │ │
│  │                      │  │  Risk: Low        │  │  Retention: ✅│ │
│  └─────────────────────┘  └──────────────────┘  └───────────────┘ │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  MICROSOFT AGENT 365 — UNIFIED REGISTRY                         ││
│  │  Registry Status: ✅ Synced                                      ││
│  │  Total Agents: 42  |  Active: 40  |  Under Review: 2            ││
│  │  Governance Compliance: 100%                                     ││
│  │  Third-Party Agents: 2 (approved, monitored)                     ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  CAPACITY & COST                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Monthly Spend: $18,400 / $25,000 budget (73.6%)                ││
│  │  Token Usage: 4.2M / 6M allocated (70%)                         ││
│  │  APIM Units: 3/5 provisioned                                    ││
│  │  Foundry PTU: 580/1000 allocated                                ││
│  │                                                                  ││
│  │  Forecast: On track. No scaling needed this month.              ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  ALERTS (Last 24h)                                                  │
│  ⚠️  3 Key Vault secrets approaching rotation date                  │
│  ℹ️  APIM scaling event (auto-scaled to 4 units at 2:30 AM)        │
│  ✅  No security incidents                                          │
│  ✅  No policy violations attempted                                 │
└─────────────────────────────────────────────────────────────────────┘
```

### KQL Queries Behind the Dashboard

```kql
// APIM Health - Last 24 hours
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| summarize 
    total_requests = count(),
    avg_latency = avg(TotalTime),
    error_rate = countif(ResponseCode >= 500) * 100.0 / count(),
    p99_latency = percentile(TotalTime, 99)
    by bin(TimeGenerated, 1h)
| order by TimeGenerated desc
```

```kql
// Policy Compliance Check
PolicyStates_CL
| where TimeGenerated > ago(24h)
| where ComplianceState_s == "NonCompliant"
| project TimeGenerated, PolicyDefinitionName_s, ResourceId_s
| count
// Expected: 0 (Azure Policy denies non-compliant resources at creation)
```

### Time Spent: 5 minutes
### Without the platform: 45 minutes checking 8+ different consoles, no unified view

---

## 7:30 AM — Secret Rotation

The dashboard flagged 3 secrets approaching their 90-day rotation. Raj handles this proactively.

### Automated Rotation (Already Configured)

```bash
# Check which secrets need rotation
az keyvault secret list \
  --vault-name kv-saf-platform \
  --query "[?attributes.expires < '2025-01-21'].[name,attributes.expires]" \
  --output table

# Output:
# Name                          Expires
# ----------------------------  -------------------------
# apim-subscription-key-team-a  2025-01-18T00:00:00+00:00
# foundry-endpoint-key-backup   2025-01-19T00:00:00+00:00
# log-analytics-shared-key      2025-01-20T00:00:00+00:00
```

### Raj's Action

Most rotations are automated via Key Vault rotation policies. He verifies the automation ran:

```bash
# Verify auto-rotation completed
az keyvault secret show \
  --vault-name kv-saf-platform \
  --name apim-subscription-key-team-a \
  --query "attributes.expires"
# Output: "2025-04-18T00:00:00+00:00"  ← rotated, new 90-day expiry
```

For the Log Analytics key (which requires manual steps):

```bash
# Regenerate Log Analytics shared key
az monitor log-analytics workspace get-shared-keys \
  --resource-group rg-saf-platform \
  --workspace-name law-saf-central \
  --query primarySharedKey -o tsv | \
az keyvault secret set \
  --vault-name kv-saf-platform \
  --name log-analytics-shared-key \
  --value @- \
  --expires "2025-04-16"
```

### Time Spent: 10 minutes
### Without the platform: Forgotten until it breaks, then emergency response

---

## 8:30 AM — Azure Policy Review

Raj reviews the weekly policy compliance report. Azure Policy automatically **denies** non-compliant resource creation, so violations are prevented — not detected after the fact.

### Policy Compliance Summary

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AZURE POLICY COMPLIANCE                           │
│                    Week of Jan 13-19, 2025                           │
│                                                                     │
│  Overall Compliance: 100% (all resources compliant)                 │
│                                                                     │
│  Denied Attempts (prevented before creation):                       │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  Date       │ Who              │ What Attempted     │ Policy     ││
│  │  ─────────  │ ────────────     │ ──────────────     │ ──────    ││
│  │  Jan 14     │ dev-team-c       │ Public IP on VM    │ no-public ││
│  │  Jan 15     │ ai-coe-jordan    │ Storage w/o        │ require-  ││
│  │             │                  │ private endpoint   │ pep       ││
│  │  Jan 16     │ dev-team-a       │ Cognitive Svc      │ approved- ││
│  │             │                  │ (non-approved      │ models    ││
│  │             │                  │  model)            │ only      ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  Result: All 3 attempts were blocked BEFORE resources existed.      │
│  No manual remediation needed. No audit findings.                   │
│  No conversations needed — the developers got clear error messages. │
└─────────────────────────────────────────────────────────────────────┘
```

### Key Policies Raj Maintains

```json
{
  "policies": [
    {
      "name": "deny-public-endpoints",
      "effect": "Deny",
      "description": "All AI services must use Private Link"
    },
    {
      "name": "require-diagnostic-settings",
      "effect": "DeployIfNotExists",
      "description": "Auto-deploy logging to Log Analytics for any new resource"
    },
    {
      "name": "approved-model-deployments",
      "effect": "Deny",
      "description": "Only allowlisted models can be deployed"
    },
    {
      "name": "require-managed-identity",
      "effect": "Deny",
      "description": "No connection strings or API keys in app settings"
    },
    {
      "name": "enforce-network-rules",
      "effect": "Deny",
      "description": "Storage/KeyVault must deny public access"
    },
    {
      "name": "require-defender",
      "effect": "DeployIfNotExists",
      "description": "Microsoft Defender enabled on all AI workloads"
    }
  ]
}
```

### Raj's Action: Update one policy

A new model (`claude-3.5-sonnet`) was approved by the AI CoE. Raj adds it to the policy:

```bash
# Update the approved models policy
az policy definition update \
  --name approved-model-deployments \
  --rules @policies/approved-models-rule.json \
  --params @policies/approved-models-params.json
```

```json
// policies/approved-models-params.json (updated)
{
  "allowedModels": {
    "value": [
      "gpt-4o",
      "gpt-4o-mini",
      "gpt-4-turbo",
      "claude-3.5-sonnet",
      "text-embedding-ada-002"
    ]
  }
}
```

### Time Spent: 15 minutes (review + one policy update)
### Without the platform: Constant audit findings, manual remediation, uncomfortable conversations with teams

---

## 10:00 AM — APIM Gateway Performance Optimization

The dashboard showed APIM auto-scaled from 3 to 4 units at 2:30 AM (a batch processing team runs heavy workloads overnight). Raj investigates whether this is expected.

### Investigation

```kql
// What caused the scaling event?
ApiManagementGatewayLogs
| where TimeGenerated between (datetime(2025-01-15 02:00) .. datetime(2025-01-15 03:30))
| summarize request_count = count() by bin(TimeGenerated, 5m), 
    SubscriptionId = tostring(BackendId)
| order by request_count desc
| take 10
```

### Findings

```
The batch-processing team (finance-forecaster-agent) made 45,000 requests
between 2:00 AM and 3:00 AM — this is their nightly batch run.

APIM auto-scaled correctly (from 3→4 units at 70% capacity).
Scaled back down to 3 units at 4:00 AM.
Cost impact: ~$2.40 for the extra unit-hour. Within budget.

Action: No change needed. Auto-scaling worked as designed.
Optionally: Set up a scheduled scale-out for the nightly window
to avoid the 30-second scaling delay.
```

### Optional Optimization

```bash
# Create scheduled auto-scale rule for known batch window
az monitor autoscale rule create \
  --resource-group rg-saf-platform \
  --autoscale-name apim-autoscale \
  --scale out 1 \
  --condition "Requests count > 500" \
  --time-grain 5m \
  --time-window 10m \
  --cooldown 5m
```

### Time Spent: 20 minutes
### Without the platform: Outage during batch window, emergency scaling, developer complaints

---

## 11:00 AM — Network Security Review

Monthly task: verify that no unintended network paths exist.

### What Raj Validates

```bash
# List all private endpoints
az network private-endpoint list \
  --resource-group rg-saf-platform \
  --query "[].{Name:name, Service:privateLinkServiceConnections[0].groupIds[0], Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table
```

```
Name                          Service             Status
----------------------------  ------------------  --------
pep-foundry                   account             Approved
pep-apim                      Gateway             Approved
pep-keyvault                  vault               Approved
pep-storage                   blob                Approved
pep-log-analytics             workspace           Approved
pep-cosmosdb                  Sql                 Approved
pep-app-insights              appInsights         Approved
```

```bash
# Verify NSG rules haven't drifted
az network nsg rule list \
  --resource-group rg-saf-platform \
  --nsg-name nsg-agents \
  --query "[?access=='Allow'].{Priority:priority, Direction:direction, Source:sourceAddressPrefix, Dest:destinationAddressPrefix, Port:destinationPortRange}" \
  --output table
```

```
Priority  Direction  Source           Dest             Port
--------  ---------  ---------------  ---------------  ----
100       Inbound    10.0.1.0/24      10.0.2.0/24      443
200       Inbound    10.0.1.0/24      10.0.2.0/24      8080
1000      Inbound    VirtualNetwork   VirtualNetwork   *
4096      Inbound    *                *                *     (Deny)
```

### Validation Complete

```
✅ All services use Private Link (no public endpoints)
✅ NSG rules unchanged from baseline
✅ No new allow rules added
✅ Default deny still in place
✅ DNS zones resolving correctly to private IPs
```

### Time Spent: 15 minutes
### Without the platform: Full day audit, custom scripts, manual verification

---

## 1:00 PM — Capacity Planning

Raj runs his monthly capacity forecast to determine if any scaling is needed for the next quarter.

### Current vs. Projected Usage

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CAPACITY FORECAST — Q1 2025                       │
│                                                                     │
│  APIM Gateway                                                       │
│  ─────────────                                                      │
│  Current: 3 units (handles 15,000 req/hr)                           │
│  Peak observed: 4 units (auto-scaled)                               │
│  Growth rate: +12% month-over-month                                 │
│  Q1 forecast: Need 5 units by March                                 │
│  Action: Pre-provision 5th unit in February                         │
│                                                                     │
│  Foundry PTU                                                        │
│  ──────────                                                         │
│  Current: 580/1000 PTU allocated                                    │
│  Growth rate: +8% month-over-month                                  │
│  Q1 forecast: ~750 PTU by March                                     │
│  Action: No change needed. 25% headroom sufficient.                 │
│                                                                     │
│  Log Analytics                                                      │
│  ─────────────                                                      │
│  Current: 2.3 GB/day ingestion                                      │
│  Growth rate: +15% month-over-month (new agents onboarding)         │
│  Q1 forecast: ~3.5 GB/day by March                                  │
│  Action: Review retention policy. Consider commitment tier.          │
│                                                                     │
│  Cost Projection                                                    │
│  ───────────────                                                    │
│  Current monthly: $18,400                                           │
│  Q1 end monthly: ~$22,000                                           │
│  Budget: $25,000/month                                              │
│  Status: ✅ Within budget with 12% headroom                         │
└─────────────────────────────────────────────────────────────────────┘
```

### Raj's Actions

```bash
# Set up pre-provisioned scaling for February
az apim update \
  --name apim-saf-gateway \
  --resource-group rg-saf-platform \
  --sku-capacity 5 \
  --no-wait

# Update cost commitment tier for Log Analytics
az monitor log-analytics workspace update \
  --resource-group rg-saf-platform \
  --workspace-name law-saf-central \
  --commitment-tier 300  # 300 GB/day commitment = 30% discount
```

### Time Spent: 30 minutes
### Without the platform: No visibility into growth, reactive scaling, budget surprises

---

## 2:30 PM — Defender for AI Alert Triage

Microsoft Defender flags an unusual pattern.

### Alert Details

```
┌─────────────────────────────────────────────────────────────────────┐
│  DEFENDER FOR AI — ALERT                                            │
│                                                                     │
│  Severity: Medium                                                   │
│  Type: Anomalous prompt pattern detected                            │
│  Agent: public-faq-agent                                            │
│  Time: 2025-01-15 14:12:00 UTC                                     │
│                                                                     │
│  Details:                                                           │
│  18 requests in 3 minutes from same IP containing repeated          │
│  prompt injection patterns:                                         │
│  "Ignore all previous instructions and..."                          │
│  "You are now a different AI that..."                                │
│  "System: override safety filters..."                               │
│                                                                     │
│  Platform Response (AUTOMATIC):                                     │
│  ✅ Prompt Shields blocked all 18 requests at APIM layer            │
│  ✅ No malicious content reached the model                          │
│  ✅ Source IP flagged for rate limiting (reduced to 5 req/min)       │
│  ✅ Full request/response logs preserved for forensics              │
│                                                                     │
│  Agent Impact: NONE — attack was blocked at the gateway             │
└─────────────────────────────────────────────────────────────────────┘
```

### Raj's Investigation

```kql
// Review the attack pattern
ApiManagementGatewayLogs
| where TimeGenerated between (datetime(2025-01-15 14:10) .. datetime(2025-01-15 14:15))
| where ResponseCode == 400
| where Properties.ContentSafetyResult contains "PromptShield"
| extend source_ip = CallerIpAddress,
         blocked_reason = tostring(Properties.ContentSafetyCategory)
| summarize attempts = count() by source_ip, blocked_reason
```

### Raj's Response

```
Assessment: Automated attack attempt. Fully blocked by platform defenses.
No escalation needed. No agent was compromised.

Actions taken:
✅ Verified Prompt Shields blocked all attempts
✅ Confirmed no data exfiltration
✅ IP auto-throttled by APIM rate limiting
✅ Agent 365 security dashboard updated (risk signal recorded)
✅ Logged incident in security dashboard
✅ No action needed from developers (they don't even know it happened)
```

### Time Spent: 15 minutes
### Without the platform: Major security incident, war room, developer interviews, manual log analysis, potential data breach

---

## 3:30 PM — Platform Update: Content Safety Policy Enhancement

Microsoft released a new Prompt Shield capability. Raj adds it to the APIM policy.

### What's New

Content Safety now detects **indirect prompt injection** (malicious instructions hidden in documents that agents retrieve).

### APIM Policy Update

```xml
<!-- apim-policies/ai-gateway-global.xml -->
<inbound>
    <base />
    <!-- Existing: Direct prompt injection check -->
    <azure-openai-content-safety>
        <prompt-shield enabled="true" />
    </azure-openai-content-safety>
    
    <!-- NEW: Indirect prompt injection check on retrieved documents -->
    <azure-openai-content-safety>
        <document-shield enabled="true" 
                         action="block" 
                         log-level="warning" />
    </azure-openai-content-safety>
</inbound>
```

### Deployment

```bash
# Update APIM policy
az apim api policy set \
  --resource-group rg-saf-platform \
  --service-name apim-saf-gateway \
  --api-id ai-gateway \
  --xml-policy @apim-policies/ai-gateway-global.xml

# Verify policy is active
az apim api policy show \
  --resource-group rg-saf-platform \
  --service-name apim-saf-gateway \
  --api-id ai-gateway \
  --query "value" | grep "document-shield"
```

### Impact

```
✅ All 42 agents now protected against indirect prompt injection
✅ No developer action needed — protection is at the gateway
✅ Developers don't even need to know about this threat
✅ Deployed in 5 minutes, effective immediately
```

### Time Spent: 20 minutes
### Without the platform: Each team must update their own code, inconsistent protection, some teams never update

---

## 4:30 PM — Infrastructure as Code: Blueprint Update

The AI CoE requested a new option in the project blueprint: support for `Confidential` data classification (adds extra encryption and access controls).

### Blueprint Enhancement

```bicep
// blueprints/foundry-project.bicep (addition)

@allowed(['Internal', 'Confidential', 'HighlyConfidential'])
param dataClassification string

// Additional resources for Confidential classification
module confidentialControls 'modules/confidential-tier.bicep' = if (dataClassification == 'Confidential') {
  name: 'confidential-controls-${projectName}'
  params: {
    projectName: projectName
    // Customer-managed keys for encryption at rest
    cmkKeyVaultId: platformKeyVault.id
    // Restricted network access (agent subnet only)
    allowedSubnets: [agentSubnet.id]
    // Enhanced audit logging
    auditLogRetentionDays: 365
    // Data loss prevention policy
    dlpPolicyId: dlpPolicy.id
  }
}
```

### Test the Blueprint

```bash
# Validate the updated blueprint (what-if deployment)
az deployment group what-if \
  --resource-group rg-saf-projects \
  --template-file blueprints/foundry-project.bicep \
  --parameters \
    projectName=test-confidential-project \
    teamName=legal-team \
    modelAllowlist="['gpt-4o']" \
    dataClassification=Confidential

# Output shows what WOULD be created — review before merging
```

### Time Spent: 45 minutes
### Without the platform: Custom infrastructure for each sensitive project, weeks per deployment

---

## 5:00 PM — End of Day Summary

### Raj's Day at a Glance

| Time | Activity | Time Spent | Without Platform |
|------|----------|-----------|-----------------|
| 7:00 | Platform health check | 5 min | 45 min (8 consoles) |
| 7:30 | Secret rotation verification | 10 min | Forgotten/break-fix |
| 8:30 | Azure Policy review + update | 15 min | Constant audit findings |
| 10:00 | APIM performance review | 20 min | Outage during batch |
| 11:00 | Network security verification | 15 min | Full day audit |
| 1:00 | Capacity planning | 30 min | No visibility, surprises |
| 2:30 | Security alert triage | 15 min | Major incident response |
| 3:30 | Platform security enhancement | 20 min | Per-team updates |
| 4:30 | Blueprint enhancement | 45 min | Weeks per deployment |

### Total Platform Operations Time: ~3 hours

The rest of Raj's day is spent on **platform improvement**: researching new Azure features, automating more operational tasks, contributing to the platform roadmap, and mentoring junior engineers.

---

## The Platform Engineering Advantage

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  WITHOUT the platform:                                              │
│  • 4-person team supports 3-4 AI projects (ticket-driven)           │
│  • 80% reactive work (incidents, provisioning requests, audits)     │
│  • Security incidents take days to detect and weeks to resolve      │
│  • Every team gets slightly different infrastructure                 │
│  • Compliance is a quarterly audit panic                            │
│                                                                     │
│  WITH the platform:                                                 │
│  • 4-person team supports 40+ agents across 12 teams               │
│  • 80% proactive work (optimization, automation, improvement)       │
│  • Security attacks blocked automatically, triaged in minutes       │
│  • Every team gets identical, hardened infrastructure                │
│  • Compliance is continuous and automatic                           │
│                                                                     │
│  Scale factor: 10x more workloads with the same headcount           │
│  Security posture: Attacks blocked before they reach agents         │
│  Developer experience: Zero infrastructure tickets                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## IT Platform Engineering Principles

### 1. Build Once, Benefit Forever

Every platform capability (APIM, Policy, Defender, networking) is built once and applies to all current and future agents. No per-team work.

### 2. Policy Over Process

Instead of writing runbooks that humans must follow, encode requirements as Azure Policy that the platform enforces automatically. Humans can't accidentally skip steps that don't exist.

### 3. Observe Everything, Alert on What Matters

Full telemetry is non-negotiable and automatic. But dashboards and alerts are curated to show actionable signals, not noise.

### 4. Security Is Architecture, Not Audit

Security isn't something you check after deployment — it's something the architecture prevents you from violating. Private Link, deny-by-default NSGs, mandatory managed identity, content safety at the gateway.

### 5. Make the Right Thing the Easy Thing

Developers shouldn't need to "remember" to use Private Link or enable logging. The platform makes the secure path the only path. Insecure options simply don't exist.

---

## Separation of Duties: What IT Does NOT Do

```
┌─────────────────────────────────────────────────────────────┐
│  CLEAR BOUNDARIES                                            │
│                                                              │
│  IT Platform Engineering DOES:                               │
│  ✓ Deploy and maintain network infrastructure                │
│  ✓ Configure and update APIM gateway policies                │
│  ✓ Manage Azure Policy definitions                           │
│  ✓ Maintain Defender for AI configuration                    │
│  ✓ Manage Key Vault and secret rotation                      │
│  ✓ Capacity planning and cost optimization                   │
│  ✓ Platform-level security incident response                 │
│  ✓ Update blueprints (infrastructure components)             │
│                                                              │
│  IT Platform Engineering does NOT:                           │
│  ✗ Approve or deny project requests (AI CoE)                 │
│  ✗ Review agent code or PRs (AI CoE)                         │
│  ✗ Choose which models teams can use (AI CoE)                │
│  ✗ Deploy agents to production (AI CoE via CI/CD)            │
│  ✗ Set evaluation thresholds (AI CoE)                        │
│  ✗ Write agent code (Developers)                             │
│  ✗ Debug agent logic (Developers)                            │
│  ✗ Manage tool integrations (Developers + AI CoE)            │
│                                                              │
│  This separation means:                                      │
│  → IT never blocks developer velocity                        │
│  → AI CoE never needs to understand networking               │
│  → Developers never touch infrastructure                     │
│  → Everyone stays in their lane and moves fast               │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Takeaway

IT Platform Engineering transforms from **reactive service desk** to **proactive platform team**:

1. **They don't provision per-team** — blueprints and self-service handle that
2. **They don't enforce compliance manually** — Azure Policy does it at resource creation
3. **They don't detect threats manually** — Defender and Prompt Shields are automatic
4. **They don't chase teams for logging** — observability is non-optional by architecture

What they DO:
- **Build and maintain the platform** (networking, gateway, security, monitoring)
- **Optimize capacity and cost** (forecasting, commitment tiers, auto-scaling)
- **Improve defenses continuously** (new policies, new content safety features)
- **Respond to platform-level incidents** (not app-level — those are blocked automatically)

The platform makes IT **10x more scalable** by eliminating per-team work and making security a property of the architecture, not a checklist item.

---

## Next Steps

- Return to [Chapter 00 — Architecture Overview](./00-overview.md) for the full platform picture
- Review [Chapter 17 — Enterprise Roles & Responsibilities](./17-roles-and-governance.md) for the governance framework
- See [Chapter 28 — Day in the Life: AI CoE](./28-day-in-life-ai-coe.md) for the AI CoE perspective
