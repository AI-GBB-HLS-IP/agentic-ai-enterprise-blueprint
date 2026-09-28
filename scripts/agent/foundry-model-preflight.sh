#!/usr/bin/env bash
set -euo pipefail

missing=0
check_required_input() {
  local input_name="$1"
  local input_value="$2"
  if [[ -z "$input_value" ]]; then
    printf 'BLOCKED: required Foundry model input %s is not set.\n' "$input_name" >&2
    missing=1
  fi
}

check_required_input FOUNDRY_REGION "${FOUNDRY_REGION:-}"
check_required_input CHAT_MODEL_DEPLOYMENT "${CHAT_MODEL_DEPLOYMENT:-}"
check_required_input CHAT_MODEL_VERSION "${CHAT_MODEL_VERSION:-}"
check_required_input CHAT_MODEL_APPROVAL_REFERENCE "${CHAT_MODEL_APPROVAL_REFERENCE:-}"
check_required_input CHAT_MODEL_CAPACITY_EVIDENCE "${CHAT_MODEL_CAPACITY_EVIDENCE:-}"
check_required_input EMBEDDING_MODEL_DEPLOYMENT "${EMBEDDING_MODEL_DEPLOYMENT:-}"
check_required_input EMBEDDING_MODEL_VERSION "${EMBEDDING_MODEL_VERSION:-}"
check_required_input EMBEDDING_MODEL_APPROVAL_REFERENCE "${EMBEDDING_MODEL_APPROVAL_REFERENCE:-}"
check_required_input EMBEDDING_MODEL_CAPACITY_EVIDENCE "${EMBEDDING_MODEL_CAPACITY_EVIDENCE:-}"
check_required_input QUERY_MODEL_DEPLOYMENT "${QUERY_MODEL_DEPLOYMENT:-}"
check_required_input QUERY_MODEL_VERSION "${QUERY_MODEL_VERSION:-}"
check_required_input QUERY_MODEL_APPROVAL_REFERENCE "${QUERY_MODEL_APPROVAL_REFERENCE:-}"
check_required_input QUERY_MODEL_CAPACITY_EVIDENCE "${QUERY_MODEL_CAPACITY_EVIDENCE:-}"

if [[ "$missing" -ne 0 ]]; then
  exit 2
fi

printf 'PENDING: Foundry model inputs and evidence references are present; approval and regional capacity are not verified.\n'
