# BridgeMindOne — Full Implementation Plan

## Goal

Transform BridgeMindOne from a mock shell (UI renders, nothing is real) into a working macOS AI coding agent application. Every interactive element should actually do something meaningful.

---

## Phase 1: Chat Infrastructure (the backbone)

### 1.1 Real LLM Provider

**File:** `Sources/Core/Chat/AnthropicProvider.swift` (new)

Implement `LLMProvider` protocol using Anthropic's Messages API. This is the primary backend for BridgeMindOne.

- `stream()` makes real `POST https://api.anthropic.com/v1/messages` calls with SSE response parsing
- Uses `ChatStreamParser` extended to handle Claude's SSE format (`delta.text`, `message_start`, `message_stop`, `content_block_start/stop/delta`)
- Reads `apiKey` from `CredentialStore` (Keychain), falling back to `ANTHROPIC_API_KEY` env var
- Supports injection, multi-turn message history, tool definitions
- `complete()` collects stream into a full `ChatMessage`
- Error types: network failure, auth failure, rate limit, context overflow

**File:** `Sources/Core/Chat/OpenAIProvider.swift` (new)

Implement `LLMProvider` for OpenAI-compatible APIs (OpenAI, Grok, DeepSeek, etc.):

- Same `LLMProvider` protocol, different SSE format (`choices[0].delta.content`)
- Configurable base URL for non-OpenAI providers
- Same Keychain credential pattern

### 1.2 MCPToolRouter Implementation

**File:** `Sources/Core/Chat/MCPToolRouter.swift` (new)

Bridge `MCPToolRouter` protocol to `PluginRegistry`:

- `listAvailableTools(pluginIds:)` — calls `PluginRegistry.validateToolCatalog()` for each connected plugin, returns unified `[ToolDefinition]`
- `callTool(_:)` — extracts plugin ID from tool name prefix (`pluginId:toolName`), looks up transport in `PluginRegistry`, sends JSON-RPC `tools/call`, returns `ToolResult`
- Handles tool result parsing (content blocks, error responses)
- Timeout wrapper (30s default) with cancellation propagation

### 1.3 Chat Orchestrator

**File:** `Sources/Core/Chat/ChatOrchestrator.swift` (new)

The missing piece that wires everything together:

```
EngineRegistry → LLMProvider → BatchedChatTurnEngine → MCPToolRouter → PluginRegistry
```

- Singleton actor, owns references to all major subsystems
- `sendMessage(sessionId:text:)` — the main entry point called from UI:
 1. Load session from database (or create new)
 2. Append user message to session
 3. Load skills relevant to current agent
 4. Build context: + skills + message history
 5. Call `BatchedChatTurnEngine.executeTurn()` with real LLM provider and MCP tool router
 6. Stream events back to UI via AsyncStream
 7. Save assistant message + tool calls to database
 8. Update session title from first user message
- Session management: create, load, delete, list
- Context windowing: trim old messages when approaching model's context limit

### 1.4 ChatSession persistence wiring

**File:** `Sources/Core/Storage/Database+Chat.swift` (new)

Extend `DatabaseManager` with chat-specific helpers:

- `createSession(title:agentId:) -> ChatSessionRecord`
- `appendMessage(sessionId:role:content:toolCallId:) -> ChatMessageRecord`
- `loadSession(_ id:) -> ChatSessionRecord?`
- `loadMessages(forSession:) -> [ChatMessageRecord]`
- `listSessions() -> [ChatSessionRecord]` (ordered by updated_at DESC, with pagination offset/limit)
- `deleteSession(_ id:)`
- `updateSessionTitle(_ id:title:)`

---

## Phase 2: UI Wiring (connect the wires)

### 2.1 Wire AppState to ChatOrchestrator

**File:** `Sources/UI/Models/AppState.swift` (modify)

- Replace `threads` array with actual session loading from database on app launch
- `selectedThreadId` selects from real database sessions
- `createNewChat()` calls `ChatOrchestrator.shared.createSession()`
- `sendCurrentMessage()` in ExactChatView calls `ChatOrchestrator.shared.sendMessage()`
- Remove mock `Task.sleep` responses — UI receives real streaming events
- Wire `isProcessing` and `statusMessage` to actual processing states

### 2.2 Real-time streaming in ExactChatView

**File:** `Sources/UI/Views/Chat/ExactChatView.swift` (modify)

- Replace mock `sendCurrentMessage()` with real streaming:
 - Open AsyncStream from ChatOrchestrator
 - On each `.chunk` event, append to the message being rendered
 - On `.toolCall` event, render a tool call card inline
 - On `.message` event, save complete message to database
 - On `.error`, show error state with retry option
- Wire model picker Menu to actual model selection (affects which LLMProvider is used)
- Wire effort level slider to actual parameter
- Wire audio dictation button to AVAudioEngine module
- Make thought block collapsible (use `isThoughtExpanded` state)

### 2.3 Remove dead code

Delete these files — they are never reachable:
- `Sources/UI/Views/Chat/ChatView.swift` (legacy MainSplitView path)
- `Sources/UI/Views/Chat/ThreadRowView.swift`
- `Sources/UI/Views/Chat/MessageRowView.swift`
- `Sources/UI/Views/MainSplitView.swift`
- `Sources/UI/Views/ThreadSidebarView.swift` (contains OrbView)

Remove `MainSplitView` from any imports/references.

---

## Phase 3: Settings Persistence

### 3.1 Settings persistence

**File:** `Sources/Core/Storage/Database+Settings.swift` (new)

- `saveSetting(key:value:)` — string value to `app_settings` table
- `loadSetting(_ key:) -> String?`
- Typed getters/setters for common settings (bool, int, string)

**File:** `Sources/UI/Models/AppState.swift` (modify)

- On `init()`, load settings from database
- On settings change, persist to database
- Sensitive values (API keys) go through `CredentialStore` (Keychain)
- Theme preference persists and actually drives `BridgeMindTheme` (add light/dark variants)

---

## Phase 4: Agent Engine Execution

### 4.1 Engine-Launched Subprocess Communication

**File:** `Sources/Core/Agents/Engines/ClaudeEngine.swift` (modify)

- Instead of static ready message, spawn `claude` binary as subprocess
- Communicate via JSON-RPC over stdio (reuse `MCPStdioTransport`)
- Stream responses back through the engine's `stream()` method
- Handle agent-initiated tool calls via the same tool router

**File:** `Sources/Core/Agents/Engines/CodexEngine.swift` (modify)

Same pattern as Claude — spawn `codex` binary, JSON-RPC stdio communication.

### 4.2 AgentSwitcherView connects to reality

**File:** `Sources/UI/Views/Settings/AgentSwitcherView.swift` (modify)

- Switching agent updates `selectedAgentId` in persistent state
- Engine health check: call `EngineRegistry.detectAllEngines()`, show availability status
- Validate selected engine binary exists at configured path before allowing switch

---

## Phase 5: MCP Plugin Connectivity

### 5.1 PluginsPanelView real connections

**File:** `Sources/UI/Views/Settings/PluginsPanelView.swift` (modify)

- Connect button calls `PluginRegistry.connect(pluginId:)`
- Shows connection progress / error state
- Disconnect button calls `disconnect(pluginId:)`
- Connection state syncs with database via `PluginRegistry`

### 5.2 Tool call dispatch from ChatOrchestrator

Already covered in 1.2 + 1.3. When BatchedChatTurnEngine receives `.toolCall`, the MCPToolRouter dispatches to PluginRegistry which uses the active transport.

---

## Phase 6: Code Mode Realism

### 6.1 File system integration

**File:** `Sources/UI/Views/Code/CodeModeView.swift` (modify)

- Add `URL` for project directory (configurable in settings)
- Read actual file contents from disk
- Make code editor writable (`TextEditor` with binding)
- Write changes back to disk on change (debounced)
- "Build & Test" button runs actual build command in project directory
- "Generate Edit" button sends current file context to LLM for editing (via ChatOrchestrator)

---

## Phase 7: Skills Execution

### 7.1 Skill injection into context

**File:** `Sources/Core/Chat/ChatOrchestrator.swift` (modify)

- When building context, look up skills for the current agent
- Call `SkillEngine.injectSkill()` and convert `[String]` to `[ChatMessage]` with role `.system`
- Inject as system messages before user message

### 7.2 Skills management

**File:** `Sources/UI/Views/Settings/SkillsView.swift` (modify)

- Add skill creation (new markdown file in skills directory)
- Add skill import from URL
- Show skill usage count from database
- Enable/disable skills per agent

---

## Phase 8: Polish & Production

### 8.1 Theme system

- Add light/dark color variants to `BridgeMindTheme`
- Consume `settings.theme` in all views via environment object
- Add typography tokens (font sizes, weights)
- Add spacing tokens

### 8.2 Audio Dictation

**File:** `Sources/UI/Views/Chat/ExactChatView.swift` (modify)

- Wire audio button to `AudioDictationModule`
- Transcribe via system Speech framework or send audio to Whisper API
- Insert transcribed text into input field

### 8.3 Sparkle Auto-Updates

**File:** `scripts/build.sh` (modify)

- Include Sparkle framework in app bundle
- Sign app with hardened runtime
- Generate Sparkle EdDSA signature for releases

### 8.4 LeftSidebarView remaining buttons

- Sidebar collapse button: toggle sidebar width
- Agents "+" button: open agent creation flow
- Moon/gear icons: toggle dark mode / open settings
- Bell icon: notification center integration

---

## Implementation Order

1. **Phase 1.1 + 1.2** — AnthropicProvider + MCPToolRouter (unblocks everything)
2. **Phase 1.3 + 1.4** — ChatOrchestrator + DB chat methods (unblocks all UI)
3. **Phase 2.1 + 2.2** — Wire UI to ChatOrchestrator (app becomes functional)
4. **Phase 2.3** — Remove dead code
5. **Phase 3** — Settings persistence
6. **Phase 4** — Real engine execution
7. **Phase 5** — Plugin connectivity
8. **Phase 6** — Code mode realism
9. **Phase 7** — Skills execution
10. **Phase 8** — Polish

Each phase builds on the previous. After Phase 2.2, the app sends real messages to Claude and gets real responses. Everything after that is enhancement.
