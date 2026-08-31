//
// AgentManager.swift
// High-level agent management — creation, supervision, IPC
//
// Bridges the bridgemind.one.agent-run and bridgemind.one.supervised-child
// internal service architecture into a Swift-native agent supervisor.
//
// Responsibilities:
// - Create/destroy agent instances
// - Assign agents to chat sessions
// - Agent supervision (restart on crash)
// - Agent communication via presence IPC
// - Working directory isolation per agent
//

import Foundation
import Combine

// MARK: - Agent Manager

public actor AgentManager: Sendable {
 // MARK: Agent Record

 public struct AgentRecord: Sendable, Equatable, Identifiable {
 public let id: String
 public var engineType: EngineType
 public var configuration: EngineConfiguration
 public var session: AgentSession
 public var processState: AgentProcess.ProcessState
 public var engineState: EngineHealth.Status
 public var createdAt: Date
 public var lastActivity: Date
 public var crashCount: Int
 public var isActive: Bool

 public init(
 id: String = UUID().uuidString,
 engineType: EngineType,
 configuration: EngineConfiguration,
 session: AgentSession
 ) {
 self.id = id
 self.engineType = engineType
 self.configuration = configuration
 self.session = session
 self.processState = .idle
 self.engineState = .unknown
 self.createdAt = Date()
 self.lastActivity = Date()
 self.crashCount = 0
 self.isActive = false
 }
 }

 // MARK: Agent Events

 public struct AgentEvent: Sendable, Equatable {
 public let agentId: String
 public let type: AgentEventType
 public let timestamp: Date
 public let message: String?

 public init(agentId: String, type: AgentEventType, message: String? = nil) {
 self.agentId = agentId
 self.type = type
 self.timestamp = Date()
 self.message = message
 }
 }

 public enum AgentEventType: Sendable, Equatable {
 case created
 case connected
 case messageReceived
 case messageSent
 case crashed(exitCode: Int32)
 case restarted(attempt: Int)
 case stopped
 case destroyed
 case error(String)
 }

 // MARK: Agent Manager Errors

 public enum AgentManagerError: LocalizedError, Equatable, Sendable {
 case agentNotFound(String)
 case agentAlreadyActive(String)
 case engineUnavailable(EngineType)
 case supervisionDisabled(String)
 case ipcUnavailable(String)
 case configurationError(String)

 public var errorDescription: String? {
 switch self {
 case .agentNotFound(let id):
 return "Agent not found: \(id)"
 case .agentAlreadyActive(let id):
 return "Agent already active: \(id)"
 case .engineUnavailable(let type):
 return "Engine '\(type.rawValue)' is not available"
 case .supervisionDisabled(let message):
 return "Supervision disabled: \(message)"
 case .ipcUnavailable(let message):
 return "IPC unavailable: \(message)"
 case .configurationError(let message):
 return "Configuration error: \(message)"
 }
 }
 }

 // MARK: Properties

 private let registry: EngineRegistry
 private var agents: [String: AgentRecord] = [:]
 private var activeEngines: [String: any AgentEngine] = [:]
 private let eventSubject = PassthroughSubject<AgentEvent, Never>()
 private let presence: PresenceIPC?
 private var supervisionTasks: [String: Task<Void, Error>] = [:]

 // MARK: Init

 public init(
 registry: EngineRegistry = EngineRegistry.shared,
 presence: PresenceIPC? = nil
 ) {
 self.registry = registry
 self.presence = presence
 }

 deinit {
 for task in supervisionTasks.values {
 task.cancel()
 }
 }

 // MARK: Public API

 public var events: AnyPublisher<AgentEvent, Never> {
 eventSubject.eraseToAnyPublisher()
 }

 public var agentCount: Int { agents.count }
 public var activeAgentCount: Int { agents.values.filter { $0.isActive }.count }

 /// Create a new agent
 public func createAgent(
 engineType: EngineType,
 session: AgentSession,
 configuration: EngineConfiguration? = nil
 ) async throws -> AgentRecord {
 guard !agents.values.contains(where: { $0.session.id == session.id }) else {
 throw AgentManagerError.configurationError("Session already has an assigned agent")
 }

 let config = configuration ?? registry.configuration(for: engineType)
 let record = AgentRecord(
 engineType: engineType,
 configuration: config,
 session: session
 )

 agents[record.id] = record
 eventSubject.send(AgentEvent(agentId: record.id, type: .created))

 return record
 }

 /// Destroy an agent and clean up resources
 public func destroyAgent(_ agentId: String) async throws {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 // Stop supervision
 supervisionTasks[agentId]?.cancel()
 supervisionTasks.removeValue(forKey: agentId)

 // Disconnect engine
 if let engine = activeEngines[agentId] {
 do {
 try await engine.disconnect()
 } catch {
 // Best-effort disconnect
 }
 }
 activeEngines.removeValue(forKey: agentId)

 agents.removeValue(forKey: agentId)
 eventSubject.send(AgentEvent(agentId: agentId, type: .destroyed))
 }

 /// Connect an agent (start the engine process)
 public func connectAgent(_ agentId: String) async throws {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 guard !record.isActive else {
 throw AgentManagerError.agentAlreadyActive(agentId)
 }

 // Check engine availability
 guard registry.isAvailable(record.engineType) else {
 throw AgentManagerError.engineUnavailable(record.engineType)
 }

 do {
 // Create engine instance if not already cached
 let engine = try await registry.engine(for: record.engineType)
 activeEngines[agentId] = engine

 // Connect the engine
 try await engine.connect()

 // Update record
 var updated = record
 updated.isActive = true
 updated.processState = .running(pid: await engine.healthCheck().latencyMs.map { _ in 0 } ?? 0)
 updated.lastActivity = Date()
 agents[agentId] = updated

 eventSubject.send(AgentEvent(agentId: agentId, type: .connected))

 // Begin supervision
 beginSupervision(for: agentId)

 // Announce via presence IPC
 await announcePresence(agentId, status: .online)

 } catch {
 // Clean up on failure
 activeEngines.removeValue(forKey: agentId)
 var failedRecord = record
 failedRecord.engineState = .offline
 agents[agentId] = failedRecord

 eventSubject.send(AgentEvent(
 agentId: agentId,
 type: .error(error.localizedDescription)
 ))
 throw error
 }
 }

 /// Disconnect an agent (stop the engine process)
 public func disconnectAgent(_ agentId: String) async throws {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 // Stop supervision
 supervisionTasks[agentId]?.cancel()
 supervisionTasks.removeValue(forKey: agentId)

 // Disconnect engine
 if let engine = activeEngines[agentId] {
 do {
 try await engine.disconnect()
 } catch {
 // Best effort
 }
 }
 activeEngines.removeValue(forKey: agentId)

 var updated = record
 updated.isActive = false
 updated.processState = .stopped(exitCode: 0)
 updated.lastActivity = Date()
 agents[agentId] = updated

 eventSubject.send(AgentEvent(agentId: agentId, type: .stopped))

 // Announce via presence IPC
 await announcePresence(agentId, status: .offline)
 }

 /// Send a message to an agent and get a streaming response
 public func sendMessage(
 to agentId: String,
 message: AgentMessage
 ) async throws -> AsyncThrowingStream<AgentStreamChunk, any Error> {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 guard let engine = activeEngines[agentId] else {
 throw AgentManagerError.configurationError("Agent engine not connected")
 }

 let stream = try await engine.sendMessage(message, session: record.session)

 // Update session with user turn
 var updatedSession = record.session
 updatedSession.messages.append(AgentTurn(role: .user, content: message.content))
 updatedSession.updatedAt = Date()
 var updatedRecord = record
 updatedRecord.session = updatedSession
 updatedRecord.lastActivity = Date()
 agents[agentId] = updatedRecord

 eventSubject.send(AgentEvent(agentId: agentId, type: .messageSent))

 return stream
 }

 /// Cancel an ongoing generation for an agent
 public func cancelGeneration(for agentId: String) async throws {
 guard activeEngines[agentId] != nil else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 try await activeEngines[agentId]?.cancelGeneration()
 }

 /// Get an agent record
 public func agent(_ agentId: String) -> AgentRecord? {
 return agents[agentId]
 }

 /// Get all agent records
 public func allAgents() -> [AgentRecord] {
 return Array(agents.values)
 }

 /// Get active agent records
 public func activeAgents() -> [AgentRecord] {
 return agents.values.filter { $0.isActive }.sorted { $0.lastActivity > $1.lastActivity }
 }

 /// Restart a crashed agent
 public func restartAgent(_ agentId: String) async throws {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 try await disconnectAgent(agentId)
 try await Task.sleep(nanoseconds: 1_000_000_000) // 1s cooldown
 try await connectAgent(agentId)

 var updated = agents[agentId] ?? record
 updated.crashCount = 0
 updated.lastActivity = Date()
 agents[agentId] = updated

 eventSubject.send(AgentEvent(
 agentId: agentId,
 type: .restarted(attempt: updated.crashCount)
 ))
 }

 /// Assign an agent to a different engine type (requires restart)
 public func reassignAgent(_ agentId: String, to newEngineType: EngineType) async throws {
 guard let record = agents[agentId] else {
 throw AgentManagerError.agentNotFound(agentId)
 }

 guard registry.isAvailable(newEngineType) else {
 throw AgentManagerError.engineUnavailable(newEngineType)
 }

 try await disconnectAgent(agentId)

 var updated = record
 updated.engineType = newEngineType
 updated.configuration = registry.configuration(for: newEngineType)
 agents[agentId] = updated
 }

 /// Refresh all agent health checks
 public func refreshHealth() async -> [String: EngineHealth] {
 var results: [String: EngineHealth] = []

 for (agentId, record) in agents where record.isActive {
 if let engine = activeEngines[agentId] {
 let health = await engine.healthCheck()
 results[agentId] = health

 var updated = record
 updated.engineState = health.status
 agents[agentId] = updated
 }
 }

 return results
 }

 /// Run a comprehensive health check on all active agents
 public func performHealthCheck() async -> AgentHealthReport {
 let activeIds = activeAgents().map(\.id)
 let healthResults = await refreshHealth()

 let healthyAgents = activeIds.filter {
 guard let health = healthResults[$0] else { return false }
 return health.status == .healthy
 }

 let degradedAgents = activeIds.filter {
 guard let health = healthResults[$0] else { return false }
 return health.status == .degraded
 }

 let offlineAgents = activeIds.filter {
 guard let health = healthResults[$0] else { return false }
 return health.status == .offline
 }

 return AgentHealthReport(
 totalAgents: agents.count,
 activeAgents: activeIds.count,
 healthyCount: healthyAgents.count,
 degradedCount: degradedAgents.count,
 offlineCount: offlineAgents.count,
 details: healthResults
 )
 }

 // MARK: Supervision

 private func beginSupervision(for agentId: String) {
 supervisionTasks[agentId]?.cancel()

 let task = Task { [weak self] in
 while !Task.isCancelled {
 do {
 try await Task.sleep(nanoseconds: 5_000_000_000) // Check every 5s

 guard let record = self?.agents[agentId],
 record.isActive,
 let engine = self?.activeEngines[agentId] else {
 continue
 }

 let health = await engine.healthCheck()

 switch health.status {
 case .offline:
 // Attempt restart
 guard let currentRecord = self?.agents[agentId] else { continue }
 if currentRecord.crashCount < currentRecord.configuration.maxRestartAttempts {
 var updated = currentRecord
 updated.crashCount += 1
 updated.processState = .error("Restarting (attempt \(updated.crashCount))")
 self?.agents[agentId] = updated

 self?.eventSubject.send(AgentEvent(
 agentId: agentId,
 type: .crashed(exitCode: -1)
 ))

 // Disconnect and reconnect
 try? await self?.disconnectAgent(agentId)
 try? await Task.sleep(nanoseconds: 2_000_000_000)
 try? await self?.connectAgent(agentId)

 } else {
 // Give up — mark as stopped
 try? await self?.disconnectAgent(agentId)
 self?.eventSubject.send(AgentEvent(
 agentId: agentId,
 type: .error("Max restart attempts exceeded")
 ))
 }
 case .degraded:
 // Log but don't restart
 break
 case .healthy:
 // Reset crash count on healthy
 if let current = self?.agents[agentId], current.crashCount > 0 {
 var updated = current
 updated.crashCount = 0
 self?.agents[agentId] = updated
 }
 default:
 break
 }

 } catch {
 // Supervision task error — just keep running
 }
 }
 }

 supervisionTasks[agentId] = task
 }

 // MARK: Presence IPC

 private func announcePresence(_ agentId: String, status: PresenceStatus) async {
 guard let presence = presence else { return }

 let statusString: String
 switch status {
 case .online: statusString = "online"
 case .offline: statusString = "offline"
 case .away: statusString = "away"
 }

 let message = PresenceMessage(
 sender: "agent-manager",
 recipient: nil,
 topic: "agent.status",
 payload: [
 "agentId": .string(agentId),
 "status": .string(statusString),
 "timestamp": .number(Date().timeIntervalSince1970)
 ]
 )

 do {
 try await presence.send(message)
 } catch {
 // IPC failure is non-fatal
 }
 }
}

// MARK: - Agent Health Report

public struct AgentHealthReport: Sendable, Equatable {
 public let totalAgents: Int
 public let activeAgents: Int
 public let healthyCount: Int
 public let degradedCount: Int
 public let offlineCount: Int
 public let details: [String: EngineHealth]

 public var allHealthy: Bool { degradedCount == 0 && offlineCount == 0 }

 public init(
 totalAgents: Int = 0,
 activeAgents: Int = 0,
 healthyCount: Int = 0,
 degradedCount: Int = 0,
 offlineCount: Int = 0,
 details: [String: EngineHealth] = [:]
 ) {
 self.totalAgents = totalAgents
 self.activeAgents = activeAgents
 self.healthyCount = healthyCount
 self.degradedCount = degradedCount
 self.offlineCount = offlineCount
 self.details = details
 }
}

// MARK: - Presence IPC

/// Inter-process communication channel for presence/status updates.
/// This abstracts the bridgemind.one.presence.ipc internal service.
public protocol PresenceIPC: Sendable {
 func send(_ message: PresenceMessage) async throws
 func subscribe() -> AsyncStream<PresenceMessage>
 func unsubscribe() async
}

public struct PresenceMessage: Sendable, Equatable, Codable {
 public let sender: String
 public let recipient: String?
 public let topic: String
 public let payload: [String: JSONValue]
 public let timestamp: Date

 public init(
 sender: String,
 recipient: String? = nil,
 topic: String,
 payload: [String: JSONValue] = [:],
 timestamp: Date = Date()
 ) {
 self.sender = sender
 self.recipient = recipient
 self.topic = topic
 self.payload = payload
 self.timestamp = timestamp
 }
}

public enum PresenceStatus: String, Sendable {
 case online
 case offline
 case away
}
