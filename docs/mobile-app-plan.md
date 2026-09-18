# Swarm Code Mobile App — Deep Research & System Design Plan

## 1. Problem Statement

Swarm Code is a native macOS app (Swift/SwiftUI, Apple Silicon only). The user wants:

- A mobile app that works on phone (Android + iOS)
- Connects to their Mac/Laptop running Swarm Code
- Lets them control Swarm Code from mobile — view chats, send messages, manage threads, see diffs, approve/reject actions, view terminal output

## 2. High-Level Architecture

### Option Comparison

| Approach | Effort | Pros | Cons |
|---|---|---|---|
| **A. Tauri Mobile + Local Bridge** (RECOMMENDED) | Medium | Same stack (Rust), cross-platform, can embed bridge server | New mobile UI layer needed |
| **B. Flutter + Local Bridge** | Medium-High | Great mobile UI, mature ecosystem | Two codebases (Swift + Dart) |
| **C. PWA + Local Bridge** | Low | Single codebase, instant deploy | Limited native access, no push notifications |
| **D. Rewrite entire Swarm Code in Flutter** | Very High | Unified codebase | Loses SwiftUI Liquid Glass, massive effort |

### Recommended: Option A — Tauri Mobile + Embedded Local Bridge

**Why:**
- Swarm Code already has a `Swarm Code_tauri` folder in the repo — the Tauri foundation exists
- Tauri v2 supports iOS and Android from a single Rust codebase
- The local bridge can be embedded directly in the existing macOS app
- WebSocket-based real-time streaming maps naturally to Swarm Code's streaming events
- Shared Rust core for protocol logic between Mac and mobile

## 3. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         MAC (Swarm Code)                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  SwiftUI App │───▶│  Bridge      │───▶│  Swarm Code Core   │  │
│  │  (existing)  │    │  Server      │    │  (Providers,    │  │
│  │              │◀───│  (new)       │◀───│   Runtime, etc) │  │
│  └──────────────┘    │              │    └─────────────────┘  │
│                      │  - REST API  │                           │
│                      │  - WebSocket │                           │
│                      │  - mDNS      │                           │
│                      └──────┬───────┘                           │
│                             │                                   │
│                      ┌──────▼───────┐                           │
│                      │  Bonjour /   │                           │
│                      │  mDNS        │                           │
│                      │  Discovery   │                           │
│                      └──────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │   Local Network (LAN)        │
              │   WebSocket :8765           │
              │   HTTP :8766                │
              └──────────────┬──────────────┘
                             │
┌─────────────────────────────────────────────────────────────────┐
│                    MOBILE (Tauri App)                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  Tauri UI    │───▶│  Mobile      │───▶│  Bridge Client  │  │
│  │  (SwiftUI    │    │  Frontend    │    │  (Rust)         │  │
│  │   for iOS,   │◀───│  (mobile-    │◀───│                 │  │
│  │   React for │    │   optimized) │    │  - WS reconnect │  │
│  │   Android)  │    │              │    │  - Auth         │  │
│  └──────────────┘    └──────────────┘    └────────┬────────┘  │
│                                                     │           │
│  ┌──────────────┐    ┌──────────────┐    ┌────────▼────────┐  │
│  │  Push        │    │  Local       │    │  Session Cache  │  │
│  │  Notifications│   │  Storage     │    │  (offline msgs) │  │
│  └──────────────┘    └──────────────┘    └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 4. Detailed Component Design

### 4.1 Bridge Server (New, Embedded in macOS App)

**Tech:** Swift (NIO) or Rust (Tauri command)
**Port:** Configurable (default 8765 for WS, 8766 for HTTP)
**Discovery:** mDNS/Bonjour advertise as `_swarmcode-bridge._tcp.local.`

**API Surface:**

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/v1/status` | GET | App connected, version, active threads |
| `/api/v1/threads` | GET | List threads with metadata |
| `/api/v1/threads/{id}` | GET | Thread detail with messages |
| `/api/v1/threads/{id}/messages` | POST | Send message (returns stream) |
| `/api/v1/threads/{id}/approve` | POST | Approve pending action |
| `/api/v1/threads/{id}/reject` | POST | Reject pending action |
| `/api/v1/threads/{id}/terminal` | GET | Terminal output stream |
| `/api/v1/diff/{id}` | GET | Diff for a turn |
| `/api/v1/checkpoint` | POST | Create git checkpoint |
| `/api/v1/git/status` | GET | Git status |
| `/api/v1/models` | GET | Available models |
| `/ws/v1/stream` | WS | Real-time event stream |

**WebSocket Event Types:**

```
// Server → Mobile
{"type": "message_delta", "thread_id": "...", "content": "...", "is_tool": false}
{"type": "message_complete", "thread_id": "...", "message_id": "..."}
{"type": "tool_call", "thread_id": "...", "tool": "bash", "input": "..."}
{"type": "tool_result", "thread_id": "...", "result": "...", "error": null}
{"type": "approval_request", "thread_id": "...", "action": "...", "details": "..."}
{"type": "thinking_delta", "thread_id": "...", "content": "..."}
{"type": "error", "thread_id": "...", "error": "..."}
{"type": "terminal_output", "thread_id": "...", "output": "..."}

// Mobile → Server
{"type": "send_message", "thread_id": "...", "content": "..."}
{"type": "approve", "thread_id": "...", "action_id": "..."}
{"type": "reject", "thread_id": "...", "action_id": "..."}
{"type": "create_thread", "project_id": "..."}
{"type": "switch_model", "thread_id": "...", "model": "..."}
```

### 4.2 Bridge Client (Rust, Tauri Command)

- Handles connection lifecycle (connect, reconnect, heartbeat)
- Queues messages when offline, flushes on reconnect
- Validates responses against JSON schemas
- Manages authentication (pairing code exchange)

### 4.3 Mobile Frontend

**Framework:** Tauri v2 with platform-specific UI:
- **iOS:** SwiftUI views rendered via Tauri (using `swift-ui-views` or native plugin)
- **Android:** Jetpack Compose

**Simpler approach:** Use Tauri's webview on both platforms with a responsive HTML/CSS/JS frontend (React or vanilla). This is the standard Tauri mobile approach and gives one codebase.

### 4.4 Authentication & Security

**Pairing Flow:**
1. Mac shows a 6-digit pairing code in Swarm Code UI
2. Mobile scans QR code (contains code + MAC address + port)
3. Mobile connects and sends pairing code
4. Mac confirms — connection established
5. Session token stored on both sides (Keychain on Mac, Keychain/Keystore on mobile)

**Security:**
- Connection only over local network (bind to `::` with firewall rule, or `0.0.0.0` with mDNS restricted)
- TLS optional for LAN (recommended with self-signed cert)
- No external internet required
- Pairing expires after 5 minutes if unused
- Revoke pairing from Mac side anytime

## 5. UI/UX Design

### 5.1 Mobile Screens

| Screen | Purpose | Key Elements |
|---|---|---|
| **Splash / Connect** | Discover Mac or enter IP | Scan QR, manual IP entry, recent connections |
| **Pairing** | Enter 6-digit code | Large digit entry, auto-submit, cancel |
| **Thread List** | Browse threads/projects | Thread title, model badge, last message preview, pin indicator |
| **Chat** | Main conversation | Message bubbles, streaming indicator, input bar, model selector |
| **Thread Detail** | View diffs & changes | Diff viewer, checkpoint list, revert button |
| **Terminal** | Embedded terminal view | Scrollable output, font size toggle |
| **Approvals** | Quick approve/reject | Action card, details, approve/reject buttons |
| **Settings** | Connection & app settings | Connected Mac info, disconnect, dark mode, font size |

### 5.2 Design Language

**Inspired by Swarm Code's Liquid Glass on Mac:**
- Translucent cards with blur (`backdrop-filter`)
- Tinted accent colors matching Swarm Code themes
- Rounded corners, generous spacing
- Dark mode default (matches coding context)
- Bottom tab navigation (Threads / Chat / Terminal / Settings)

**Color Palette:**
- Background: `rgba(20, 20, 25, 0.9)` with blur
- Cards: `rgba(255, 255, 255, 0.05)` with blur
- Accent: User's Swarm Code theme color synced from Mac
- Text: White primary, grey secondary
- Streaming indicator: Animated gradient (same as Mac)

### 5.3 Interaction Patterns

- **Pull to refresh** — re-sync thread list
- **Swipe thread** — pin / archive / delete
- **Long press message** — copy, resend, delete
- **Tap diff** — inline diff viewer with line numbers
- **Haptic feedback** — on send, approve, receive message
- **Quick actions** (3D Touch / long press) — new thread, switch model

## 6. Technology Stack

| Layer | Technology | Rationale |
|---|---|---|
| **macOS App (existing)** | Swift / SwiftUI | Already built |
| **Bridge Server (new)** | Swift NIO or Rust | Fast, async, lightweight |
| **Mobile App** | Tauri v2 (Rust core + WebView UI) | Cross-platform, leverages Rust |
| **Mobile UI** | React + TailwindCSS (in WebView) | Responsive, one codebase |
| **Communication** | WebSocket + REST | Real-time streaming + commands |
| **Discovery** | mDNS/Bonjour | Auto-find Mac on network |
| **Auth** | Pairing code + Keychain | Simple, secure, no accounts needed |
| **State** | SQLite on mobile, in-memory on bridge | Cache messages for offline reading |

## 7. Implementation Roadmap

### Phase 1: Bridge Server (Weeks 1-2)
- [ ] Create `Swarm Code/Bridge/` module
- [ ] Implement WebSocket server on Swift NIO
- [ ] Implement REST endpoints
- [ ] Add mDNS discovery advertising
- [ ] Integrate pairing code generation/validation
- [ ] Wire into existing AppModel to expose threads, messages, models
- [ ] Add connection status indicator in Swarm Code UI

### Phase 2: Mobile App Shell (Weeks 3-4)
- [ ] Scaffold Tauri v2 mobile project (`Swarm Code_Mobile/`)
- [ ] Set up iOS + Android targets
- [ ] Build connection/pairing screens
- [ ] Implement bridge client in Rust
- [ ] Build thread list screen with offline caching
- [ ] Implement WebSocket message streaming

### Phase 3: Chat Experience (Weeks 5-6)
- [ ] Build chat screen with streaming messages
- [ ] Message input with model selector
- [ ] Thinking/reasoning display
- [ ] Tool call display
- [ ] Error handling and retry
- [ ] Push notification for incoming messages (via local notification when app in background)

### Phase 4: Advanced Features (Weeks 7-8)
- [ ] Diff viewer for code changes
- [ ] Terminal output viewer
- [ ] Approval/Reject actions
- [ ] Thread creation from mobile
- [ ] Checkpoint/revert
- [ ] Settings screen

### Phase 5: Polish (Weeks 9-10)
- [ ] iPad layout (split view)
- [ ] Widget for quick status
- [ ] Watch companion (basic notifications)
- [ ] Performance optimization
- [ ] Testing on real devices
- [ ] App store prep (icons, screenshots, etc.)

## 8. Key Decisions & Tradeoffs

| Decision | Choice | Reason |
|---|---|---|
| Mobile UI approach | WebView in Tauri | One codebase, faster iteration |
| Bridge protocol | WebSocket + REST | Natural fit for streaming + commands |
| Discovery | mDNS/Bonjour | Zero-config on local network |
| Auth | Pairing code | No cloud accounts, simple UX |
| Offline | SQLite cache | Read recent messages offline |
| Real-time sync | Event-sourced via WS | Push-based, no polling |
| Platform | Tauri v2 | Reuses Rust, cross-platform |

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Mobile WebView performance lag on streaming | Use native text rendering for chat, minimize DOM updates |
| Bridge server crashes / instability | Crash isolation, auto-restart, health endpoint |
| Network instability (WiFi drops) | Exponential backoff reconnect, message queue |
| macOS version constraints | Bridge runs on macOS 14+, not limited to 26 |
| Tauri mobile maturity | Tauri v2 is stable as of 2025; monitor roadmap |
| Battery drain from persistent connection | Heartbeat every 30s, sleep when app backgrounds |

## 10. Open Questions

1. Should the bridge be a separate process or embedded in Swarm Code? → Embedded (simpler deployment)
2. How to handle terminal streaming at high output rates? → Throttle + batch WebSocket messages
3. Should we support remote access over internet? → No (out of scope per README)
4. iPad-specific layout or just scaled iPhone? → Split view in Phase 5
5. Should mobile app support dark/light toggle or follow Mac? → Follow Mac theme via bridge
