# BridgeMind One

**AI Development Orchestrator for macOS**
Version 0.1.12 | Swift + SwiftUI | macOS 26.0+

## What is BridgeMind One?

BridgeMind One is a macOS app that orchestrates AI coding agents and connects them to your tools. It launches Claude Code, Codex, Cursor, Aider, and other engines, manages 24 MCP plugin connections, provides voice dictation, and persists your chat sessions.

## Features

### Agent Engines
- **Claude Code** — Anthropic's CLI coding agent
- **Codex** — OpenAI's CLI agent
- **Cursor** — Cursor IDE integration
- **Copilot** — GitHub Copilot via MCP
- **Aider** — Aider coding assistant
- **DeepSeek, Gemini, Grok, OpenCode, Antigravity, Droid**

### MCP Plugins (24)
**Development Tools:** Blender, Unity, Unreal, GitHub, Vercel, Cloudflare, Supabase

**Business SaaS:** Apollo, Gmail, Google Ads, Linear, Notion, QuickBooks, Shopify, Slack, Stripe, Sentry, Resend, RevenueCat, Meta Ads, YouTube, vidIQ, fal.ai, Higgsfield

### Built-in Skills (7)
- `research-a-question` — Look up and answer questions
- `root-cause` — Diagnose bugs and trace causes
- `lean-code` — Write small, focused code
- `save-tokens` — Optimize token usage
- `write-a-skill` — Create new skills
- `keep-a-memory` — Manage persistent memory
- `draft-for-a-reader` — Write for real people

### Native Features
- **Voice Dictation** — Press fn to transcribe
- **Multi-pane UI** — Sidebar threads + chat + plugin panel
- **SQLite Storage** — Chat history and sessions
- **OAuth 2.0** — Secure authentication for 20+ services
- **Auto-update** — Sparkle framework
- **Analytics** — PostHog (anonymous)

## Architecture

```
BridgeMindOne/
├── Sources/
│ ├── App/ # App entry point
│ ├── Core/
│ │ ├── MCP/ # MCP protocol engine
│ │ │ ├── Models/ # JSON-RPC types, tool/resource/prompt models
│ │ │ └── Transports/ # HTTP+SSE, stdio, loopback transports
│ │ ├── Plugins/ # Plugin system
│ │ │ ├── Plugins/ # 24 plugin definitions
│ │ │ ├── OAuth/ # OAuth 2.0 PKCE flows
│ │ │ └── Gateway/ # Plugin registry & lifecycle
│ │ ├── Agents/ # Agent engine management
│ │ │ ├── Process/ # Subprocess management
│ │ │ └── Engines/ # Engine-specific adapters
│ │ ├── Chat/ # Chat orchestration & streaming
│ │ ├── Skills/ # Skills engine
│ │ ├── Storage/ # SQLite persistence (GRDB)
│ │ ├── Auth/ # Credential store (Keychain + CryptoKit)
│ │ ├── Presence/ # IPC & presence
│ │ ├── Analytics/ # PostHog integration
│ │ └── Performance/ # Metrics & watchdog
│ ├── UI/ # SwiftUI views
│ │ ├── Views/ # Chat, plugins, settings, agents
│ │ ├── Components/ # Orb, status indicators
│ │ └── Models/ # App state
│ └── Resources/ # Skills, sounds, assets
└── Tests/ # Unit & UI tests
```

## Building

### Prerequisites
- macOS 14.0+ (Sonoma) or macOS 26.0+ (Tahoe)
- Xcode 15.0+
- Swift 5.9+
- Claude Code, Codex, or other agent binaries in PATH

### Build with Xcode
```bash
# Open the project
open Package.swift

# Or build from command line
swift build
```

### Build with Swift Package Manager
```bash
swift build -c release
swift test
```

## Configuration

### Agent Engines
The app auto-detects agent binaries from your PATH. Set custom paths in Settings > Engines:
- Claude Code: `claude` (Anthropic)
- Codex: `codex` (OpenAI)
- Cursor: `cursor` (Anysphere)

### MCP Plugins
Plugins are configured in `~/.bridgemind/settings.json`:
```json
{
 "plugins": {
 "bridgemind_plugins__slack": {
 "enabled": true,
 "auth": "oauth"
 },
 "bridgemind_plugins__supabase": {
 "enabled": true,
 "api_key": "env:SUPABASE_API_KEY"
 }
 }
 }
```

### Environment Variables
- `BRIDGEMIND_MCP_SESSION_TOKEN` — MCP session bearer token
- `OPENAI_API_KEY` — OpenAI API key (for Codex)
- `ANTHROPIC_API_KEY` — Anthropic API key (for Claude)

## Internal Services

| Service ID | Purpose |
|------------|---------|
| `bridgemind.one.agent-run` | Agent process launcher |
| `bridgemind.one.chat-sqlite` | Chat persistence |
| `bridgemind.one.plugin-gateway` | MCP plugin orchestrator |
| `bridgemind.one.plugin-oauth` | OAuth token management |
| `bridgemind.one.presence.ipc` | Inter-process presence |
| `bridgemind.one.session-persistence` | Session state |
| `bridgemind.one.supervised-child` | Child process supervision |

## Security

- **Credentials:** Stored in macOS Keychain, encrypted with CryptoKit
- **OAuth:** Full PKCE flow, tokens never logged or shared
- **Plugin Safety:** Agents operate within (no auto-send, no bypass)
- **Local Network:** Loopback-only for local plugins (Blender, Unity, Unreal)
- **Microphone:** Only active during fn-key dictation

## Privacy

- Telemetry is opt-in (PostHog analytics)
- No prompts or chat content sent to analytics
- All chat history stored locally in SQLite
- Plugins connect directly to their services (not through BridgeMind servers)

## License

Copyright © BridgeMind LLC. All rights reserved.

## Links

- **Website:** https://bridgemind.ai
- **Docs:** https://docs.bridgemind.ai
- **Issues:** https://github.com/bridgemind/bridgemind-one/issues
