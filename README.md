# T3 Code for Mac

A native macOS rewrite of [T3 Code](https://github.com/pingdotgg/t3code), the minimal GUI for coding agents. Written entirely in Swift and SwiftUI with Liquid Glass, for macOS 26 and later.

It drives the coding agents you already have installed and signed in, on your own subscriptions:

| Provider | Command line tool | Protocol |
| --- | --- | --- |
| Codex | `codex` | app-server JSON-RPC |
| Claude | `claude` | stream-json with permission prompts |
| Cursor | `cursor-agent` | Agent Client Protocol |
| OpenCode | `opencode` | Agent Client Protocol |
| Grok | `grok` | Agent Client Protocol |

## What it does

- Projects and threads in a glass sidebar, with pinning, archiving and search.
- Streaming conversations with reasoning, tool calls, plans, to-do lists and errors.
- Approvals and questions from the agent, answered inline.
- Plan mode, model and reasoning selection, and four permission modes per thread.
- A diff for every turn, captured as hidden git checkpoints, with revert.
- An embedded terminal per thread, plus project scripts from `t3.json`.
- New threads in their own git worktree.
- Commit, push and pull requests, with generated commit messages and thread titles.
- A command palette, keyboard shortcuts and notifications when work finishes.

Remote access, the mobile apps, T3 Connect, cloud sync, telemetry and the web client are left out on purpose.

## Requirements

- macOS 26 or later
- At least one provider installed and signed in, for example `codex login` or `claude auth login`
- Git, plus `gh` or `glab` for pull requests

## Build

```bash
brew install xcodegen
xcodegen generate
open T3Code.xcodeproj
```

SwiftTerm, the only dependency, is fetched by Swift Package Manager. Xcode asks once to trust its build plugin.

## Release

`scripts/release.sh` archives a universal build, signs it with Developer ID, notarizes and staples both the app and a disk image, and checks Gatekeeper. The disk image lands in `build/`.

## Layout

| Folder | Contents |
| --- | --- |
| `T3Code/App` | App entry, commands, settings and the project library |
| `T3Code/Providers` | Codex, Claude and ACP adapters behind one event model |
| `T3Code/Runtime` | Per-thread state, streaming, checkpoints and rewind |
| `T3Code/Git` | Git, worktrees, checkpoints and diff parsing |
| `T3Code/Views` | Sidebar, timeline, composer, changes, terminal, palette and settings |
| `T3Code/Support` | Process I/O, JSON-RPC and the login shell environment |

## License

MIT, like the original T3 Code. See [LICENSE](LICENSE).
