# POC environment deployment (`infra/envs/poc`)

This environment composes the Network Foundation MVP module.

## Prerequisites

- Azure CLI (`az`) with Bicep support
- Active Azure login (`az login`)
- Subscription selected (`az account set --subscription <SUBSCRIPTION_ID>`)
- Subscription permissions: Owner, or Contributor plus User Access Administrator (UAA is needed for
  role assignments, not for creating the network resources themselves). For deployment via
  `az deployment group create`, the deploying identity must have `Microsoft.Resources/deployments/*`
  permissions (included in Contributor/Owner).
- Entra ID permission to create security groups, or a tenant administrator (e.g., Global/Groups/User
  Administrator, per tenant policy) who can create the `platform-eng`, `ai-coe`, and `developers`
  groups before downstream RBAC work.

Run the documented preflight checks in `specs/00-network-foundation/spec.md` before deployment.

For the full ordered sequence, including validation gates, known deviations, and which steps are
not yet automated, follow
[`docs/deploy-00-network.md`](../../../docs/deploy-00-network.md).

## Validate before deploying

```bash
# FR-019/FR-020 policy inputs (keep the input file untracked)
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json

# Repository confidentiality gate
./scripts/network/scan-confidentiality.sh

# Deterministic validation suite
./tests/network/run-tests.sh
```

## Deploy

Resource-group topology is fully configurable, not fixed at three. Each template independently
accepts the resource group name(s) of the resources it depends on
(`networkResourceGroupName` on `foundry.bicep`/`apim.bicep`, `foundryResourceGroupName` on
`apim.bicep`), each defaulting to `resourceGroup().name` — i.e. "the RG I'm being deployed into."
That means the same three templates support any of these topologies (and combinations in between)
by choosing which RG name(s) you pass to `az group create`/`az deployment group create` and which
override params you set:

| Topology | RGs | How |
|---|---|---|
| Single RG | 1 | Deploy `main.bicep`, `foundry.bicep`, `apim.bicep` all into the same RG. Leave `networkResourceGroupName`/`foundryResourceGroupName` at their defaults. |
| Network isolated | 2 | Network in its own RG; Foundry + APIM share a second RG. Set `networkResourceGroupName` on both `foundry.customer.bicepparam` and `apim.bicepparam` to the network RG name; deploy `foundry.bicep` and `apim.bicep` into the shared second RG (`foundryResourceGroupName` on apim defaults correctly since it equals apim's own RG). |
| Foundry isolated | 2 | Network + APIM share one RG; Foundry gets its own. Deploy `main.bicep` and `apim.bicep` into the shared RG (network default works); set `foundryResourceGroupName` on `apim.bicepparam` to the Foundry RG name, and `networkResourceGroupName` on `foundry.customer.bicepparam` to the shared RG name. |
| Fully separated | 3 | Network, Foundry, and APIM each in their own RG (example below). Set both override params on `foundry.customer.bicepparam`/`apim.bicepparam`. |

None of this requires touching the module code — only which RG name(s) you deploy each template
into and which of the two override params you set in the `.bicepparam` files. The example below
uses the fully-separated (3 RG) topology; adapt the RG names/count per the table above.

```bash
LOCATION="eastus2"
NETWORK_RG="rg-agent-blueprint-poc-network"
FOUNDRY_RG="rg-agent-blueprint-poc-foundry"
APIM_RG="rg-agent-blueprint-poc-apim"

az group create --name "$NETWORK_RG" --location "$LOCATION"
az group create --name "$FOUNDRY_RG" --location "$LOCATION"
az group create --name "$APIM_RG" --location "$LOCATION"

# 1. Network foundation
az deployment group what-if \
  --resource-group "$NETWORK_RG" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json

az deployment group create \
  --resource-group "$NETWORK_RG" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json

# 2. Foundry (references the network RG's vnet/subnets/DNS zones)
cp infra/envs/poc/foundry.bicepparam.example \
   infra/envs/poc/foundry.customer.bicepparam

az deployment group what-if \
  --resource-group "$FOUNDRY_RG" \
  --template-file infra/envs/poc/foundry.bicep \
  --parameters infra/envs/poc/foundry.customer.bicepparam

az deployment group create \
  --resource-group "$FOUNDRY_RG" \
  --template-file infra/envs/poc/foundry.bicep \
  --parameters infra/envs/poc/foundry.customer.bicepparam

# 3. APIM (references the network RG's vnet/subnet and the Foundry RG's account)
# REQUIRED before every APIM deployment in hostnameMode preserve (default) or merge:
# capture the live custom domains. Skipping it fails the deployment (it would otherwise remove them).
export APIM_EXISTING_HOSTNAMES_JSON="$(scripts/apim/get-existing-hostnames.sh "$APIM_RG" "<apim-name>")"

az deployment group what-if \
  --resource-group "$APIM_RG" \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam

az deployment group create \
  --resource-group "$APIM_RG" \
  --template-file infra/envs/poc/apim.bicep \
  --parameters infra/envs/poc/apim.bicepparam
```

### APIM custom domains

> **Important:** custom domains that use an uploaded PFX certificate cannot be preserved. APIM
> never returns the certificate or its password, so `get-existing-hostnames.sh` omits them (and
> prints `[]` when they are the only custom domains). If your APIM has such domains, every
> deployment removes them unless you re-declare them in `hostnameConfigurations` with the PFX and
> password and deploy with `hostnameMode=merge` or `replace`. Keep the PFX files and passwords
> available for each deployment. Only Key Vault-backed and APIM-managed certificate domains are
> preserved automatically.

APIM replaces `hostnameConfigurations` on every deployment (including SKU changes), so omitting
domains removes them. `preserve` and `merge` therefore require the captured list and fail without
it. `hostnameMode` controls the result:

| Mode | Deployed domains | Use when |
|---|---|---|
| `preserve` (default) | Live domains captured by `get-existing-hostnames.sh` | Redeploying without domain changes |
| `merge` | Captured domains plus `hostnameConfigurations`; a declared entry replaces a captured one with the same type and hostName, and a declared non-`Proxy` type replaces the captured domain of that type. A declared `Proxy` with `defaultSslBinding` clears it on retained `Proxy` domains | Adding or updating a domain |
| `replace` | Only `hostnameConfigurations`; an empty list removes all domains. Does not need the capture step | Declarative ownership or removing a domain |

1. Run `get-existing-hostnames.sh` before every deployment in `preserve` or `merge` mode (step 3
   above). It prints the JSON array to stdout, so capture it in `APIM_EXISTING_HOSTNAMES_JSON`.
   On a first deployment it prints `[]`.
2. Key Vault-backed domains are captured automatically. Domains using an uploaded PFX are never
   returned by APIM; the script warns and omits them, so declare them in `hostnameConfigurations`
   with `merge` or `replace`.
3. Declare PFX domains with `certificateKey` entries (`Proxy` = gateway, `DeveloperPortal`,
   `Management`) and supply the base64 PFX and password through the secure
   `hostnameCertificates` parameter from environment variables or a pipeline secret. See
   `apim.customer.example.bicepparam`. Never commit certificate material.
4. Review `what-if` output for the `hostnameConfigurations` change before running `create`.
   Both parameter files accept `APIM_HOSTNAME_CONFIGURATIONS_JSON` (declared array) and
   secret `APIM_HOSTNAME_CERTIFICATES_JSON` (certificate-key object). The customer example
   retains its three placeholder declarations and individual PFX/password environment
   defaults; the JSON certificate object overrides matching keys. The standard file defaults
   to an empty declared array and empty certificate object. Never print or commit the
   certificate JSON.
5. Custom hostnames need operator-managed DNS/routing for this Internal APIM. Built-in mode
   creates the five built-in records when blueprint-owned; custom mode creates no DNS resources.

### APIM client endpoint selection (Stage 1)

Endpoint selection is separate from certificate `hostnameMode` and DNS ownership.

| `APIM_ENDPOINT_MODE` | `APIM_PRIVATE_DNS_MODE` | `APIM_ENDPOINT_ACCESS_PATH` |
|---|---|---|
| `built-in` (default) | `blueprint` or `external` | `direct-private` (default) |
| `custom` | `external` only | `direct-private` or `corporate-routed` |

Other combinations fail. Custom mode requires all three configured roles and performs no
built-in client checks; legacy portal/SCM are excluded only from custom client acceptance.
Azure-managed platform dependency/firewall requirements are unchanged.

```bash
export APIM_ENDPOINT_MODE=custom
export APIM_PRIVATE_DNS_MODE=external
export APIM_ENDPOINT_ACCESS_PATH=direct-private
export APIM_CUSTOM_ENDPOINT_HOSTNAMES='{"gateway":"api.example.com","developerPortal":"developer.example.com","management":"management.example.com"}'
```

Names are lowercase-normalized DNS hostnames, not URLs, ports, paths, wildcards, or built-in
names. The selected roles must match effective Proxy/DeveloperPortal/Management bindings;
capture and re-declare manual PFX certificates with merge/replace as described above.
Built-in `apimGatewayHostname` remains for compatibility; use additive
`selectedGatewayHostname`, `apimGatewayUrl`, and `endpointAccess` for client settings.
Custom `privateDnsHandoff` lists only those three selected endpoints and records exclusions.

`APIM_ENDPOINT_VALIDATION_EVIDENCE` is JSON extending the generic validation contract
(`specs/00-network-foundation/contracts/validation-evidence.md`). Keep its base fields generic;
replace extension placeholders only in ignored inputs/handoffs and approved evidence storage.
The following is a **redacted shape, not passing deployment evidence**:

```json
{
  "validationType": "apim-endpoint-access",
  "status": "blocked",
  "owner": "network-owner",
  "scope": "apim-foundation",
  "approvalReference": "approval-generic-001",
  "evidenceSummary": "Endpoint validation and approved routing evidence pending.",
  "timestampUtc": "2026-10-11T00:00:00Z",
  "apimServiceId": "<selected-apim-service-id>",
  "endpointMode": "custom",
  "endpointAccessPath": "corporate-routed",
  "selectedHostnames": {
    "gateway": "api.example.com",
    "developerPortal": "developer.example.com",
    "management": "management.example.com"
  },
  "validationReference": "<retained-validation-record>",
  "routingApprovalReference": "<network-owner-route-approval>"
}
```

All base/extension fields must be non-empty strings except the exact three-role hostname map.
`validationType` must identify this gate; `timestampUtc` is ISO-8601 UTC, with no timestamp
aliases. `validationReference` must be non-placeholder. Corporate routing additionally
requires `owner: network-owner` and a separate non-placeholder `routingApprovalReference`
identifying retained approval of the intended Internal APIM upstream and approved client path
without unapproved public exposure. It cannot be inferred from an IP range or HTTP response.

Direct-private checks require DNS equality to live APIM private IPs and certificate-validated
TLS. Corporate routing additionally requires current approval; DNS/TLS are measurements,
upstream identity/routing are operator attestation. Missing evidence leaves custom DNS readiness
pending; fail/blocked cannot advance; invalid or context-mismatched evidence fails explicitly.
Only complete matching pass evidence, with all other foundation gates, advances readiness.
Do not populate the legacy `APIM_EXTERNAL_DNS_VALIDATION_REFERENCE` in custom mode.
ARM checks structure/context, not timestamp validity or approval authenticity.
Revalidate after service/hostname/route/certificate changes, preview/redeploy foundation,
and retain the handoff from that exact deployment before Stage 2. Client transport never proves
private APIM-to-Foundry connectivity or managed-identity authorization.

Environment variables must be present in the shell that runs Azure CLI. WSL exports are not
automatically forwarded to Windows processes; use one environment consistently or explicitly
forward only the required variables without printing certificates, passwords, keys, or payloads.

### Selected Stage 2 and Client Handoff

Copy `apimServiceId`, `foundationReadiness`, and `endpointAccess` from the **exact validated**
foundation deployment into `APIM_STAGE1_SERVICE_ID`, `APIM_STAGE1_FOUNDATION_READINESS`,
and `APIM_STAGE1_ENDPOINT_ACCESS`. Retain the same endpoint mode/path/custom hostname map in
both integration parameter files. Legacy metadata-free handoffs permit only built-in/direct-private.
Stage 2 checks selected service/context, complete passing custom evidence, and the live gateway;
it references APIM rather than redeploying APIM/DNS/monitoring.

```bash
export APIM_STAGE1_ENDPOINT_ACCESS="$(az deployment group show \
  --resource-group "$APIM_RESOURCE_GROUP" --name apim-foundation \
  --query properties.outputs.endpointAccess.value -o json)"
export APIM_GATEWAY_URL="$(jq -er '.selectedGatewayUrl' <<<"$APIM_STAGE1_ENDPOINT_ACCESS")"
```

Populate project/portal `APIM_URL`, stored URL settings, and CI `APIM_GATEWAY_URL` from that
selected value; retain existing model/MCP/A2A paths and do not rewrite independent Foundry
or API Center endpoints. Integration emits `apimGatewayUrl` (origin) and `apimClientUrl`
(origin plus configured `apiPath`). Runtime smoke requests append `/chat/completions`.
`APIM_INTEGRATION_REQUEST_URL` overrides must use the selected HTTPS host and exact API
path, no userinfo/query/fragment, and implicit or explicit 443. Other ports are rejected before
credentials. Authorized model/identity/telemetry acceptance remains separate and mandatory.

## Verify

```bash
az network vnet subnet list \
  --resource-group "$NETWORK_RG" \
  --vnet-name vnet-agent-factory-poc \
  --query "[].{name:name,prefix:addressPrefix,delegations:delegations[*].serviceName,nsg:networkSecurityGroup.id}" \
  --output table

az network private-dns zone list \
  --resource-group "$NETWORK_RG" \
  --query "[].name" \
  --output table

# Private-by-default check: expect no public IP unless Bastion is intentionally enabled
az network public-ip list --resource-group "$NETWORK_RG" --query "[].name" --output table
```

## Bastion validation

Azure Bastion is **optional and disabled by default** in the approved design. When it is disabled,
the deployment must contain no `AzureBastionSubnet`, no Bastion host, and no public IP, and this
section does not apply.

> **Current deviation**: `main.bicep` still deploys Bastion unconditionally and exposes no
> `deployBastion` parameter. Making Bastion conditional is tracked by tasks T025 and T059-T063.

When Bastion is intentionally enabled, the deployment includes an Azure Bastion Basic host and its
required Standard static public IP.
For a full interactive Bastion validation, create a temporary test VM without a public IP in
`hybridsubnet-privateendpoints`, connect through the Azure Portal, and run `nslookup` for a private
endpoint record. Delete the test VM and its NIC/disk after validation.

The Basic SKU supports portal-based Bastion access but does not support the Azure CLI native-client
or tunnel commands. Use Standard or Premium if CLI/SSH tunnel validation is required. For a
non-interactive DNS-only check, Azure Run Command can execute `nslookup` inside the private VM:

```bash
az vm run-command invoke \
  --resource-group "$NETWORK_RG" \
  --name vm-dns-test \
  --command-id RunShellScript \
  --scripts 'nslookup validation-endpoint.privatelink.openai.azure.com'
```

The validation record is temporary and must be removed with:

```bash
az network private-dns record-set a delete \
  --resource-group "$NETWORK_RG" \
  --zone-name privatelink.openai.azure.com \
  --name validation-endpoint \
  --yes
```

Remove the temporary VM and attached resources after validation:

```bash
VM_NAME="vm-dns-test"
NIC_ID="$(az vm show --resource-group "$NETWORK_RG" --name "$VM_NAME" --query 'networkProfile.networkInterfaces[0].id' -o tsv)"
NIC_NAME="${NIC_ID##*/}"
DISK_NAME="$(az vm show --resource-group "$NETWORK_RG" --name "$VM_NAME" \
  --query 'storageProfile.osDisk.name' -o tsv)"

az vm delete --resource-group "$NETWORK_RG" --name "$VM_NAME" --yes
az network nic delete --resource-group "$NETWORK_RG" --name "$NIC_NAME"
az disk delete --resource-group "$NETWORK_RG" --name "$DISK_NAME" --yes
```

- Parameters are in `network.parameters.json`; update `location` and names as needed.
- Azure `what-if` may report platform-generated Bastion `dnsName`/`publicUri` fields as modified;
  these are read-only service properties and are expected false positives.
