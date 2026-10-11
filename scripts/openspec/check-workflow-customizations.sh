#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
root=${1:-$repo_root}
failures=0

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  failures=$((failures + 1))
}

require_text() {
  local file=$1 text=$2
  if ! grep -Fq -- "$text" "$root/$file"; then
    fail "$file: missing customization: $text"
  fi
}

reject_pattern() {
  local file=$1 pattern=$2
  if grep -Eq -- "$pattern" "$root/$file"; then
    fail "$file: forbidden generated behavior: $pattern"
  fi
}

for workflow in apply archive explore propose sync; do
  case "$workflow" in
    apply) skill=openspec-apply-change ;;
    archive) skill=openspec-archive-change ;;
    explore) skill=openspec-explore ;;
    propose) skill=openspec-propose ;;
    sync) skill=openspec-sync-specs ;;
  esac
  prompt=".github/prompts/opsx-$workflow.prompt.md"
  skill_file=".github/skills/$skill/SKILL.md"
  for file in "$prompt" "$skill_file"; do
    if [[ ! -f "$root/$file" ]]; then
      fail "$file: required workflow file is missing"
      continue
    fi
    if [[ "$file" == "$skill_file" ]]; then
      reject_pattern "$file" '^allowed-tools:'
    fi
    case "$workflow" in
      archive)
        require_text "$file" '<planningHome.root>/specs/<capability-path>/spec.md'
        require_text "$file" 'explicitly selected standalone store'
        require_text "$file" 'openspec archive "<name>" --yes --skip-specs --json'
        require_text "$file" 'Require a zero exit status and valid JSON'
        require_text "$file" 'Never replace a failed CLI archive with a manual directory move.'
        require_text "$file" 'If the sync reports any stop or blocking condition'
        require_text "$file" 'Do not delegate it to a background task'
        reject_pattern "$file" '^[[:space:]]*(mv|mkdir)[[:space:]]'
        if [[ "$file" == "$prompt" ]]; then
          require_text "$file" '/opsx-sync'
        else
          require_text "$file" 'openspec-sync-specs'
        fi
        ;;
      explore)
        require_text "$file" '<root.path>/specs/**/spec.md'
        require_text "$file" 'Never interpret an empty CLI'
        require_text "$file" 'explicitly selected standalone'
        ;;
      sync)
        require_text "$file" 'set `<main-spec-root>` to `<planningHome.root>/specs/`'
        require_text "$file" 'explicitly selected standalone store'
        require_text "$file" '<main-spec-root>/<capability-path>/spec.md'
        require_text "$file" 'never migrate, rename, or convert a chapter implicitly.'
        require_text "$file" 'automated CLI main-spec'
        require_text "$file" 'validation is unavailable for this layout, not passed.'
        require_text "$file" 'report `BLOCKED` and do not claim sync success'
        ;;
    esac
  done
done

require_text '.github/copilot-instructions.md' '## OpenSpec Upgrade Policy'
require_text 'openspec/config.yaml' 'Follow the Pre-PR Readiness Gate'

if [[ "$failures" -ne 0 ]]; then
  printf 'OpenSpec customization guard failed (%s checks). Reconcile the upgrade with repository policy.\n' "$failures" >&2
  exit 1
fi
printf 'OpenSpec customization guard passed (five prompt/skill pairs and durable policy).\n'
