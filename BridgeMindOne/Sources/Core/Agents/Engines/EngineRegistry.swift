//
// EngineRegistry.swift
// Registry of all available AI coding agent engines
//

import Foundation
import Combine

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
 ) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error>
 func cancelGeneration() async throws
 func healthCheck() async -> EngineHealth
}

// MARK: - Engine Registry

public actor EngineRegistry: Sendable {
 public static let shared = EngineRegistry()

 // Published state
 @Published public private(set) var availableEngines: [EngineType: Bool] = [:]
 @Published public private(set) var engineCapabilities: [EngineType: EngineCapabilities] = [:]
 @Published public private(set) var engineConfigurations: [EngineType: EngineConfiguration] = [:]

 // Detection results
 public struct DetectionResult: Sendable, Equatable {
 public let engineType: EngineType
 public let isAvailable: Bool
 public let binaryPath: String?
 public let version: String?
 public let capabilities: EngineCapabilities
 public let error: String?

 public init(
 engineType: EngineType,
 isAvailable: Bool,
 binaryPath: String? = nil,
 version: String? = nil,
 capabilities: EngineCapabilities? = nil,
 error: String? = nil
 ) {
 self.engineType = engineType
 self.isAvailable = isAvailable
 self.binaryPath = binaryPath
 self.version = version
 self.capabilities = capabilities ?? EngineCapabilities(
 supportsStreaming: false,
 supportsToolUse: false,
 supportsMultiTurn: false,
 supportsFileEditing: false,
 supportsWorkspaceAccess: false
 )
 self.error = error
 }
 }

 public struct EngineCapabilities: Sendable, Codable, Equatable {
 public let supportsStreaming: Bool
 public let supportsToolUse: Bool
 public let supportsMultiTurn: Bool
 public let supportsFileEditing: Bool
 public let supportsWorkspaceAccess: Bool

 public init(
 supportsStreaming: Bool = true,
 supportsToolUse: Bool = true,
 supportsMultiTurn: Bool = true,
 supportsFileEditing: Bool = false,
 supportsWorkspaceAccess: Bool = false
 ) {
 self.supportsStreaming = supportsStreaming
 self.supportsToolUse = supportsToolUse
 self.supportsMultiTurn = supportsMultiTurn
 self.supportsFileEditing = supportsFileEditing
 self.supportsWorkspaceAccess = supportsWorkspaceAccess
 }
 }

 // Storage
 private var engines: [EngineType: any AgentEngine] = [:]
 private var discoveryTask: Task<Void, Error>?

 // Init
 private init() {
 registerDefaultConfigurations()
 }

 // MARK: Public API

 public func detectAllEngines() async -> [DetectionResult] {
 return await withTaskGroup(of: DetectionResult.self) { group in
 for type in EngineType.allCases {
 group.addTask {
 await self.detectEngine(type)
 }
 }

 var results: [DetectionResult] = []
 for await result in group {
 results.append(result)
 }
 return results
 }
}

 public func detectEngine(_ type: EngineType) async -> DetectionResult {
 let binaryName = defaultBinaryName(for: type)
 let binaryPath = await AgentProcess.findBinary(binaryName)

 if let path = binaryPath {
 let version = await probeVersion(for: type, at: path)
 let capabilities = capabilities(for: type)
 return DetectionResult(
 engineType: type,
 isAvailable: true,
 binaryPath: path,
 version: version,
 capabilities: capabilities
 )
 } else {
 return DetectionResult(
 engineType: type,
 isAvailable: false,
 error: "Binary '\(binaryName)' not found in PATH"
 )
 }
 }

 public func isAvailable(_ type: EngineType) -> Bool {
 availableEngines[type] ?? false
 }

 public func configuration(for type: EngineType) -> EngineConfiguration {
 engineConfigurations[type] ?? defaultConfiguration(for: type)
 }

 public func createEngine(for type: EngineType) throws -> any AgentEngine {
 guard isAvailable(type) else {
 throw AgentEngineError.notFound
 }

 let config = configuration(for: type)

 switch type {
 case .claude:
 return try ClaudeEngine(configuration: config)
 case .codex:
 return try CodexEngine(configuration: config)
 case .cursor:
 return try CursorEngine(configuration: config)
 case .aider:
 return try AiderEngine(configuration: config)
 case .deepseek:
 return try DeepSeekEngine(configuration: config)
 case .grok:
 return try GrokEngine(configuration: config)
 case .gemini:
 return try GeminiEngine(configuration: config)
 case .opencode:
 return try OpenCodeEngine(configuration: config)
 }
 }

 public func engine(for type: EngineType) async throws -> any AgentEngine {
 if let existing = engines[type] {
 return existing
 }

 let engine = try createEngine(for: type)
 engines[type] = engine
 return engine
 }

 public func capabilities(for type: EngineType) -> EngineCapabilities {
 if let caps = engineCapabilities[type] { return caps }
 return capabilities(for: type)
 }

 public func refreshAvailability() async {
 discoveryTask?.cancel()
 discoveryTask = Task {
 let results = await detectAllEngines()
 let newAvailability: [EngineType: Bool] = [:]
 let newCapabilities: [EngineType: EngineCapabilities] = [:]

 for result in results {
 newAvailability[result.engineType] = result.isAvailable
 if result.isAvailable {
 newCapabilities[result.engineType] = result.capabilities
 }
 }

 await MainActor.run {
 self.availableEngines = newAvailability
 self.engineCapabilities = newCapabilities
 }
 }
 }

 // MARK: Private Helpers

 private func registerDefaultConfigurations() {
 for type in EngineType.allCases {
 engineConfigurations[type] = defaultConfiguration(for: type)
 engineCapabilities[type] = capabilities(for: type)
 }
 }

 private func defaultBinaryName(for type: EngineType) -> String {
 switch type {
 case .claude: return "claude"
 case .codex: return "codex"
 case .cursor: return "cursor"
 case .aider: return "aider"
 case .deepseek: return "deepseek"
 case .grok: return "grok"
 case .gemini: return "gemini"
 case .opencode: return "opencode"
 }
 }

 private func defaultConfiguration(for type: EngineType) -> EngineConfiguration {
 let models: [EngineType: String] = [
 .claude: "claude-sonnet-4-20250514",
 .codex: "gpt-4",
 .cursor: "claude-3.5-sonnet",
 .aider: "claude-3-5-sonnet-20241022",
 .deepseek: "deepseek-chat",
 .grok: "grok-3",
 .gemini: "gemini-2.0-flash",
 .opencode: "claude-3-5-sonnet"
 ]

 let caps = capabilities(for: type)

 return EngineConfiguration(
 engineType: type,
 binaryPath: nil,
 model: models[type] ?? "default",
 supportsStreaming: caps.supportsStreaming,
 supportsToolUse: caps.supportsToolUse,
 supportsMultiTurn: caps.supportsMultiTurn,
 autoRestart: true,
 maxRestartAttempts: 3,
 restartDelay: .seconds(2)
 )
 }

 private func capabilities(for type: EngineType) -> EngineCapabilities {
 switch type {
 case .claude, .codex, .cursor, .aider, .deepseek, .opencode:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .grok, .gemini:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: false,
 supportsWorkspaceAccess: false
 )
 }
 }

 private func probeVersion(for type: EngineType, at path: String) async -> String? {
 let task = Process()
 task.executableURL = URL(fileURLWithPath: path)
 task.arguments = ["--version"]
 task.standardOutput = Pipe()
 task.standardError = Pipe()

 do {
 try task.run()
 task.waitUntilExit()

 let pipe = task.standardOutput as! Pipe
 let data = pipe.fileHandleForReading.readDataToEndOfFile()
 let output = String(data: data, encoding: .utf8) ?? ""
 let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
 return cleaned.isEmpty ? nil : cleaned
 } catch {
 return nil
 }
 }
}

// MARK: - Placeholder Engines

public struct AiderEngine: AgentEngine {
 public typealias StreamChunk = AgentStreamChunk
 public let type: EngineType = .aider
 public let displayName: String = "Aider"
 public let iconName: String = "agent-aider"
 public let supportsStreaming: Bool = true
 public let supportsToolUse: Bool = true
 public let supportsMultiTurn: Bool = true
 public let configuration: EngineConfiguration

 public init(configuration: EngineConfiguration) {
 self.configuration = configuration
 }

 public func connect() async throws {}
 public func disconnect() async throws {}
 public func sendMessage(_ message: AgentMessage, session: AgentSession) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 AsyncThrowingStream { $0.finish(throwing: AgentEngineError.configurationError("Aider adapter not yet implemented")) }
 }
 public func cancelGeneration() async throws {}
 public func healthCheck() async -> EngineHealth {
 EngineHealth(status: .unknown, message: "Not yet implemented")
 }
}

public struct DeepSeekEngine: AgentEngine {
 public typealias StreamChunk = AgentStreamChunk
 public let type: EngineType = .deepseek
 public let displayName: String = "DeepSeek"
 public let iconName: String = "agent-deepseek"
 public let supportsStreaming: Bool = true
 public let supportsToolUse: Bool = true
 public let supportsMultiTurn: Bool = true
 public let configuration: EngineConfiguration

 public init(configuration: EngineConfiguration) {
 self.configuration = configuration
 }

 public func connect() async throws {}
 public func disconnect() async throws {}
 public func sendMessage(_ message: AgentMessage, session: AgentSession) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 AsyncThrowingStream { $0.finish(throwing: AgentEngineError.configurationError("DeepSeek adapter not yet implemented")) }
 }
 public func cancelGeneration() async throws {}
 public func healthCheck() async -> EngineHealth {
 EngineHealth(status: .unknown, message: "Not yet implemented")
 }
}

public struct GrokEngine: AgentEngine {
 public typealias StreamChunk = AgentStreamChunk
 public let type: EngineType = .grok
 public let displayName: String = "Grok"
 public let iconName: String = "agent-grok"
 public let supportsStreaming: Bool = true
 public let supportsToolUse: Bool = true
 public let supportsMultiTurn: Bool = true
 public let configuration: EngineConfiguration

 public init(configuration: EngineConfiguration) {
 self.configuration = configuration
 }

 public func connect() async throws {}
 public func disconnect() async throws {}
 public func sendMessage(_ message: AgentMessage, session: AgentSession) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 AsyncThrowingStream { $0.finish(throwing: AgentEngineError.configurationError("Grok adapter not yet implemented")) }
 }
 public func cancelGeneration() async throws {}
 public func healthCheck() async -> EngineHealth {
 EngineHealth(status: .unknown, message: "Not yet implemented")
 }
}

public struct GeminiEngine: AgentEngine {
 public typealias StreamChunk = AgentStreamChunk
 public let type: EngineType = .gemini
 public let displayName: String = "Gemini CLI"
 public let iconName: String = "agent-gemini"
 public let supportsStreaming: Bool = true
 public let supportsToolUse: Bool = true
 public let supportsMultiTurn: Bool = true
 public let configuration: EngineConfiguration

 public init(configuration: EngineConfiguration) {
 self.configuration = configuration
 }

 public func connect() async throws {}
 public func disconnect() async throws {}
 public func sendMessage(_ message: AgentMessage, session: AgentSession) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 AsyncThrowingStream { $0.finish(throwing: AgentEngineError.configurationError("Gemini adapter not yet implemented")) }
 }
 public func cancelGeneration() async throws {}
 public func healthCheck() async -> EngineHealth {
 EngineHealth(status: .unknown, message: "Not yet implemented")
 }
}

public struct OpenCodeEngine: AgentEngine {
 public typealias StreamChunk = AgentStreamChunk
 public let type: EngineType = .opencode
 public let displayName: String = "OpenCode"
 public let iconName: String = "agent-opencode"
 public let supportsStreaming: Bool = true
 public let supportsToolUse: Bool = true
 public let supportsMultiTurn: Bool = true
 public let configuration: EngineConfiguration

 public init(configuration: EngineConfiguration) {
 self.configuration = configuration
 }

 public func connect() async throws {}
 public func disconnect() async throws {}
 public func sendMessage(_ message: AgentMessage, session: AgentSession) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 AsyncThrowingStream { $0.finish(throwing: AgentEngineError.configurationError("OpenCode adapter not yet implemented")) }
 }
 public func cancelGeneration() async throws {}
 public func healthCheck() async -> EngineHealth {
 EngineHealth(status: .unknown, message: "Not yet implemented")
 }
}
