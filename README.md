<img src="docs/icon.png" width="128" alt="Droppy Code icon">

# Droppy Code

The coding app by Droppy. A native macOS app for your coding agents. Written entirely in Swift and SwiftUI with Liquid Glass, for Macs with Apple silicon on macOS 26 and later.

It drives the coding agents you already have installed and signed in, on your own subscriptions:

| Provider | Command line tool | Protocol |
| --- | --- | --- |
| Codex | `codex` | app-server JSON-RPC |
| Claude | `claude` | stream-json with permission prompts |
| Cursor | `cursor-agent` | Agent Client Protocol |
| OpenCode | `opencode` | Agent Client Protocol |
| Grok | `grok` | Agent Client Protocol |

## What it does

- Projects and threads in a glass sidebar with search, pinning, archiving and drag to resize.
- Streaming conversations with reasoning, tool calls, plans, to-do lists and errors.
- Approvals and questions from the agent, answered inline.
- Plan mode, model and reasoning selection, and four permission modes per thread.
- A diff for every turn, captured as hidden git checkpoints, with revert.
- An embedded terminal per thread, plus project scripts from `droppy-code.json`.
- New threads in their own git worktree.
- Commit, push and pull requests, with generated commit messages and thread titles.
- A command palette, keyboard shortcuts and notifications when work finishes.

Remote access, mobile apps, cloud sync, telemetry and a web client are left out on purpose.

## Requirements

- A Mac with Apple silicon running macOS 26 or later
- At least one provider installed and signed in, for example `codex login` or `claude auth login`
- Git, plus `gh` or `glab` for pull requests

## Build

```bash
brew install xcodegen
xcodegen generate
open DroppyCode.xcodeproj
```

SwiftTerm, the only dependency, is fetched by Swift Package Manager. Xcode asks once to trust its build plugin.

## Release

`scripts/release.sh` archives an Apple silicon build, signs it with Developer ID, notarizes and staples both the app and a disk image, and checks Gatekeeper. The disk image lands in `build/`.

## Layout

| Folder | Contents |
| --- | --- |
| `DroppyCode/App` | App entry, commands, settings and the project library |
| `DroppyCode/Providers` | Codex, Claude and ACP adapters behind one event model |
| `DroppyCode/Runtime` | Per-thread state, streaming, checkpoints and rewind |
| `DroppyCode/Git` | Git, worktrees, checkpoints and diff parsing |
| `DroppyCode/Views` | Window chrome, sidebar, timeline, composer, changes, terminal, palette and settings |
| `DroppyCode/Support` | Process I/O, JSON-RPC and the login shell environment |

## Acknowledgements

The working indicators, the gradient pulse beside a reply and the mini pulse on working threads, along with their rotating words, are ported from [Zeron](https://github.com/zeronsh/zeron) by Wing, under the MIT License. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE).
