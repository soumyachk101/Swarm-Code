# BridgeMind One — Reverse Engineering Report
**File:** `BridgeMindOne-universal.dmg`
**App:** BridgeMind One v0.1.12
**Bundle ID:** `ai.bridgemind.one`
**Signer:** Developer ID Application: BRIDGEMIND LLC (9CBJCDR3J2)
**Build:** release / standard
**Git SHA:** 88ada94ca0646bf9affd2c0dd192736b92dcc4a9
**Date analyzed:** 2026-09-01

---

## 1. Binary Architecture

| Property | Value |
|----------|-------|
| Format | Mach-O Universal Binary |
| Architectures | x86_64 (Intel), arm64 (Apple Silicon) |
| Text segment | ~14.3 MB |
| Sections | 27 (including Swift metadata) |
| Code signing | Runtime hardened, notarized |
| Linked frameworks | Sparkle 2.9.6, SwiftUI, AppKit, Charts, WebKit, PDFKit, Metal, Combine, AVFAudio, CryptoKit |
| Localization | 30+ languages (Sparkle) |
| Update mechanism | Sparkle (SUFeedURL: https://downloads.bridgemind.ai/bridgemind-one/latest/appcast.xml) |
| Analytics | PostHog (`phc_xwHPCc9bhzdrsFSKZRvdZf2estjpbvTTghvDqzKKSPmS`) |
| Databases | SQLite (libsqlite3.dylib) |

---

## 2. Internal Services (XPC / Bundle Architecture)

The app uses a microservice-style internal architecture with 10 distinct services:

| Service ID | Purpose |
|------------|---------|
| `bridgemind.one.agent-run` | Agent process launcher |
| `bridgemind.one.chat-sqlite` | Chat message persistence (SQLite) |
| `bridgemind.one.loopback` | Local HTTP loopback server |
| `bridgemind.one.metric-reports` | Performance metrics collection |
| `bridgemind.one.perf.sampler` | Performance sampling |
| `bridgemind.one.perf.sink` | Performance data sink |
| `bridgemind.one.perf.watchdog` | Performance watchdog/monitoring |
| `bridgemind.one.plugin-gateway` | MCP plugin gateway (main orchestrator) |
| `bridgemind.one.plugin-oauth` | OAuth token management for plugins |
| `bridgemind.one.presence.ipc` | Inter-process presence/communication |
| `bridgemind.one.session-persistence` | Session state persistence |
| `bridgemind.one.supervised-child` | Supervised child process management |

---

## 3. Plugin Ecosystem (24 MCP Plugins)

The app includes embedded descriptions for 24 MCP (Model Context Protocol) plugins:

### Agent Engines
- **Aider** — `agent-aider-onDark.png / onLight.png`
- **Claude (Anthropic)** — `agent-claude.png`
- **Codex (OpenAI)** — `agent-codex-onDark.png / onLight.png`
- **Copilot (GitHub)** — `agent-copilot-onDark.png / onLight.png`
- **Cursor** — `agent-cursor-onDark.png / onLight.png`
- **DeepSeek** — `agent-deepseek.png`
- **Grok (xAI)** — `agent-grok-onDark.png / onLight.png`
- **OpenCode** — `agent-opencode-onDark.png / onLight.png`

### Development Tools
- **Antigravity** — `agent-antigravity.png`
- **Gemini (Google)** — `agent-gemini-onDark.png / onLight.png`
- **Droid (Factory.ai)** — `agent-droid-onDark.png / onLight.png`

### Business / SaaS Plugins (MCP URLs)
| Plugin | MCP Endpoint | Auth |
|--------|--------------|------|
| Apollo | `https://mcp.apollo.io/mcp` | API key |
| Blender | `127.0.0.1:9876` (local) | None (local add-on) |
| Cloudflare | `https://mcp.cloudflare.com/mcp` | OAuth |
| fal.ai | `https://mcp.fal.ai/mcp` | API key |
| GitHub | via GitHub Copilot MCP | OAuth/PAT |
| Gmail | `https://gmail.googleapis.com/gmail/v1/` | OAuth |
| Google Ads | `https://googleads.googleapis.com/v25/` | OAuth |
| Higgsfield | `https://mcp.higgsfield.ai/mcp` | API key |
| Linear | `https://mcp.linear.app/mcp` | OAuth |
| Meta Ads | `https://mcp.facebook.com/ads` | OAuth |
| Notion | `https://mcp.notion.com/mcp` | OAuth |
| QuickBooks | `https://quickbooks.api.intuit.com/v3/company/` | OAuth |
| Resend | `https://mcp.resend.com/mcp` | API key |
| RevenueCat | `https://mcp.revenuecat.ai/mcp` | API key |
| Sentry | `https://mcp.sentry.dev/mcp` | OAuth |
| Shopify | Shopify Admin API | OAuth |
| Slack | `https://slack.com/api/` | Bot token |
| Stripe | `https://mcp.stripe.com` | Restricted key |
| Supabase | `https://mcp.supabase.com/mcp` | API key |
| Unity | `127.0.0.1:8000` (local) | None (editor bridge) |
| Unreal | `127.0.0.1:8000` (local) | None (editor bridge) |
| Vercel | `https://mcp.vercel.com` | OAuth |
| vidIQ | `https://mcp.vidiq.com/mcp` | API key |
| YouTube | `https://www.googleapis.com/youtube/v3/` | OAuth |

### Other Integrations
- **DuckDuckGo** — web search (`https://duckduckgo.com/`)
- **PostHog** — analytics/telemetry
- **Sparkle** — auto-update framework

---

## 4. Bundled Skills (7 Built-in Skills)

| Skill File | Purpose |
|------------|---------|
| `skill-draft-for-a-reader.md` | Writing/editing skill |
| `skill-keep-a-memory.md` | Memory management skill |
| `skill-lean-code.md` | Code optimization skill |
| `skill-research-a-question.md` | Research skill |
| `skill-root-cause.md` | Debugging/analysis skill |
| `skill-save-tokens.md` | Token optimization skill |
| `skill-write-a-skill.md` | Meta-skill for creating skills |

---

## 5. Key Swift Protocols & Classes (from binary)

### Core Protocols
- `MCPMethod` — MCP JSON-RPC method dispatching
- `MCPTransport` — Transport abstraction (stdio, HTTP/SSE, loopback)
- `MCPNotification` — MCP notifications
- `MCPTokenStorage` — Token persistence
- `MCPOAuthURLValidating` — OAuth URL validation
- `MCPSessionIDGenerator` — Session ID generation
- `MCPOAuthScopeSelecting` — OAuth scope selection
- `MCPHTTPClientAuthorizer` — HTTP authorization
- `MCPHTTPContextProviding` — HTTP context
- `MCPHTTPRequestValidator` — Request validation
- `MCPOAuthTokenRequesting` — Token request flow
- `MCPOAuthClientRegistering` — OAuth client registration
- `MCPOAuthDiscoveryFetching` — OAuth discovery
- `MCPOAuthMetadataDiscovering` — OAuth metadata
- `MCPNetworkConnectionProtocol` — Network connections
- `MCPOAuthAuthorizationDelegate` — OAuth delegate
- `MCPOAuthWWWAuthenticateParsing` — WWW-Authenticate header parsing
- `MCPHTTPRequestValidationPipeline` — Request pipeline
- `MCPOAuthAuthorizationCodeFlowing` — Auth code flow

### Core Classes
- `PluginConnector` — Plugin connection management
- `PluginHTTPTransport` — HTTP-based plugin transport
- `PluginToolProviding` — Tool catalog exposure
- `PluginGatewayLeasing` — Gateway lease management
- `PluginUpstreamCreating` — Upstream connection creation
- `LocalMCPProbing` — Local MCP server discovery
- `ChatStreamParser` — Streaming response parser
- `ChatTurnEngine` — Chat turn orchestration
- `BatchedChatTurnEngine` — Batched turn execution
- `InteractiveChatSession` — Interactive chat session
- `AutoPilotTurnService` — Automated agent turns
- `ApolloCLIProcessRunning` — Apollo CLI process management
- `ApolloCLIDriving` — Apollo CLI driver
- `BlenderTransport` — Blender MCP transport
- `AnalyticsBackend` — Analytics (PostHog)
- `CredentialStore` — Credential storage (CryptoKit)
- `PresenceTransport` — IPC presence
- `NotificationSoundPlaying` — Audio notifications
- `SystemNotificationDelivering` — macOS notifications
- `AudioRecording` — Dictation/audio input

### UI Classes
- `PaneOccupant` — Window pane management
- `AutoPilotPane` — Auto-pilot UI
- `ThreadPaneEngine` — Thread/chat pane
- `KeyViewSearchSuppressing` — Keyboard handling

### OAuth/Token Classes
- `GmailGrantReading` — Gmail OAuth grants
- `GmailAccessTokenProviding` — Gmail token provider
- `GoogleAdsGrantReading` — Google Ads OAuth grants
- `GoogleAdsAccessTokenProviding` — Google Ads token provider
- `YouTubeGrantReading` — YouTube OAuth grants
- `QuickBooksGrantReading` — QuickBooks OAuth grants

### Performance
- `OrbUniforms` — Metal shader uniforms (GPU)
- `VertexOut` — Metal vertex shader output

---

## 6. App Configuration

```xml
<key>CFBundleDisplayName</key><string>BridgeMind</string>
<key>CFBundleShortVersionString</key><string>0.1.12</string>
<key>LSMinimumSystemVersion</key><string>26.0</string> <!-- macOS Tahoe -->
<key>NSMicrophoneUsageDescription</key><string>BridgeMind listens when you press fn so it can transcribe what you say</string>
<key>NSAppTransportSecurity</key>
<key>NSAllowsLocalNetworking</key><true/>
```

### Auto-Update
- Sparkle framework (v2.9.6)
- Update feed: `https://downloads.bridgemind.ai/bridgemind-one/latest/appcast.xml`
- Check interval: 4 hours
- Public EdDSA key for signature verification

---

## 7. Security & Privacy Observations

1. **Credential Storage**: Uses `CryptoKit` (Apple's native crypto) — likely stores tokens in Keychain or encrypted SQLite
2. **Bearer Token Env Var**: `BRIDGEMIND_MCP_SESSION_TOKEN` — exported to child processes
3. **OAuth flows**: Full OAuth 2.0 with PKCE support (OAuthClientRegistering, OAuthAuthorizationCodeFlowing)
4. **Local networking**: Allowed (for local MCP plugins like Blender, Unity, Unreal)
5. **Microphone access**: For voice dictation (fn key transcription)
6. **Desktop/Documents/Downloads access**: For workspace folder access
7. **SQLite database**: `ai.bridgemind.one.chat-sqlite` — chat message storage

---

## 8. Extracted File Structure

```
bridgemind-re/
├── analysis/
│ ├── swift_protocols.txt # 31 Swift protocol definitions
│ ├── plugins.txt # 24 plugin identifiers
│ ├── internal_services.txt # 12 internal XPC service IDs
│ ├── swift_types.txt # Extracted type names
│ ├── keywords.txt # 6290 relevant keywords
│ ├── bridgemind_mentions.txt # 83 BridgeMind-specific strings
│ ├── urls_and_apis.txt # 45 URLs/API endpoints
│ ├── domain_frequency.txt # 25 domains by frequency
│ └── mcp_server_configs.txt # MCP server configurations
├── extracted/
│ ├── strings/
│ │ ├── all_strings.txt # 99,876 raw strings
│ │ └── urls_and_apis.txt
│ └── (plist, resources, binaries)
└── reports/
 └── REPORT.md # This document
```

---

## 9. Technology Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift (SwiftUI) |
| UI Framework | SwiftUI + AppKit |
| GPU/Shader | Metal + MetalKit |
| PDF | PDFKit |
| Charts | Charts framework |
| Network | URLSession + Network.framework |
| Crypto | CryptoKit + Security.framework |
| Database | SQLite3 |
| Audio | AVFAudio + AudioToolbox + CoreAudio |
| Notifications | UserNotifications + UserNotificationsUI |
| Autoupdate | Sparkle 2.9.6 |
| Analytics | PostHog |
| Protocol | MCP (Model Context Protocol) |
| Build system | Swift Package Manager (`.build/` paths found) |

---

## 10. Summary

**BridgeMind One** is a macOS AI development orchestrator that:
1. Launches AI coding agents (Claude Code, Codex, Cursor, etc.)
2. Manages MCP plugin connections (24+ integrations)
3. Provides voice dictation via fn key
4. Persists chat sessions in SQLite
5. Auto-updates via Sparkle
6. Tracks usage via PostHog analytics
7. Handles OAuth flows for 20+ SaaS services
8. Runs as a SwiftUI native macOS app (Tahoe+)

The binary is well-architected with clear separation between MCP transport, plugin management, OAuth, UI, and agent orchestration layers.
