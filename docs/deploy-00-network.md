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
| VNet discovery | n/a | ✅ scripted | — (T032) |
| Subnet capacity sizing | n/a | ✅ proposed by generator | IPAM approval is still yours |
| Parameter file authoring | ⚠️ manual | ✅ generated | — |
| Fail-closed preflight | n/a | ⚠️ partial | T039 (generator covers names, overlap, containment) |
| `what-if` boundary enforcement | ⚠️ manual | ⚠️ manual | T027 / T047 / T053 |
| Optional Bastion | ❌ always deployed | n/a | T005, T059–T063 |

⚠️ means it works, but **you** must do the checking. Every manual step below tells you exactly
what to look for.

> Any `./scripts/network/<name>.sh` referenced in `specs/` that is not listed in
> [Section 7](#7-scripts-that-exist) does not exist yet.

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

### 5.1 Discover the existing VNet

Run the read-only discovery script. It only issues `az ... show/list` calls and writes a single
JSON document; it changes nothing.

```bash
./scripts/network/discover-existing-vnet.sh \
  --resource-group "<existing-vnet-resource-group>" \
  --vnet "<existing-vnet-name>" \
  --dns-resource-group "<dns-zone-resource-group>"    # optional, inventories the zones too
```

Output goes to `./network-discovery-<vnet>.json` by default (git-ignored). Use `--output` for a
different path or `--stdout` to skip writing a file. **Never commit this file** — it contains
subscription-specific values.

<details>
<summary>Equivalent manual commands, if you cannot run the script</summary>

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

</details>

### 5.2 Generate the parameter files

The generator turns discovery output into both `.bicepparam` files for you, picking the first
free block in the VNet and carving it into the five subnets.

```bash
./scripts/network/generate-brownfield-params.sh \
  --discovery ./network-discovery-<vnet>.json \
  --dns-resource-group "<dns-zone-resource-group>"
```

It prints the proposed allocation, then writes `infra/envs/poc/brownfield-network.bicepparam` and
`infra/envs/poc/brownfield-dns.bicepparam` (both git-ignored). Add `--dry-run` to see the proposal
without writing anything, and `--force` to overwrite a previous run.

The generated allocation is a **proposal for review, not an approval.** Read it, then get IPAM
sign-off on the CIDRs before deploying.

**Checks the generator enforces (fail-closed):**

| Check | Behaviour |
| --- | --- |
| Requested subnet name already exists in the VNet | **Error**, and it names the route table / NAT gateway / service endpoints that a deploy would remove. Override with `--name-prefix`, or `--allow-name-collision` only if you own those subnets |
| Block overlaps an existing subnet | Error |
| Block not contained in a VNet address prefix | Error |
| Block too small for the platform minimums | Error |
| No free block of the requested size | Error, with a prompt to request an allocation |
| `--reuse-existing-nsgs` without both NSG IDs | Error |

**Common options:**

| Option | Use it when |
| --- | --- |
| `--block <cidr>` | IPAM handed you a specific range — skips auto-selection but still validates it |
| `--block-size <n>` | You want something other than a `/25` (`/25` recommended; `/26` is the minimum viable size — see below) |
| `--name-prefix <prefix>` | Default `hybridsubnet-*` names collide, or your naming standard differs |
| `--shared-hybrid-nsg-id <id>` | NSG mode 1 (see below) |
| `--reuse-existing-nsgs` + `--existing-apim-nsg-id` + `--existing-compute-nsg-id` | NSG mode 2 |
| `--private-endpoints-network-policies NetworkSecurityGroupEnabled` | NSG rules must actually be *enforced* on private endpoint traffic |

**Partially allocated VNets are the normal case.** The generator subtracts every existing subnet
from the VNet address space and picks the first *aligned* free block of the requested size, so
occupied ranges — including `GatewaySubnet`, `AzureFirewallSubnet`, and non-contiguous gaps — are
skipped automatically. If no block of that size is free, it reports the largest free ranges it
found so you can pass one with `--block` or take the numbers to the network admin.

**How the block is split:** the first half becomes the foundry subnet, the second half is divided
into four equal subnets. A `/25` therefore yields `/26` foundry plus four `/28`s — the worked
example below. Platform minimums: foundry `/27`, APIM (classic Premium, VNet-injected) `/29`;
every subnet loses 5 addresses to Azure.

**Minimum viable block: `/26`.** If your VNet can't spare a full `/25` (for example, an existing
subnet already fragments the space), pass `--block-size 26` or `--block <a /26 you have free>`.
A `/26` splits into `/27` foundry (meets the platform minimum with zero slack) plus four `/29`s —
apim meets its `/29` minimum with zero slack, and private endpoints/compute/CI/CD agents each get
only **3 usable addresses** after the 5 Azure-reserved. Check that 3 is actually enough before
relying on it: the Foundry module can create up to 5 private endpoints in the `privateEndpoints`
subnet (foundry, key vault, storage, Cosmos DB, AI Search) unless you point it at existing
resources via `existingStoragePrivateEndpoint` / `existingCosmosDBPrivateEndpoint` /
`existingAISearchPrivateEndpoint` in `foundry.bicepparam` to cut that count down. Treat `/26` as a
stopgap for when you can't extend or reclaim VNet space, and get a larger allocation when
possible. Anything smaller than `/26` cannot satisfy the platform minimums and the generator
rejects it.

| Subnet | Platform minimum | Recommended |
| --- | --- | --- |
| Foundry (delegated) | `/27` | `/26` or larger |
| APIM (classic Premium, VNet-injected) | `/29` | `/27` or larger |
| Private endpoints | endpoint count + 5 Azure-reserved + growth | |
| Compute, CI/CD agents | workload + 5 Azure-reserved + growth | |

**Choose one NSG mode:**

| Mode | How to select | NSGs created | Subnets associated |
| --- | --- | --- | --- |
| 1 — shared hybrid NSG | `--shared-hybrid-nsg-id` | none | all five |
| 2 — per-purpose existing | `--reuse-existing-nsgs` + both `--existing-*-nsg-id` | none | APIM, compute |
| 3 — blueprint-owned (default) | pass nothing | APIM + compute | APIM, compute |

Use **mode 1** where policy mandates a single pre-existing NSG on every subnet. Pass its full ARM
resource ID; it may live in another resource group or subscription, and is referenced only, never
modified. Mode 1 overrides mode 2.

> `privateEndpointsNetworkPolicies` defaults to `Disabled`, which **associates** the NSG with the
> private endpoints subnet but does not let it filter private endpoint traffic. Use
> `NetworkSecurityGroupEnabled` if the rules must actually be enforced there.

<details>
<summary>Writing the parameter file by hand instead</summary>

```bash
cp infra/envs/poc/brownfield-network.bicepparam.example \
   infra/envs/poc/brownfield-network.bicepparam
```

Replace **every** `<placeholder>` in the copy: `existingVnetName` and
`existingVnetResourceGroupName` from the network admin, `location` from the existing VNet, the
five `*SubnetPrefix` from your IPAM-approved sizing, the five `*SubnetName` (defaults are fine
unless the name already exists), the NSG parameters for your chosen mode, and
`privateEndpointsNetworkPolicies`.

Nothing prompts you interactively. A missing required parameter fails with
`Missing input parameters: <name>`.

</details>

### 5.3 Preflight (partly manual — T039)

The generator already fails closed on name collisions, overlap, and containment, so re-running it
against fresh discovery output *is* the collision check. Re-run discovery immediately before
deploying if the VNet may have changed since.

Still yours to confirm manually: IPAM approval of the block, the same-subscription boundary, your
permissions at the target scope, and the `what-if` review in step 5.4.

<details>
<summary>Manual collision check, if you wrote the parameter file by hand</summary>

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
inside a VNet address prefix and overlaps no existing subnet.

</details>

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
# generate-brownfield-params.sh already wrote infra/envs/poc/brownfield-dns.bicepparam.
# If you skipped it, copy the example and fill in the placeholders instead:
#   cp infra/envs/poc/brownfield-dns.bicepparam.example \
#      infra/envs/poc/brownfield-dns.bicepparam

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
./scripts/network/discover-existing-vnet.sh --resource-group <rg> --vnet <name>   # read-only
./scripts/network/generate-brownfield-params.sh --discovery <discovery.json>
./scripts/network/validate-policy-inputs.sh --input policy-inputs.local.json
./scripts/network/scan-confidentiality.sh
./tests/network/run-tests.sh
```

Pass `--help` to any of them for the full option list. Run the last two before every commit. The confidentiality scan fails closed on subscription and
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
