# Swarm Code — System Architecture

## Overview

Swarm Code is a native macOS coding-agent client. It does not embed its own models.
It shells out to the CLI tools you already have installed and signed in, on your own
subscriptions, then wraps the resulting streams in a persistent project, thread, and
worktree surface.

The codebase has two implementations of the same product: a native SwiftUI app
(`SwarmCode`) and a cross-platform Tauri port (`SwarmCode_tauri`). A third repo,
`SwarmCode_Mobile`, is the mobile companion that pairs over a local bridge.

---

## Repository Layout

```
Swarm-Code/
  SwarmCode/          SwiftUI native app (macOS 26+)
  SwarmCode_tauri/    Tauri cross-platform port (Rust + Svelte 5)
  SwarmCode_Mobile/   Mobile companion (Tauri)
  mobile-bridge/      Local pairing service for the mobile app
  website/            Marketing site (swarmcode.vercel.app)
  release/            DMG packaging, signing, notarization
  docs/               Design docs, audits, plans
  scripts/            Release automation
```

---

## Four-Layer Architecture (SwiftUI App)

The Swift app is split into four layers with a strict one-way dependency rule.
Each lower layer knows nothing of the layers above it.

```
App  (entry, model, runtime, windows, captures, every feature view)
  |
  +-- Services (Git, Store, Providers)
  |     |
  |     +-- Core (models, pure support)
  |
  +-- UI (Chrome, Common, Markdown, Theme, Sound)
        |
        +-- Core (models, pure support)
```

### Core

Pure domain logic with zero app-level imports. Contains the types that every other
layer depends on:

- **Projects and threads** — the fundamental workspace units.
- **Timeline** — the turn-by-turn record of a conversation.
- **Provider kinds** — the enum that identifies which CLI is driving a session.
- **Hydra** — the multi-head orchestration model (launch, status, report, merge).
- **Shortcuts** — keyboard shortcut definitions.
- **Process I/O** — stdio wrappers, JSON-RPC framing, login shell helpers.
- **No external app dependency.** Core can be unit-tested in isolation.

### Services

Stateful subsystems that own persistence and external tool integration.
Depends on Core only.

- **Git** — diff parsing, blame, log, touched-paths, worktree creation, commit/push.
- **Store** — on-disk JSON persistence with versioned migrations, crash-safe writes
  (tmp-then-rename).
- **Providers** — adapters for each supported coding agent CLI. Each adapter translates
  that tool's protocol into the app's unified event model.

### UI

Renderer-agnostic presentation logic. Depends on Core only.

- **Window chrome** — resizable panels, draggable splitters, veil effects.
- **Common controls** — buttons, sliders, palette, toggles.
- **Markdown rendering** — streaming-aware markdown with tool-call plans, to-do lists,
  error blocks, reasoning disclosure.
- **Theme** — 26 tinted-glass themes, including System, Catppuccin, Dracula, Claude,
  and Codex.
- **Sound** — chime on completion, per-provider tone mapping.

### App

The top-level assembly. Knows about everything.

- App entry and lifecycle.
- Settings model and defaults.
- Project library, thread runtime, and capture system.
- Every feature view: sidebar, chat, composer, changes, terminal, palette, settings,
  usage, tour.
- Welcome tour on first launch (six pages of real captures).
- Notification and permission handling.

---

## Tauri Port (SwarmCode_tauri)

The cross-platform port mirrors the Swift architecture in a Tauri shell. Rust owns
the backend; Svelte 5 owns the frontend.

### Rust backend (`src-tauri/`)

```
src-tauri/src/
  main.rs          App bootstrap, Tauri plugins, invoke handler registration
  lib.rs           Module declarations
  commands/        Tauri command handlers (1:1 with Swift command surface)
    ├── threads.rs
    ├── messages.rs
    ├── providers.rs
    ├── hydra.rs
    ├── library.rs
    ├── git.rs
    ├── terminal.rs
    ├── filesystem.rs
    ├── shortcuts.rs
    ├── events.rs
    └── mcp.rs
  providers/       Provider adapters (mirrors Swift Providers layer)
    ├── claude.rs
    ├── codex.rs
    ├── copilot.rs
    ├── antigravity.rs
    ├── deepseek.rs
    ├── meta.rs
    ├── registry.rs
    ├── session.rs
    ├── credits.rs
    ├── plan_limits.rs
    ├── text_generation.rs
    └── acp.rs
  runtime/         Background agent execution
    ├── thread_runtime.rs
    └── auto_continue.rs
  mcp/             Model Context Protocol integration
    ├── catalog.rs
    └── store.rs
  models/          Domain types (mirrors Swift Core)
    ├── thread.rs
    ├── provider.rs
    ├── hydra.rs
    ├── library.rs
    ├── merge_link.rs
    ├── requests.rs
    ├── timeline.rs
    └── theme.rs
  store/           Persistence layer (mirrors Swift Store)
    ├── mod.rs     AppStore, AppSettings, Library, persistence
    └── migration.rs
  terminal/        PTY-backed terminal sessions
    └── terminal_store.rs
  support/         Shared utilities
    ├── json_rpc.rs
    ├── stdio_process.rs
    ├── shell.rs
    ├── shortcuts.rs
    ├── cache.rs
    ├── coding.rs
    ├── text.rs
    ├── tone.rs
    ├── thumbnail.rs
    ├── tour_captures.rs
    └── website_captures.rs
  types.rs         Shared type aliases and re-exports
```

### Frontend (`src/lib/`)

```
src/lib/
  api/             Tauri invoke wrappers (commands.ts, events.ts)
  components/      Svelte 5 components (40+ files)
  stores/          Svelte stores (chat, settings, sidebar, hydra, error log, sync)
  types/           TypeScript type definitions
  utils/           Validation, timeouts, checkpoint security, panel scene
  app.css          Global styles
```

---

## Provider Adapters

Swarm Code shells out to the CLI tools you already use. Each provider adapter
translates that tool's native protocol into Swarm Code's unified streaming event
model. Nine adapters ship with the app.

| Provider | CLI | Protocol |
| --- | --- | --- |
| Claude | `claude` | stream-json with permission prompts |
| Codex | `codex` | app-server JSON-RPC |
| OpenCode | `opencode` | Agent Client Protocol |
| Cursor | `cursor-agent` | Agent Client Protocol |
| Grok | `grok` | Agent Client Protocol |
| Antigravity | `agy` | stream-json headless |
| Copilot | `copilot` | headless JSON-RPC (Copilot SDK protocol) |
| Command Code | `cmd` | headless print mode (NDJSON events) |
| Pi | `pi` | RPC mode (JSONL over stdio) |

Two additional providers connect via native API, bypassing a CLI entirely:

| Provider | Auth |
| --- | --- |
| DeepSeek | `DEEPSEEK_API_KEY` (OpenAI-compatible) |
|  | `ZAI_API_KEY` (OpenAI-compatible,  Coding Plan) |
| Meta | `MODEL_API_KEY` at `api.meta.ai/v1` (Muse Spark) |

### Provider lifecycle

1. **Detection** — on startup, `ProviderRegistry::detect()` scans for installed CLIs
   on `$PATH` and checks authentication state.
2. **Registration** — each found provider is registered in the `AppStore`.
3. **Session creation** — when a thread is assigned a provider, a session object is
   spawned. The session owns the child process (or HTTP client for native APIs).
4. **Event streaming** — stdout/stderr (or SSE) is parsed into structured events:
   text chunks, reasoning blocks, tool calls, plans, errors.
5. **Teardown** — on thread close or app exit, the child process is terminated and
   the PTY/pipe is closed.

### Credits and plan limits

Each provider adapter tracks its own quota state:

- **Codex** — rolling window resets; a banked reset can be spent from the usage
  popover.
- **Claude, Antigravity, Copilot, Command Code, ** — per-plan rolling limits
  and reset timers.
- **DeepSeek** — API key credit balance.
- **Command Code** — usage also tracked via API key credits.

The effort slider fuses the lead's model and the heads' model into a single control
when Hydra is active.

---

## Hydra: One Chat, Many Heads

Hydra turns a single conversation into parallel agent work. When enabled, the lead
agent writes briefs, dispatches heads in parallel, and lands their results back into
the checkout as one merge.

### Architecture

```
Lead agent (your chat)
  ├── brief generator  →  writes per-head task descriptions
  ├── head launcher    →  spawns N isolated worktrees
  │     ├── Head 0  (Provider A, model X)
  │     ├── Head 1  (Provider A, model X)
  │     └── Head N  (Provider B, model Y)   ← cross-provider allowed
  └── merge driver     →  lands all heads, resolves conflicts
```

### Key invariants

- Each head runs in its own copy of the project (a git worktree).
- A Hydra pair configures the lead's model and the heads' model independently.
- The pair can cross providers: a strong lead on one, quick heads on another.
- One effort slider controls both the lead and the heads.
- Heads can be queued (run one at a time) or launched in parallel.
- The lead's floating panel shows each head's status, tool calls, and token spend.

---

## Model Context Protocol (MCP)

Swarm Code includes a full MCP server integration layer:

- **Catalog** — 30+ preconfigured MCP tools across five categories: Developer,
  Browser, Knowledge, Database, Communication.
- **Connection manager** — add, update, delete, and monitor MCP server connections
  from Settings.
- **Transport support** — stdio, HTTP, and SSE transports.
- **Local proxy** — the app runs a local proxy so tools can reach MCP servers without
  exposing them externally.
- **OAuth authentication** — MCP servers that require OAuth are handled through the
  app's auth flow.

MCP connections are stored in the `AppStore` alongside projects and threads, so they
persist across launches.

---

## Skills and Plugins

Swarm Code supports external skills and plugins to extend its behavior.

### Skills

Skills are loaded from `.claude/skills/` and `.agents/skills/` in the repository.
Each skill is a self-contained directory with a `SKILL.md` frontmatter file that
declares its name and description.

The skill system allows specialized behavior to be injected without modifying the
core app:

- **Design engineering skill** — encodes UI polish, animation decisions, and
  component-building principles.
- Skills are loaded on demand and their instructions replace the default behavior
  for the relevant task type.

### Plugins (Tauri plugins)

The Tauri backend loads four first-party plugins at startup:

- `tauri-plugin-shell` — shell command execution.
- `tauri-plugin-dialog` — native file and alert dialogs.
- `tauri-plugin-fs` — filesystem access with permission scoping.
- `tauri-plugin-http` — HTTP client with CORS handling.

Additional plugin capabilities can be added through the Tauri plugin API.

---

## State Management

All persistent state lives in a single `AppStore` struct, serialized to a JSON file
on disk.

```
AppStore
  ├── library
  │     ├── projects: Vec<Project>
  │     ├── threads: Vec<ChatThread>
  │     ├── thread_documents: Vec<ThreadDocument>
  │     ├── hydra_pairs: Vec<HydraPair>
  │     └── mcp: MCPStore
  ├── settings: AppSettings
  ├── providers: Vec<Provider>
  ├── library_items: Vec<LibraryItem>
  └── mcp: MCPStore (connections)
```

### Persistence guarantees

- **Crash-safe writes** — every save goes to a `.tmp` file first, then renames.
  A crash mid-write cannot leave a partial JSON file.
- **Versioned migrations** — the store file carries a version envelope. The migration
  layer detects old shapes and upgrades them on load.
- **Convenience fields** — top-level `projects`, `threads`, and `hydra_pairs` are
  convenience accessors kept in sync with `library` via `sync_convenience_fields()`.

---

## Frontend Architecture (Tauri Port)

The Svelte 5 frontend communicates with the Rust backend exclusively through Tauri
commands and events. No direct filesystem or process access.

### Component tree

```
App.svelte
  ├── Sidebar.svelte          Project/thread library, search, pinning
  ├── HydraPanel.svelte       Hydra configuration and head status
  ├── ChatView.svelte         Streaming conversation display
  │     ├── MessageBubble.svelte
  │     ├── WorkingIndicator.svelte
  │     ├── TimelineRows.svelte
  │     └── TimelineMinimap.svelte
  ├── Composer.svelte         Message input with attachments
  ├── TerminalPanel.svelte    Per-thread embedded terminal
  ├── DiffViewer.svelte       Per-turn diff display
  ├── CommandPalette.svelte   Quick actions and navigation
  ├── Settings views          Per-area settings panels
  └── Tour.svelte             First-launch walkthrough
```

### State flow

```
Svelte stores (chatStore, settingsStore, sidebarStore, hydraStore, crashStore)
  │
  ├── read AppSettings via commands.get_settings
  ├── write AppSettings via commands.update_settings
  ├── send messages via commands.send_message
  ├── receive streaming chunks via events.message_chunk
  └── receive hydra progress via events.hydra_progress
```

---

## Event Model

The app uses a pub/sub event system for streaming data from the backend to the
frontend. Events are emitted from Rust command handlers and received by the
Svelte frontend.

| Event | Payload | Source |
| --- | --- | --- |
| `message-chunk` | Text delta, tool call, reasoning block | Provider session stdout parser |
| `hydra-progress` | Head status, tool calls, tokens | Hydra head launcher |
| `thread-update` | Thread metadata changes | Thread CRUD commands |
| `terminal-output` | PTY stdout/stderr | Terminal PTY reader |

Events flow through Tauri's event system. The frontend subscribes to the events it
cares about and updates the relevant Svelte store.

---

## Security Model

### Checkpoint security

Every diff generated by a thread is stored as a hidden git checkpoint. Checkpoints
are secured with HMAC-SHA256 so they cannot be tampered with externally.

### Approval timeouts

Agent requests that require user approval have a configurable timeout. After the
timeout expires, the request is auto-rejected (configurable behavior).

### Credential isolation

Provider credentials (API keys, OAuth tokens) are stored in the app's settings and
never logged or transmitted to any backend except the provider's own API endpoint.

### Crash reporting

Crash reports are captured locally and can be submitted to the developer. Reports
include the store state (scrubbed of credentials) and the crash traceback.

### Auto-update

The Tauri port supports auto-updates via `tauri-plugin-updater`. Updates are signed
and verified before installation. The public key for signature verification is
shipped with the app.

---

## Data Flow: Send a Message

```
User types in Composer.svelte
  │
  ├── Frontend validates input
  │
  ├── invoke commands.send_message(thread_id, text, attachments)
  │     │
  │     ├── Rust handler reads AppStore
  │     │     finds thread, finds provider
  │     │
  │     ├── Spawns provider session (child process or HTTP client)
  │     │
  │     ├── Writes message to provider stdin / sends HTTP request
  │     │
  │     ├── Spawns stdout parser
  │     │     │
  │     │     └── On each parsed event:
  │     │           emit message-chunk event
  │     │
  │     └── Returns ThreadUpdate to frontend
  │
  ├── Frontend receives message-chunk events
  │     appends to chatStore
  │     re-renders ChatView
  │
  └── On completion:
        emit hydra-progress (if Hydra active)
        save checkpoint (if git repo)
        notify (if notify_when_finished)
```

---

## Build and Release

### Swift app

```
xcodegen generate
open SwarmCode.xcodeproj
```

Build is the check. There is no test target.

### Tauri port

```
npm install
npm run dev       # development
npm run build     # production
```

### DMG packaging

`scripts/package_dmg.sh` stages three pre-baked assets into every release DMG:

- `installer-background.tiff` — HiDPI window backdrop.
- `installer-DS_Store.base64` — window geometry and icon placement (stored as base64
  so git tracks it as readable source).
- `AppIcon.icns` — mounted volume icon, copied from the built app at package time.

Load-bearing invariants: the volume name must be `Swarm Code`, the background must be
`/.background.tiff`, the app must be `Swarm Code.app`, and the symlink must be
`Applications`. Any mismatch silently breaks Finder window styling.

### Release automation

`scripts/release.sh` archives an Apple silicon build, signs it with Developer ID,
notarizes and staples both the app and a disk image, and checks Gatekeeper. The disk
image lands in `build.noindex/` (Spotlight-skipped).

`scripts/publish_release.sh` publishes to `soumyachk101/Swarm-Code-Release`. Every
release also updates the website version badge and changelog.
