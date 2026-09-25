# Repository Contribution Instructions

## Response Language

- Respond only in English unless the user explicitly requests another language.
- Before sending a response, check for unintended non-English words or mixed-language text.

## Branch Safety

- Never make feature, documentation, infrastructure, or specification changes directly on
  `master`.
- Before starting work, run `git branch --show-current` and `git status --short`.
- If the current branch is `master`, create or switch to a task-specific branch from the latest
  `origin/master` before editing files.
- Use descriptive branch names such as `spec/01-foundry-byo-networking`,
  `feat/apim-ai-gateway`, `fix/private-dns-validation`, or `docs/network-foundation`.
- Keep unrelated work on separate branches. Do not reuse a completed feature branch for a new
  feature unless the work is a direct continuation.
- Commit changes on the feature branch, push the branch, and open a pull request into `master`.
- Do not reset, rebase, or force-push `master`. If local `master` contains unpushed work, stop and
  move that work to a feature branch before continuing.

## Starting a New Task

```bash
git fetch origin
git switch master
git pull --ff-only origin master
git switch -c <type>/<short-description>
```

For a continuation branch that already exists:

```bash
git fetch origin
git switch <branch>
git status --short
```

## Pre-PR Readiness Gate

Before opening a ready-for-review PR, marking a draft ready, or describing a proposal as
implementation-ready, perform the following review on the complete candidate revision. Apply it
to both initial proposals and material revisions; do not rely on the PR reviewer to finish the
design. Scale the evidence to the change: documentation-only work does not require a new feature
specification, deployment, or unrelated tests.

1. **Feasibility:** Check material guarantees against the existing implementation and authoritative
   platform behavior before finalizing the proposal. Cite relevant code paths and documentation.
   Distinguish syntax/compilation checks from evaluated behavior and live proof. For infrastructure,
   examine create/update versus reference semantics, scope, deployment ordering, and concurrency
   where relevant. Do not promise behavior that the proposed mechanism cannot enforce.
2. **Coverage:** Inventory affected entry points, callers, modes, resource/ownership branches,
   compatibility constraints, and dependencies. Record unsupported or excluded surfaces explicitly.
   Establish this baseline during proposal/design work, not solely as a future implementation task.
3. **Cross-artifact consistency:** Map each material requirement to its design decision,
   implementation task, and acceptance scenario in the existing design/plan or PR description.
   Use artifact-relative paths plus requirement/scenario names and task IDs. Reconcile the proposal,
   specs, design/plan, tasks, examples, and issue/PR scope; check names, defaults, guarantees, error
   behavior, and dependencies agree. No orphan requirement, unassigned mechanism, or unsupported
   completion claim may remain. For changes without those artifacts, use an equivalent concise
   scope-to-change-to-verification mapping in the PR description.
4. **Decision closure:** Obtain user approval for material scope changes, weakened guarantees,
   compatibility breaks, and accepted residual risks before treating them as settled. Do not choose
   an architecture merely to silence review comments. An unresolved decision or unverified
   feasibility assumption that changes the approach blocks implementation-ready status; ask for
   guidance or keep the work explicitly draft/blocked. A future implementation dependency may
   remain pending only when its contract, owning task/change, and blocking relationship are clear.
5. **Evidence and disposition:** Run applicable existing validators and review the complete diff.
   In the PR description, include a concise readiness record covering feasibility sources,
   coverage/traceability, approved decisions and limitations, and commands actually run with their
   outcomes. Explain any not-applicable checks. Mark unavailable mandatory checks `BLOCKED`;
   never equate artifact existence, OpenSpec `done` status, strict validation, compilation, or a
   quiet AI review with semantic correctness or live success. Identify which stage a blocked
   check gates: unavailable implementation/live evidence need not block a specification PR when
   feasibility is established, but still blocks any completion/approval that requires that evidence.

If the gate is not satisfied, report the specific blocker and do not publish a ready-for-review PR
or an implementation-ready handoff. A draft PR may expose unresolved work, with its blockers
explicitly recorded. This is an instruction-level review gate, not an automated CI or branch
protection check and not a guarantee that later review will find no issues.

After review feedback, distinguish confirmed defects from duplicates, stale findings, and optional
hardening. Fix each underlying issue across all affected artifacts, rerun the relevant gate checks
on a coherent revision, and only then request another review. New mechanisms require feasibility,
integration tasks, and acceptance coverage; do not let comment-by-comment fixes silently expand
the approved scope.

## Completion

Before handing off work, confirm:

```bash
git branch --show-current
git status --short
git log --oneline -3
```

The active branch must not be `master` for task changes, and the working tree should be clean
after committing.

## GitHub Issue Conventions

- Create one tracking issue for each feature or chapter implementation before substantial work
  begins.
- Apply exactly one `type:` label, one `area:` label, and one `priority:` label.
- Use the existing controlled labels:
  - Types: `type: spec`, `type: infra`, `type: pipeline`, or `type: docs`
  - Areas: `area: network`, `area: foundry`, `area: apim`, `area: governance`, or `area: agent`
  - Priorities: `priority: p0`, `priority: p1`, or `priority: p2`
- Link the issue to the branch and the relevant `spec.md`, `plan.md`, and `tasks.md` artifacts.
- Include scope and explicit completion criteria in the issue body.
