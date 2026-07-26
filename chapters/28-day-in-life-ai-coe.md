# Chapter 28 — Day in the Life: AI Center of Excellence

## Objective

Walk through a **typical day for an AI CoE team member** operating within the Secure Agent Factory. Demonstrate how the platform transforms the AI CoE role from bottleneck gatekeeper into a high-leverage enabler — reviewing outcomes instead of implementations, running blueprints instead of writing Terraform, and managing a catalog instead of auditing individual agents.

---

## The AI CoE Role in This Platform

### What the AI CoE Is

The AI Center of Excellence is the **governance and quality layer** between IT infrastructure and developers. They don't build agents and they don't manage networks — they ensure that every agent built on the platform meets organizational standards for safety, quality, and compliance.

### What Changes With This Platform

| Traditional AI CoE | AI CoE on This Platform |
|--------------------|------------------------|
| Manual security reviews for every agent | CI/CD gates auto-verify; review results, not code |
| Custom infrastructure provisioning per project | Run a Bicep blueprint in 5 minutes |
| Maintain spreadsheets of approved models/tools | Manage a live registry (API Center + model allowlist) |
| Bottleneck on every deployment | Same-day turnaround; gates do the heavy lifting |
| Firefighting quality issues in production | Foundry Evaluations catch issues before deploy |
| No standard for "good enough" | Define thresholds once → enforced everywhere |

---

## Meet Priya — AI CoE Lead

> **Priya** leads a 3-person AI CoE team at a 5,000-person enterprise. Her team governs 40+ agents across 12 development teams. Here's her Tuesday.

---

## 7:30 AM — Morning Dashboard Review

Priya opens her **AI CoE Operations Dashboard** (Azure Workbook) with her coffee. This is her single pane of glass.

### What She Checks

```
┌─────────────────────────────────────────────────────────────────────┐
│                    AI CoE OPERATIONS DASHBOARD                       │
│                                                                     │
│  ┌─────────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │  Active Projects: 14 │  │  Pending Reviews: │  │  Agents in    │ │
│  │  In Development: 8   │  │  Project Reqs: 2  │  │  Production:  │ │
│  │  In CI/CD: 3         │  │  Tool Approvals: 1│  │  42           │ │
│  │  In Production: 42   │  │  Model Requests: 0│  │  Healthy: 40  │ │
│  │                      │  │                   │  │  Warning: 2   │ │
│  └─────────────────────┘  └──────────────────┘  └───────────────┘ │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  QUALITY TRENDS (Last 7 Days)                                   ││
│  │                                                                  ││
│  │  Avg Groundedness:  0.87 ████████░░  (threshold: 0.80) ✓        ││
│  │  Avg Relevance:     0.91 █████████░  (threshold: 0.85) ✓        ││
│  │  Avg Safety:        0.98 ██████████  (threshold: 0.95) ✓        ││
│  │  Failed Evals:      3/142 deployments blocked this week          ││
│  │                                                                  ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  ALERTS                                                          ││
│  │  ⚠️  customer-support-agent: groundedness dropped to 0.79       ││
│  │  ⚠️  finance-forecaster: token usage 180% above forecast         ││
│  │  ✓  All other agents within thresholds                           ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### KQL Query Behind the Dashboard

```kql
// Quality score trends across all production agents
AppTraces
| where TimeGenerated > ago(7d)
| where Properties.evaluation_type in ("groundedness", "relevance", "safety")
| extend agent_name = tostring(Properties.agent_name),
         eval_type = tostring(Properties.evaluation_type),
         score = todouble(Properties.score)
| summarize avg_score = avg(score), 
            min_score = min(score),
            eval_count = count()
    by agent_name, eval_type, bin(TimeGenerated, 1d)
| order by TimeGenerated desc
```

### Time Spent: 5 minutes
### Without the platform: 2 hours of checking individual agent logs, Slack threads, and spreadsheets

---

## 8:00 AM — Process Incoming Project Request

Two new project requests came in overnight. Priya reviews them.

### Request #1: Marketing Campaign Agent

```yaml
Title: [Project Request] Campaign Performance Agent
Team: Marketing Analytics
Models Needed: gpt-4o-mini
Tools Needed: get_campaign_metrics, search_brand_guidelines
Data Classification: Internal
Expected Volume: 2,000 interactions/month
Budget: $200/month
```

### Priya's Review Checklist (Mental, takes 2 minutes)

```
✓ Model requested (gpt-4o-mini) — on approved list
✓ Tools requested — get_campaign_metrics exists in registry,
  search_brand_guidelines needs creation (flag for tool team)
✓ Data classification Internal — no PII handling required
✓ Budget reasonable for volume
✓ Business justification clear
```

### Action: Approve and Provision

Priya runs the SAF Blueprint to create the project:

```bash
# Run the Foundry Project Blueprint
az deployment group create \
  --resource-group rg-saf-projects \
  --template-file blueprints/foundry-project.bicep \
  --parameters \
    projectName=marketing-campaign-agent \
    teamName=marketing-analytics \
    modelAllowlist="['gpt-4o-mini']" \
    monthlyTokenBudget=500000 \
    toolAccess="['get_campaign_metrics']" \
    dataClassification=Internal
```

### What the Blueprint Creates (Automatically)

```
┌─────────────────────────────────────────────────────────────┐
│  Project: marketing-campaign-agent                           │
│                                                              │
│  Created in 4 minutes:                                       │
│  ✓ Foundry project with model deployment (gpt-4o-mini)      │
│  ✓ APIM subscription with rate limits + token quota          │
│  ✓ App Insights workspace (pre-connected)                    │
│  ✓ Key Vault for project secrets                             │
│  ✓ Managed Identity for the agent                            │
│  ✓ GitHub repo from template (with CI/CD pre-configured)     │
│  ✓ CODEOWNERS file (AI CoE as reviewer)                      │
│  ✓ Branch protection rules                                   │
│  ✓ Azure Policy assignment (project-scoped)                  │
│  ✓ Defender for AI monitoring enabled                         │
│                                                              │
│  Developer receives:                                         │
│  📧 Email with repo link, APIM endpoint, quick-start guide   │
└─────────────────────────────────────────────────────────────┘
```

### Time Spent: 7 minutes (2 min review + 5 min blueprint run)
### Without the platform: 2-3 days (tickets to IT, manual Terraform, security review meeting, provisioning, documentation)

---

## 9:00 AM — Review CI/CD Gate Results

Three PRs triggered CI/CD gates overnight. Priya checks the results.

### PR #1: customer-support-agent (Update to response formatting)

```
┌─────────────────────────────────────────────────────────────┐
│  CI/CD Gate Results — PR #847                                │
│  Agent: customer-support-agent                               │
│  Author: alex@company.com                                    │
│                                                              │
│  Gate 1: Static Analysis          ✅ PASSED                  │
│    No secrets, no hardcoded endpoints, proper error handling │
│                                                              │
│  Gate 2: Policy Compliance        ✅ PASSED                  │
│    Only approved models, only approved tools                 │
│                                                              │
│  Gate 3: Unit Tests               ✅ PASSED (47/47)          │
│                                                              │
│  Gate 4: Integration Tests        ✅ PASSED                  │
│    APIM routing verified, auth flow confirmed                │
│                                                              │
│  Gate 5: Foundry Evaluation       ✅ PASSED                  │
│    Groundedness: 0.89 (threshold: 0.80)                      │
│    Relevance:    0.92 (threshold: 0.85)                      │
│    Safety:       0.99 (threshold: 0.95)                      │
│    Coherence:    0.94 (threshold: 0.85)                      │
│                                                              │
│  Gate 6: Red Team Scan            ✅ PASSED                  │
│    0 jailbreak vulnerabilities                               │
│    0 prompt injection risks                                  │
│    0 data exfiltration paths                                 │
│                                                              │
│  ──────────────────────────────────────────────────────────  │
│  RECOMMENDATION: ✅ Safe to merge and deploy                  │
└─────────────────────────────────────────────────────────────┘
```

**Priya's action:** Approve merge. All gates passed. No code review needed — the gates verified everything.

### PR #2: hr-benefits-agent (New tool integration)

```
┌─────────────────────────────────────────────────────────────┐
│  CI/CD Gate Results — PR #234                                │
│  Agent: hr-benefits-agent                                    │
│  Author: maya@company.com                                    │
│                                                              │
│  Gate 1: Static Analysis          ✅ PASSED                  │
│  Gate 2: Policy Compliance        ❌ FAILED                  │
│    ↳ Tool "query_employee_ssn" not in approved registry      │
│    ↳ Tool accesses PII without data classification upgrade   │
│                                                              │
│  Remaining gates: SKIPPED (Gate 2 failure is blocking)       │
│                                                              │
│  ──────────────────────────────────────────────────────────  │
│  RECOMMENDATION: ❌ Cannot merge. Policy violation.           │
│  ACTION NEEDED: Developer must use approved PII-safe tool    │
│                 or submit tool approval request               │
└─────────────────────────────────────────────────────────────┘
```

**Priya's action:** Comment on PR explaining the issue. The developer needs to either:
1. Use the existing `get_employee_benefits_summary` tool (which strips PII), or
2. Submit a tool approval request for the new tool (with data classification upgrade)

### PR #3: sales-forecast-agent (Model upgrade)

All gates passed. Approve merge.

### Time Spent: 12 minutes for all three PRs
### Without the platform: Full day of manual security review per PR, reading through code, testing manually, writing review comments

---

## 10:00 AM — Tool Registry Management

A developer submitted a new tool for the registry: `analyze_contract_terms`.

### Tool Approval Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  TOOL APPROVAL REQUEST                                       │
│                                                              │
│  Tool Name: analyze_contract_terms                           │
│  Type: MCP Server                                            │
│  Author: legal-team@company.com                              │
│  Description: Extracts key terms from uploaded contracts     │
│                                                              │
│  Priya's Review:                                             │
│                                                              │
│  ☐ Does it access external systems? → No (local docs only)  │
│  ☐ PII exposure? → Yes (contract names, dollar amounts)     │
│  ☐ Data classification required? → Confidential             │
│  ☐ APIM policy needed? → Yes (content filtering on output)  │
│  ☐ Rate limiting? → Standard (100 calls/min)                │
│  ☐ Owner identified? → Yes (legal-team)                     │
│  ☐ SLA defined? → 99.5% availability                        │
│                                                              │
│  Decision: APPROVE with conditions                           │
│  Conditions:                                                 │
│  • Data classification: Confidential                         │
│  • Only available to agents with Confidential clearance      │
│  • Content filtering policy applied at APIM                  │
│  • Quarterly access review required                          │
└─────────────────────────────────────────────────────────────┘
```

### Registration in API Center

```bash
# Register the approved tool in API Center
az apic api create \
  --resource-group rg-saf-platform \
  --service-name saf-api-center \
  --api-id analyze-contract-terms \
  --title "Analyze Contract Terms" \
  --type mcp-server \
  --custom-properties '{
    "data_classification": "Confidential",
    "owner": "legal-team",
    "sla": "99.5",
    "apim_policy": "content-filter-confidential",
    "approved_date": "2025-01-14",
    "approved_by": "priya@company.com"
  }'
```

### Time Spent: 15 minutes
### Without the platform: Multiple meetings, email chains, manual documentation, no central registry

---

## 11:00 AM — Investigate Quality Alert

The morning dashboard showed the `customer-support-agent` dropped below the groundedness threshold (0.79 vs 0.80 required).

### Investigation via KQL

```kql
// Find when groundedness started dropping
AppTraces
| where TimeGenerated > ago(3d)
| where Properties.agent_name == "customer-support-agent"
| where Properties.evaluation_type == "groundedness"
| extend score = todouble(Properties.score),
         query = tostring(Properties.user_query),
         source_docs = tostring(Properties.retrieved_documents)
| where score < 0.80
| project TimeGenerated, score, query, source_docs
| order by TimeGenerated desc
| take 20
```

### Root Cause Found

```
Pattern: All low-groundedness queries are about the "Q1 2025 pricing update"
Reason:  Knowledge base hasn't been refreshed since December 2024
Fix:     Trigger knowledge index refresh with latest pricing docs
```

### Priya's Action

```bash
# Trigger knowledge index refresh
az rest --method POST \
  --url "https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-saf-platform/providers/Microsoft.CognitiveServices/accounts/saf-foundry/indexes/product-knowledge/refresh?api-version=2024-10-01"
```

### Time Spent: 20 minutes (investigate + fix)
### Without the platform: Hours of guessing, no telemetry, manual testing, maybe never found

---

## 1:00 PM — Model Governance

A team requests access to `gpt-4o` (currently only `gpt-4o-mini` is on the standard allowlist).

### Model Upgrade Request Review

```
┌─────────────────────────────────────────────────────────────┐
│  MODEL ACCESS REQUEST                                        │
│                                                              │
│  Team: Financial Planning                                    │
│  Current Model: gpt-4o-mini                                  │
│  Requested Model: gpt-4o                                     │
│  Justification: Complex financial analysis requires          │
│                 higher reasoning capability. Mini model       │
│                 fails on multi-step calculations.             │
│                                                              │
│  Priya's Assessment:                                         │
│                                                              │
│  ☐ Cost impact? → ~3x increase ($500 → $1,500/month)        │
│  ☐ Budget approved? → Team has $2,000/month allocation       │
│  ☐ Model on platform allowlist? → Yes (gpt-4o approved)      │
│  ☐ Content safety policies compatible? → Yes                 │
│  ☐ Rate limits need adjustment? → Yes (lower TPM for 4o)    │
│                                                              │
│  Decision: APPROVE                                           │
│  Action: Update APIM backend pool + token quota              │
└─────────────────────────────────────────────────────────────┘
```

### Implementation (2 minutes)

```bash
# Update the project's model allowlist
az deployment group create \
  --resource-group rg-saf-projects \
  --template-file blueprints/update-model-access.bicep \
  --parameters \
    projectName=financial-planning-agent \
    modelAllowlist="['gpt-4o-mini','gpt-4o']" \
    monthlyTokenBudget=2000000
```

### Time Spent: 10 minutes
### Without the platform: Procurement process, manual APIM configuration, security review, weeks of waiting

---

## 2:30 PM — Quarterly Standards Update

Priya updates the evaluation thresholds based on last quarter's data.

### What She Reviews

```
┌─────────────────────────────────────────────────────────────┐
│  QUARTERLY STANDARDS REVIEW                                  │
│                                                              │
│  Metric Performance (Q4 2024):                               │
│  • 142 deployments attempted                                 │
│  • 139 passed all gates (97.9% pass rate)                    │
│  • 3 blocked by evaluation gates                             │
│  • 0 production incidents from approved deployments          │
│  • 2 incidents caught by Defender before impact              │
│                                                              │
│  Threshold Adjustments for Q1 2025:                          │
│  • Groundedness: 0.80 → 0.82 (raising the bar)              │
│  • Safety: 0.95 → 0.95 (maintaining)                        │
│  • NEW: Add "citation accuracy" metric (threshold: 0.75)     │
│                                                              │
│  Updated in: cicd-gates/evaluation-config.yaml               │
│  Effective: Next deployment for all agents                    │
└─────────────────────────────────────────────────────────────┘
```

### Update the Gate Configuration

```yaml
# cicd-gates/evaluation-config.yaml
evaluation_thresholds:
  groundedness: 0.82      # raised from 0.80
  relevance: 0.85
  coherence: 0.85
  safety: 0.95
  citation_accuracy: 0.75  # NEW metric
  
evaluation_dataset: "datasets/standard-eval-v3.jsonl"
red_team_scenarios: "datasets/red-team-v2.jsonl"
```

### Time Spent: 30 minutes
### Without the platform: No data to base decisions on; standards are arbitrary and unenforced

---

## 4:00 PM — Onboard New AI CoE Team Member

A new team member, Jordan, joins the AI CoE. Priya's onboarding:

### What Jordan Needs to Know

```
┌─────────────────────────────────────────────────────────────┐
│  AI CoE ONBOARDING CHECKLIST                                 │
│                                                              │
│  Access Granted:                                             │
│  ✓ Azure Portal (AI CoE resource group)                      │
│  ✓ AI CoE Operations Dashboard (read)                        │
│  ✓ GitHub org (CODEOWNERS reviewer role)                     │
│  ✓ API Center (tool registry admin)                          │
│  ✓ Foundry (evaluation access)                               │
│                                                              │
│  Access NOT Granted (separation of duties):                   │
│  ✗ APIM management (IT owns)                                 │
│  ✗ VNet/NSG configuration (IT owns)                          │
│  ✗ Azure Policy definitions (IT owns)                        │
│  ✗ Defender configuration (IT owns)                          │
│  ✗ Production agent code repos (developers own)              │
│                                                              │
│  Daily Workflow:                                              │
│  1. Check dashboard (5 min)                                  │
│  2. Process project requests (as they arrive)                │
│  3. Review CI/CD gate results for pending PRs                │
│  4. Investigate any quality alerts                           │
│  5. Manage tool/model approval requests                      │
│                                                              │
│  Key Principle:                                               │
│  "We review OUTCOMES, not IMPLEMENTATIONS.                    │
│   If the gates pass, the agent is good.                       │
│   We only dig deeper when gates fail or alerts fire."        │
└─────────────────────────────────────────────────────────────┘
```

### Time Spent: 45 minutes
### Without the platform: Weeks of shadowing with no clear process, tribal knowledge transfer

---

## 5:00 PM — End of Day Summary

### Priya's Day at a Glance

| Time | Activity | Time Spent | Without Platform |
|------|----------|-----------|-----------------|
| 7:30 | Dashboard review | 5 min | 2 hours |
| 8:00 | Project provisioning (2 projects) | 14 min | 2-3 days each |
| 9:00 | CI/CD gate reviews (3 PRs) | 12 min | Full day each |
| 10:00 | Tool registry approval | 15 min | Multiple meetings |
| 11:00 | Quality alert investigation | 20 min | Hours/never found |
| 1:00 | Model access upgrade | 10 min | Weeks |
| 2:30 | Quarterly standards update | 30 min | Impossible (no data) |
| 4:00 | Team member onboarding | 45 min | Weeks of shadowing |

### Total Productive Governance Time: ~2.5 hours

The rest of Priya's day is spent on **strategic work**: researching new evaluation techniques, attending AI ethics committee meetings, planning the next quarter's model additions, and writing best-practice guides for developers.

### The Platform's Impact on AI CoE

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  WITHOUT the platform:                                       │
│  • 3-person team governs 5-8 agents (bottleneck)             │
│  • Average deployment takes 2 weeks                          │
│  • 80% of time on manual reviews                             │
│  • Governance perceived as "the team that blocks things"     │
│                                                              │
│  WITH the platform:                                          │
│  • 3-person team governs 40+ agents (leverage)               │
│  • Average deployment takes same day                         │
│  • 80% of time on strategic improvement                      │
│  • Governance perceived as "the team that accelerates us"    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Takeaway

The AI CoE's job transforms from **gatekeeper** to **enabler**:

1. **They don't review code** — CI/CD gates do that automatically
2. **They don't provision infrastructure** — blueprints do that in minutes
3. **They don't monitor agents** — Application Insights and Defender do that continuously
4. **They don't enforce policy** — Azure Policy and APIM do that at the platform level

What they DO:
- **Set standards** (evaluation thresholds, model allowlists, tool approvals)
- **Run blueprints** (project provisioning in minutes)
- **Review outcomes** (gate results, quality trends, alerts)
- **Improve the system** (raise the bar, add metrics, update datasets)

The platform makes the AI CoE **10x more effective** by eliminating manual work and letting them focus on what humans do best: judgment, strategy, and continuous improvement.

---

## Next Steps

- [Chapter 29 — Day in the Life: IT Platform Engineering](./29-day-in-life-it-platform.md)
