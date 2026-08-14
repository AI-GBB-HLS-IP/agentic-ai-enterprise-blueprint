# Research: Foundry with BYO Networking

## Decisions

### Resource model
- Use `Microsoft.CognitiveServices/accounts` (`kind: AIServices`, `sku: S0`) for the Foundry account and `accounts/projects` for the project.
- Use `accounts/deployments` for the approved model deployment. Deployment is account-scoped in the ARM model even though the model is consumed by a project.
- Use `Microsoft.Storage/storageAccounts`, `Microsoft.KeyVault/vaults`, and an optional SQL resource only when the selected workload requires it.

### Existing network consumption
- Treat `rg-agent-factory-poc`, `vnet-agent-factory-poc`, `snet-foundry`, and `snet-privateendpoints` as `existing` resources. Validate, but do not recreate or mutate, their address ranges and ownership.
- `snet-foundry` must remain delegated to `Microsoft.App/environments` and is the agent-service subnet. The existing `/24` provides the recommended headroom; validation should block at or above 80% utilization.
- Create private endpoints in `snet-privateendpoints` and attach DNS zone groups to the existing service-specific zones. Existing zones and VNet links are inputs, not resources owned by this feature.

### Private networking and ordering
- Set `publicNetworkAccess: Disabled` and a deny-by-default network ACL on the account and supporting services.
- Configure network injection/BYO VNet at account creation when the chosen Foundry Agent Service API supports it. Treat this as create-time-only for hosted agents.
- Create the project before the Foundry private endpoint where the service requires a provisioned project; this avoids the observed `AccountProvisioningStateInvalid` race.
- Discover private-link group IDs and required DNS zones from the target API/provider response rather than assuming a project-specific group ID.

### Model and quota parameters
- Make model name, version, format, deployment name, SKU/serving option, and capacity explicit parameters with no fallback model.
- Preflight regional model availability and quota. Capacity semantics are model/SKU-specific; do not infer TPM from capacity. Stop on insufficient quota or unavailable model.

## Risks and unresolved confirmations

1. **API version and BYO VNet schema:** The exact `networkInjections` shape and supported API version can vary by region and preview lifecycle. Confirm with the target subscription's resource provider/API schema before implementation.
2. **Private-link subresources/DNS:** Official samples commonly use `groupIds: ['account']`, while documentation describes account and project private access. Query `privateLinkResources` and confirm the required group IDs and zones (`privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, and/or `privatelink.services.ai.azure.com`) before hardcoding them.
3. **Supporting-resource contract:** Confirm whether the selected Foundry workload needs SQL and whether Foundry account properties must reference storage, Key Vault, and SQL IDs or identities.
4. **Model quota scope:** Current quotas may be subscription-shared, regional, or model-specific. Validate live quota and deployment availability immediately before deployment.
5. **Private endpoint approval:** Determine whether connections auto-approve in the POC subscription or require an explicit approval operation; validation must fail while any connection is pending or rejected.
6. **Subnet utilization signal:** Confirm the authoritative Azure metric/API for delegated-subnet IP utilization; otherwise use an explicitly documented conservative calculation and mark it as an approximation.

## Alternatives considered

- **Create a new VNet or DNS zones:** rejected because the network foundation is an explicit prerequisite and duplicate zones would break idempotency.
- **Portal-only BYO VNet configuration:** rejected as the primary path because infrastructure must be parameterized IaC; retain a documented manual gate only if no supported ARM/Bicep property exists.
- **Enable public fallback for deployment or smoke tests:** rejected by the private-by-default/no-bypass constitution principle.
- **Automatically choose another model or SKU:** rejected because AI CoE approval and quota are explicit inputs.

## Sources

- Microsoft Foundry resource template: https://learn.microsoft.com/en-us/azure/foundry/how-to/create-resource-template
- Cognitive Services accounts template: https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-06-01/accounts
- Foundry projects: https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects
- Foundry deployments: https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/deployments
- Agent Service virtual networks: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks
- Foundry private link: https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link
- Private endpoint DNS: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
- Model deployment types: https://learn.microsoft.com/en-us/azure/foundry/foundry-models/concepts/deployment-types
- Quotas and limits: https://learn.microsoft.com/en-us/azure/foundry/foundry-models/quotas-limits

