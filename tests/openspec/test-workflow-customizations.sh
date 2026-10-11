#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
checker="$repo_root/scripts/openspec/check-workflow-customizations.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/.github" "$fixture/openspec"
cp -R "$repo_root/.github/prompts" "$fixture/.github/"
cp -R "$repo_root/.github/skills" "$fixture/.github/"
cp "$repo_root/.github/copilot-instructions.md" "$fixture/.github/"
cp "$repo_root/openspec/config.yaml" "$fixture/openspec/"

"$checker" "$fixture"

expect_failure() {
  local expected=$1
  if "$checker" "$fixture" >"$fixture/result.log" 2>&1; then
    printf 'FAIL: guard accepted drift: %s\n' "$expected" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$fixture/result.log"; then
    printf 'FAIL: guard did not report expected drift: %s\n' "$expected" >&2
    cat "$fixture/result.log" >&2
    exit 1
  fi
}

for skill in openspec-apply-change openspec-archive-change openspec-explore openspec-propose openspec-sync-specs; do
  file=".github/skills/$skill/SKILL.md"
  printf '\nallowed-tools: Bash(openspec:*)\n' >>"$fixture/$file"
  expect_failure "$file: forbidden generated behavior"
  cp "$repo_root/$file" "$fixture/$file"
done

for surface in .github/prompts/opsx-archive.prompt.md .github/skills/openspec-archive-change/SKILL.md; do
  sed 's|<planningHome.root>/specs/|<planningHome.root>/openspec/specs/|g' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: <planningHome.root>/specs/"
  cp "$repo_root/$surface" "$fixture/$surface"
  sed '/openspec archive "<name>" --yes --skip-specs --json/d' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: openspec archive"
  cp "$repo_root/$surface" "$fixture/$surface"
  printf '\nmv "<changeRoot>" archive/\n' >>"$fixture/$surface"
  expect_failure "$surface: forbidden generated behavior"
  cp "$repo_root/$surface" "$fixture/$surface"
  sed '/If the sync reports any stop or blocking condition/d' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: If the sync reports"
  cp "$repo_root/$surface" "$fixture/$surface"
done

for surface in .github/prompts/opsx-sync.prompt.md .github/skills/openspec-sync-specs/SKILL.md; do
  sed 's|<planningHome.root>/specs/|<planningHome.root>/openspec/specs/|g' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: set"
  cp "$repo_root/$surface" "$fixture/$surface"
  sed '/validation is unavailable for this layout, not passed./d' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: validation is unavailable"
  cp "$repo_root/$surface" "$fixture/$surface"
done

for surface in .github/prompts/opsx-explore.prompt.md .github/skills/openspec-explore/SKILL.md; do
  sed '/<root.path>\/specs\/\*\*\/spec.md/d' "$repo_root/$surface" >"$fixture/$surface"
  expect_failure "$surface: missing customization: <root.path>/specs/"
  cp "$repo_root/$surface" "$fixture/$surface"
done

rm "$fixture/.github/prompts/opsx-sync.prompt.md"
expect_failure '.github/prompts/opsx-sync.prompt.md: required workflow file is missing'
cp "$repo_root/.github/prompts/opsx-sync.prompt.md" "$fixture/.github/prompts/"
sed '/## OpenSpec Upgrade Policy/d' "$repo_root/.github/copilot-instructions.md" >"$fixture/.github/copilot-instructions.md"
expect_failure '.github/copilot-instructions.md: missing customization: ## OpenSpec Upgrade Policy'
cp "$repo_root/.github/copilot-instructions.md" "$fixture/.github/"

"$checker" "$fixture"
printf 'PASS: OpenSpec customization drift detection and recovery.\n'
