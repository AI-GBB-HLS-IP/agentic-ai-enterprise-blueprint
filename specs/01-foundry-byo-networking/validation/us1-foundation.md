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
