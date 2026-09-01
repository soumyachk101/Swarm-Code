//
// PluginRegistry.swift
// BridgeMind One — Plugin lifecycle, transport creation, OAuth flow, state tracking
//
// The PluginRegistry is the central orchestrator for all 24 MCP plugins.
// It is responsible for:
// - Selecting the correct transport per plugin type (HTTP, stdio, OAuth, builtin)
// - Managing plugin lifecycle (connect, disconnect, reconnect, enable, disable)
// - Initiating OAuth flows with PKCE
// - Tracking plugin state in the SQLite database via DatabaseManager
// - Validating tool catalogs returned by remote MCP servers
// - Enforcing safety rules at call time
//
// SECURITY: No credentials are stored in source. API keys are resolved from
// environment variables at runtime. OAuth tokens are stored in the system
// Keychain via CredentialStore. See CredentialStore.swift and OAuthFlows.swift.
//
// Thread safety: PluginRegistry is an actor, serializing all mutations.
// Transport instances are wrapped in a type-erased wrapper to allow
// heterogeneous storage (MCPHTTPTransport and MCPStdioTransport share one dict).
//

import Foundation
import os.log

// MARK: - Plugin Registry Errors

public enum PluginRegistryError: Error, Equatable, LocalizedError {

 case pluginNotFound(String)
 case pluginAlreadyConnected(String)
 case pluginNotEnabled(String)
 case transportCreationFailed(String)
 case oauthFlowFailed(String)
 case toolValidationFailed(String)
 case invalidConfiguration(String)

 public var errorDescription: String? {
 switch self {
 case .pluginNotFound(let id): return "Plugin not found: \(id)"
 case .pluginAlreadyConnected(let id): return "Plugin already connected: \(id)"
 case .pluginNotEnabled(let id): return "Plugin is not enabled: \(id)"
 case .transportCreationFailed(let reason): return "Transport creation failed: \(reason)"
 case .oauthFlowFailed(let reason): return "OAuth flow failed: \(reason)"
 case .toolValidationFailed(let reason): return "Tool validation failed: \(reason)"
 case .invalidConfiguration(let reason): return "Invalid configuration: \(reason)"
 }
 }
}

// MARK: - Plugin Runtime State

/// Tracks the runtime state of a single plugin instance (mirrors DB for fast access).
public struct PluginRuntimeState: Sendable, Equatable, Codable {
 public var pluginId: String
 public var enabled: Bool
 public var connected: Bool
 public var lastError: String?
 public var updatedAt: String

 public init(
 pluginId: String,
 enabled: Bool = true,
 connected: Bool = false,
 lastError: String? = nil,
 updatedAt: String = ISO8601DateFormatter().string(from: Date())
 ) {
 self.pluginId = pluginId
 self.enabled = enabled
 self.connected = connected
 self.lastError = lastError
 self.updatedAt = updatedAt
 }
}

// MARK: - Plugin Validation Result

public struct PluginValidationResult: Sendable, Equatable {
 public var valid: Bool
 public var toolsCount: Int
 public var error: String?

 public init(valid: Bool = true, toolsCount: Int = 0, error: String? = nil) {
 self.valid = valid
 self.toolsCount = toolsCount
 self.error = error
 }
}

// MARK: - Type-Erased Transport Wrapper

/// Wraps any concrete MCP transport behind a unified interface.
///
/// Why: `MCPTransport` has an `associatedtype Message`, preventing it from being
/// used as an existential (`any MCPTransport` is ill-formed in Swift).
///
/// `AnyTransport` boxes each concrete transport and exposes common operations
/// via closure-based type erasure — no subclassing, no reference cycles.
public struct AnyTransport: Sendable, Equatable {

 private let _connect: @Sendable () async throws -> Void
 private let _disconnect: @Sendable () async -> Void
 private let _sendRequest: @Sendable (JSONRPCRequest) async throws -> JSONRPCResponse
 private let _id: String

 public init<T: MCPHTTPTransport>(_ transport: T) {
 self._id = transport.sessionID ?? "http-\(transport.baseURL.host ?? "unknown")"
 self._connect = { try await transport.connect() }
 self._disconnect = { await transport.disconnect() }
 self._sendRequest = { request in
 // Convert JSONRPCRequest -> JSONValue, send, convert response -> JSONRPCResponse.
 let payload: JSONValue = .object([
 "jsonrpc": .string("2.0"),
 "id": .string(request.id),
 "method": .string(request.method),
 "params": request.params ?? .object([:])
 ])
 let response = try await transport.sendRequest(payload)
 switch response {
 case .object(let dict):
 let respId = dict["id"]?.stringValue ?? request.id
 let result = dict["result"]
 if let errorDict = dict["error"]?.dictionaryValue {
 let code = Int(errorDict["code"]?.numberValue ?? 0)
 let message = errorDict["message"]?.stringValue ?? "Unknown error"
 let data = errorDict["data"]
 return JSONRPCResponse(id: respId, result: result,
 error: JSONRPCError(code: code, message: message, data: data))
 }
 return JSONRPCResponse(id: respId, result: result, error: nil)
 default:
 return JSONRPCResponse(id: request.id, result: response, error: nil)
 }
 }
 }

 public init<T: MCPStdioTransport>(_ transport: T) {
 self._id = transport.sessionId ?? "stdio-\(transport.configuration.executable)"
 self._connect = { try await transport.connect() }
 self._disconnect = { await transport.disconnect() }
 self._sendRequest = { request in try await transport.sendRequest(request) }
 }

 public var id: String { _id }

 public func connect() async throws {
 try await _connect()
 }

 public func disconnect() async {
 await _disconnect()
 }

 public func sendRequest(_ request: JSONRPCRequest) async throws -> JSONRPCResponse {
 try await _sendRequest(request)
 }

 public static func == (lhs: AnyTransport, rhs: AnyTransport) -> Bool {
 lhs._id == rhs._id
 }
}

// MARK: - Plugin Transport Factory

/// Creates the appropriate MCP transport instance for a given plugin identity.
///
/// SECURITY: For API-key plugins, the environment variable is injected into
/// the child process environment (stdio) or passed to the upstream MCP server.
/// The raw key is never logged or exposed to the app layer.
public enum PluginTransportFactory: Sendable {

 /// Build and return a type-erased transport ready for connection.
 public static func create(
 for identity: PluginIdentity,
 credentialStore: CredentialStore? = nil
 ) async throws -> AnyTransport {
 switch identity.type {

 // ── Remote plugins: HTTP MCP server ──────────────────────────
 case .remote:
 guard let url = identity.mcpURL else {
 throw PluginRegistryError.transportCreationFailed(
 "Plugin '\(identity.id)' is remote but has no mcpURL."
 )
 }

 // For OAuth remote plugins, resolve the bearer token from Keychain.
 var bearerToken: String? = nil
 if identity.authType == .oauth, let store = credentialStore {
 let token = try await store.retrieveToken(for: identity)
 bearerToken = token?.accessToken
 if bearerToken == nil {
 throw PluginRegistryError.transportCreationFailed(
 "No OAuth token found for '\(identity.id)'. Run the OAuth flow first."
 )
 }
 }

 // Fallback: check for session token in environment.
 if bearerToken == nil,
 let envToken = ProcessInfo.processInfo.environment[AppConfig.sessionTokenEnvVar],
 !envToken.isEmpty {
 bearerToken = envToken
 }

 let config = MCPHTTPTransport.Configuration(
 sessionID: ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_ID_\(identity.id)"],
 bearerToken: bearerToken,
 timeout: 30,
 maximumRetryCount: 3,
 additionalHeaders: [:]
 )

 let transport = try await MCPHTTPTransport(baseURL: url, configuration: config)
 return AnyTransport(transport)

 // ── Local plugins: stdio MCP server ───────────────────────────
 case .local:
 var env = ProcessInfo.processInfo.environment

 if let apiKeyEnv = identity.apiKeyEnv,
 let keyValue = ProcessInfo.processInfo.environment[apiKeyEnv] {
 env[apiKeyEnv] = keyValue
 }

 let command = identity.displayName.lowercased()
 let config = MCPStdioTransport.Configuration(
 executable: command,
 arguments: ["--mcp"],
 workingDirectory: nil,
 environment: env,
 requestTimeout: .seconds(30),
 stderrLogHandler: { line in
 Logger(subsystem: "com.bridgemind.mcp.plugin.\(identity.id)", category: "stderr")
 .debug("\(line, privacy: .public)")
 }
 )

 let transport = MCPStdioTransport(configuration: config)
 return AnyTransport(transport)

 // ── OAuth plugins: must complete flow first ───────────────────
 case .oauth:
 throw PluginRegistryError.transportCreationFailed(
 "Plugin '\(identity.id)' requires OAuth. Run the OAuth flow before connecting."
 )

 // ── Built-in plugins: no external transport needed ─────────────
 case .builtin:
 throw PluginRegistryError.transportCreationFailed(
 "Built-in plugin '\(identity.id)' handles requests internally."
 )
 }
 }
}

// MARK: - Plugin Registry (actor)

/// Central registry managing all 24 plugin instances.
///
/// Responsibilities:
/// - Lifecycle: connect, disconnect, reconnect, enable, disable
/// - Transport creation per plugin type
/// - OAuth flow initiation and token persistence
/// - State tracking (persisted to SQLite via DatabaseManager)
/// - Tool catalog validation after connecting
/// - Safety rule enforcement at call time
///
/// Thread safety: This is an actor. All state mutations are serialized.
///
/// SECURITY: Never log raw API keys or OAuth tokens. Token references use
/// redacted identifiers only.
public actor PluginRegistry {

 // MARK: Dependencies

 private let database: DatabaseManager
 private let credentialStore: CredentialStore

 // MARK: Runtime State

 /// Active transports keyed by plugin id.
 private let transports: [String: AnyTransport] = [:]

 /// Runtime state cached in memory (mirrors the DB for fast access).
 private let states: [String: PluginRuntimeState] = [:]

 /// Pending PKCE verifiers held for the duration of an OAuth flow.
 private var pendingPKCE: [String: String] = [:]

 /// Pending OAuth state values for CSRF validation.
 private var pendingOAuthState: [String: String] = [:]

 // MARK: Logging

 private let logger = Logger(subsystem: "com.bridgemind.one", category: "PluginRegistry")

 // MARK: Initialization

 public init(
 database: DatabaseManager,
 credentialStore: CredentialStore
 ) {
 self.database = database
 self.credentialStore = credentialStore

 // Load persisted states from DB on startup (non-fatal).
 Task {
 await loadStatesFromDatabase()
 }
 }

 // MARK: - Plugin Lifecycle

 /// Connect a plugin by its stable identifier.
 ///
 /// Steps:
 /// 1. Resolve the plugin identity from the collection.
 /// 2. Verify the plugin is enabled.
 /// 3. Check not already connected.
 /// 4. Create the appropriate transport.
 /// 5. Connect the transport.
 /// 6. Validate the tool catalog.
 /// 7. Persist connected state to DB.
 ///
 /// - Parameter pluginId: Stable identifier (e.g. `"bridgemind_plugins__github"`).
 /// - Returns: The connected PluginIdentity.
 @discardableResult
 public func connect(pluginId: String) async throws -> PluginIdentity {
 logger.info("Connecting plugin: \(pluginId, privacy: .public)")

 // 1. Resolve identity
 guard let identity = AllPlugins.byId(pluginId) else {
 logger.error("Plugin not found: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 // 2. Check enabled
 let currentState = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 guard currentState.enabled else {
 logger.error("Plugin not enabled: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginNotEnabled(pluginId)
 }

 // 3. Check not already connected
 if transports[pluginId] != nil {
 logger.warning("Plugin already connected: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginAlreadyConnected(pluginId)
 }

 // 4. Create transport
 let transport = try await PluginTransportFactory.create(
 for: identity,
 credentialStore: credentialStore
 )

 // 5. Connect transport
 logger.info("Connecting transport for \(pluginId, privacy: .public)…")
 try await transport.connect()
 logger.info("Transport connected for \(pluginId, privacy: .public)")

 // 6. Validate tool catalog
 let validation = try await validateToolCatalog(for: identity, transport: transport)
 guard validation.valid else {
 await transport.disconnect()
 logger.error("Tool validation failed for \(pluginId): \(validation.error ?? "unknown", privacy: .public)")
 throw PluginRegistryError.toolValidationFailed(validation.error ?? "Unknown validation error")
 }

 // 7. Store transport and update state
 transports[pluginId] = transport
 states[pluginId] = PluginRuntimeState(
 pluginId: pluginId,
 enabled: true,
 connected: true,
 lastError: nil
 )

 // 8. Persist to DB
 do {
 try await database.savePluginState(pluginId: pluginId, enabled: true, connected: true)
 } catch {
 logger.warning("Failed to persist plugin state: \(error.localizedDescription, privacy: .public)")
 }

 logger.info("Plugin connected: \(pluginId, privacy: .public) [\(validation.toolsCount) tools]")
 return identity
 }

 /// Disconnect a plugin and release its transport.
 public func disconnect(pluginId: String) async {
 logger.info("Disconnecting plugin: \(pluginId, privacy: .public)")

 guard let transport = transports[pluginId] else {
 logger.warning("Plugin not connected, skipping: \(pluginId, privacy: .public)")
 return
 }

 do {
 try await transport.disconnect()
 } catch {
 logger.warning("Disconnect error for \(pluginId): \(error.localizedDescription, privacy: .public)")
 }

 transports.removeValue(forKey: pluginId)

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.connected = false
 states[pluginId] = state

 do {
 try await database.savePluginState(pluginId: pluginId, enabled: state.enabled, connected: false)
 } catch {
 logger.warning("Failed to persist disconnect state: \(error.localizedDescription, privacy: .public)")
 }

 logger.info("Plugin disconnected: \(pluginId, privacy: .public)")
 }

 /// Disconnect all connected plugins. Called on app shutdown.
 public func disconnectAll() async {
 let connectedIds = Array(transports.keys)
 logger.info("Disconnecting all \(connectedIds.count) active plugins…")
 for id in connectedIds {
 await disconnect(pluginId: id)
 }
 logger.info("All plugins disconnected")
 }

 /// Enable a plugin so it can be connected.
 public func enable(pluginId: String) async throws {
 guard AllPlugins.byId(pluginId) != nil else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.enabled = true
 state.lastError = nil
 states[pluginId] = state

 try await database.savePluginState(pluginId: pluginId, enabled: true, connected: state.connected)
 logger.info("Plugin enabled: \(pluginId, privacy: .public)")
 }

 /// Disable a plugin. If currently connected, disconnect first.
 public func disable(pluginId: String) async throws {
 guard AllPlugins.byId(pluginId) != nil else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 if transports[pluginId] != nil {
 await disconnect(pluginId: pluginId)
 }

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.enabled = false
 states[pluginId] = state

 try await database.savePluginState(pluginId: pluginId, enabled: false, connected: false)
 logger.info("Plugin disabled: \(pluginId, privacy: .public)")
 }

 /// Reconnect a plugin — disconnects then re-connects, refreshing the transport.
 public func reconnect(pluginId: String) async throws -> PluginIdentity {
 logger.info("Reconnecting plugin: \(pluginId, privacy: .public)")
 await disconnect(pluginId: pluginId)
 return try await connect(pluginId: pluginId)
 }

 // MARK: - Transport Access

 /// Return the active transport for a plugin, or nil if not connected.
 public func transport(for pluginId: String) -> AnyTransport? {
 transports[pluginId]
 }

 /// Return true if the plugin has an active transport.
 public func isConnected(_ pluginId: String) -> Bool {
 transports[pluginId] != nil
 }

 // MARK: - OAuth Flow

 /// Initiate the OAuth 2.0 authorization code + PKCE flow for a plugin.
 ///
 /// Flow:
 /// 1. Generate PKCE challenge (RFC 7636).
 /// 2. Discover the provider's OAuth metadata endpoints.
 /// 3. Build the authorization URL and present it via the delegate.
 /// 4. The delegate handles user authorization (external browser).
 /// 5. Exchange the authorization code + PKCE verifier for tokens.
 /// 6. Persist tokens in Keychain via CredentialStore.
 ///
 /// - Parameter pluginId: The stable plugin identifier.
 /// - Parameter delegate: Handles presenting the authorization URL to the user.
 /// - Returns: The obtained OAuthToken (also stored in Keychain).
 public func initiateOAuthFlow(
 for pluginId: String,
 delegate: any MCPOAuthAuthorizationDelegate
 ) async throws -> OAuthToken {
 logger.info("Initiating OAuth flow for: \(pluginId, privacy: .public)")

 guard let identity = AllPlugins.byId(pluginId) else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 guard identity.authType == .oauth else {
 throw PluginRegistryError.invalidConfiguration(
 "Plugin '\(pluginId)' does not use OAuth (authType: \(identity.authType.rawValue))"
 )
 }

 guard let scopes = identity.scopes, !scopes.isEmpty else {
 throw PluginRegistryError.invalidConfiguration(
 "Plugin '\(pluginId)' has no OAuth scopes configured."
 )
 }

 // 1. Generate PKCE challenge
 let pkce = PKCEChallenge()
 pendingPKCE[pluginId] = pkce.codeVerifier

 // 2. Discover OAuth metadata
 let discovery: OAuthDiscovery

 if let url = identity.mcpURL {
 let discoveryURL = url.appendingPathComponent(".well-known/oauth-authorization-server")
 discovery = try await fetchDiscoveryDocument(from: discoveryURL) ?? fallbackDiscovery(for: pluginId)
 } else {
 discovery = fallbackDiscovery(for: pluginId)
 }

 // 3. Build authorization URL
 let stateValue = UUID().uuidString
 pendingOAuthState[pluginId] = stateValue

 let authURL = buildAuthorizationURL(
 discovery: discovery,
 scopes: scopes,
 codeChallenge: pkce.codeChallenge,
 codeChallengeMethod: pkce.method,
 state: stateValue
 )

 // 4-6. Present URL, obtain code, exchange for token
 let authorizationCode = try await delegate.handleAuthorizationURL(authURL)

 let token = try await exchangeCodeForToken(
 code: authorizationCode,
 verifier: pkce.codeVerifier,
 discovery: discovery
 )

 // Store token in Keychain — never in source or logs.
 try await credentialStore.storeToken(token, for: identity)

 pendingPKCE.removeValue(forKey: pluginId)
 pendingOAuthState.removeValue(forKey: pluginId)

 logger.info("OAuth flow complete for: \(pluginId, privacy: .public)")
 return token
 }

 /// Retrieve the PKCE verifier for a pending OAuth flow.
 public func popPKCEVerifier(for pluginId: String) throws -> String {
 guard let verifier = pendingPKCE.removeValue(forKey: pluginId) else {
 throw PluginRegistryError.oauthFlowFailed(
 "No pending PKCE verifier for '\(pluginId)'. Initiate the OAuth flow first."
 )
 }
 return verifier
 }

 /// Retrieve and validate the OAuth state for a pending flow.
 public func popOAuthState(for pluginId: String) throws -> String {
 guard let state = pendingOAuthState.removeValue(forKey: pluginId) else {
 throw PluginRegistryError.oauthFlowFailed(
 "No pending OAuth state for '\(pluginId)'."
 )
 }
 return state
 }

 // MARK: - Tool Catalog Validation

 /// Validate the tool catalog for a plugin by sending tools/list via its transport.
 public func validateToolCatalog(
 for identity: PluginIdentity,
 transport: AnyTransport
 ) async throws -> PluginValidationResult {
 logger.debug("Validating tool catalog for \(identity.id, privacy: .public)…")

 let request = JSONRPCRequest(
 id: UUID().uuidString,
 method: MCPMethod.toolsList.rawValue,
 params: JSONValue.object([:])
 )

 do {
 let response = try await transport.sendRequest(request)

 guard let result = response.result, case .object(let dict) = result else {
 return PluginValidationResult(
 valid: false,
 toolsCount: 0,
 error: "Invalid tools/list response format."
 )
 }

 guard let toolsArray = dict["tools"]?.arrayValue else {
 return PluginValidationResult(
 valid: false,
 toolsCount: 0,
 error: "Response missing 'tools' array."
 )
 }

 let count = toolsArray.count

 for toolValue in toolsArray {
 guard case .object(let toolDict) = toolValue else {
 return PluginValidationResult(valid: false, toolsCount: count,
 error: "Tool entry is not a JSON object.")
 }
 if toolDict["name"]?.stringValue == nil {
 return PluginValidationResult(valid: false, toolsCount: count,
 error: "Tool missing required 'name' field.")
 }
 }

 logger.info("Tool catalog validated for \(identity.id): \(count) tools")
 return PluginValidationResult(valid: true, toolsCount: count)

 } catch {
 logger.error("Tool validation error for \(identity.id): \(error.localizedDescription, privacy: .public)")
 return PluginValidationResult(valid: false, toolsCount: 0, error: error.localizedDescription)
 }
 }

 /// Validate the tool catalog for a connected plugin by id.
 public func validateToolCatalog(pluginId: String) async throws -> PluginValidationResult {
 guard let identity = AllPlugins.byId(pluginId) else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }
 guard let transport = transports[pluginId] else {
 throw PluginRegistryError.pluginNotEnabled(pluginId)
 }
 return try await validateToolCatalog(for: identity, transport: transport)
 }

 // MARK: - Safety Rule Enforcement

 /// Check whether a pending tool call would violate any safety rule.
 /// Returns nil if safe, or a descriptive violation string.
 ///
 /// Safety rules are looked up from the pluginSafetyRules dictionary
 /// defined in PluginDefinitions.swift. Rules are pattern-matched against
 /// the tool name to determine if the call should be blocked.
 public func checkSafetyViolation(
 pluginId: String,
 toolName: String
 ) -> String? {
 let rules = pluginSafetyRules[pluginId] ?? []
 if rules.isEmpty { return nil }

 let lowered = toolName.lowercased()

 if rules.contains(where: { $0.contains("Never auto-send") }),
 lowered.contains("send") && lowered.contains("email") {
 return rules.first { $0.contains("Never auto-send") }
 }

 if rules.contains(where: { $0.contains("bypass billing") || $0.contains("bypass payment") }),
 lowered.contains("bill") || lowered.contains("payment") || lowered.contains("charge") {
 return rules.first { $0.contains("bypass") }
 }

 if rules.contains(where: { $0.contains("without user approval") }),
 lowered.contains("merge") || lowered.contains("push") {
 return rules.first { $0.contains("without user approval") }
 }

 if rules.contains(where: { $0.contains("without user confirmation") || $0.contains("without explicit confirmation") }),
 lowered.contains("delete") || lowered.contains("remove") || lowered.contains("destroy") {
 return rules.first {
 $0.contains("without user confirmation") || $0.contains("without explicit confirmation") || $0.contains("without approval")
 }
 }

 if rules.contains(where: { $0.contains("without explicit user approval") }),
 lowered.contains("deploy") || lowered.contains("publish") {
 return rules.first { $0.contains("without explicit user approval") }
 }

 if rules.contains(where: { $0.contains("without user authorization") }),
 lowered.contains("read") {
 return rules.first { $0.contains("without user authorization") }
 }

 return nil
 }

 // MARK: - State Queries

 /// Return the cached runtime state for a plugin.
 public func state(for pluginId: String) -> PluginRuntimeState {
 states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 }

 /// Return all known plugin IDs from the registry.
 public func allPluginIds() -> [String] {
 AllPlugins.allCases.map { $0.identity.id }
 }

 /// Return runtime states for all known plugins, sorted by id.
 public func allStates() -> [PluginRuntimeState] {
 states.values.sorted { $0.pluginId < $1.pluginId }
 }

 /// Return true if the plugin is enabled and connected.
 public func isAvailable(_ pluginId: String) -> Bool {
 guard let state = states[pluginId] else { return false }
 return state.enabled && state.connected
 }

 // MARK: - Private Helpers

 private func loadStatesFromDatabase() async {
 do {
 let records = try await database.getAllPluginStates()
 for record in records {
 states[record.pluginId] = PluginRuntimeState(
 pluginId: record.pluginId,
 enabled: record.enabled,
 connected: record.connected,
 lastError: record.lastError,
 updatedAt: record.updatedAt
 )
 }
 logger.info("Loaded \(records.count) plugin states from database")
 } catch {
 logger.warning("Failed to load plugin states: \(error.localizedDescription, privacy: .public)")
 }
 }

 private func fetchDiscoveryDocument(from url: URL) async throws -> OAuthDiscovery? {
 do {
 let (data, response) = try await URLSession.shared.data(from: url)
 guard let httpResponse = response as? HTTPURLResponse,
 (200...299).contains(httpResponse.statusCode) else {
 return nil
 }
 return try JSONDecoder().decode(OAuthDiscovery.self, from: data)
 } catch {
 logger.debug("OAuth discovery unavailable at \(url.absoluteString, privacy: .public)")
 return nil
 }
 }

 private func fallbackDiscovery(for pluginId: String) -> OAuthDiscovery {
 // Known provider OAuth endpoints — these are public URLs, not secrets.
 let wellKnownURLs: [String: URL] = [
 "bridgemind_plugins__google": URL(string: "https://accounts.google.com")!,
 "bridgemind_plugins__github": URL(string: "https://github.com")!,
 "bridgemind_plugins__slack": URL(string: "https://slack.com")!,
 "bridgemind_plugins__notion": URL(string: "https://api.notion.com")!,
 "bridgemind_plugins__linear": URL(string: "https://linear.app")!,
 "bridgemind_plugins__stripe": URL(string: "https://connect.stripe.com")!,
 "bridgemind_plugins__metaads": URL(string: "https://facebook.com")!,
 "bridgemind_plugins__shopify": URL(string: "https://shopify.com")!,
 "bridgemind_plugins__supabase": URL(string: "https://supabase.com")!,
 "bridgemind_plugins__youtube": URL(string: "https://accounts.google.com")!
 ]

 let issuerURL = wellKnownURLs[pluginId] ?? URL(string: "https://\(pluginId).com")!

 return OAuthDiscovery(
 issuer: issuerURL,
 authorizationEndpoint: URL(string: "\(issuerURL.absoluteString)/oauth/authorize")!,
 tokenEndpoint: URL(string: "\(issuerURL.absoluteString)/oauth/token")!,
 registrationEndpoint: nil,
 scopesSupported: nil
 )
 }

 private func buildAuthorizationURL(
 discovery: OAuthDiscovery,
 scopes: [String],
 codeChallenge: String,
 codeChallengeMethod: String,
 state: String
 ) -> URL {
 var components = URLComponents(url: discovery.authorizationEndpoint, resolvingAgainstBaseURL: false)!

 components.queryItems = [
 URLQueryItem(name: "client_id", value: "bridgemind-one"),
 URLQueryItem(name: "redirect_uri", value: "\(AppConfig.appIdentifier)://oauth/callback"),
 URLQueryItem(name: "response_type", value: "code"),
 URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
 URLQueryItem(name: "state", value: state),
 URLQueryItem(name: "code_challenge", value: codeChallenge),
 URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod)
 ]

 return components.url ?? discovery.authorizationEndpoint
 }

 private func exchangeCodeForToken(
 code: String,
 verifier: String,
 discovery: OAuthDiscovery
 ) async throws -> OAuthToken {
 let bodyString = [
 "grant_type=authorization_code",
 "code=\(code)",
 "redirect_uri=\(AppConfig.appIdentifier)://oauth/callback",
 "client_id=bridgemind-one",
 "code_verifier=\(verifier)"
 ].joined(separator: "&")

 var request = URLRequest(url: discovery.tokenEndpoint)
 request.httpMethod = "POST"
 request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
 request.httpBody = Data(bodyString.utf8)

 let (data, response) = try await URLSession.shared.data(for: request)
 guard let httpResponse = response as? HTTPURLResponse,
 (200...299).contains(httpResponse.statusCode) else {
 let status = (response as? HTTPURLResponse)?.statusCode ?? -1
 throw PluginRegistryError.oauthFlowFailed(
 "Token endpoint returned HTTP \(status)."
 )
 }

 struct TokenResponse: Codable {
 let access_token: String
 let refresh_token: String?
 let token_type: String
 let expires_in: TimeInterval?
 let scope: String?
 }

 let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

 return OAuthToken(
 accessToken: tokenResponse.access_token,
 refreshToken: tokenResponse.refresh_token,
 tokenType: tokenResponse.token_type,
 expiresIn: tokenResponse.expires_in,
 scope: tokenResponse.scope
 )
 }
}
