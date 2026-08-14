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
