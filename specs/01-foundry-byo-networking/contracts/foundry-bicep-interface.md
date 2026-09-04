# Foundry Bicep Module Interface

The implementation should expose a resource-group-scoped Foundry module and an environment
parameter file. This is a design contract, not infrastructure code.

## Required parameters

- `location`, `foundryAccountName`, `projectName`
- Existing IDs: `vnetId`, `foundrySubnetId`, `privateEndpointSubnetId`
- Existing DNS zone IDs/names for Cognitive Services/Foundry, Storage Blob, Key Vault, and
  conditional Azure OpenAI/SQL
- `enableSql`
- Approved model: `modelDeploymentName`, `modelName`, `modelVersion`, `modelFormat`,
  `deploymentSku`, `deploymentCapacity`
- Network Foundation policy handoff: `publicNetworkAccessDisabled`, `localAuthDisabled`, and
  `allowedModelSkus` from the validated `policyInputs` object. The booleans must remain `true`;
  `allowedModelSkus` is a non-empty exact-SKU allowlist.
- `enableModelDeployment` and a quota/availability preflight assertion

## Outputs

- Account, project, supporting-resource, and private-endpoint resource IDs
- Model deployment ID and declared model metadata
- A structured validation/readiness result distinguishing existing, deployed, pending, and
  failed resources

## Contract invariants

The module must not create the existing VNet, subnets, DNS zones, or public IPs. It must fail
closed when required IDs are absent, the subnet properties do not match, private endpoint
connections are not approved, DNS integration is incomplete, or quota/model preflight fails.
It must also fail closed when the Network Foundation policy handoff is absent or invalid,
configure supported Foundry resources with public network access disabled and local
authentication disabled, and reject `deploymentSku` unless it is an exact member of
`allowedModelSkus` before creating the model deployment. The module must not replace the
allowlist with a default, wildcard, case-normalized, or alternate model selection.
