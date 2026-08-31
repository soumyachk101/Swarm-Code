//
// EngineRegistry.swift
// Registry of all available AI coding agent engines
//
// Auto-detects installed agent binaries, manages engine instances,
// tracks capabilities, and provides per-engine configuration.
// Bridges the bridgemind.one.agent-run service discovery pattern.
//

import Foundation
import Combine

// MARK: - EngineRegistry

public actor EngineRegistry: Sendable {
 public static let shared = EngineRegistry()

 // MARK: Published State

 @Published public private(set) var availableEngines: [EngineType: Bool] = [:]
 @Published public private(set) var engineCapabilities: [EngineType: EngineCapabilities] = [:]
 @Published public private(set) var engineConfigurations: [EngineType: EngineConfiguration] = [:]

 // MARK: Detection Results

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

 // MARK: Engine Capabilities

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

 // MARK: Private

 private var engines: [EngineType: any AgentEngine] = [:]
 private var discoveryTask: Task<Void, Error>?
 private let discoveryQueue = DispatchQueue(label: "ai.bridgemind.one.engine-registry", attributes: .concurrent)

 // MARK: Init

 private init() {
 // Register default configurations for all known engine types
 registerDefaultConfigurations()
 }

 // MARK: Public API

 /// Auto-detect all available engines on the system
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

 /// Detect a specific engine
 public func detectEngine(_ type: EngineType) async -> DetectionResult {
 let binaryName = Self.defaultBinaryName(for: type)
 let binaryPath = await AgentProcess.findBinary(binaryName)

 if let path = binaryPath {
 let version = await Self.probeVersion(for: type, at: path)
 let capabilities = Self.capabilities(for: type)
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

 /// Check if a specific engine is available
 public func isAvailable(_ type: EngineType) -> Bool {
 return availableEngines[type] ?? false
 }

 /// Get the default configuration for an engine type
 public func configuration(for type: EngineType) -> EngineConfiguration {
 return engineConfigurations[type] ?? Self.defaultConfiguration(for: type)
 }

 /// Create an engine instance
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

 /// Get or create an engine instance for a type
 public func engine(for type: EngineType) async throws -> any AgentEngine {
 if let existing = engines[type] {
 return existing
 }

 let engine = try createEngine(for: type)
 engines[type] = engine
 return engine
 }

 /// Get capabilities for an engine type
 public func capabilities(for type: EngineType) -> EngineCapabilities {
 if let caps = engineCapabilities[type] { return caps }
 return Self.capabilities(for: type)
 }

 /// Run a one-time discovery of all engines and update state
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
 }

 // MARK: Private

 private func registerDefaultConfigurations() {
 for type in EngineType.allCases {
 engineConfigurations[type] = Self.defaultConfiguration(for: type)
 engineCapabilities[type] = Self.capabilities(for: type)
 }
 }

 private static func defaultBinaryName(for type: EngineType) -> String {
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

 private static func defaultConfiguration(for type: EngineType) -> EngineConfiguration {
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

 private static func capabilities(for type: EngineType) -> EngineCapabilities {
 switch type {
 case .claude:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .codex:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .cursor:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .aider:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .deepseek:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 case .grok:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: false,
 supportsWorkspaceAccess: false
 )
 case .gemini:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: false,
 supportsWorkspaceAccess: false
 )
 case .opencode:
 return EngineCapabilities(
 supportsStreaming: true,
 supportsToolUse: true,
 supportsMultiTurn: true,
 supportsFileEditing: true,
 supportsWorkspaceAccess: true
 )
 }
 }

 private static func probeVersion(for type: EngineType, at path: String) async -> String? {
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

// Lightweight stubs for engines not yet implemented as full adapters.
// They conform to AgentEngine for registry compatibility but defer full
// implementation to their respective Engine adapters.

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
