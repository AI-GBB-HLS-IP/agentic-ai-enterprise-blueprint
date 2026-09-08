# Quickstart Validation Guide

> **To deploy Chapter 00, use [`docs/deploy-00-network.md`](../../docs/deploy-00-network.md).**
> That document is the single operator entry point for both greenfield and brownfield, and it is
> the only place deployment steps and automation status are maintained.

This file remains as the spec-kit artifact for the feature. It records *what must be true* for the
chapter to be considered validated, not *how to run it*.

## Validation gates

| # | Gate | Where it is exercised |
| --- | --- | --- |
| 1 | Both entry points compile (`az bicep build`) | `tests/network/run-tests.sh` |
| 2 | Deterministic test suite passes | `tests/network/run-tests.sh` |
| 3 | Policy inputs validate against the contract | `scripts/network/validate-policy-inputs.sh` |
| 4 | No confidential material in tracked files | `scripts/network/scan-confidentiality.sh` |
| 5 | Greenfield `what-if` shows only blueprint-owned creates | manual review — see deploy guide §4.2 |
| 6 | Brownfield subnet names do not collide with existing subnets | manual review — see deploy guide §5.3 |
| 7 | Brownfield network-owner `what-if` shows no `~ Modify` or `- Delete` | manual review — see deploy guide §5.4 |
| 8 | DNS-owner `what-if` shows only virtual network link creates | manual review — see deploy guide §5.5 |
| 9 | Deployed topology matches the approved design | manual review — see deploy guide §6 |
| 10 | Re-running with unchanged parameters is a no-op | manual review — see deploy guide §6 |

Gates 5–10 are manual because the corresponding validators are not implemented. The automation
status table in the deploy guide is the authority on which task each gap maps to.

## Partial failure

Both brownfield stages are independently re-runnable. If the network-owner stage succeeds and the
DNS-owner stage fails, re-run only the DNS-owner stage after fixing the cause; do not roll back
subnets.
