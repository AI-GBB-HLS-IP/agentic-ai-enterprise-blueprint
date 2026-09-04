# Network validation fixtures

This directory stores deterministic, generic validation fixtures only. All examples must remain
non-production values: use placeholders, approved greenfield constants, and illustrative address
ranges only. Do not store real customer identifiers, discovery output, subscription IDs,
parameter values, live approval evidence, or organization-specific policy names.

## Allowed pattern

- `policyInputs` examples use `true` booleans and exact SKU strings such as
  `generic-model-sku-a`.
- Example CIDRs must be illustrative placeholders, such as `10.0.0.0/16`, not discovery-derived
  values from a real environment.
- A fixture may document a `what-if` or approval check only as a generic note, never as raw output
  from a live Azure deployment.

## Rejected pattern

- real emails, names, resource IDs, absolute local paths, or raw parameter content
- customer, tenant, or subscription-specific naming
- live approval artifacts or real brownfield parameter values
- wildcard or pattern strings in `allowedModelSkus`
