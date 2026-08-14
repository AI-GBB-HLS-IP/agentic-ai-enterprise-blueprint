# Repository Contribution Instructions

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

## Completion

Before handing off work, confirm:

```bash
git branch --show-current
git status --short
git log --oneline -3
```

The active branch must not be `master` for task changes, and the working tree should be clean
after committing.
