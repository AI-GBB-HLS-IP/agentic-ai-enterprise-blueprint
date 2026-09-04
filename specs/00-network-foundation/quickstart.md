# Quickstart Validation Guide

This guide validates both Network Foundation modes without containing real customer identifiers or
deployment values.

For the ordered end-to-end sequence against a live subscription, including which steps are not yet
automated, see [`RUNBOOK.md`](RUNBOOK.md).

## Prerequisites

1. Install Azure CLI with Bicep support and `jq`.
2. Select the approved tenant and subscription.
3. Keep real brownfield parameters in an untracked file.
4. Obtain network/IPAM approval for every requested brownfield subnet name and CIDR.
5. Obtain approved existing NSG, route-table, and Private DNS zone resource IDs where required.
6. Confirm the responsible network and DNS owners for the separate approval stages.

## Policy-input validation

Validate the FR-019/FR-020 handoff before either mode is previewed. Keep the input file untracked.

```bash
./scripts/network/validate-policy-inputs.sh --input "<untracked-policy-inputs>"
```

Expected: `publicNetworkAccessDisabled` and `localAuthDisabled` are present and `true`, and
`allowedModelSkus` is a non-empty array of unique, non-empty, exact SKU strings with no wildcard or
pattern entries. Any other shape fails closed and blocks deployment.

## Deterministic validation suite

```bash
./tests/network/run-tests.sh
```

Expected: every `tests/network/test-*.sh` case passes.

## Greenfield validation

```bash
az bicep build --file infra/envs/poc/main.bicep

az deployment group what-if \
  --resource-group "<blueprint-resource-group>" \
  --template-file infra/envs/poc/main.bicep \
  --parameters @infra/envs/poc/network.parameters.json
```

Expected: the blueprint-owned VNet, five fixed workload subnets, NSGs, and Private DNS zones/links
are proposed. Bastion resources appear only when explicitly enabled.

## Brownfield discovery

Run the planned read-only discovery against the selected existing VNet before choosing CIDRs:

```bash
./scripts/network/discover-existing-vnet.sh \
  --vnet-resource-id "<existing-vnet-resource-id>" \
  --output "<temporary-local-discovery>"
```

Expected: local inventory of VNet address spaces, existing subnet names/CIDRs, delegations,
NSG/route-table associations, peerings, DNS configuration, DDoS settings, and calculated
unallocated ranges. Do not commit the output.

Use the result to prepare a capacity plan:

- Foundry: `/27` platform minimum; `/26` or larger recommended for POC headroom.
- Classic Premium APIM: `/29` platform minimum; `/27` or larger recommended for POC headroom.
- Private endpoints: expected endpoint count plus Azure-reserved addresses and growth.
- Compute and CI/CD: selected service/agent consumption plus Azure-reserved addresses and growth.

Obtain network/IPAM approval before creating the untracked parameter file.

## Brownfield preflight

Run the planned read-only validator with the untracked parameter file:

```bash
./scripts/network/validate-brownfield-inputs.sh \
  --parameters "<untracked-network-parameters>"
```

Expected:

- the existing VNet resolves;
- discovery and capacity approval are present;
- every requested subnet name is unused, or prior deployment outputs identify it as
  blueprint-managed for the same deployment key and its properties match;
- every CIDR is inside a VNet address prefix and overlaps neither existing nor requested subnets;
- each service profile meets current minimums and documented growth headroom;
- approved existing NSGs and route tables resolve;
- required permissions are available;
- no customer values are written to repository artifacts.

Any failure blocks `what-if`.

## Network-owner preview and deployment

```bash
az bicep build --file infra/envs/poc/brownfield-network.bicep

az deployment group what-if \
  --resource-group "<blueprint-resource-group>" \
  --template-file infra/envs/poc/brownfield-network.bicep \
  --parameters "<untracked-network-parameters>" \
  > "<temporary-network-what-if>"

./scripts/network/validate-network-what-if.sh \
  --input "<temporary-network-what-if>"
```

Expected: only approved new subnets, blueprint-owned NSGs, approved associations, and explicitly
enabled Bastion resources are proposed. No existing VNet, subnet, NSG, route, peering, DNS, or
unrelated resource changes are allowed.

After network-owner approval:

```bash
az deployment group create \
  --resource-group "<blueprint-resource-group>" \
  --template-file infra/envs/poc/brownfield-network.bicep \
  --parameters "<untracked-network-parameters>"
```

## DNS-owner preview and deployment

Run the DNS-specific read-only preflight once per DNS owner scope:

```bash
./scripts/network/validate-dns-inputs.sh \
  --subscription "<dns-subscription-id>" \
  --resource-group "<dns-zone-resource-group>" \
  --parameters "<untracked-dns-parameters>"
```

Expected: every zone resolves, the deployment identity can manage VNet links, and no requested
link name conflicts with an unrelated existing link.

```bash
az bicep build --file infra/envs/poc/brownfield-dns.bicep

az deployment group what-if \
  --subscription "<dns-subscription-id>" \
  --resource-group "<dns-zone-resource-group>" \
  --template-file infra/envs/poc/brownfield-dns.bicep \
  --parameters "<untracked-dns-parameters>" \
  > "<temporary-dns-what-if>"

./scripts/network/validate-dns-what-if.sh \
  --input "<temporary-dns-what-if>"
```

Expected: only approved Private DNS VNet-link child resources are proposed. No zone or record
changes are allowed.

After DNS-owner approval:

```bash
az deployment group create \
  --subscription "<dns-subscription-id>" \
  --resource-group "<dns-zone-resource-group>" \
  --template-file infra/envs/poc/brownfield-dns.bicep \
  --parameters "<untracked-dns-parameters>"
```

## Validate readiness

1. Confirm every new subnet has the approved name, CIDR, delegation, NSG, and route-table
   association.
2. Confirm no existing VNet property or existing subnet changed.
3. Confirm each approved zone has one expected VNet link with registration disabled.
4. Resolve representative private endpoint names from a customer-provided approved in-network
   validation host. Creating a test VM is outside this feature.
5. Re-run both stage previews with unchanged parameters and require no unexpected changes.
6. When Bastion is disabled, confirm no Bastion subnet, host, or public IP exists.

## Partial failure

If the DNS stage fails after network deployment, do not remove the approved network resources.
Correct the DNS issue, rerun the DNS preview, obtain DNS-owner approval, and retry only the DNS
stage. Foundry and APIM deployment remains blocked until DNS readiness passes.

## Confidentiality gate

Before committing:

```bash
./scripts/network/scan-confidentiality.sh
```

Expected: no customer identifiers, identities, resource names, CIDRs, peer details, policy names,
absolute discovery paths, raw discovery output, or real brownfield parameter files are present in
committed artifacts.
