# BridgeMindOne — Build Fixes Required (Remaining TODO)

> Project location: `/Users/soumyachakraborty/Documents/01-Projects/SwarmAI/BridgeMindOne`
> Date: 2026-09-01
> Status: **Build FAILS** — 7 error categories remain

---

## Fix 1 — Duplicate `AgentEngine` protocol

**Files involved:**
- `Sources/Core/Agents/AgentTypes.swift:91` — **keep this one** (richer, uses `AgentStreamChunk`/`AgentMessage`/`AgentSession`/`AgentTurn`)
- `Sources/Core/Agents/Process/AgentProcess.swift:8` — **remove this duplicate**

**Action:** Delete lines 8–19 of `AgentProcess.swift` (the entire `public protocol AgentEngine` block). The actor `AgentProcess` itself should remain.

**After fix:** `EngineRegistry.swift`, `ClaudeEngine.swift`, `CodexEngine.swift`, `CursorEngine.swift` will all use the single canonical `AgentEngine` protocol from `AgentTypes.swift`.

---

## Fix 2 — Duplicate `AgentManager` actor

**Files involved:**
- `Sources/Core/Agents/AgentManager.swift:21` — **keep this one** (full production implementation with supervision, IPC, health checks)
- `Sources/Core/Agents/Process/AgentProcess.swift:120` — **remove this duplicate** (lines 118–146)

**Action:** Delete lines 118–146 of `AgentProcess.swift` (the second `public actor AgentManager` block).

---

## Fix 3 — Duplicate `JSONValue` enum

**Files involved:**
- `Sources/Core/MCP/Models/MCPTypes.swift:62` — **keep this one** (has full custom `Codable` implementation)
- `Sources/Core/MCP/Transports/MCPHTTPTransport.swift:511` — **remove this duplicate**

**Action:** Delete lines 508–536 of `MCPHTTPTransport.swift` (the entire `// MARK: - JSONValue` section).

---

## Fix 4 — Swift 6 Actor Isolation errors in `EngineRegistry.swift`

**Errors:**
- Line 101: `actor-isolated 'registerDefaultConfigurations()' cannot be called from nonisolated init`
- Line 203: `cannot assign through subscript because 'newAvailability' is a 'let' constant`

**Actions:**
1. Wrap `registerDefaultConfigurations()` call in `init` with `Task { @MainActor in ... }` or mark it `nonisolated`.
2. Change `let newAvailability` → `var newAvailability` and `let newCapabilities` → `var newCapabilities` on lines ~202–203 inside `refreshAvailability()`.

---

## Fix 5 — Private `AgentProcess.findBinary` access

**Error:** `AgentProcess.findBinary` is `private` (line 94) but called from `EngineRegistry.swift` as `AgentProcess.findBinary(binaryName)`.

**Action:** Change `private func findBinary()` → `public func findBinary()` in `AgentProcess.swift` line 94.

---

## Fix 6 — Missing `UserNotifications` framework in `NotificationSounds.swift`

**Error:** `UNUserNotificationCenter`, `UNMutableNotificationContent`, `UNNotificationRequest` all unresolved.

**Action:**
1. Add `import UserNotifications` at the top of `NotificationSounds.swift`.
2. In `Package.swift`, add `.systemLibrary("UserNotifications")` or ensure the target links the framework.

---

## Fix 7 — `MockLLMProvider` incomplete protocol conformance

**Error:** `MockLLMProvider` does not conform to `LLMProvider` — missing `complete(context:tools:)` method.

**Action:** Add the missing method stub to `MockLLMProvider.swift`:
```swift
public func complete(context: ChatContext, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<LLMResponse, Error> {
 AsyncThrowingStream { $0.finish(throwing: LLMError.notImplemented) }
}
```

---

## Fix 8 — Remove self-imports of `Core` within `Core` module

**Files:**
- `Sources/Core/Chat/MockLLMProvider.swift:7` — remove `import Core`
- `Sources/Core/Storage/DatabaseManager.swift:7` — remove `import Core`

---

## Fix 9 — `AgentEngineType` references should be `EngineType`

**Files with wrong type name:**
- `Sources/Core/Agents/Process/AgentProcess.swift` (multiple occurrences)
- Any UI files referencing `AgentEngineType`

**Action:** Replace all `AgentEngineType` with `EngineType` across the project.

---

## Summary Table

| # | Issue | Severity | Estimated effort |
|---|-------|----------|-----------------|
| 1 | Duplicate `AgentEngine` protocol | 🔴 High | 2 min |
| 2 | Duplicate `ActorManager` | 🔴 High | 1 min |
| 3 | Duplicate `JSONValue` | 🔴 High | 1 min |
| 4 | Actor isolation in `EngineRegistry` | 🟠 Medium | 5 min |
| 5 | Private `findBinary` | 🟡 Low | 1 min |
| 6 | Missing UserNotifications framework | 🟠 Medium | 3 min |
| 7 | `MockLLMProvider` incomplete conformance | 🟡 Low | 2 min |
| 8 | Self-imports of `Core` | 🟡 Low | 1 min |
| 9 | `AgentEngineType` → `EngineType` | 🟡 Low | 2 min |

**Total estimated time: ~20 minutes** for a full clean build.
