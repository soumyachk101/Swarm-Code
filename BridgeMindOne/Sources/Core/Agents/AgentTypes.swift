//
// AgentTypes.swift
// Shared types for the agent engine subsystem
//

import Foundation
import Combine

// MARK: - Engine Type

public enum EngineType: String, Codable, Equatable, Sendable, CaseIterable {
 case claude = "claude"
 case codex = "codex"
 case cursor = "cursor"
 case aider = "aider"
 case deepseek = "deepseek"
 case grok = "grok"
 case gemini = "gemini"
 case opencode = "opencode"

 public var displayName: String {
 switch self {
 case .claude: return "Claude Code"
 case .codex: return "OpenAI Codex"
 case .cursor: return "Cursor"
 case .aider: return "Aider"
 case .deepseek: return "DeepSeek"
 case .grok: return "Grok"
 case .gemini: return "Gemini CLI"
 case .opencode: return "OpenCode"
 }
 }
}

// MARK: - Engine Configuration

public struct EngineConfiguration: Sendable, Codable, Equatable {
 public let engineType: EngineType
 public var binaryPath: String?
 public var model: String
 public var workingDirectory: String?
 public var environment: [String: String]
 public var apiKey: String?
 public var maxTokens: Int
 public var maxTurns: Int
 public var supportsStreaming: Bool
 public var supportsToolUse: Bool
 public var supportsMultiTurn: Bool
 public var extraEnvironment: [String: String]
 public var autoRestart: Bool
 public var maxRestartAttempts: Int
 public var restartDelay: Duration

 public init(
 engineType: EngineType,
 binaryPath: String? = nil,
 model: String = "default",
 workingDirectory: String? = nil,
 environment: [String: String] = [:],
 apiKey: String? = nil,
 maxTokens: Int = 4096,
 maxTurns: Int = 10,
 supportsStreaming: Bool = true,
 supportsToolUse: Bool = true,
 supportsMultiTurn: Bool = true,
 extraEnvironment: [String: String] = [:],
 autoRestart: Bool = true,
 maxRestartAttempts: Int = 3,
 restartDelay: Duration = .seconds(2)
 ) {
 self.engineType = engineType
 self.binaryPath = binaryPath
 self.model = model
 self.workingDirectory = workingDirectory
 self.environment = environment
 self.apiKey = apiKey
 self.maxTokens = maxTokens
 self.maxTurns = maxTurns
 self.supportsStreaming = supportsStreaming
 self.supportsToolUse = supportsToolUse
 self.supportsMultiTurn = supportsMultiTurn
 self.extraEnvironment = extraEnvironment
 self.autoRestart = autoRestart
 self.maxRestartAttempts = maxRestartAttempts
 self.restartDelay = restartDelay
 }
}

// MARK: - Agent Engine Protocol

public protocol AgentEngine: Sendable {
 associatedtype StreamChunk: Sendable

 var type: EngineType { get }
 var displayName: String { get }
 var iconName: String { get }
 var configuration: EngineConfiguration { get }
 var supportsStreaming: Bool { get }
 var supportsToolUse: Bool { get }
 var supportsMultiTurn: Bool { get }

 func connect() async throws
 func disconnect() async throws
 func sendMessage(
 _ message: AgentMessage,
 session: AgentSession
 ) async throws -> AsyncThrowingStream<AgentStreamChunk, Error>
 func cancelGeneration() async throws
 func healthCheck() async -> EngineHealth
}

// MARK: - Agent Stream Chunk

public enum AgentStreamChunk: Sendable, Equatable {
 case text(String)
 case toolCall(AgentToolCall)
 case thinking(String)
 case error(String)
 case done

 public var text: String? {
 if case .text(let text) = self { return text }
 return nil
 }
}

// MARK: - Agent Tool Call

public struct AgentToolCall: Sendable, Equatable, Codable {
 public let id: String
 public let name: String
 public let arguments: [String: JSONValue]
 public let result: String?

 public init(id: String, name: String, arguments: [String: JSONValue], result: String? = nil) {
 self.id = id
 self.name = name
 self.arguments = arguments
 self.result = result
 }
}

// MARK: - Agent Message

public struct AgentMessage: Sendable, Equatable, Codable {
 public let id: String
 public let content: String
 public let systemInstruction: String?
 public let attachments: [AgentAttachment]
 public let metadata: [String: JSONValue]

 public init(
 id: String = UUID().uuidString,
 content: String,
 systemInstruction: String? = nil,
 attachments: [AgentAttachment] = [],
 metadata: [String: JSONValue] = [:]
 ) {
 self.id = id
 self.content = content
 self.systemInstruction = systemInstruction
 self.attachments = attachments
 self.metadata = metadata
 }
}

// MARK: - Agent Attachment

public struct AgentAttachment: Sendable, Equatable, Codable {
 public let id: String
 public let url: URL?
 public let localPath: URL?
 public let mimeType: String?
 public let data: Data?

 public init(
 id: String = UUID().uuidString,
 url: URL? = nil,
 localPath: URL? = nil,
 mimeType: String? = nil,
 data: Data? = nil
 ) {
 self.id = id
 self.url = url
 self.localPath = localPath
 self.mimeType = mimeType
 self.data = data
 }
}

// MARK: - Agent Session

public struct AgentSession: Sendable, Equatable, Codable, Identifiable {
 public let id: String
 public var engineType: EngineType
 public var messages: [AgentTurn]
 public var systemPrompt: String?
 public var workingDirectory: String?
 public var metadata: [String: JSONValue]
 public var createdAt: Date
 public var updatedAt: Date

 public var history: [AgentTurn] { messages }

 public init(
 id: String = UUID().uuidString,
 engineType: EngineType,
 messages: [AgentTurn] = [],
 systemPrompt: String? = nil,
 workingDirectory: String? = nil,
 metadata: [String: JSONValue] = [:]
 ) {
 self.id = id
 self.engineType = engineType
 self.messages = messages
 self.systemPrompt = systemPrompt
 self.workingDirectory = workingDirectory
 self.metadata = metadata
 self.createdAt = Date()
 self.updatedAt = Date()
 }
}

// MARK: - Agent Turn

public struct AgentTurn: Sendable, Equatable, Codable, Identifiable {
 public let id: String
 public let role: AgentRole
 public let content: String
 public let toolCalls: [AgentToolCall]
 public let timestamp: Date
 public let tokenCount: Int?

 public init(
 id: String = UUID().uuidString,
 role: AgentRole,
 content: String,
 toolCalls: [AgentToolCall] = [],
 tokenCount: Int? = nil
 ) {
 self.id = id
 self.role = role
 self.content = content
 self.toolCalls = toolCalls
 self.timestamp = Date()
 self.tokenCount = tokenCount
 }
}

// MARK: - Agent Role

public enum AgentRole: String, Codable, Equatable, Sendable, CaseIterable {
 case user = "user"
 case assistant = "assistant"
 case system = "system"
 case tool = "tool"
}

// MARK: - Engine Health

public struct EngineHealth: Sendable, Equatable {
 public enum Status: String, Sendable, Equatable {
 case healthy
 case degraded
 case offline
 case unknown
 }

 public let status: Status
 public let latencyMs: Double?
 public let message: String?
 public let timestamp: Date

 public init(status: Status, latencyMs: Double? = nil, message: String? = nil) {
 self.status = status
 self.latencyMs = latencyMs
 self.message = message
 self.timestamp = Date()
 }
}

// MARK: - Agent Engine Errors

public enum AgentEngineError: LocalizedError, Equatable, Sendable {
 case notConnected
 case sendFailed(Error)
 case readFailed(Error)
 case invalidMessage
 case invalidResponse(String)
 case remoteError(String)
 case connectionLost
 case notFound
 case configurationError(String)

 public var errorDescription: String? {
 switch self {
 case .notConnected:
 return "Engine is not connected"
 case .sendFailed(let error):
 return "Failed to send message: \(error.localizedDescription)"
 case .readFailed(let error):
 return "Failed to read response: \(error.localizedDescription)"
 case .invalidMessage:
 return "Invalid message format"
 case .invalidResponse(let message):
 return "Invalid response from engine: \(message)"
 case .remoteError(let message):
 return "Engine error: \(message)"
 case .connectionLost:
 return "Connection to engine was lost"
 case .notFound:
 return "Engine binary not found"
 case .configurationError(let message):
 return "Engine configuration error: \(message)"
 }
 }
}
