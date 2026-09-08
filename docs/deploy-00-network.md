# Deploy the Network Foundation (Chapter 00)

**This is the only document you need to deploy Chapter 00.** It covers both deployment modes end
to end: what to change, what to run, and what to check.

The `specs/00-network-foundation/` folder is design history and requirements. You do not need to
read it to deploy. Links to it appear at the bottom if you want the reasoning behind a decision.

---

## 1. Pick your mode

| | Greenfield | Brownfield |
| --- | --- | --- |
| **Use when** | You own the whole address space and can create a VNet | A network admin gives you an existing VNet |
| **Creates the VNet?** | Yes | No — writes subnets into theirs |
| **Entry point** | `infra/envs/poc/main.bicep` | `infra/envs/poc/brownfield-network.bicep`, then `brownfield-dns.bicep` |
| **Parameters** | `infra/envs/poc/network.parameters.json` (tracked) | `brownfield-*.bicepparam` (you create, git-ignored) |
| **Stages** | One | Two — network owner, then DNS owner |
| **Go to** | [Section 4](#4-greenfield-deployment) | [Section 5](#5-brownfield-deployment) |

Both modes produce the same shape: five purpose-keyed subnets and eight private DNS zones.

---

## 2. What is automated today

Read this before you start. Several safety gates are **not built yet**, so parts of the process
are manual. This table is the single source of truth for automation status; task IDs refer to
[`specs/00-network-foundation/tasks.md`](../specs/00-network-foundation/tasks.md).

| Capability | Greenfield | Brownfield | Missing piece |
| --- | --- | --- | --- |
| Template compiles | ✅ | ✅ | — |
| Deployment runs | ✅ | ✅ | — |
| Policy input validation | ✅ | ✅ | wiring into the template (T074) |
| Deployment-time `tags` object | ❌ | ❌ | T026 |
| Confidentiality scan | ✅ | ✅ | — |
| Prerequisite / quota check | ⚠️ manual | ⚠️ manual | T017 |
| VNet discovery | n/a | ⚠️ manual | T032 |
| Subnet capacity sizing | n/a | ⚠️ manual | T033 |
| Fail-closed preflight | n/a | ⚠️ manual | T039 |
| `what-if` boundary enforcement | ⚠️ manual | ⚠️ manual | T027 / T047 / T053 |
| Optional Bastion | ❌ always deployed | n/a | T005, T059–T063 |

⚠️ means it works, but **you** must do the checking. Every manual step below tells you exactly
what to look for.

> Any `./scripts/network/<name>.sh` referenced in `specs/` that is not listed in
> [Section 7](#7-scripts-that-exist) does not exist yet. Only `validate-policy-inputs.sh` and
> `scan-confidentiality.sh` are implemented.

---

## 3. Prerequisites (both modes)

```bash
az version && az bicep version && jq --version && python3 --version
az login
az account set --subscription "<subscription-id>"
az account show --query "{name:name, id:id, state:state}" -o table
```

Expected: the intended subscription, `state` is `Enabled`.

You need **Owner**, or **Contributor + User Access Administrator**, at the target scope.
Contributor alone covers the network resources here; User Access Administrator is required later
for role assignments in Chapter 01.

```bash
az role assignment list \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table

az provider show --namespace Microsoft.Network --query registrationState -o tsv   # want: Registered
```

If not registered: `az provider register --namespace Microsoft.Network --wait`

**Never paste returned subscription or tenant IDs into a tracked file.**

### Policy inputs (optional, both modes)

Create an untracked `policy-inputs.local.json`:

```json
{
  "policyInputs": {
    "publicNetworkAccessDisabled": true,
    "localAuthDisabled": true,
    "allowedModelSkus": ["<approved-sku-a>", "<approved-sku-b>"]
  }
}
```

```bash
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json
```

> The templates do not consume this object yet (T074), so validation is standalone for now.

---

## 4. Greenfield deployment

### 4.1 What to change

Edit `infra/envs/poc/network.parameters.json`. In practice you change **only `location`**, unless
the address plan collides with existing connectivity — the sizing is fixed by design.

| Parameter | Default | Change it? |
| --- | --- | --- |
| `location` | `eastus2` | **Yes** — your approved region |
| `vnetAddressSpace` | `10.0.0.0/16` | Only on collision |
| `apimSubnetPrefix` | `10.0.1.0/24` | Only on collision |
| `foundrySubnetPrefix` | `10.0.2.0/24` | Only on collision |
| `computeSubnetPrefix` | `10.0.3.0/24` | Only on collision |
| `privateEndpointsSubnetPrefix` | `10.0.4.0/24` | Only on collision |
| `cicdAgentsSubnetPrefix` | `10.0.5.0/24` | Only on collision |
| `bastionSubnetPrefix` | `10.0.6.0/26` | Only on collision |

### 4.2 Run it

```bash
RG_NAME="<blueprint-resource-group>"
LOCATION="<azure-region>"

az bicep build --file infra/envs/poc/main.bicep --stdout > /dev/null && echo "build OK"
az group create --name "$RG_NAME" --location "$LOCATION"

az deployment group what-if \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json
```

**Review the preview manually** (T027 not built). Accept only: one VNet, the five workload
subnets, `AzureBastionSubnet`, two NSGs, eight private DNS zones and their links, and the Bastion
host plus its public IP. Reject any delete, any change to a resource the blueprint does not own,
or any public IP other than Bastion's.

> **Bastion is always deployed today**, including a public IP. The approved design makes it
> optional and disabled by default, but `main.bicep` has no `deployBastion` parameter yet
> (T005, T025, T059–T063). If a public IP is unacceptable in your environment, stop here.

```bash
az deployment group create \
  --resource-group "$RG_NAME" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json \
  --name network-foundation
```

Then verify with [Section 6](#6-verify).

---

## 5. Brownfield deployment

Brownfield writes subnets **into someone else's VNet**. Read this warning before anything else.

> ### ⚠ A subnet name collision is destructive
>
> `subnets.bicep` writes each subnet as a plain child PUT, building the request body from a fixed
> property set (`addressPrefix`, `privateEndpointNetworkPolicies`, optionally one delegation and
> one NSG). A subnet PUT replaces the entire object. So if a name you request **already exists**
> in the target VNet:
>
> - its address prefix, delegation and NSG association are replaced; and
> - every property the template does not send — **route table (UDR), service endpoints, NAT
>   gateway** — is absent from the request and is therefore **removed**.
>
> There is no `routeTableId` parameter, so a UDR can neither be attached nor preserved. In a
> forced-tunneling environment, silently dropping a UDR can blackhole egress or bypass an
> inspection appliance. **No preflight detects this yet** — [step 5.3](#53-preflight-manual--t039)
> is how you catch it.

### 5.1 Discover the existing VNet (manual — T032)

All read-only. Save the output somewhere untracked.

```bash
RG=<existing-vnet-resource-group>
VNET=<existing-vnet-name>

az network vnet show -g "$RG" -n "$VNET" \
  --query "{addressSpace:addressSpace.addressPrefixes, dnsServers:dhcpOptions.dnsServers}" -o json

az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name, prefix:addressPrefix, nsg:networkSecurityGroup.id, \
routeTable:routeTable.id, delegation:delegations[0].serviceName}" -o table

az network vnet peering list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name, state:peeringState}" -o table
```

The `name` and `routeTable` columns drive the collision check in step 5.3.

### 5.2 Size the subnets and write the parameter file

Sizing minimums:

| Subnet | Platform minimum | Recommended |
| --- | --- | --- |
| Foundry (delegated) | `/27` | `/26` or larger |
| APIM (classic Premium, VNet-injected) | `/29` | `/27` or larger |
| Private endpoints | endpoint count + 5 Azure-reserved + growth | |
| Compute, CI/CD agents | workload + 5 Azure-reserved + growth | |

A `/25` allocation fits exactly: `.0/26` foundry, `.64/28` apim, `.80/28` private endpoints,
`.96/28` compute, `.112/28` cicdagents. **Get IPAM approval before continuing.**

Create the parameter file — it is already git-ignored:

```bash
cp infra/envs/poc/brownfield-network.bicepparam.example \
   infra/envs/poc/brownfield-network.bicepparam
```

Replace **every** `<placeholder>` in the copy:

| Parameter | Value comes from |
| --- | --- |
| `existingVnetName`, `existingVnetResourceGroupName` | the network admin |
| `location` | the existing VNet's region |
| the five `*SubnetPrefix` | your IPAM-approved sizing above |
| the five `*SubnetName` | defaults are fine **unless** the name already exists — see 5.3 |
| `sharedHybridNsgId` | see the NSG modes below |
| `privateEndpointsNetworkPolicies` | leave `Disabled` unless NSG rules must be *enforced* on private endpoint traffic |

Nothing prompts you interactively. A missing required parameter fails with
`Missing input parameters: <name>`.

**Choose one NSG mode:**

| Mode | How to select | NSGs created | Subnets associated |
| --- | --- | --- | --- |
| 1 — shared hybrid NSG | set `sharedHybridNsgId` | none | all five |
| 2 — per-purpose existing | `reuseExistingNsgs = true` + both `existing*NsgId` | none | APIM, compute |
| 3 — blueprint-owned (default) | leave both unset | APIM + compute | APIM, compute |

Use **mode 1** where policy mandates a single pre-existing NSG on every subnet (for example a
hybrid NSG named `hybrid-nsg-<subscription>-<region>`). Pass its full ARM resource ID; it may live
in another resource group or subscription, and is referenced only, never modified. Mode 1
overrides `reuseExistingNsgs`.

> `privateEndpointsNetworkPolicies` defaults to `Disabled`, which **associates** the NSG with the
> private endpoints subnet but does not let it filter private endpoint traffic. Use
> `NetworkSecurityGroupEnabled` if the rules must actually be enforced there.

### 5.3 Preflight (manual — T039)

The critical check: none of your requested subnet names may already exist.

```bash
RG=<existing-vnet-resource-group>
VNET=<existing-vnet-name>

existing="$(az network vnet subnet list -g "$RG" --vnet-name "$VNET" --query "[].name" -o tsv)"
for want in hybridsubnet-foundry hybridsubnet-apim hybridsubnet-privateendpoints \
            hybridsubnet-compute hybridsubnet-cicdagents; do
  if grep -qx "$want" <<<"$existing"; then
    echo "COLLISION: $want already exists — rename yours, or confirm it is blueprint-owned"
  else
    echo "ok: $want is free"
  fi
done
```

Substitute your own names if you overrode the defaults. Also confirm by eye that every CIDR sits
inside a VNet address prefix and overlaps no existing subnet — nothing checks this yet.

### 5.4 Network-owner stage

Deploy to the **same resource group that holds the existing VNet** — subnets are written as its
children.

```bash
az bicep build --file infra/envs/poc/brownfield-network.bicep --stdout > /dev/null

az deployment group what-if \
  --resource-group "<existing-vnet-resource-group>" \
  --template-file infra/envs/poc/brownfield-network.bicep \
  --parameters infra/envs/poc/brownfield-network.bicepparam \
  > "<untracked-what-if-output>"
```

**Review every line** (T047 not built):

| Symbol | Meaning | Action |
| --- | --- | --- |
| `+ Create` | new resource | ✅ expected: the five subnets, plus NSGs in mode 3 |
| `~ Modify` | existing resource changes | 🛑 **stop** unless you created it in a previous run |
| `- Delete` | existing resource removed | 🛑 **stop**, always |
| `= NoChange` / `* Ignore` | untouched | ✅ fine |

A `~ Modify` on a subnet you did not create is the destructive collision case. Expand it and look
for `routeTable`, `serviceEndpoints` or `natGateway` being removed. If you see any, abort and
rename your subnet.

```bash
az deployment group create \
  --resource-group "<existing-vnet-resource-group>" \
  --template-file infra/envs/poc/brownfield-network.bicep \
  --parameters infra/envs/poc/brownfield-network.bicepparam
```

### 5.5 DNS-owner stage

This stage only **links** existing private DNS zones to the VNet. It never creates or modifies a
zone, so the zones must already exist. Required zones:

```
privatelink.cognitiveservices.azure.com   privatelink.openai.azure.com
privatelink.azure-api.net                 privatelink.vaultcore.azure.net
privatelink.blob.core.windows.net         privatelink.database.windows.net
privatelink.documents.azure.com           privatelink.search.windows.net
```

Confirm they exist and are not already linked (T049 not built):

```bash
az network private-dns zone list -g "<dns-zone-resource-group>" \
  --query "[].{zone:name, links:numberOfVirtualNetworkLinks}" -o table
```

Then:

```bash
cp infra/envs/poc/brownfield-dns.bicepparam.example \
   infra/envs/poc/brownfield-dns.bicepparam
# fill in the placeholders, then:

az deployment group what-if \
  --resource-group "<dns-zone-resource-group>" \
  --template-file infra/envs/poc/brownfield-dns.bicep \
  --parameters infra/envs/poc/brownfield-dns.bicepparam
```

Accept only `+ Create` on virtual network links. Reject any change to a zone or record set
(T053 not built). Then run `az deployment group create` with the same arguments.

Run this stage once per DNS owner scope if the zones are split across resource groups.

---

## 6. Verify

```bash
RG=<resource-group-holding-the-vnet>
VNET=<vnet-name>          # greenfield default: vnet-agent-factory-poc

az network vnet subnet list -g "$RG" --vnet-name "$VNET" \
  --query "[].{name:name, prefix:addressPrefix, delegation:delegations[0].serviceName, \
nsg:networkSecurityGroup.id}" -o table

az network private-dns zone list -g "<dns-zone-resource-group>" \
  --query "[].{zone:name, links:numberOfVirtualNetworkLinks}" -o table

az network public-ip list -g "$RG" --query "[].name" -o table
```

Expected:

- every subnet has the approved name and prefix;
- `hybridsubnet-foundry` shows the `Microsoft.App/environments` delegation;
- NSG associations match the mode you chose;
- each required zone reports at least one VNet link;
- no public IP, except Bastion's in greenfield.

**Idempotency:** re-run `what-if` with unchanged parameters and expect no changes. In greenfield,
Azure may report Bastion `dnsName` and `publicUri` as modified — these are read-only platform
properties and are expected false positives.

---

## 7. Scripts that exist

```bash
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json
./scripts/network/scan-confidentiality.sh
./tests/network/run-tests.sh
```

Run the last two before every commit. The confidentiality scan fails closed on subscription and
tenant GUIDs, resolved ARM resource IDs, real email addresses, absolute home directory paths, and
private address ranges outside the blueprint's own plan.

Never commit `what-if` output, discovery output, or your `.bicepparam` files. `.gitignore` already
excludes `**/brownfield-*.bicepparam`.

---

## 8. Reference

Design rationale and requirements — not needed to deploy:

- [`spec.md`](../specs/00-network-foundation/spec.md) — requirements
- [`plan.md`](../specs/00-network-foundation/plan.md) — architecture decisions
- [`tasks.md`](../specs/00-network-foundation/tasks.md) — backlog and task IDs
- [`research.md`](../specs/00-network-foundation/research.md) — sizing evidence and Azure behaviour
- [`infra/modules/network/README.md`](../infra/modules/network/README.md) — module internals

Remaining brownfield safety tooling is tracked in issue #48.
