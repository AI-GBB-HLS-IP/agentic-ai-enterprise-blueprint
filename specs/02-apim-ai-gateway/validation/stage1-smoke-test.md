# Stage 1 Customer Smoke Test

This runbook validates and deploys only the APIM foundation. It performs no Foundry lookup,
requires no Foundry permission, and must not be used to mark the OpenSpec live tasks complete
until the resulting evidence has been reviewed.

## Fast Path

Use one local parameter file instead of exporting every template input:

```bash
cp infra/envs/poc/apim.customer.example.bicepparam \
  infra/envs/poc/apim.customer.bicepparam

export APIM_FOUNDATION_PARAMETERS_FILE='infra/envs/poc/apim.customer.bicepparam'
```

Replace every angle-bracket fallback value or export the corresponding `APIM_*` environment
variable. Every parameter follows the same environment-backed pattern, and the local customer
file is ignored by Git. The POC template creates the approved Standard/static APIM platform
public IP, including its DNS label and `ProjectCode=APIM` tag.

`APIM_FOUNDATION_PARAMETERS_FILE` is used by both the explicit Azure deployment commands and the
validator. The legacy `FOUNDATION_PARAMETERS` alias remains supported.

The customer example defaults `APIM_PRIVATE_DNS_MODE` to `external`. This matches the observed
production pattern: custom corporate hostnames and certificates resolve through corporate DNS
servers reached through the hub. The deployment outputs `privateDnsHandoff` with the private IP
and required APIM hostnames for the DNS team. After live validation confirms those hostnames resolve
to the APIM private IPs and are reachable from the approved network, set
`APIM_EXTERNAL_DNS_VALIDATION_REFERENCE` to the non-secret evidence reference and redeploy Stage 1.

Run the three standard Azure checks:

```bash
az deployment group validate \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group what-if \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group create \
  --resource-group <apim-resource-group> \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"
```

The remaining sections are the advanced evidence and runtime-verification path.

## 1. Prerequisites

Run from Bash with Azure CLI 2.60 or later, `jq`, `curl`, and Bicep support through `az bicep`.
Use an identity with:

- read access to the existing VNet, APIM subnet, NSG, and route table;
- Contributor or equivalent deployment rights in the APIM resource group;
- permission to create APIM, private DNS, monitoring resources, and deployment records;
- access to an internal network that can resolve and reach the APIM private VIP for the runtime
  endpoint check.

Obtain customer approval for:

- the APIM subscription, resource group, region, service name, and Developer or Premium capacity;
- the existing APIM subnet and approved NSG;
- the approved route table, or the active tenant-policy exception that requires no route table;
- the subnet naming exception when the name does not match `apimsubnet-*`;
- the customer-approved public IP name, DNS label, and tags that the template will create;
- the corporate publisher email;
- blueprint-owned or policy-owned APIM resource diagnostic settings.

Do not commit raw customer resource IDs, subscription details, or command output. Store raw
evidence in the customer-approved evidence location and return a redacted summary.

## 2. Check Out the Pushed Branch

```bash
set -euo pipefail

git fetch origin
if git show-ref --verify --quiet refs/heads/feat/split-apim-foundry-deployment; then
  git switch feat/split-apim-foundry-deployment
else
  git switch --track origin/feat/split-apim-foundry-deployment
fi
git pull --ff-only origin feat/split-apim-foundry-deployment

git rev-parse --short HEAD
# Expected at or after: d6b1d19
```

## 3. Export Approved Stage 1 Values

Replace every angle-bracket value. Keep one of the route-table alternatives empty.

```bash
export AZURE_SUBSCRIPTION_ID='<customer-subscription-id>'
export APIM_FOUNDATION_PARAMETERS_FILE='infra/envs/poc/apim.customer.bicepparam'

export APIM_RESOURCE_GROUP='<apim-resource-group>'
export APIM_LOCATION='<approved-region>'
export APIM_SERVICE_NAME='<globally-unique-apim-name>'
export APIM_PUBLISHER_EMAIL='<corporate-admin-email>'
export APIM_PUBLISHER_NAME='<approved-publisher-name>'

export APIM_NETWORK_RESOURCE_GROUP='<network-resource-group>'
export APIM_VNET_NAME='<existing-vnet-name>'
export APIM_SUBNET_NAME='<existing-apim-subnet-name>'
export APIM_APPROVED_NSG_RESOURCE_ID='<approved-nsg-resource-id>'

# Route-table profile: set the approved ID and leave the exception empty.
export APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID='<approved-route-table-resource-id>'
export APIM_ROUTE_TABLE_EXCEPTION_REFERENCE=''

# Tenant-exception profile: leave the route-table ID empty and provide the evidence reference.
# export APIM_APPROVED_ROUTE_TABLE_RESOURCE_ID=''
# export APIM_ROUTE_TABLE_EXCEPTION_REFERENCE='<policy-assignment-or-approved-exception-reference>'

# Required only when APIM_SUBNET_NAME does not match apimsubnet-*.
export APIM_SUBNET_NAMING_EXCEPTION_REFERENCE='<approved-naming-exception-reference-or-empty>'

export APIM_PUBLIC_IP_NAME='<customer-approved-public-ip-name>'
export APIM_PUBLIC_IP_DNS_LABEL='<globally-unique-regional-dns-label>'
export APIM_PUBLIC_NETWORK_ACCESS='Enabled'
export APIM_DNS_RECORD_NAME="$APIM_SERVICE_NAME"
export APIM_SKU_NAME='Developer'
export APIM_SKU_CAPACITY='1'

export APIM_APP_INSIGHTS_NAME='<application-insights-name>'
export APIM_LOG_ANALYTICS_WORKSPACE_ID='<existing-workspace-resource-id-or-empty>'
export APIM_LOG_ANALYTICS_WORKSPACE_NAME='<workspace-name-if-created>'
export APIM_DIAGNOSTIC_SETTING_NAME='<diagnostic-setting-name>'
export APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP='<blueprint-or-policy>'
export APIM_CAPACITY_ALERT_NAME='<capacity-alert-name>'

az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az account show --query '{subscription:id,name:name,tenant:tenantId}' -o table
test -f "$APIM_FOUNDATION_PARAMETERS_FILE"
```

For the observed shared-hybrid-NSG tenant profile, use the tenant-exception route configuration:
the subnet must have no route table and the exception reference must identify the active policy
or approved customer decision.

## 4. Verify Prerequisite Resources

```bash
az group show --name "$APIM_RESOURCE_GROUP" \
  --query '{name:name,location:location,state:properties.provisioningState}' -o table

az network vnet subnet show \
  --resource-group "$APIM_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$APIM_VNET_NAME" \
  --name "$APIM_SUBNET_NAME" \
  --query '{
    name:name,
    prefix:addressPrefix,
    nsg:networkSecurityGroup.id,
    routeTable:routeTable.id,
    delegations:delegations[].serviceName,
    serviceEndpoints:serviceEndpoints[].service
  }' -o json

```

Expected:

- subnet name is `apimsubnet-*` or the naming exception is non-empty;
- subnet NSG exactly matches `APIM_APPROVED_NSG_RESOURCE_ID`;
- route table exactly matches the approved ID, or is absent when exception evidence is supplied;
- `delegations` is empty;
- service endpoints include Azure Active Directory, Key Vault, SQL, and Storage;
- public IP naming, DNS label, and `ProjectCode=APIM` tag are customer-approved; the template
  enforces Standard, Static, Regional, and `APIM_LOCATION`.

## 5. Run Offline Validation

```bash
OFFLINE_ONLY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

Expected: `Validation passed for mode: foundation`.

## 6. Run Foundation Preflight and Customer What-If

Choose a customer-approved local evidence directory:

```bash
export APIM_EVIDENCE_DIR='<customer-approved-local-evidence-directory>'
mkdir -p "$APIM_EVIDENCE_DIR"

VALIDATION_PHASE=preview \
RUN_WHAT_IF=false \
  specs/02-apim-ai-gateway/validation/validate.sh foundation \
  2>&1 | tee "$APIM_EVIDENCE_DIR/foundation-preflight.txt"

az deployment group validate \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE" \
  2>&1 | tee "$APIM_EVIDENCE_DIR/foundation-validate.txt"

az deployment group what-if \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation-preview \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE" \
  --result-format ResourceIdOnly \
  2>&1 | tee "$APIM_EVIDENCE_DIR/foundation-preview.txt"
```

Expected:

- the validator preflight exits `0` and prints `Foundation preview validation passed`;
- Azure validation succeeds and the what-if uses the populated customer parameter file;
- proposed resources are limited to APIM, private `azure-api.net` DNS, Application
  Insights/Log Analytics, APIM diagnostics, and the capacity alert;
- no `Microsoft.CognitiveServices`, Foundry role assignment, APIM backend, named-value model
  mapping, governed API, or product is proposed;
- no Foundry resource ID, endpoint, model, or permission was supplied.

If the diagnostic ownership is `policy`, the blueprint must not propose its own APIM resource
diagnostic setting. Azure Policy may add or remediate the setting separately.

The APIM logger and API diagnostic are locationless child resources after creation. Their
deployment requests explicitly carry the APIM region so the customer allowed-region policy can evaluate
them before the APIM resource provider discards that request-only metadata. If policy still
reports a null or disallowed location for `Microsoft.ApiManagement/service/loggers` or
`Microsoft.ApiManagement/service/diagnostics`, retain the validation output and request a policy
exclusion or exemption; changing the APIM region or using `global` is not an equivalent fix.

## 7. Deploy Stage 1

Review the preview before running:

```bash
az deployment group create \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE" \
  --query '{state:properties.provisioningState,outputs:properties.outputs}' \
  -o json | tee "$APIM_EVIDENCE_DIR/foundation-deployment.txt"
```

APIM provisioning can take 30–60 minutes. Expected deployment outputs:

- `apimVirtualNetworkType` is `Internal`;
- `apimPrincipalId` is non-empty;
- `privateIpAddresses` contains at least one address;
- `apimPublicIpPurpose` is `classic-internal-platform-management`;
- `integrationReadiness` is `not-deployed`;
- `foundationReadiness.status` is `deployed` when blueprint-owned DNS and diagnostics are ready, or
  remains `pending` until the required external DNS and policy-owned diagnostic validation
  references are supplied.

For policy-owned diagnostics, first run the runtime checks below and retain the redacted evidence
in the customer-approved evidence location. Then set
`APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE` to that real, non-placeholder evidence reference
and redeploy the unchanged Stage 1 template. The resulting `foundationReadiness` output records
the reference and reports observability and overall status as `deployed`; do not set the value
before the live diagnostic destination and categories have passed validation.

## 8. Run Runtime Smoke Checks

Run from a host connected to the deployment VNet or an explicitly linked network:

```bash
VALIDATION_PHASE=runtime \
RUN_WHAT_IF=false \
APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation \
  2>&1 | tee "$APIM_EVIDENCE_DIR/foundation-runtime.txt"
```

Expected:

- APIM uses the selected Developer or Premium SKU, is internal VNet-injected, and has a
  system-assigned principal;
- TLS 1.0/1.1 and the prohibited weak cipher are disabled;
- gateway, developer, portal, management, and SCM private DNS A records exist;
- each APIM hostname resolves to RFC1918 space and is reachable from the approved internal host;
- the platform public IP is not treated as a public gateway;
- diagnostics include enabled AllLogs and AllMetrics at the required destination;
- the average `Capacity` alert exists with `GreaterThan` and threshold `60`;
- integration remains absent/pending and no Foundry check executes.

If Azure Policy owns diagnostics, allow policy remediation to complete before rerunning runtime
validation. If the command is not run from an internal network, leave
`APIM_VALIDATE_ENDPOINT_REACHABILITY=false`; exit code `3` then correctly means the reachability
gate remains blocked.

## 9. Re-run the Unchanged Preview

Without changing any exported value or template:

```bash
az deployment group what-if \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation-idempotency-preview \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE" \
  --result-format ResourceIdOnly \
  2>&1 | tee "$APIM_EVIDENCE_DIR/foundation-idempotency-preview.txt"
```

Expected: no duplicate or unexpected APIM, identity, DNS, networking, workspace, Application
Insights, diagnostics, or capacity-alert changes. Policy-owned resources may appear only as
policy-owned effects and must not be overwritten by the template.

## 10. Return Redacted Evidence

Return:

1. Commit SHA tested.
2. Subscription alias and region, with subscription ID redacted.
3. Foundation preview resource-type summary and confirmation that no Foundry resource appeared.
4. Deployment provisioning state and redacted outputs.
5. Runtime validator result, including DNS/reachability, diagnostics, and alert checks.
6. Unchanged-preview summary.
7. Any policy remediation delay, denied action, or unexpected resource change.

After review, repository maintainers can update `foundation-preview.md`,
`foundation-runtime.md`, `idempotency.md`, #71, and OpenSpec tasks 2.8, 5.2, and 5.4. Stage 2
tasks remain unchecked until separate Foundry approval and integration evidence are available.
