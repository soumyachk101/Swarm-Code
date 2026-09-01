//
// PresenceTransport.swift
// IPC and presence management
//

import Foundation

// MARK: - Presence Protocol

public protocol PresenceTransport: Sendable {
    func broadcastPresence(_ presence: PresenceState) async throws
    func listenForPresence() async throws -> AsyncStream<PresenceState>
    func announceAgent(agentId: String, name: String) async throws
    func announceDisconnect(agentId: String) async throws
}

// MARK: - Presence State

public struct PresenceState: Codable, Equatable, Sendable {
    public let agentId: String
    public let agentName: String
    public let status: AgentPresenceStatus
    public let lastSeen: Date
    public let capabilities: [String]

    public init(
        agentId: String,
        agentName: String,
        status: AgentPresenceStatus = .online,
        lastSeen: Date = Date(),
        capabilities: [String] = []
    ) {
        self.agentId = agentId
        self.agentName = agentName
        self.status = status
        self.lastSeen = lastSeen
        self.capabilities = capabilities
    }
}

public enum AgentPresenceStatus: String, Codable, Equatable, Sendable {
    case online
    case away
    case busy
    case offline
    case error
}

// MARK: - IPC Names

public enum IPCName: String, Codable, Equatable, Sendable {
    case loopback = "bridgemind.one.loopback"
    case agentRun = "bridgemind.one.agent-run"
    case supervisedChild = "bridgemind.one.supervised-child"
    case chatSQLite = "bridgemind.one.chat-sqlite"
    case sessionPersistence = "bridgemind.one.session-persistence"
    case presenceIPC = "bridgemind.one.presence.ipc"
    case metricReports = "bridgemind.one.metric-reports"
    case perfSampler = "bridgemind.one.perf.sampler"
    case perfSink = "bridgemind.one.perf.sink"
    case perfWatchdog = "bridgemind.one.perf.watchdog"
    case pluginGateway = "bridgemind.one.plugin-gateway"
    case pluginOAuth = "bridgemind.one.plugin-oauth"
}

// MARK: - XPC Service Manager

public actor XPCServiceManager {
    private var services: [IPCName: XPCConnection] = [:]

    public init() {}

    public func connect(to service: IPCName) async throws -> XPCConnection {
        if let existing = services[service] {
            return existing
        }

        let connection = XPCConnection(serviceName: service.rawValue)
        try await connection.connect()
        services[service] = connection
        return connection
    }

    public func disconnect(service: IPCName) async {
        await services[service]?.disconnect()
        services.removeValue(forKey: service)
    }

    public func disconnectAll() async {
        for service in services.keys {
            await disconnect(service: service)
        }
    }

    public func isConnected(service: IPCName) async -> Bool {
        if let connection = services[service] {
            return await connection.checkIsConnected()
        }
        return false
    }
}

// MARK: - XPC Connection (simplified)

public actor XPCConnection {
    private let serviceName: String
    private var connected = false

    public init(serviceName: String) {
        self.serviceName = serviceName
    }

    public func connect() async throws {
        connected = true
    }

    public func disconnect() {
        connected = false
    }

    public func checkIsConnected() -> Bool {
        connected
    }

    public func send(message: Data) async throws -> Data? {
        guard connected else { throw PresenceError.notConnected }
        return nil
    }
}

// MARK: - Errors

public enum PresenceError: Error, Equatable, Sendable {
    case notConnected
    case serviceNotFound(String)
    case messageFailed(String)

    public var localizedDescription: String {
        switch self {
        case .notConnected: return "Not connected to service"
        case .serviceNotFound(let name): return "Service not found: \(name)"
        case .messageFailed(let msg): return "Message failed: \(msg)"
        }
    }
}

