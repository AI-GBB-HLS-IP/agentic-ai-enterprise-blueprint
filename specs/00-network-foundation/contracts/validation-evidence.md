# Network Foundation Validation Evidence

This contract defines the minimum evidence shape for generic validation records and is intentionally
redacted: no live Azure IDs, customer names, path values, or parameter data are committed.

## Required fields

Every validation record must include:

- `validationType`: the check or gate name, such as `discovery`, `capacity`, `ownership`,
  `what-if`, `dns`, or `confidentiality`
- `status`: `pass`, `fail`, or `blocked`
- `owner`: the responsible Azure role (for example, `network-owner` or `dns-owner`)
- `scope`: a generic deployment scope, such as `greenfield`, `brownfield-network`, or
  `brownfield-dns`
- `approvalReference`: a generic, non-live approval reference token or note
- `evidenceSummary`: short human-readable summary without customer-specific details
- `timestampUtc`: ISO-8601 timestamp for the validation event

## Optional fields

- `discoveryArtifact`: local path or file name only when it remains untracked and generic
- `capacityApproval`: a generic statement describing approved subnet sizing and headroom
- `networkWhatIf`: redacted change summary describing allowed or blocked delta types
- `dnsWhatIf`: redacted VNet-link or zone-sensitive summary
- `recoveryAction`: generic retry or roll-forward guidance when a stage is rerun
- `idempotencyCheck`: `same-parameters` or `unchanged-rerun` status
- `confidentialityCheck`: `pass` or `fail` for the repo-level gate

## Example record

```json
{
  "validationType": "policy-inputs",
  "status": "pass",
  "owner": "network-owner",
  "scope": "greenfield",
  "approvalReference": "approval-generic-001",
  "evidenceSummary": "Required booleans are true and allowedModelSkus is a non-empty exact allowlist.",
  "timestampUtc": "2026-09-04T00:00:00Z",
  "idempotencyCheck": "unchanged-rerun",
  "confidentialityCheck": "pass"
}
```

The evidence contract is intentionally generic and must never contain live subscription IDs,
resource IDs, raw brownfield parameter values, absolute discovery paths, or customer-derived names.
