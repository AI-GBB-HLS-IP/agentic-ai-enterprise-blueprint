# Chapter 02 APIM gateway final validation report (T039)

Status date: 2026-08-27

## Offline deterministic checks

- APIM module family created under `infra/modules/apim/`
- POC composition + parameters created:
  - `infra/envs/poc/apim.bicep`
  - `infra/envs/poc/apim.bicepparam`
- Validation runner created:
  - `specs/02-apim-ai-gateway/validation/validate.sh`
- Scope-boundary documentation/evidence files created in this directory
- `./specs/02-apim-ai-gateway/validation/validate.sh` executed successfully
- `az bicep build` succeeded for every APIM module and composition file

## Live Azure gates

Executed and recorded:

- Provider/API version inspection (`Microsoft.ApiManagement/service` API versions include `2024-05-01`).
- Prerequisite inspection for RG/VNet/subnets/Foundry/model deployment (T008-T010).
- APIM what-if preview for US1/US3 (T017, T031).

Outstanding blockers:

- T006: authoritative live confirmation of current `llm-token-limit` and
  `llm-emit-token-metric` schema source remains manual.
- T032: request behavior passed, but Foundry telemetry correlation for the rejected request is
  still required.
- T033: token-metric attribution and secret-safe telemetry inspection remain required.
- T038: post-deployment unchanged-parameter idempotency validation remains required.

Completed live gates:

- T018: classic Premium internal VNet posture, subnet placement, NSG preservation, and absence
  of public gateway IP addresses passed.
- T024: account-scoped managed identity, private DNS link, and private hostname resolution passed.
- T032 request subset: private approved-model requests passed 10/10; missing-key and unsupported
  model requests were rejected by APIM.
