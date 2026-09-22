# Quickstart: Staged APIM AI Gateway

## Stage 1 — APIM Foundation

Stage 1 requires Azure networking and APIM approvals only. Foundry may be unavailable.

Use one untracked customer parameter file for Stage 1 parameter resolution:

```bash
cp infra/envs/poc/apim.customer.example.bicepparam \
  infra/envs/poc/apim.customer.bicepparam
```

Replace the example fallback values in that file, or export the corresponding environment
variables. The Bicep parameter file resolves its `readEnvironmentVariable` values when Azure CLI
runs; the validator also loads the selected file's defaults for live checks, while already-exported
values take precedence. This is file-driven, not entirely file-only: the deployment subscription
and resource group remain Azure CLI inputs, and runtime validation still requires values that are
not parameters in the file, including `APIM_RESOURCE_GROUP`. For the complete Stage 1 runtime
value list, use [`validation/README.md`](validation/README.md).

Select the same file for deployment and validation:

```bash
export APIM_SERVICE_TAGS='{"Environment":"Example","Owner":"ApiPlatform"}'
export APIM_PUBLIC_IP_TAGS='{"Environment":"Example","Owner":"NetworkPlatform"}'
export APIM_LOG_ANALYTICS_WORKSPACE_TAGS='{"Environment":"Example","Owner":"ObservabilityPlatform"}'
export APIM_APP_INSIGHTS_TAGS='{"Environment":"Example","Owner":"ApplicationPlatform"}'
export APIM_CAPACITY_ALERT_TAGS='{"Environment":"Example","Owner":"OperationsPlatform"}'
export APIM_PRIVATE_DNS_ZONE_TAGS='{"Environment":"Example","Owner":"DnsPlatform"}'
export APIM_PRIVATE_DNS_VNET_LINK_TAGS='{"Environment":"Example","Owner":"DnsPlatform"}'
```

These sanitized examples demonstrate independent tag objects; replace them with approved
deployment-time values and do not commit live customer tag data. Omitted new tag variables
default to `{}`. `APIM_PUBLIC_IP_TAGS` retains the mandatory `ProjectCode=APIM` override.
Workspace tags apply only when the template creates the workspace, and private DNS tags apply
only in `blueprint` DNS mode. Existing workspaces and customer-managed DNS resources are never
retagged.

Then validate, preview, and deploy:

```bash
export APIM_FOUNDATION_PARAMETERS_FILE='infra/envs/poc/apim.customer.bicepparam'
export APIM_RESOURCE_GROUP='<apim-resource-group>'

az deployment group validate \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group what-if \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"

az deployment group create \
  --resource-group "$APIM_RESOURCE_GROUP" \
  --name apim-foundation \
  --template-file infra/envs/poc/apim.bicep \
  --parameters "$APIM_FOUNDATION_PARAMETERS_FILE"
```

The template creates the customer-named Standard/static APIM platform public IP, DNS label, and
`ProjectCode=APIM` tag. It applies each other supplied tag object only to its corresponding
taggable resource. APIM logger and diagnostic children, the Azure Monitor diagnostic setting,
and private DNS A records do not support independent tag inputs. The customer example defaults
`APIM_PRIVATE_DNS_MODE` to `external` for customer-managed corporate DNS through the hub. Verify
the preview contains only APIM foundation, public IP, monitoring, and alert resources and no
Foundry resources or workload-owned private DNS zone.

After deployment, use the advanced validator only for runtime evidence:

```bash
VALIDATION_PHASE=runtime \
RUN_WHAT_IF=false \
APIM_VALIDATE_ENDPOINT_REACHABILITY=true \
  specs/02-apim-ai-gateway/validation/validate.sh foundation
```

For evidence capture and the unchanged-preview procedure, see
[`validation/stage1-smoke-test.md`](validation/stage1-smoke-test.md).

With the customer example's default `APIM_DIAGNOSTIC_SETTINGS_OWNERSHIP=policy`, the initial
checkpoint is `foundationReadiness.status=pending` and `integrationReadiness=not-deployed`.
Readiness remains pending until the policy-created diagnostic setting is verified with enabled
`AllLogs` and `AllMetrics` sent to the selected workspace. Store the redacted runtime evidence,
set `APIM_POLICY_DIAGNOSTICS_VALIDATION_REFERENCE` to its real non-placeholder reference, and
redeploy the unchanged Stage 1 template; only that redeployment records the evidence and can
produce `foundationReadiness.status=deployed`. Do not claim deployed readiness before those
steps. If the customer explicitly selects `blueprint` diagnostics ownership, the template owns
the setting instead, but runtime checks and the other Stage 1 gates still apply.

The approved classic-tier public IP may exist for platform management; validate that APIM service
endpoints remain internal instead of treating the public IP resource itself as exposure.

## Optional Enterprise DNS Extension

The default private `azure-api.net` zone supports the deployment VNet and explicitly linked
networks. For broader enterprise resolution, separately obtain approved custom domains and CA
certificates, configure APIM custom hostnames, and request internal DNS A records to the APIM
private VIP.

## Stage 2 — Foundry Integration

Begin only after Stage 1 is ready and customer Foundry governance is complete.

1. Export the validated Stage 1 outputs as `APIM_STAGE1_SERVICE_ID` and the JSON
   `APIM_STAGE1_FOUNDATION_READINESS`, set
   `APIM_INTEGRATION_PARAMETERS_FILE='infra/envs/poc/apim-foundry-integration.bicepparam'`, and
   populate the selected parameter file's environment-backed values for the Foundry account,
   governance evidence, explicitly approved regions, approved model mappings, and API policy
   settings. Values with empty defaults, including the Stage 1 handoff and governance evidence,
   must be exported; they cannot be inferred from the parameter file name.
2. Run integration preflight:

   ```bash
   specs/02-apim-ai-gateway/validation/validate.sh integration
   ```

3. Preview integration-owned changes:

   ```bash
   az deployment group what-if \
     --resource-group "$APIM_RESOURCE_GROUP" \
     --name apim-foundry-integration-preview \
     --template-file infra/envs/poc/apim-foundry-integration.bicep \
     --parameters "$APIM_INTEGRATION_PARAMETERS_FILE" \
     --result-format ResourceIdOnly
   ```

4. Confirm the preview adds only the Foundry account-scoped role assignment and APIM
   backend/model/API/product/policies. It must not declare APIM, DNS, workspace, Application
   Insights, diagnostic settings, or alerts.
5. Deploy and validate:

   ```bash
   az deployment group create \
     --resource-group "$APIM_RESOURCE_GROUP" \
     --name apim-foundry-integration \
     --template-file infra/envs/poc/apim-foundry-integration.bicep \
     --parameters "$APIM_INTEGRATION_PARAMETERS_FILE"

   specs/02-apim-ai-gateway/validation/validate.sh integration
   ```

6. Record `validation/integration-runtime.md` with authorized, unsupported-model,
   unauthenticated, and telemetry results.

Use `validate.sh all` to run both stages in order when every Stage 2 prerequisite is available.
