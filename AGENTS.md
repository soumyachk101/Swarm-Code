# AGENTS.md — Swarm Code agent workflow

## Worktrees (mandatory for coding)

- Never code directly in `/Users/soumyachakraborty/Documents/Swarm-Code` (main checkout) for experimental tasks.
- Setup per task:
  1. `git fetch origin --prune`
  2. `git worktree add -b <branch> ~/.swarm-code/worktrees/agent-<slug> origin/main`
     (or from the agreed base branch instead of `origin/main`)
  3. Do all edits, builds and `scripts/quick_run.sh` runs inside that worktree.
- Cleanup only when the task is done/merged:
  `git worktree remove --force ~/.swarm-code/worktrees/agent-<slug>` + `git worktree prune`.
- Never delete the main checkout, never touch another agent's worktree.

## Layout (four layers, one way)

- `SwarmCode/Core` (models, pure support) reaches into nothing else in the app.
  `SwarmCode/Services` (Git, Store, Providers) and `SwarmCode/UI` (Chrome, Common,
  Markdown, Theme, Sound) reach only into Core. `SwarmCode/App` (entry, model, runtime,
  windows, captures and every feature view) reaches into everything.
- New code goes in the lowest layer whose dependencies it has. A Core file that needs
  the provider registry, the settings or a view is in the wrong layer: split the part
  that needs them into an extension in the layer above (see `App/HydraCookbook+Resolve.swift`).
- There is no test target and no test scripts; the build is the check
  (`xcodebuild -project SwarmCode.xcodeproj -scheme SwarmCode -configuration Debug build`).

## Hydra heads (the chat team)

- A head never builds or otherwise verifies: no `xcodebuild`, no `scripts/quick_run.sh`, no check command. It edits the files the lead briefed it on and reports, nothing more.
- The lead runs the one build that proves the change, in the checkout, after the heads report.

## Relaunching (never unprompted)

- NEVER run `scripts/quick_run.sh` or otherwise quit/relaunch Swarm Code unless Soumya explicitly asks for it in that moment.
- Building inside the worktree is fine; installing to /Applications and relaunching is not.
- "Finish", "merge", "done" or "test it" do not imply relaunch — only an explicit request to run/relaunch the app does.

## Releases (only to release repo)

- All DMG releases, app updates, and GitHub release publications must ONLY be made to `soumyachk101/Swarm-Code-Release`.
- Never publish releases or upload binaries/assets to the main source repository (`soumyachk101/Swarm-Code`).
