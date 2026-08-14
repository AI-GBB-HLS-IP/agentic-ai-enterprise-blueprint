# Foundry API and private-network confirmation

## Status

**Incomplete — deployment code remains blocked until the unresolved gates below are closed.**

## Confirmed on 2026-08-14

- Target resource group: `rg-agent-factory-poc`
- Region: `eastus2`
- `Microsoft.CognitiveServices`, `Microsoft.Network`, `Microsoft.App`, `Microsoft.Storage`,
  `Microsoft.KeyVault`, and `Microsoft.Sql` providers are registered.
- Existing network prerequisites passed inspection:
  - `vnet-agent-factory-poc`
  - `snet-foundry` — `10.0.2.0/24`, delegated to `Microsoft.App/environments`
  - `snet-privateendpoints` — `10.0.4.0/24`
  - six existing private DNS zones linked to the VNet
- The Cognitive Services provider advertises current `accounts` and `accounts/projects`
  API versions including `2026-07-01` and `2026-07-15-preview`.
- Azure AI Services SKU `S0` is available in `eastus2`.

The prerequisite commands were run through Azure CLI. Re-run `validate.sh` to reproduce the
read-only network checks.

## Unresolved gates

1. Confirm the supported Foundry BYO VNet/network-injection property shape and API version for
   the selected Agent Service workload. Do not infer this from the provider version list alone.
2. Create or inspect the Foundry account before querying `privateLinkResources`; confirm the
   authoritative group IDs and DNS zones rather than hardcoding them.
3. Confirm whether the selected workload requires SQL or additional account-level resource
   references.
4. Confirm private-endpoint approval behavior in this subscription.
5. Confirm the authoritative delegated-subnet utilization signal.

## References

- https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks
- https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/agents-networking-deep-dive
- https://learn.microsoft.com/en-us/azure/foundry/how-to/configure-private-link
- https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts
- https://learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/accounts/projects
