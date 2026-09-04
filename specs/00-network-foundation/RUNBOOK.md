# Network Foundation Runbook

Ordered, executable sequence for validating and deploying the Network Foundation against a real
subscription.

This runbook is deliberately explicit about **what works today** and **what is not implemented
yet**, so a live walkthrough surfaces gaps instead of failing silently.

- Design contract: [`spec.md`](spec.md), [`plan.md`](plan.md)
- Parameter contract: [`contracts/deployment-parameters.md`](contracts/deployment-parameters.md)
- Validation gates: [`quickstart.md`](quickstart.md)
- Task backlog: [`tasks.md`](tasks.md)

## Status legend

| Symbol | Meaning |
|---|---|
| READY | Implemented; can be run now |
| MANUAL | Works, but review is manual because the automated gate is not implemented yet |
| PENDING | Not implemented; tracked as a task |

## Scope of this runbook

Greenfield mode only. Brownfield (existing VNet) is PENDING across Phase 5 and has no entry point
yet, so it cannot be executed today.

---

## Step 0 — Tooling

**Status**: READY

```bash
az version
az bicep version
jq --version
python3 --version
```

Install anything missing before continuing. `az bicep install --upgrade` provisions Bicep.

---

## Step 1 — Authenticate and select the subscription

**Status**: READY

```bash
az login
az account set --subscription "<subscription-id>"
az account show --query "{name:name, id:id, tenantId:tenantId, state:state}" --output table
```

Expected: the intended subscription is selected and `state` is `Enabled`.

Do not paste the returned identifiers into any tracked file.

---

## Step 2 — Confirm permissions and provider registration

**Status**: MANUAL — the automated validator is PENDING (task T017,
`scripts/network/validate-deployment-prerequisites.sh`)

```bash
# Effective role assignments for the signed-in identity
az role assignment list \
  --assignee "$(az ad signed-in-user show --query id --output tsv)" \
  --query "[].{role:roleDefinitionName, scope:scope}" \
  --output table

# Resource provider registration
az provider show --namespace Microsoft.Network --query registrationState --output tsv
```

Expected:

- Owner, or Contributor plus User Access Administrator, at the target scope.
  Contributor alone is sufficient for the network resources in this step; User Access
  Administrator is required later for role assignments.
- `Microsoft.Network` returns `Registered`. If not:

```bash
az provider register --namespace Microsoft.Network --wait
```

---

## Step 3 — Confirm region and quota

**Status**: MANUAL — automated quota-approval gate is PENDING (task T017)

```bash
LOCATION="<azure-region>"

az cognitiveservices usage list --location "$LOCATION" --output table
```

Expected: available tokens-per-minute for the intended models meets or exceeds the planned POC
traffic estimate. If it does not, file and obtain a quota increase before deploying. Record the
approval reference outside the repository, per
[`contracts/validation-evidence.md`](contracts/validation-evidence.md).

Do not commit raw quota output.

---

## Step 4 — Prepare and validate policy inputs

**Status**: READY (validator) / PENDING (template wiring, task T074)

Create an **untracked** file, for example `policy-inputs.local.json`:

```json
{
  "policyInputs": {
    "publicNetworkAccessDisabled": true,
    "localAuthDisabled": true,
    "allowedModelSkus": [
      "generic-model-sku-a",
      "generic-model-sku-b"
    ]
  }
}
```

Replace the SKU strings with the exact SKUs approved for your environment.

```bash
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json
```

Expected: the validator echoes the accepted object. It fails closed when either boolean is
missing, non-boolean, or `false`, and when `allowedModelSkus` is missing, empty, duplicated,
whitespace-only, or contains wildcard or pattern syntax.

> Known gap: `infra/envs/poc/main.bicep` does not yet accept `policyInputs`, so the validated
> object is not forwarded to the template. Validation is standalone until task T074 lands.

---

## Step 5 — Review deployment parameters

**Status**: READY

Greenfield defaults live in `infra/envs/poc/network.parameters.json`:

| Parameter | Default | Notes |
|---|---|---|
| `location` | `eastus2` | Change to your approved region |
| `vnetName` | `vnet-agent-factory-poc` | Blueprint-owned |
| `vnetAddressSpace` | `10.0.0.0/16` | Fixed greenfield supernet |
| `apimSubnetPrefix` | `10.0.1.0/24` | APIM (VNet-injected) |
| `foundrySubnetPrefix` | `10.0.2.0/24` | Delegated to `Microsoft.App/environments` |
| `computeSubnetPrefix` | `10.0.3.0/24` | Gateway-path egress only |
| `privateEndpointsSubnetPrefix` | `10.0.4.0/24` | Private endpoint policies disabled |
| `cicdAgentsSubnetPrefix` | `10.0.5.0/24` | Build agents |
| `bastionSubnetPrefix` | `10.0.6.0/26` | Only when Bastion is enabled |
| `apimNsgName` / `computeNsgName` | `nsg-apim` / `nsg-compute` | Blueprint-owned |
| `privateDnsZoneNames` | six `privatelink.*` zones | Blueprint-owned zones and links |

Set `location` to your approved region. Keep the address plan unless it collides with existing
connectivity.

> Known gap: Bastion is currently **always** deployed. The approved design makes Bastion optional
> and disabled by default, with five workload subnets. See "Known deviations" below.

---

## Step 6 — Build the template

**Status**: READY

```bash
az bicep build --file infra/envs/poc/main.bicep --stdout > /dev/null && echo "build OK"
```

Expected: no errors. This is a pure compile check and touches no Azure resource.

---

## Step 7 — Create the resource group

**Status**: READY

```bash
RG_NAME="<blueprint-resource-group>"
LOCATION="<azure-region>"

az group create --name "$RG_NAME" --location "$LOCATION"
```

---

## Step 8 — Preview changes with what-if

**Status**: MANUAL — the automated allowlist gate is PENDING (task T027,
`scripts/network/validate-greenfield-what-if.sh`)

```bash
az deployment group what-if \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json
```

Review manually and confirm that the preview proposes only:

- one blueprint-owned VNet;
- the workload subnets from Step 5;
- the two blueprint-owned NSGs;
- the six Private DNS zones and their VNet links;
- Bastion resources only if Bastion is intentionally enabled.

Reject the preview if it proposes any delete, any change to a resource the blueprint does not own,
or any public IP other than an intentionally enabled Bastion public IP.

Do not commit the what-if output; `.gitignore` already excludes the documented temporary paths.

---

## Step 9 — Deploy

**Status**: READY

```bash
az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json \
  --name network-foundation
```

---

## Step 10 — Verify the deployed network

**Status**: READY

```bash
az network vnet subnet list \
  --resource-group "$RG_NAME" \
  --vnet-name vnet-agent-factory-poc \
  --query "[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName, nsg:networkSecurityGroup.id}" \
  --output table

az network private-dns zone list \
  --resource-group "$RG_NAME" \
  --query "[].{zone:name, links:numberOfVirtualNetworkLinks}" \
  --output table

# Private-by-default check: expect no public IP unless Bastion is intentionally enabled
az network public-ip list --resource-group "$RG_NAME" --query "[].name" --output table
```

Expected:

- every subnet has the approved name and prefix;
- `snet-foundry` shows the `Microsoft.App/environments` delegation;
- `snet-apim` and `snet-compute` show their NSG associations;
- each Private DNS zone reports one VNet link;
- no public IP exists unless Bastion is intentionally enabled.

---

## Step 11 — Confirm idempotency

**Status**: READY

Re-run Step 8 with unchanged parameters.

Expected: no changes. Azure may report Bastion `dnsName` and `publicUri` as modified; these are
read-only platform properties and are expected false positives when Bastion is deployed.

---

## Step 12 — Confidentiality gate before committing

**Status**: READY

```bash
./scripts/network/scan-confidentiality.sh
./tests/network/run-tests.sh
```

Expected: both pass. The scan fails closed on subscription or tenant GUIDs, resolved ARM resource
IDs, real email addresses, absolute home directory paths, and private address ranges outside the
blueprint's own plan. Placeholder tokens, documented sample domains, public Microsoft role
definition and application IDs, and the approved greenfield address plan are permitted.

---

## Known deviations from the approved design

These are real gaps to confirm during a live walkthrough.

| # | Deviation | Impact | Task |
|---|---|---|---|
| 1 | Bastion, its subnet, and its public IP are always deployed | Violates the optional-Bastion contract and introduces a public IP that may be unwanted | T005, T059-T063 |
| 2 | `main.bicep` has no `deployBastion` parameter | Bastion cannot be disabled without editing the template | T025, T060 |
| 3 | `main.bicep` accepts no `policyInputs` | The validated policy object is not forwarded downstream | T074 |
| 4 | `main.bicep` accepts no `tags` object | Policy-required tags cannot be supplied at deployment time | T026 |
| 5 | No `subnets.bicep`; subnets are declared inline | Diverges from the shared serialized-write module design | T009, T022 |
| 6 | No prerequisite or quota validator | Steps 2 and 3 remain manual | T017 |
| 7 | No greenfield what-if allowlist validator | Step 8 review remains manual | T027 |
| 8 | No brownfield entry points or discovery tooling | Existing-VNet mode cannot be executed | Phase 5 |

## What cannot be executed today

- Brownfield discovery, capacity calculation, and preflight
- Brownfield network-owner and DNS-owner stages
- Automated what-if boundary enforcement
- Bastion-disabled deployment without editing the template
