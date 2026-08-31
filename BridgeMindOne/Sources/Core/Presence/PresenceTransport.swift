//
// PresenceTransport.swift
// IPC and presence management
//

import Foundation

// MARK: - Presence Protocol

public protocol PresenceTransport: Sendable {
 func broadcastPresence(_ presence: PresenceState) async throws
 func listenForPresence() async throws -> AsyncStream<PresenceState>
 func announceAgent(_ agent: AgentIdentity) async throws
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

public enum AgentPresenceStatus: String, Codable, Equatable {
 case online
 case away
 case busy
 case offline
 case error
}

// MARK: - IPC Names

public enum IPCName: String, Codable, Equatable {
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
 services[service]?.disconnect()
 services.removeValue(forKey: service)
 }

 public func disconnectAll() async {
 for service in services.keys {
 await disconnect(service: service)
 }
 }

 public func isConnected(service: IPCName) -> Bool {
 services[service]?.isConnected ?? false
 }
}

// MARK: - XPC Connection (simplified)

public actor XPCConnection {
 private let serviceName: String
 public private(set) var isConnected = false

 public init(serviceName: String) {
 self.serviceName = serviceName
 }

 public func connect() async throws {
 // XPC connection would be established here
 // Using NSXPCConnection on macOS
 isConnected = true
 }

 public func disconnect() {
 isConnected = false
 }

 public func send(message: Data) async throws -> Data? {
 guard isConnected else { throw PresenceError.notConnected }
 // Send message via XPC
 return nil
 }
}

// MARK: - Errors

public enum PresenceError: Error, Equatable {
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
