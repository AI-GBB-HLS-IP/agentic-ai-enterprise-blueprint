#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
tests=("${SCRIPT_DIR}"/test-*.sh)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "No network tests found in ${SCRIPT_DIR}" >&2
  exit 1
fi

for test_script in "${tests[@]}"; do
  echo "==> $(basename "$test_script")"
  "$test_script"
done

echo "All network tests passed."
