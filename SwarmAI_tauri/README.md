# SwarmAI (Tauri Edition)

Tauri-based cross-platform desktop port of [SwarmAI](https://droppy-code.github.io/SwarmAI/), a multi-provider AI swarm coordination tool.

## Features

- **Multi-provider AI swarm coordination** — Claude, Codex, Copilot, Cursor, DeepSeek, Devin, Grok, Meta AI, Antigravity, OpenCode
- **Hydra head visualization** — Up to 24 concurrent AI heads working in parallel
- **Pair-based collaboration tracking** — Monitor worker/leader head pairs
- **Markdown rendering** — With syntax highlighting and rich formatting
- **Dark/Light theme support** — System-aware with manual toggle
- **Onboarding tour** — Interactive first-run experience
- **Real-time streaming** — Live updates from AI providers with delta-based rendering
- **Session persistence** — Thread history and settings saved to local JSON files
- **File watching** — Automatic detection of workspace changes
- **Terminal integration** — Built-in process management for AI CLI tools
- **Keyboard shortcuts** — Quick actions and navigation

## Architecture

```
src-tauri/
  src/
    main.rs            # App entry point, Tauri setup
    lib.rs              # Module declarations, init functions
    types.rs            # Shared type definitions
    store/
      mod.rs            # AppStore with thread-safe data management
    models/
      mod.rs            # Domain model definitions
      provider.rs       # AI provider abstraction
      hydra.rs          # Multi-head swarm logic
      timeline.rs       # Timeline/replay data structures
      requests.rs       # Request/response types
      thread.rs         # Thread model
    providers/
      mod.rs            # Provider registry
      registry.rs       # Provider lookup and management
      session.rs        # Session tracking
      text_generation.rs # Text generation service
      credits.rs        # Provider credit tracking
    runtime/
      mod.rs            # Runtime module
      thread_runtime.rs # Per-thread AI execution
      auto_continue.rs  # Auto-resume after rate limits
    commands/
      mod.rs            # Command registration
      threads.rs        # Thread CRUD
      messages.rs       # Message sending/receiving
      providers.rs      # Provider management
      hydra.rs          # Hydra controls
      events.rs         # Event streaming
      settings.rs       # App settings
      library.rs        # File library
      search.rs         # Search functionality
      git.rs            # Git integration
      terminal.rs       # Terminal process management
      shortcuts.rs      # Keyboard shortcuts
    support/
      mod.rs            # Support module
      shell.rs          # Command execution
      stdio_process.rs  # Process management
      json_rpc.rs       # JSON-RPC helper
      id.rs             # ID generation
      cache.rs          # Caching utilities
      coding.rs         # JSON/codec utilities
      thumbnail.rs      # Image thumbnails
      tone.rs           # Audio synthesis
      website_captures.rs # Website screenshots
      tour_captures.rs  # Tour capture data
    terminal/
      mod.rs            # Terminal module
      terminal_store.rs # Terminal state management
```

## Tech Stack

- **Tauri 2** — Cross-platform desktop framework (Rust backend + web frontend)
- **Rust 2021** — Backend with async/await via Tokio
- **Svelte 5** — Frontend with reactive runes
- **Vite 6** — Build tool and dev server
- **TypeScript** — Frontend type safety

## Prerequisites

- **Node.js** 20+ and npm
- **Rust** 1.75+ (via rustup)
- **System dependencies**:
  ```bash
  # macOS
  brew install node@20
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

  # Ubuntu/Debian
  sudo apt install nodejs npm libwebkit2gtk-4.1-dev
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

## Development Setup

```bash
# Install dependencies
npm install

# Run in development mode (with hot reload)
npm run tauri:dev

# Build for production
npm run build

# Run Tauri CLI commands
npm run tauri -- build
```

## Build Instructions

### Development Build

```bash
npm run tauri:dev
```

This starts the Vite dev server and launches the Tauri app with live reload.

### Production Build

```bash
# Build frontend and Rust backend
npm run build

# Or use Tauri's build command
npm run tauri build
```

Output will be in `src-tauri/target/release/bundle/`.

## Known Limitations vs Native macOS Version

The original SwarmAI is built natively for macOS with Swift. This Tauri port reimplements the architecture in Rust + Svelte. Known differences:

1. **Performance** — Svelte 5 + Vite dev server has slightly slower startup vs a native SwiftUI app
2. **Native integration** — Some macOS-specific features (Touch Bar, native notifications, AppKit integration) may have reduced fidelity
3. **Audio** — System sounds (`afplay`) work on macOS; other platforms need audio file assets
4. **Theme** — Vibrancy effects and macOS-specific visual styling may differ
5. **Hotkey registration** — Uses `global-hotkey` crate vs native macOS APIs; behavior may vary
6. **WebView rendering** — WebKit on Linux vs WebKit2 on macOS may render slightly differently
7. **File system** — Path handling and permissions differ across platforms (this version targets all platforms)

## Project Structure

- `src/` — Svelte 5 frontend source
- `src-tauri/` — Rust backend source and Tauri configuration
- `src-tauri/src/` — Main Rust source code

## License

MIT
