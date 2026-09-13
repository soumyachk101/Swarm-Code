# AGENTS.md — DroppyCode agent workflow

## Worktrees (mandatory for coding)

- Never code directly in `/Users/jordyspruit/Desktop/DroppyCode` (Jordy's checkout).
- For every coding task: first create your own worktree, then work there.
- Setup per task:
  1. `git fetch origin --prune`
  2. `git worktree add -b <branch> ~/.droppy-code/worktrees/agent-<slug> origin/main`
     (or from the agreed base branch instead of `origin/main`)
  3. Do all edits, builds and `scripts/quick_run.sh` runs inside that worktree.
- Cleanup only when the task is done/merged:
  `git worktree remove --force ~/.droppy-code/worktrees/agent-<slug>` + `git worktree prune`.
- Never delete Jordy's main checkout, never touch another agent's worktree.

## Merging (always via glab)

- When Jordy says "merge", always merge via `glab`: push the branch, `glab mr create`, `glab mr merge`, then sync the checkout.
- Never merge locally into `main` and never push straight to `main`.
