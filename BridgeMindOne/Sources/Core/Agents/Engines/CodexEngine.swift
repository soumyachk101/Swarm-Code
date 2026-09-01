//
// CodexEngine.swift
// OpenAI Codex CLI adapter
//
// Communicates with the `codex` binary from OpenAI via its standard
// JSON streaming protocol on stdin/stdout pipes. Similar to ClaudeEngine
// but adapted to OpenAI's Codex CLI format.
//
// Binary: `codex` (OpenAI Codex CLI)
// Protocol: newline-delimited JSON on stdin/stdout
//

import Foundation
import Combine

// MARK: - CodexEngine

public actor CodexEngine: AgentEngine, Sendable {
 public static let engineType: EngineType = .codex
 public let configuration: EngineConfiguration

 public nonisolated var type: EngineType { Self.engineType }
 public nonisolated var displayName: String { "OpenAI Codex" }
 public nonisolated var iconName: String { "agent-codex" }
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

        // Build Codex CLI prompt
        let prompt = CodexPrompt(
            model: Self.mapModel(configuration.model),
            messages: Self.buildMessages(message, session: session),
            systemPrompt: Self.buildSystemPrompt(message, session: session),
            maxTokens: configuration.maxTokens,
            tools: Self.buildTools(configuration)
        )

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
 try? await Task.sleep(nanoseconds: 10_000_000)
 }
 }

 private func processBuffer(for requestId: String, continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation) {
 let separator = UInt8(ascii: "\n")
 var lines = messageBuffer.split(separator: separator, omittingEmptySubsequences: false)

 for lineData in lines {
 guard let line = String(data: lineData, encoding: .utf8),
 !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

 if let range = messageBuffer.range(of: lineData) {
 messageBuffer.removeSubrange(range.lowerBound..<range.upperBound)
 messageBuffer.append(separator)
 }

 parseCodexResponse(line, for: requestId, continuation: continuation)
 }
 }

 private func parseCodexResponse(
 _ line: String,
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
 guard let data = line.data(using: .utf8) else { return }

 // Try Codex response
 if let response = try? jsonDecoder.decode(CodexResponse.self, from: data) {
 handleCodexResponse(response, for: requestId, continuation: continuation)
 return
 }

 // Try streaming chunk
 if let chunk = try? jsonDecoder.decode(CodexStreamChunk.self, from: data) {
 handleCodexChunk(chunk, for: requestId, continuation: continuation)
 return
 }

 // Try error response
 if let error = try? jsonDecoder.decode(CodexErrorResponse.self, from: data) {
 continuation.finish(throwing: AgentEngineError.remoteError(error.error.message))
 pendingRequests.removeValue(forKey: requestId)
 return
 }

 continuation.yield(.text(line))
 }

 private func handleCodexResponse(
 _ response: CodexResponse,
 for requestId: String,
 continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
 ) {
 if let choices = response.choices {
 for choice in choices {
 if let content = choice.message?.content {
 continuation.yield(.text(content))
 }
                if let toolCalls = choice.message?.toolCalls {
                    for toolCall in toolCalls {
                        continuation.yield(.toolCall(.init(
                            id: toolCall.id ?? UUID().uuidString,
                            name: toolCall.function.name ?? "",
                            arguments: toolCall.function.arguments
                        )))
                    }
                }
            }
        }

        if let finishReason = response.choices?.first?.finishReason,
           ["stop", "length"].contains(finishReason) {
            continuation.finish()
            pendingRequests.removeValue(forKey: requestId)
        }
    }

    private func handleCodexChunk(
        _ chunk: CodexStreamChunk,
        for requestId: String,
        continuation: AsyncThrowingStream<AgentStreamChunk, Error>.Continuation
    ) {
        if let choices = chunk.choices {
            for choice in choices {
                if let delta = choice.delta {
                    if let text = delta.content {
                        continuation.yield(.text(text))
                    }
                    if let toolCall = delta.toolCall {
                        continuation.yield(.toolCall(.init(
                            id: toolCall.id ?? UUID().uuidString,
                            name: toolCall.function.name ?? "",
                            arguments: toolCall.function.arguments
                        )))
                    }
                }
                if let finishReason = choice.finishReason,
                   ["stop", "length"].contains(finishReason) {
                    continuation.finish()
                    pendingRequests.removeValue(forKey: requestId)
                }
            }
        }
    }

 // MARK: Static Builders

 private static func resolveBinaryPath(_ config: EngineConfiguration) -> String {
 if let binaryPath = config.binaryPath, !binaryPath.isEmpty {
 return binaryPath
 }
 return "codex"
 }

 private static func buildArguments(_ config: EngineConfiguration) -> [String] {
 var args: [String] = ["--output-format", "stream-json", "--verbose"]

        if config.model != "default" && !config.model.isEmpty {
            args += ["--model", config.model]
        }

 args += ["--max-turns", "\(config.maxTurns)"]
 args += ["-q"] // Quiet mode for piping

 return args
 }

 private static func buildEnvironment(_ config: EngineConfiguration) -> [String: String] {
 var env: [String: String] = [:]
 if let apiKey = config.apiKey {
 env["OPENAI_API_KEY"] = apiKey
 }
 for (key, value) in config.extraEnvironment {
 env[key] = value
 }
 return env
 }

 private static func mapModel(_ model: String) -> String {
 model == "default" ? "gpt-4" : model
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

 for turn in session.history {
 let role = turn.role == .user ? "user" : "assistant"
 messages.append([
 "role": .string(role),
 "content": .string(turn.content)
 ])
 }

 messages.append([
 "role": .string("user"),
 "content": .string(message.content)
 ])

 return messages
 }

 private static func buildTools(_ config: EngineConfiguration) -> [JSONValue]? {
 guard config.supportsToolUse else { return nil }
 return nil
 }
}

// MARK: - Codex Protocol Types

private struct CodexPrompt: Codable {
 let model: String
 let messages: [[String: JSONValue]]
 let systemPrompt: String?
 let maxTokens: Int
 let tools: [JSONValue]?
 let stream: Bool = true

 enum CodingKeys: String, CodingKey {
 case model, messages, systemPrompt
 case maxTokens = "max_tokens"
 case tools, stream
 }
}

private struct CodexResponse: Codable {
 let id: String
 let choices: [CodexChoice]?
 let usage: CodexUsage?

 struct CodexChoice: Codable {
 let index: Int
 let message: CodexMessage?
 let finishReason: String?
 }

 struct CodexMessage: Codable {
 let role: String
 let content: String?
 let toolCalls: [CodexToolCall]?
 }
}

private struct CodexToolCall: Codable {
 let id: String
 let type: String
 let function: CodexFunctionCall

 struct CodexFunctionCall: Codable {
 let name: String
 let arguments: [String: JSONValue]
 }
}

private struct CodexStreamChunk: Codable {
 let id: String
 let choices: [CodexStreamChoice]?
 let usage: CodexUsage?

 struct CodexStreamChoice: Codable {
 let index: Int
 let delta: CodexDelta?
 let finishReason: String?
 }
}

private struct CodexDelta: Codable {
 let role: String?
 let content: String?
 let toolCall: CodexStreamToolCall?
}

private struct CodexStreamToolCall: Codable {
 let index: Int
 let id: String?
 let type: String
 let function: CodexFunctionDelta

 struct CodexFunctionDelta: Codable {
 let name: String?
 let arguments: [String: JSONValue]
 }
}

private struct CodexErrorResponse: Codable {
 let error: CodexError

 struct CodexError: Codable {
 let message: String
 let type: String?
 let code: String?
 }
}

private struct CodexUsage: Codable {
 let promptTokens: Int
 let completionTokens: Int
 let totalTokens: Int

 enum CodingKeys: String, CodingKey {
 case promptTokens = "prompt_tokens"
 case completionTokens = "completion_tokens"
 case totalTokens = "total_tokens"
 }
}
