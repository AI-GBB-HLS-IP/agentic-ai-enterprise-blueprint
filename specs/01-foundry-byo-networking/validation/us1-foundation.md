# US1 live foundation validation

Validation timestamp: 2026-08-14

Deployment: `foundry-agent-factory-poc-20260814`

## Result

US1 deployment succeeded in `rg-agent-factory-poc` / `eastus2`.

Created resources:

- Foundry account: `foundry-agent-factory-poc`
- Foundry project: `prj-agent-factory-poc`
- Model deployment: `gpt-4.1-mini`, version `2025-04-14`, Standard capacity `10`
- Storage account: `stagentfactorypoc`
- Key Vault: `kv-agent-factory-poc`
- Private endpoints: Foundry account, Storage Blob, and Key Vault

## Security state

- Foundry account public network access: `Disabled`
- Storage public network access: `Disabled`
- Key Vault public network access: `Disabled`
- Foundry private endpoint: `Approved`
- Storage private endpoint: `Approved`
- Key Vault private endpoint: `Approved`

## Pending VNet validation

Portal access from an internet-connected workstation is expected to show `Private network access required`.
DNS resolution, TCP reachability, and Foundry data-plane smoke testing remain pending until a client has
VNet connectivity through a Bastion-connected VM, point-to-site VPN, or ExpressRoute.

SQL was not provisioned because it is not required by the current POC workload.

## DNS zone gap found and fixed (2026-08-14)

Manual VNet validation from `vm-fnd-jbox` (private jump box, Bastion access) found that
`foundry-agent-factory-poc.services.ai.azure.com` resolved to a public IP instead of a private
address, even though `pe-foundry` was approved.

Root cause: per the official BYO VNet private-link table
(https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks), the Foundry
`account` private-link resource requires three zones on the same private endpoint DNS zone
group — `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, and
`privatelink.services.ai.azure.com`. Only the first zone was wired.

Fix:
- Added `privatelink.services.ai.azure.com` as a managed private DNS zone with a VNet link in
  `infra/envs/poc/foundry.bicep` (it did not previously exist in the network foundation).
- Extended `infra/modules/foundry/private-endpoint.bicep` and `main.bicep` to add `openai` and
  `services-ai` zone configs to the `pe-foundry` DNS zone group.
- Re-ran `az deployment group create` (`foundry-dns-fix-20260814`) to reconcile IaC state with
  the live fix. Result: `Succeeded`.

Post-fix validation from `vm-fnd-jbox`:

```text
nslookup foundry-agent-factory-poc.services.ai.azure.com
-> foundry-agent-factory-poc.privatelink.services.ai.azure.com
-> 10.0.4.7
```

All three Foundry account FQDNs now resolve to private `10.0.4.x` addresses.
