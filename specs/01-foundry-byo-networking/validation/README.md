# Chapter 01 validation evidence

This directory stores prerequisite, deployment-preview, private-connectivity, and model
validation evidence for Microsoft Foundry with BYO Networking.

Run the prerequisite check from the repository root:

```bash
./specs/01-foundry-byo-networking/validation/validate.sh
```

The check is read-only and validates the existing Network Foundation. It does not create or
modify Azure resources.

## Current evidence

- `api-confirmation.md` records provider/API findings and unresolved Foundry BYO VNet details.
- `model-approval.md` is the required AI CoE approval and quota evidence template.

Do not mark Chapter 01 ready until unresolved API, private-link, workload, and model approval
gates have been resolved.

## GitHub Actions preflight

The `Foundry request preflight` workflow is manually triggered from the Actions tab with the
request values and optional issue number. It is read-only and requires repository secrets for
Azure workload identity federation:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

The workflow validates the existing network and model quota, then posts the result to the issue.
It does not deploy Foundry resources.
