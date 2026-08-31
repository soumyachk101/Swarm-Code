//
// PluginRegistry.swift
// Plugin registration and lifecycle management
//

import Foundation

public enum PluginError: Error, Equatable {
 case notFound(String)
 case alreadyConnected(String)
 case notConnected(String)
 case authFailed(String, String)
 case toolCatalogError(String)
 case transportError(String)

 public var localizedDescription: String {
 switch self {
 case .notFound(let id): return "Plugin not found: \(id)"
 case .alreadyConnected(let id): return "Plugin already connected: \(id)"
 case .notConnected(let id): return "Plugin not connected: \(id)"
 case .authFailed(let id, let reason): return "Auth failed for \(id): \(reason)"
 case .toolCatalogError(let id): return "Tool catalog error for \(id)"
 case .transportError(let msg): return "Transport error: \(msg)"
 }
 }
}

public struct PluginState: Codable, Equatable, Sendable {
 public let pluginId: PluginIdentity
 public var enabled: Bool
 public var connected: Bool
 public var lastError: String?
 public var lastConnectedAt: Date?
 public var toolCount: Int = 0

 public init(pluginId: PluginIdentity, enabled: Bool = true, connected: Bool = false) {
 self.pluginId = pluginId
 self.enabled = enabled
 self.connected = connected
 self.lastConnectedAt = nil
 self.lastError = nil
 }
}

public actor PluginRegistry {
 private var plugins: [PluginIdentity: PluginState] = [:]
 private var transports: [PluginIdentity: any MCPTransport] = [:]
 private var listeners: [String] = []

 public init() {}

 public func register(_ plugin: PluginIdentity) {
 plugins[plugin] = PluginState(pluginId: plugin)
 }

 public func registerAll(_ pluginList: [PluginIdentity]) {
 for plugin in pluginList {
 register(plugin)
 }
 }

 public func connect(plugin: PluginIdentity) async throws {
 guard var state = plugins[plugin] else {
 throw PluginError.notFound(plugin.id)
 }

 guard !state.connected else {
 throw PluginError.alreadyConnected(plugin.id)
 }

 // Create appropriate transport
 let transport = try await createTransport(for: plugin)

 // Connect
 try await transport.connect()

 // Initialize
 let initRequest = JSONRPCRequest(
 id: UUID().uuidString,
 method: MCPMethod.initialize.rawValue,
 params: JSONValue.object([
 "protocolVersion": .string("2025-03-26"),
 "capabilities": .object([:]), "clientInfo": .object([
 "name": .string("bridgemind-one"),
 "version": .string("0.1.12"),
 ]),
 ])
 )

 let response = try await transport.sendRequest(initRequest)
 if let error = response.error {
 throw PluginError.authFailed(plugin.id, error.message)
 }

 // Send initialized notification
 _ = try? await transport.sendNotification(JSONRPCNotification(
 method: MCPMethod.initialized.rawValue
 ))

 // List tools
 let toolsRequest = JSONRPCRequest(
 id: UUID().uuidString,
 method: MCPMethod.toolsList.rawValue
 )

 let toolsResponse = try await transport.sendRequest(toolsRequest)

 state.connected = true
 state.lastConnectedAt = Date()
 state.lastError = nil
 plugins[plugin] = state
 transports[plugin] = transport

 // Notify listeners
 await notifyListeners(.connected(plugin.id))
 }

 private func createTransport(for plugin: PluginIdentity) async throws -> any MCPTransport {
 switch plugin.type {
 case .remote:
 return MCPHTTPTransport(
 baseURL: plugin.mcpURL!,
 authType: plugin.authType
 )
 case .local:
 return MCPStdioTransport(
 command: "", // configured per plugin
 environment: plugin.apiKeyEnv.map { [$0: ""] } ?? [:]
 )
 case .oauth:
 return MCPHTTPTransport(
 baseURL: plugin.mcpURL!,
 authType: .oauth
 )
 case .builtin:
 throw PluginError.transportError("Built-in plugins use direct calls")
 }
 }

 public func disconnect(plugin: PluginIdentity) async {
 guard var state = plugins[plugin] else { return }

 state.connected = false
 plugins[plugin] = state

 if let transport = transports[plugin] {
 await transport.disconnect()
 }
 transports.removeValue(forKey: plugin)

 await notifyListeners(.disconnected(plugin.id))
 }

 public func state(of plugin: PluginIdentity) -> PluginState? {
 plugins[plugin]
 }

 public func allPlugins() -> [PluginIdentity] {
 Array(plugins.keys)
 }

 public func enabledPlugins() -> [PluginIdentity] {
 plugins.compactMap { $0.value.enabled ? $0.key : nil }
 }

 public func connectedPlugins() -> [PluginIdentity] {
 plugins.compactMap { $0.value.connected ? $0.key : nil }
 }

 public func togglePlugin(_ plugin: PluginIdentity, enabled: Bool) {
 if var state = plugins[plugin] {
 state.enabled = enabled
 plugins[plugin] = state
 }
 }

 public func addListener(_ listener: @escaping (PluginEvent) -> Void) {
 listeners.append("\(listeners.count)")
 }

 private func notifyListeners(_ event: PluginEvent) {
 // Notify UI listeners via Combine or async stream
 }
}

// MARK: - Plugin Events

public enum PluginEvent: Equatable {
 case connected(String)
 case disconnected(String)
 case error(String, String)
 case toolsUpdated(String, [MCPTool])
}
