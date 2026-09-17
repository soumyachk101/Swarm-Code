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

## Layout (four layers, one way)

- `DroppyCode/Core` (models, pure support) reaches into nothing else in the app.
  `DroppyCode/Services` (Git, Store, Providers) and `DroppyCode/UI` (Chrome, Common,
  Markdown, Theme, Sound) reach only into Core. `DroppyCode/App` (entry, model, runtime,
  windows, captures and every feature view) reaches into everything.
- New code goes in the lowest layer whose dependencies it has. A Core file that needs
  the provider registry, the settings or a view is in the wrong layer: split the part
  that needs them into an extension in the layer above (see `App/HydraCookbook+Resolve.swift`).
- There is no test target and no test scripts; the build is the check
  (`xcodebuild -project DroppyCode.xcodeproj -scheme DroppyCode -configuration Debug build`).

## Relaunching (never unprompted)

- NEVER run `scripts/quick_run.sh` or otherwise quit/relaunch Droppy Code unless Jordy explicitly asks for it in that moment.
- Building inside the worktree is fine; installing to /Applications and relaunching is not.
- "Finish", "merge", "done" or "test it" do not imply relaunch — only an explicit request to run/relaunch the app does.

## Merging (always via glab, always squash)

- Project history is already bloated: 4,292 commits on GitLab, mostly tiny
  Hydra head commits plus one merge commit per MR (project `merge_method`
  is `merge`, `squash_option` is `default_off`). Do not let it grow: every
  team merge MUST land as exactly one commit on `main`.
- When Jordy says "merge", always merge via `glab`: push the branch,
  `glab mr create --squash-before-merge`, `glab mr merge --squash --remove-source-branch`,
  then sync the checkout.
- Never merge without `--squash` (create: `--squash-before-merge`, merge:
  `-s`/`--squash`). Never merge locally into `main` and never push
  straight to `main`.
- Do not rewrite existing history (`rebase -i`, `filter-branch`,
  `filter-repo`, force-push to `main`) to "fix" the 4,292 commits; squash
  applies to new merges only.
