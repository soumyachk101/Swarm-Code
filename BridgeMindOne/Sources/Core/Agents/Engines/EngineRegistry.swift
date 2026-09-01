//
// EngineRegistry.swift
// Registry of all available AI coding agent engines
//

import Foundation
import Combine

// MARK: - Engine Registry

public actor EngineRegistry: Sendable {
    public static let shared = EngineRegistry()

    // Published state
    public private(set) var availableEngines: [EngineType: Bool] = [:]
    public private(set) var engineCapabilities: [EngineType: EngineCapabilities] = [:]
    public private(set) var engineConfigurations: [EngineType: EngineConfiguration] = [:]

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
    public init() {
        var configs: [EngineType: EngineConfiguration] = [:]
        var caps: [EngineType: EngineCapabilities] = [:]
        for type in EngineType.allCases {
            configs[type] = Self.defaultConfiguration(for: type)
            caps[type] = Self.defaultCapabilities(for: type)
        }
        self.engineConfigurations = configs
        self.engineCapabilities = caps
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
        let binaryPath = AgentProcess.findBinary(binaryName)

        if let path = binaryPath {
            return DetectionResult(
                engineType: type,
                isAvailable: true,
                binaryPath: path,
                capabilities: capabilities(for: type)
            )
        } else {
            return DetectionResult(
                engineType: type,
                isAvailable: false,
                capabilities: capabilities(for: type),
                error: "\(type.displayName) binary not found"
            )
        }
    }

    public func isAvailable(_ type: EngineType) -> Bool {
        availableEngines[type] ?? false
    }

    public func configuration(for type: EngineType) -> EngineConfiguration {
        engineConfigurations[type] ?? Self.defaultConfiguration(for: type)
    }

    public func setConfiguration(_ config: EngineConfiguration, for type: EngineType) {
        engineConfigurations[type] = config
    }

    public func engine(for type: EngineType) async throws -> any AgentEngine {
        if let existing = engines[type] {
            return existing
        }
        let created = try createEngine(for: type)
        engines[type] = created
        return created
    }

    private func createEngine(for type: EngineType) throws -> any AgentEngine {
        let config = configuration(for: type)
        switch type {
        case .claude:
            return try ClaudeEngine(configuration: config)
        case .codex:
            return try CodexEngine(configuration: config)
        case .cursor:
            return try CursorEngine(configuration: config)
        case .aider:
            return AiderEngine(configuration: config)
        case .deepseek:
            return DeepSeekEngine(configuration: config)
        case .grok:
            return GrokEngine(configuration: config)
        case .gemini:
            return GeminiEngine(configuration: config)
        case .opencode:
            return OpenCodeEngine(configuration: config)
        }
    }

    public func capabilities(for type: EngineType) -> EngineCapabilities {
        if let caps = engineCapabilities[type] { return caps }
        return Self.defaultCapabilities(for: type)
    }

    public func refreshAvailability() async {
        discoveryTask?.cancel()
        discoveryTask = Task {
            let results = await self.detectAllEngines()
            var newAvailability: [EngineType: Bool] = [:]
            var newCapabilities: [EngineType: EngineCapabilities] = [:]

            for result in results {
                newAvailability[result.engineType] = result.isAvailable
                if result.isAvailable {
                    newCapabilities[result.engineType] = result.capabilities
                }
            }

            self.availableEngines = newAvailability
            self.engineCapabilities = newCapabilities
        }
    }

    // MARK: Static Helpers

    public static func defaultCapabilities(for type: EngineType) -> EngineCapabilities {
        switch type {
        case .claude, .codex, .cursor, .aider:
            return EngineCapabilities(supportsStreaming: true, supportsToolUse: true, supportsMultiTurn: true, supportsFileEditing: true, supportsWorkspaceAccess: true)
        default:
            return EngineCapabilities(supportsStreaming: true, supportsToolUse: true, supportsMultiTurn: true, supportsFileEditing: false, supportsWorkspaceAccess: false)
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

    public static func defaultConfiguration(for type: EngineType) -> EngineConfiguration {
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

        let caps = defaultCapabilities(for: type)

        return EngineConfiguration(
            engineType: type,
            binaryPath: nil,
            model: models[type] ?? "default",
            supportsStreaming: caps.supportsStreaming,
            supportsToolUse: caps.supportsToolUse,
            supportsMultiTurn: caps.supportsMultiTurn
        )
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
        AsyncThrowingStream { cont in
            cont.yield(.text("Aider engine ready."))
            cont.finish()
        }
    }
    public func cancelGeneration() async throws {}
    public func healthCheck() async -> EngineHealth {
        EngineHealth(status: .unknown, message: "Aider engine")
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
        AsyncThrowingStream { cont in
            cont.yield(.text("DeepSeek engine ready."))
            cont.finish()
        }
    }
    public func cancelGeneration() async throws {}
    public func healthCheck() async -> EngineHealth {
        EngineHealth(status: .unknown, message: "DeepSeek engine")
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
        AsyncThrowingStream { cont in
            cont.yield(.text("Grok engine ready."))
            cont.finish()
        }
    }
    public func cancelGeneration() async throws {}
    public func healthCheck() async -> EngineHealth {
        EngineHealth(status: .unknown, message: "Grok engine")
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
        AsyncThrowingStream { cont in
            cont.yield(.text("Gemini engine ready."))
            cont.finish()
        }
    }
    public func cancelGeneration() async throws {}
    public func healthCheck() async -> EngineHealth {
        EngineHealth(status: .unknown, message: "Gemini engine")
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
        AsyncThrowingStream { cont in
            cont.yield(.text("OpenCode engine ready."))
            cont.finish()
        }
    }
    public func cancelGeneration() async throws {}
    public func healthCheck() async -> EngineHealth {
        EngineHealth(status: .unknown, message: "OpenCode engine")
    }
}
