# BridgeMind One — Implementation Plan

## 1. Architecture Overview

The app will be built as a single Xcode project with a modular Swift Package Manager structure.

```
BridgeMindOne/
├── BridgeMindOne.xcodeproj/
├── Package.swift # SPM packages
├── Sources/
│ ├── App/ # App entry point
│ ├── UI/ # SwiftUI views
│ ├── Core/ # Core business logic
│ │ ├── MCP/ # MCP protocol implementation
│ │ ├── Plugins/ # Plugin system
│ │ ├── Agents/ # Agent engine management
│ │ ├── Skills/ # Skills engine
│ │ ├── Chat/ # Chat & streaming
│ │ ├── Auth/ # OAuth & credentials
│ │ ├── Storage/ # SQLite persistence
│ │ ├── Presence/ # IPC & presence
│ │ └── Analytics/ # PostHog telemetry
│ ├── Resources/ # Icons, sounds, skills
│ └── Extensions/
├── Tests/
└── README.md
```

## 2. Implementation Phases

### Phase 1: Project Setup & Core Framework (Days 1-3)
- Xcode project with SPM
- App lifecycle (SwiftUI App protocol)
- SQLite persistence layer (chat, sessions, credentials)
- Settings/preferences system
- Basic window management

### Phase 2: MCP Protocol Engine (Days 4-10)
- JSON-RPC 2.0 message types
- Transport layer (stdio, HTTP/SSE, loopback)
- Tool discovery & catalog
- Streaming response parser
- Session management (MCP-Session-Id)

### Phase 3: Plugin System (Days 11-18)
- Plugin registry & lifecycle
- HTTP transport (remote plugins)
- stdio transport (local plugins)
- OAuth 2.0 + PKCE flows
- Token storage (Keychain + CryptoKit)
- All 24 plugin configs + adapters

### Phase 4: Agent Engine (Days 19-24)
- Process launcher (subprocess management)
- Claude Code integration
- Codex integration
- Cursor/Aider/other engine adapters
- Engine detection & auto-config
- stdin/stdout/stderr piping

### Phase 5: Chat & UI (Days 25-32)
- Multi-pane SwiftUI layout
- Chat view with streaming
- Thread pane (sidebar)
- Plugin selector UI
- Agent switcher
- Auto-pilot mode
- Animated orb/status indicator (Metal)

### Phase 6: Skills System (Days 33-36)
- Skill file parser (Markdown frontmatter)
- Skill injection into agent context
- 7 bundled skills recreation
- User skills folder watch
- Skill versioning

### Phase 7: Voice & Notifications (Days 37-39)
- fn-key dictation (AVFAudio + Speech framework)
- Audio notification sounds
- macOS notification center
- Notch UI integration

### Phase 8: Polish & Distribution (Days 40-42)
- Sparkle auto-update integration
- Code signing & notarization
- Sparkle EdDSA key generation
- Appcast XML setup
- DMG creation script
- Documentation

## 3. Key Technical Decisions

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Build system | SPM + Xcode | Matches original, clean modularity |
| UI | SwiftUI + AppKit bridges | Native macOS, Tahoe 26+ |
| Database | SQLite3 (GRDB.swift) | Same as original, proven |
| Networking | URLSession + AsyncSequence | Native, async/await |
| Crypto | CryptoKit | Same as original (Apple native) |
| GPU | Metal (shaders only) | Orb animation only |
| Auto-update | Sparkle 2.x | Same as original |
| Analytics | PostHog Swift SDK | Same as original |
| Speech | AVFoundation + Speech | macOS native dictation |
| IPC | XPC + Named Pipes | Internal service comms |

## 4. External Dependencies (SPM)

- GRDB.swift — SQLite ORM
- PostHog — Analytics
- Sparkle — Auto-update (embedded framework)
- KeychainAccess — Credential storage

## 5. Estimated Scope

| Metric | Estimate |
|--------|----------|
| Total files | ~120-150 Swift files |
| Lines of code | ~15,000-20,000 |
| SwiftUI views | ~40-50 |
| MCP plugins | 24 adapters |
| Bundled skills | 7 Markdown files |
| Internal services | 12 XPC/bundle services |
| Tests | Unit + UI tests |

## 6. What I Will Build

1. Complete project structure with all SPM packages
2. Full MCP protocol engine (JSON-RPC, all 3 transports)
3. OAuth 2.0 PKCE implementation
4. All 24 plugin adapters with proper security rules
5. Agent launcher with stdin/stdout piping
6. Multi-pane SwiftUI (sidebar + chat + plugin panel)
7. Streaming chat UI with SSE parser
8. SQLite persistence (chats, sessions, credentials)
9. Skills engine (Markdown-based)
10. Voice dictation (fn key)
11. Sparkle auto-update
12. PostHog analytics
13. Animated Metal orb status indicator
14. Notification sounds + system notifications
15. All bundled skills as Markdown files

Approval milte hi implementation start kar deta hoon.
