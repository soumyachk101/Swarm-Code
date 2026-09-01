//
// ClaudeEngine.swift
// Claude Code CLI adapter — pipes stdin/stdout with JSON protocol
//
// Communicates with the `claude` binary from Anthropic via its standard
// JSON streaming protocol on stdin/stdout pipes. Handles prompt messages,
// response streaming, tool use detection, and session management.
//
// Binary: `claude` (Anthropic Claude Code CLI)
// Protocol: newline-delimited JSON on stdin/stdout
//

import Foundation
import Combine

// MARK: - ClaudeEngine

public actor ClaudeEngine: AgentEngine, Sendable {
 public static let engineType: EngineType = .claude
 public let configuration: EngineConfiguration

 public nonisolated var type: EngineType { Self.engineType }
 public nonisolated var displayName: String { "Claude Code" }
 public nonisolated var iconName: String { "agent-claude" }
 public nonisolated var supportsStreaming: Bool { true }
 public nonisolated var supportsToolUse: Bool { true }
 public nonisolated var supportsMultiTurn: Bool { true }

 // MARK: State

 private enum EngineState: Equatable {
 case idle
 case initializing
 case ready
 case generating
 case error(String)
 }

 private var engineState: EngineState = .idle
 private let process: AgentProcess
 private var jsonDecoder: JSONDecoder
 private var jsonEncoder: JSONEncoder
 private var pendingRequests: [String: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation] = [:]
 private var messageBuffer: Data = Data()
 private var responseTask: Task<Void, Error>?
 private var processMonitor: Task<Void, Error>?

 // MARK: Init

 public init(
 configuration: EngineConfiguration,
 credentialStore: CredentialStore? = nil
 ) throws {
 self.configuration = configuration
 let binaryPath = Self.resolveBinaryPath(configuration)
 self.process = AgentProcess(configuration: AgentProcess.Configuration(
 binaryPath: binaryPath,
 arguments: Self.buildArguments(configuration),
 workingDirectory: configuration.workingDirectory,
 environment: configuration.environment,
 envToInject: Self.buildEnvironment(configuration),
 inheritedEnvironment: true,
 restartOnCrash: configuration.autoRestart,
 maxRestartAttempts: configuration.maxRestartAttempts,
 restartDelay: configuration.restartDelay
 ))

        self.jsonDecoder = JSONDecoder()
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.outputFormatting = [.sortedKeys]

        // Monitor process state changes
        let processEvents = self.process.events
        self.processMonitor = Task { [weak self] in
            for await event in processEvents {
                await self?.handleProcessEvent(event.state)
            }
        }
    }

    private func handleProcessEvent(_ state: AgentProcess.ProcessState) {
        switch state {
        case .running:
            self.engineState = .ready
        case .stopped, .crashed:
            self.engineState = .idle
            self.pendingRequests.values.forEach { $0.finish(throwing: AgentEngineError.connectionLost) }
            self.pendingRequests.removeAll()
        case .error(let message):
            self.engineState = .error(message)
        default:
            break
        }
    }

    deinit {
        processMonitor?.cancel()
        responseTask?.cancel()
    }

    // MARK: Public API

    public func connect() async throws {
        let isRunning = await process.isRunning
        guard !isRunning else { return }
        engineState = .initializing
        try await process.start()
    }

    public func disconnect() async throws {
        processMonitor?.cancel()
        responseTask?.cancel()
        try await process.stop()
        engineState = .idle
    }

    public func sendMessage(
        _ message: AgentMessage,
        session: AgentSession
    ) async throws -> AsyncThrowingStream<AgentStreamChunk, Error> {
        guard engineState == .ready else {
            throw AgentEngineError.notConnected
        }

        var continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation!
        let stream = AsyncThrowingStream<AgentStreamChunk, Error> { cont in
            continuation = cont
        }

        let requestId = UUID().uuidString
        pendingRequests[requestId] = continuation

        // Build Claude Code prompt message
        let prompt = ClaudePrompt(
            model: Self.mapModel(configuration.model),
            messages: Self.buildMessages(message, session: session),
            system: Self.buildSystemPrompt(message, session: session),
            maxTokens: configuration.maxTokens,
            tools: Self.buildTools(configuration)
        )

        // Send as JSON to stdin
        let requestData = try jsonEncoder.encode(prompt)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            continuation.finish(throwing: AgentEngineError.invalidMessage)
            return stream
        }
        let requestLine = requestString + "\n"

        do {
            try await process.writeStringToStdin(requestLine)
        } catch {
            continuation.finish(throwing: AgentEngineError.sendFailed(error))
            pendingRequests.removeValue(forKey: requestId)
            return stream
        }

        // Begin reading responses
        responseTask?.cancel()
        responseTask = Task {
            await self.readResponses(for: requestId, continuation: continuation)
        }

        return stream
    }

 public func cancelGeneration() async throws {
 responseTask?.cancel()
 responseTask = nil
 pendingRequests.values.forEach { $0.finish() }
 pendingRequests.removeAll()
 engineState = .ready
 }

    public func healthCheck() async -> EngineHealth {
        let isRunning = await process.isRunning
        guard isRunning else {
            return EngineHealth(status: .offline, latencyMs: nil, message: "Process not running")
        }
        let start = Date()
        do {
            _ = try await process.readStdout()
            let latency = Date().timeIntervalSince(start) * 1000
            return EngineHealth(status: .healthy, latencyMs: latency, message: nil)
        } catch {
            return EngineHealth(status: .degraded, latencyMs: nil, message: error.localizedDescription)
        }
    }

 // MARK: Private

 private func readResponses(
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) async {
 while !Task.isCancelled {
 do {
 if let data = try await process.readStdout() {
 messageBuffer.append(data)
 processBuffer(for: requestId, continuation: continuation)
 }
 } catch {
 continuation.finish(throwing: AgentEngineError.readFailed(error))
 pendingRequests.removeValue(forKey: requestId)
 return
 }

 try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
 }
 }

 private func processBuffer(for requestId: String, continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation) {
 var lines = messageBuffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)

 for lineData in lines {
 guard let line = String(data: lineData, encoding: .utf8),
 !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
 continue
 }

 // Remove processed line from buffer
 if let range = messageBuffer.range(of: lineData) {
 messageBuffer.removeSubrange(range.lowerBound..<range.upperBound)
 messageBuffer.append(UInt8(ascii: "\n"))
 }

 // Parse Claude Code JSON response
 parseClaudeResponse(line, for: requestId, continuation: continuation)
 }
 }

 private func parseClaudeResponse(
 _ line: String,
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
 guard let data = line.data(using: .utf8) else { return }

 // Try response type
 if let response = try? jsonDecoder.decode(ClaudeResponse.self, from: data) {
 handleClaudeResponse(response, for: requestId, continuation: continuation)
 return
 }

 // Try streaming chunk
 if let chunk = try? jsonDecoder.decode(ClaudeStreamChunk.self, from: data) {
 handleClaudeChunk(chunk, for: requestId, continuation: continuation)
 return
 }

 // Try error response
 if let error = try? jsonDecoder.decode(ClaudeErrorResponse.self, from: data) {
 continuation.finish(throwing: AgentEngineError.remoteError(error.error.message))
 pendingRequests.removeValue(forKey: requestId)
 return
 }

 // Unknown message — pass through as text
 continuation.yield(.text(line))
 }

 private func handleClaudeResponse(
 _ response: ClaudeResponse,
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
 if let content = response.content {
 continuation.yield(.text(content))
 }
 if let toolCalls = response.toolCalls {
 for toolCall in toolCalls {
 continuation.yield(.toolCall(.init(
 id: toolCall.id,
 name: toolCall.name,
 arguments: toolCall.arguments
 )))
 }
 }
 if response.stopReason == "end_turn" || response.stopReason == "max_tokens" {
 continuation.finish()
 pendingRequests.removeValue(forKey: requestId)
 }
 }

 private func handleClaudeChunk(
 _ chunk: ClaudeStreamChunk,
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
 switch chunk.type {
 case "content_block_delta":
 if let delta = chunk.delta {
 continuation.yield(.text(delta.text))
 }
 case "tool_use_delta":
 if let delta = chunk.delta {
 continuation.yield(.toolCall(.init(
 id: chunk.id ?? UUID().uuidString,
 name: delta.name ?? "",
 arguments: delta.arguments ?? [:]
 )))
 }
 case "message_stop":
 continuation.finish()
 pendingRequests.removeValue(forKey: requestId)
 default:
 break
 }
 }

 // MARK: Static Builders

 private static func resolveBinaryPath(_ config: EngineConfiguration) -> String {
 if let binaryPath = config.binaryPath, !binaryPath.isEmpty {
 return binaryPath
 }
 // Default PATH search
 return "claude"
 }

 private static func buildArguments(_ config: EngineConfiguration) -> [String] {
 var args: [String] = ["--output-format", "stream-json", "--verbose"]

        if config.model != "default" && !config.model.isEmpty {
            args += ["--model", config.model]
        }

 if config.supportsToolUse == false {
 args += ["--no-tools"]
 }

 args += ["--max-turns", "\(config.maxTurns)"]
 args += ["-p"] // Print mode (non-interactive)

 return args
 }

 private static func buildEnvironment(_ config: EngineConfiguration) -> [String: String] {
 var env: [String: String] = [:]
 if let apiKey = config.apiKey {
 env["ANTHROPIC_API_KEY"] = apiKey
 }
 for (key, value) in config.extraEnvironment {
 env[key] = value
 }
 return env
 }

 private static func mapModel(_ model: String) -> String {
 // Normalize model names
 let normalized = model.lowercased()
 if normalized.contains("claude") { return model }
 return model
 }

 private static func buildSystemPrompt(_ message: AgentMessage, session: AgentSession) -> String? {
 var parts: [String] = []
 if let system = session.systemPrompt, !system.isEmpty {
 parts.append(system)
 }
 if let instruction = message.systemInstruction, !instruction.isEmpty {
 parts.append(instruction)
 }
 return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
 }

 private static func buildMessages(_ message: AgentMessage, session: AgentSession) -> [[String: JSONValue]] {
 var messages: [[String: JSONValue]] = []

 // Include conversation history
 for turn in session.history {
 let role = turn.role == .user ? "user" : "assistant"
 var msg: [String: JSONValue] = ["role": .string(role), "content": .string(turn.content)]
 messages.append(msg)
 }

 // Add current message
 messages.append([
 "role": .string("user"),
 "content": .string(message.content)
 ])

 return messages
 }

 private static func buildTools(_ config: EngineConfiguration) -> [JSONValue]? {
 guard config.supportsToolUse else { return nil }
 // Tools would be passed as JSON schema objects; return nil to use defaults
 return nil
 }
}

// MARK: - Claude Protocol Types

private struct ClaudePrompt: Codable {
 let model: String
 let messages: [[String: JSONValue]]
 let system: String?
 let maxTokens: Int
 let tools: [JSONValue]?
 let stream: Bool = true

 enum CodingKeys: String, CodingKey {
 case model, messages, system
 case maxTokens = "max_tokens"
 case tools, stream
 }
}

private struct ClaudeResponse: Codable {
 let id: String?
 let type: String?
 let role: String?
 let content: String?
 let toolCalls: [ClaudeToolCall]?
 let stopReason: String?
 let stopSequence: String?
 let usage: ClaudeUsage?

 enum CodingKeys: String, CodingKey {
 case id, type, role, content
 case toolCalls = "tool_calls"
 case stopReason = "stop_reason"
 case stopSequence = "stop_sequence"
 case usage
 }
}

private struct ClaudeToolCall: Codable {
 let id: String
 let type: String
 let name: String
 let arguments: [String: JSONValue]

 enum CodingKeys: String, CodingKey {
 case id, type, name
 case arguments = "arguments"
 }
}

private struct ClaudeStreamChunk: Codable {
 let type: String
 let index: Int?
 let id: String?
 let delta: ClaudeDelta?

 enum CodingKeys: String, CodingKey {
 case type, index, id, delta
 }
}

private struct ClaudeDelta: Codable {
 let type: String?
 let text: String?
 let name: String?
 let arguments: [String: JSONValue]?
 let partialJSON: String?

 enum CodingKeys: String, CodingKey {
 case type, text, name, arguments
 case partialJSON = "partial_json"
 }
}

private struct ClaudeErrorResponse: Codable {
 let error: ClaudeError

 struct ClaudeError: Codable {
 let type: String
 let message: String
 }
}

private struct ClaudeUsage: Codable {
 let promptTokens: Int
 let completionTokens: Int
 let totalTokens: Int

 enum CodingKeys: String, CodingKey {
 case promptTokens = "prompt_tokens"
 case completionTokens = "completion_tokens"
 case totalTokens = "total_tokens"
 }
}
