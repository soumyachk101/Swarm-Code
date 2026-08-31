//
// PluginRegistry.swift
// BridgeMind One — Plugin lifecycle, transport creation, OAuth flow, state tracking
//
// The PluginRegistry is the central orchestrator for all 24 MCP plugins.
// It is responsible for:
// - Selecting the correct transport per plugin type (HTTP, stdio, OAuth, builtin)
// - Managing plugin lifecycle (connect, disconnect, reconnect)
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
// Transport instances are wrapped in a type-erased AnyTransport to allow
// heterogeneous storage (MCPHTTPTransport + MCPStdioTransport share one dict).
// The type erasure uses closure boxing — no subclassing, no reference cycles.
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

// MARK: - Type-Erased Transport Wrapper

/// Wraps any concrete MCP transport (HTTP or stdio) behind a unified interface.
///
/// Why: Both `MCPHTTPTransport` and `MCPStdioTransport` conform to `MCPTransport`,
/// but that protocol has an `associatedtype Message`, preventing it from being
/// used as an existential (`any MCPTransport` is ill-formed in Swift).
///
/// `AnyTransport` boxes each concrete transport and exposes a common set of
/// operations needed by the registry. This is a closure-based type erasure —
/// no inheritance, no reference cycles, fully Sendable.
public struct AnyTransport: Sendable, Equatable {

 private let _connect: @Sendable () async throws -> Void
 private let _disconnect: @Sendable () async -> Void
 private let _sendRequest: @Sendable (JSONRPCRequest) async throws -> JSONRPCResponse
 private let _isConnected: @Sendable () async -> Bool
 private let _id: String

 public init<T: MCPHTTPTransport>(_ transport: T) {
 self._id = transport.sessionID ?? "http-\(transport.baseURL.host ?? "unknown")"
 self._connect = { try await transport.connect() }
 self._disconnect = { await transport.disconnect() }
 self._sendRequest = { request in
 // HTTP transport uses JSONValue — wrap request into JSONValue object
 let params: JSONValue? = request.params.map { params in
 .object(["id": .string(request.id), "method": .string(request.method), "params": params])
 } ?? .object(["id": .string(request.id), "method": .string(request.method)])

 let jsonValue = JSONValue.object([
 "jsonrpc": .string("2.0"),
 "id": .string(request.id),
 "method": .string(request.method),
 "params": params ?? .object([:])
 ])

 let response = try await transport.send(jsonValue)

 // Convert JSONValue response to JSONRPCResponse
 switch response {
 case .object(let dict):
 let respId = dict["id"]?.stringValue ?? request.id
 let result = dict["result"]
 let errorDict = dict["error"]?.dictionaryValue
 let error: JSONRPCError?
 if let e = errorDict {
 let code = Int(e["code"]?.numberValue ?? 0)
 let message = e["message"]?.stringValue ?? "Unknown error"
 let data = e["data"]
 error = JSONRPCError(code: code, message: message, data: data)
 } else {
 error = nil
 }
 return JSONRPCResponse(id: respId, result: result, error: error)
 default:
 return JSONRPCResponse(id: request.id, result: response, error: nil)
 }
 }
 self._isConnected = { await transport.isConnected }
 }

 public init<T: MCPStdioTransport>(_ transport: T) {
 self._id = transport.sessionId ?? "stdio-\(transport.configuration.executable)"
 self._connect = { try await transport.connect() }
 self._disconnect = { await transport.disconnect() }
 self._sendRequest = { request in try await transport.sendRequest(request) }
 self._isConnected = { [sessionId = transport.sessionId] in
 // MCPStdioTransport doesn't expose isConnected directly in a synchronous way.
 // We approximate: if sessionId is set and transport exists, it's likely connected.
 sessionId != nil
 }
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

 public var isConnected: Bool {
 get async {
 await _isConnected()
 }
 }
}

// MARK: - Plugin Transport Factory

/// Creates the appropriate MCP transport instance for a given plugin descriptor.
///
/// SECURITY: For API-key plugins, the environment variable is injected into
/// the child process environment (stdio) or the transport reads it at
/// request time. The raw key is never logged or exposed to the app layer.
public enum PluginTransportFactory: Sendable {

 /// Build and return a type-erased transport ready for connection.
 @discardableResult
 public static func create(
 for descriptor: PluginDescriptor,
 credentialStore: CredentialStore? = nil
 ) async throws -> AnyTransport {
 switch descriptor.transport {

 // ── HTTP transport (remote MCP server) ──────────────────────────
 case .http:
 let httpTransport = try await createHTTPTransport(descriptor: descriptor, credentialStore: credentialStore)
 return AnyTransport(httpTransport)

 // ── Stdio transport (local MCP server process) ──────────────────
 case .stdio(let command, let arguments):
 let stdioTransport = try createStdioTransport(command: command, arguments: arguments, descriptor: descriptor)
 return AnyTransport(stdioTransport)

 // ── OAuth transport ─────────────────────────────────────────────
 case .oauth:
 throw PluginRegistryError.transportCreationFailed(
 "OAuth transport must be created after completing the authorization code flow. "
 + "Call initiateOAuthFlow(_:) first."
 )

 // ── Built-in transport ──────────────────────────────────────────
 case .builtin:
 throw PluginRegistryError.transportCreationFailed(
 "Built-in plugins do not require a transport. They handle requests internally."
 )
 }
 }

 // MARK: HTTP Transport

 private static func createHTTPTransport(
 descriptor: PluginDescriptor,
 credentialStore: CredentialStore?
 ) async throws -> MCPHTTPTransport {
 guard let url = descriptor.transport.httpURL else {
 throw PluginRegistryError.transportCreationFailed(
 "Plugin '\(descriptor.id)' has no valid HTTP URL."
 )
 }

 // Resolve bearer token: for OAuth plugins, read from Keychain.
 // For API-key plugins, the upstream MCP server handles auth — we just connect.
 var bearerToken: String? = nil

 if descriptor.authType == .oauth, let store = credentialStore {
 let identity = PluginIdentity(
 id: descriptor.id,
 displayName: descriptor.displayName,
 type: .remote,
 authType: .oauth
 )
 let token = try await store.retrieveToken(for: identity)
 bearerToken = token?.accessToken

 if bearerToken == nil {
 throw PluginRegistryError.transportCreationFailed(
 "No OAuth token found for '\(descriptor.id)'. Run the OAuth flow first."
 )
 }
 }

 // Resolve session ID from environment if set
 let sessionID = ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_ID_\(descriptor.id.uppercased())"]

 let config = MCPHTTPTransport.Configuration(
 sessionID: sessionID,
 bearerToken: bearerToken,
 timeout: 30,
 maximumRetryCount: 3,
 additionalHeaders: [:]
 )

 return try await MCPHTTPTransport(
 baseURL: url,
 configuration: config
 )
 }

 // MARK: Stdio Transport

 private static func createStdioTransport(
 command: String,
 arguments: [String],
 descriptor: PluginDescriptor
 ) throws -> MCPStdioTransport {
 // Build environment: inherit current env and inject the plugin's API key
 // if one is configured.
 var env = ProcessInfo.processInfo.environment

 if let apiKeyEnv = descriptor.apiKeyEnv,
 let keyValue = ProcessInfo.processInfo.environment[apiKeyEnv] {
 // Pass the key through so the child MCP server process can read it.
 // The key itself is never logged or exposed to BridgeMind One's logic.
 env[apiKeyEnv] = keyValue
 }

 let config = MCPStdioTransport.Configuration(
 executable: command,
 arguments: arguments,
 workingDirectory: nil,
 environment: env,
 requestTimeout: .seconds(30),
 stderrLogHandler: { [logger = Logger(subsystem: "com.bridgemind.mcp.plugin.\(descriptor.id)", category: "stderr")] line in
 logger.debug("\(line, privacy: .public)")
 }
 )

 return MCPStdioTransport(configuration: config)
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
/// Transport instances are stored as `AnyTransport` (type-erased wrapper).
///
/// SECURITY: Never log raw API keys or OAuth tokens. Token references use
/// redacted identifiers only.
public actor PluginRegistry {

 // MARK: Dependencies

 private let database: DatabaseManager
 private let credentialStore: CredentialStore

 // MARK: Runtime State

 /// Active transports keyed by plugin id.
 /// An entry exists only while the plugin is connected.
 private var transports: [String: AnyTransport] = [:]

 /// Runtime state cached in memory (mirrors the DB for fast access).
 private var states: [String: PluginRuntimeState] = [:]

 /// PKCE verifiers keyed by plugin id (held for the duration of an OAuth flow).
 private var pendingPKCE: [String: String] = [:]

 /// OAuth state values keyed by plugin id (for CSRF validation).
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

 // Load persisted states from DB on startup.
 // This is a fire-and-forget task — failure is non-fatal.
 Task {
 await loadStatesFromDatabase()
 }
 }

 // MARK: - Plugin Lifecycle

 /// Connect a plugin by its stable identifier.
 ///
 /// Steps:
 /// 1. Resolve the plugin descriptor from the collection.
 /// 2. Verify the plugin is enabled.
 /// 3. Create the appropriate transport (HTTP, stdio).
 /// 4. Connect the transport.
 /// 5. Validate the tool catalog.
 /// 6. Persist connected state to DB.
 ///
 /// - Parameter pluginId: The stable plugin identifier (e.g. `"github"`).
 /// - Returns: The connected plugin descriptor.
 @discardableResult
 public func connect(pluginId: String) async throws -> PluginDescriptor {
 logger.info("Connecting plugin: \(pluginId, privacy: .public)")

 // ── 1. Resolve descriptor ──────────────────────────────────────
 guard let descriptor = PluginCollection.byId(pluginId) else {
 logger.error("Plugin not found: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 // ── 2. Check enabled ───────────────────────────────────────────
 let currentState = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 guard currentState.enabled else {
 logger.error("Plugin not enabled: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginNotEnabled(pluginId)
 }

 // ── 3. Check already connected ─────────────────────────────────
 if transports[pluginId] != nil {
 logger.warning("Plugin already connected: \(pluginId, privacy: .public)")
 throw PluginRegistryError.pluginAlreadyConnected(pluginId)
 }

 // ── 4. Create and connect transport ────────────────────────────
 // For OAuth plugins, verify a token exists before attempting connection.
 if descriptor.authType == .oauth {
 let identity = PluginIdentity(
 id: descriptor.id,
 displayName: descriptor.displayName,
 type: .remote,
 authType: .oauth
 )
 let existingToken = try await credentialStore.retrieveToken(for: identity)
 guard existingToken != nil, existingToken?.isExpired == false else {
 logger.error("OAuth token missing or expired for: \(pluginId, privacy: .public)")
 throw PluginRegistryError.transportCreationFailed(
 "OAuth token is missing or expired for '\(pluginId)'. Run the OAuth flow first."
 )
 }
 }

 let transport = try await PluginTransportFactory.create(
 for: descriptor,
 credentialStore: credentialStore
 )

 logger.info("Connecting transport for \(pluginId, privacy: .public)…")
 try await transport.connect()
 logger.info("Transport connected for \(pluginId, privacy: .public)")

 // ── 5. Validate tool catalog ───────────────────────────────────
 let validation = try await validateToolCatalog(for: descriptor, transport: transport)
 guard validation.valid else {
 await transport.disconnect()
 logger.error("Tool validation failed for \(pluginId): \(validation.error ?? "unknown", privacy: .public)")
 throw PluginRegistryError.toolValidationFailed(validation.error ?? "Unknown validation error")
 }

 // ── 6. Store transport and update state ─────────────────────────
 transports[pluginId] = transport
 states[pluginId] = PluginRuntimeState(
 pluginId: pluginId,
 enabled: true,
 connected: true,
 lastError: nil
 )

 // ── 7. Persist to DB ───────────────────────────────────────────
 do {
 try database.savePluginState(pluginId: pluginId, enabled: true, connected: true)
 } catch {
 logger.warning("Failed to persist plugin state: \(error.localizedDescription, privacy: .public)")
 }

 logger.info("Plugin connected successfully: \(pluginId, privacy: .public) [\(validation.toolsCount) tools]")
 return descriptor
 }

 /// Disconnect a plugin and release its transport.
 public func disconnect(pluginId: String) async {
 logger.info("Disconnecting plugin: \(pluginId, privacy: .public)")

 guard let transport = transports[pluginId] else {
 logger.warning("Plugin not connected, skipping disconnect: \(pluginId, privacy: .public)")
 return
 }

 do {
 try await transport.disconnect()
 } catch {
 logger.warning("Error during disconnect for \(pluginId): \(error.localizedDescription, privacy: .public)")
 }

 transports.removeValue(forKey: pluginId)

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.connected = false
 states[pluginId] = state

 do {
 try database.savePluginState(pluginId: pluginId, enabled: state.enabled, connected: false)
 } catch {
 logger.warning("Failed to persist disconnect state: \(error.localizedDescription, privacy: .public)")
 }

 logger.info("Plugin disconnected: \(pluginId, privacy: .public)")
 }

 /// Disconnect all connected plugins. Called on app shutdown.
 public func disconnectAll() async {
 let connectedIds = Array(transports.keys)
 logger.info("Disconnecting all \(connectedIds.count) active plugins…")

 // Serialize disconnects to avoid overwhelming the process manager.
 for id in connectedIds {
 await disconnect(pluginId: id)
 }

 logger.info("All plugins disconnected")
 }

 /// Enable a plugin so it can be connected.
 public func enable(pluginId: String) async throws {
 guard PluginCollection.byId(pluginId) != nil else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.enabled = true
 state.lastError = nil
 states[pluginId] = state

 try database.savePluginState(pluginId: pluginId, enabled: true, connected: state.connected)
 logger.info("Plugin enabled: \(pluginId, privacy: .public)")
 }

 /// Disable a plugin. If currently connected, disconnect first.
 public func disable(pluginId: String) async throws {
 guard PluginCollection.byId(pluginId) != nil else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 if transports[pluginId] != nil {
 await disconnect(pluginId: pluginId)
 }

 var state = states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 state.enabled = false
 states[pluginId] = state

 try database.savePluginState(pluginId: pluginId, enabled: false, connected: false)
 logger.info("Plugin disabled: \(pluginId, privacy: .public)")
 }

 /// Reconnect a plugin — disconnects then re-connects, refreshing the transport.
 public func reconnect(pluginId: String) async throws -> PluginDescriptor {
 logger.info("Reconnecting plugin: \(pluginId, privacy: .public)")
 await disconnect(pluginId: pluginId)
 return try await connect(pluginId: pluginId)
 }

 // MARK: - Transport Access

 /// Return the active transport for a plugin, or nil if not connected.
 public func transport(for pluginId: String) -> AnyTransport? {
 transports[pluginId]
 }

 /// Return true if the plugin is currently connected and has an active transport.
 public func isConnected(_ pluginId: String) -> Bool {
 transports[pluginId] != nil
 }

 // MARK: - OAuth Flow

 /// Initiate the OAuth 2.0 authorization code + PKCE flow for a plugin.
 ///
 /// Flow:
 /// 1. Generate PKCE challenge (code_verifier + code_challenge per RFC 7636).
 /// 2. Discover the provider's OAuth metadata endpoints.
 /// 3. Build the authorization URL and present it via the delegate.
 /// 4. The delegate handles the user authorization (external browser).
 /// 5. Exchange the returned authorization code + PKCE verifier for tokens.
 /// 6. Persist the access/refresh tokens in Keychain via CredentialStore.
 ///
 /// - Parameter pluginId: The plugin identifier.
 /// - Parameter delegate: Handles presenting the authorization URL to the user.
 /// - Returns: The obtained OAuthToken (also stored in Keychain).
 public func initiateOAuthFlow(
 for pluginId: String,
 delegate: any MCPOAuthAuthorizationDelegate
 ) async throws -> OAuthToken {
 logger.info("Initiating OAuth flow for: \(pluginId, privacy: .public)")

 guard let descriptor = PluginCollection.byId(pluginId) else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 guard descriptor.authType == .oauth else {
 throw PluginRegistryError.invalidConfiguration(
 "Plugin '\(pluginId)' does not use OAuth (authType: \(descriptor.authType.rawValue))"
 )
 }

 guard let scopes = descriptor.scopes, !scopes.isEmpty else {
 throw PluginRegistryError.invalidConfiguration(
 "Plugin '\(pluginId)' has no OAuth scopes configured."
 )
 }

 // ── 1. Generate PKCE challenge ─────────────────────────────────
 // RFC 7636: code_verifier is 43-128 chars from the unreserved set.
 // The verifier is stored for the duration of the flow.
 let pkce = PKCEChallenge()
 pendingPKCE[pluginId] = pkce.codeVerifier

 // ── 2. Discover OAuth metadata ─────────────────────────────────
 let discovery: OAuthDiscovery

 if let httpURL = descriptor.transport.httpURL {
 let discoveryURL = httpURL.appendingPathComponent(".well-known/oauth-authorization-server")
 discovery = try await fetchDiscoveryDocument(from: discoveryURL) ?? fallbackDiscovery(for: pluginId)
 } else {
 discovery = fallbackDiscovery(for: pluginId)
 }

 // ── 3. Build authorization URL ─────────────────────────────────
 // State parameter prevents CSRF — stored for validation on callback.
 let stateValue = UUID().uuidString
 pendingOAuthState[pluginId] = stateValue

 let authURL = buildAuthorizationURL(
 discovery: discovery,
 scopes: scopes,
 codeChallenge: pkce.codeChallenge,
 codeChallengeMethod: pkce.method,
 state: stateValue,
 pluginId: descriptor.id
 )

 // ── 4-6. Delegate presents URL, obtains code, we exchange ───────
 let authorizationCode = try await delegate.handleAuthorizationURL(authURL)

 let token = try await exchangeCodeForToken(
 code: authorizationCode,
 verifier: pkce.codeVerifier,
 discovery: discovery,
 pluginId: descriptor.id
 )

 // Store token in Keychain via CredentialStore (never in source or logs).
 let identity = PluginIdentity(
 id: descriptor.id,
 displayName: descriptor.displayName,
 type: .remote,
 authType: .oauth
 )

 try await credentialStore.storeToken(token, for: identity)

 // Clean up pending flow state.
 pendingPKCE.removeValue(forKey: pluginId)
 pendingOAuthState.removeValue(forKey: pluginId)

 logger.info("OAuth flow complete, token stored for: \(pluginId, privacy: .public)")
 return token
 }

 /// Retrieve the PKCE verifier for a pending OAuth flow.
 /// Called by the OAuth callback handler to complete the code exchange.
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

 /// Validate the tool catalog for a connected plugin by sending tools/list.
 ///
 /// The validation checks:
 /// - The response is a valid JSON-RPC 2.0 response.
 /// - The `tools` array is present.
 /// - Each tool entry has a required `name` field.
 public func validateToolCatalog(
 for descriptor: PluginDescriptor,
 transport: AnyTransport
 ) async throws -> PluginValidationResult {
 logger.debug("Validating tool catalog for \(descriptor.id, privacy: .public)…")

 let requestId = UUID().uuidString
 let request = JSONRPCRequest(
 id: requestId,
 method: MCPMethod.toolsList.rawValue,
 params: JSONValue.object([:])
 )

 do {
 let response = try await transport.sendRequest(request)

 guard let result = response.result, case .object(let dict) = result else {
 return PluginValidationResult(
 valid: false,
 toolsCount: 0,
 error: "Invalid tools/list response format — expected JSON object."
 )
 }

 guard let toolsArray = dict["tools"]?.arrayValue else {
 return PluginValidationResult(
 valid: false,
 toolsCount: 0,
 error: "Response missing required 'tools' array."
 )
 }

 let count = toolsArray.count

 // Validate each tool entry has required fields.
 for toolValue in toolsArray {
 guard case .object(let toolDict) = toolValue else {
 return PluginValidationResult(
 valid: false,
 toolsCount: count,
 error: "Tool entry is not a JSON object."
 )
 }

 if toolDict["name"]?.stringValue == nil {
 return PluginValidationResult(
 valid: false,
 toolsCount: count,
 error: "Tool missing required 'name' field."
 )
 }
 }

 logger.info("Tool catalog validated for \(descriptor.id): \(count) tools available")
 return PluginValidationResult(valid: true, toolsCount: count)

 } catch {
 logger.error("Tool catalog validation error for \(descriptor.id): \(error.localizedDescription, privacy: .public)")
 return PluginValidationResult(valid: false, toolsCount: 0, error: error.localizedDescription)
 }
 }

 /// Validate the tool catalog for a connected plugin by id.
 public func validateToolCatalog(pluginId: String) async throws -> PluginValidationResult {
 guard let descriptor = PluginCollection.byId(pluginId) else {
 throw PluginRegistryError.pluginNotFound(pluginId)
 }

 guard let transport = transports[pluginId] else {
 throw PluginRegistryError.pluginNotEnabled(pluginId)
 }

 return try await validateToolCatalog(for: descriptor, transport: transport)
 }

 // MARK: - Safety Rule Enforcement

 /// Check whether a pending tool call would violate any safety rule.
 ///
 /// Call this before executing any tool call through the tool router.
 /// Returns nil if the call is safe, or a descriptive violation string.
 ///
 /// Safety rules are pattern-matched against the tool name. If a rule
 /// matches, the call is blocked and the violation message is returned.
 public func checkSafetyViolation(
 pluginId: String,
 toolName: String,
 arguments: [String: JSONValue]
 ) -> String? {
 guard let descriptor = PluginCollection.byId(pluginId) else {
 return "Unknown plugin: \(pluginId)"
 }

 let lowered = toolName.lowercased()

 // Pattern 1: Never auto-send emails
 if descriptor.safetyRules.contains(where: { $0.contains("Never auto-send") }),
 lowered.contains("send") && lowered.contains("email") {
 return descriptor.safetyRules.first { $0.contains("Never auto-send") }
 }

 // Pattern 2: Never bypass billing / payments
 if descriptor.safetyRules.contains(where: { $0.contains("bypass billing") || $0.contains("bypass payment") }),
 lowered.contains("bill") || lowered.contains("payment") || lowered.contains("charge") {
 return descriptor.safetyRules.first { $0.contains("bypass") }
 }

 // Pattern 3: Never merge/force-push without approval
 if descriptor.safetyRules.contains(where: { $0.contains("without user approval") }),
 lowered.contains("merge") || lowered.contains("push") {
 return descriptor.safetyRules.first { $0.contains("without user approval") }
 }

 // Pattern 4: Never delete without confirmation
 if descriptor.safetyRules.contains(where: { $0.contains("without user confirmation") || $0.contains("without explicit confirmation") }),
 lowered.contains("delete") || lowered.contains("remove") || lowered.contains("destroy") || lowered.contains("drop") {
 return descriptor.safetyRules.first {
 $0.contains("without user confirmation") || $0.contains("without explicit confirmation") || $0.contains("without approval")
 }
 }

 // Pattern 5: Never access private data without authorization
 if descriptor.safetyRules.contains(where: { $0.contains("without user authorization") || $0.contains("without authorization") }),
 lowered.contains("read") && (lowered.contains("private") || lowered.contains("personal")) {
 return descriptor.safetyRules.first {
 $0.contains("without user authorization") || $0.contains("without authorization")
 }
 }

 // Pattern 6: Never deploy without approval
 if descriptor.safetyRules.contains(where: { $0.contains("without explicit user approval") }),
 lowered.contains("deploy") || lowered.contains("publish") {
 return descriptor.safetyRules.first { $0.contains("without explicit user approval") }
 }

 return nil
 }

 // MARK: - State Queries

 /// Return the cached runtime state for a plugin.
 public func state(for pluginId: String) -> PluginRuntimeState {
 states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 }

 /// Return runtime states for all known plugins, sorted by id.
 public func allStates() -> [PluginRuntimeState] {
 states.values.sorted { $0.pluginId < $1.pluginId }
 }

 /// Return true if the plugin is enabled and currently connected.
 public func isAvailable(_ pluginId: String) -> Bool {
 guard let state = states[pluginId] else { return false }
 return state.enabled && state.connected
 }

 /// Return descriptors for all plugins matching a given state filter.
 public func plugins(matching filter: (PluginRuntimeState) -> Bool) -> [PluginDescriptor] {
 PluginCollection.allCases
 .map(\.descriptor)
 .filter { descriptor in
 guard let state = states[descriptor.id] else { return false }
 return filter(state)
 }
 }

 // MARK: - Private Helpers

 private func loadStatesFromDatabase() async {
 do {
 let records = try database.getAllPluginStates()
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
 // Known provider OAuth endpoints keyed by plugin identifier.
 // SECURITY: These are public well-known URLs, not secrets.
 let wellKnownURLs: [String: URL] = [
 "google": URL(string: "https://accounts.google.com")!,
 "github": URL(string: "https://github.com")!,
 "slack": URL(string: "https://slack.com")!,
 "notion": URL(string: "https://api.notion.com")!,
 "linear": URL(string: "https://linear.app")!,
 "stripe": URL(string: "https://connect.stripe.com")!,
 "metaads": URL(string: "https://facebook.com")!,
 "shopify": URL(string: "https://shopify.com")!,
 "supabase": URL(string: "https://supabase.com")!
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
 state: String,
 pluginId: String
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
 discovery: OAuthDiscovery,
 pluginId: String
 ) async throws -> OAuthToken {
 // Build the token exchange request body (x-www-form-urlencoded).
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
 request.httpBody = bodyString.data(using: .utf8)

 let (data, response) = try await URLSession.shared.data(for: request)
 guard let httpResponse = response as? HTTPURLResponse,
 (200...299).contains(httpResponse.statusCode) else {
 let status = (response as? HTTPURLResponse)?.statusCode ?? -1
 logger.error("Token exchange failed for \(pluginId, privacy: .public): HTTP \(status)")
 throw PluginRegistryError.oauthFlowFailed(
 "Token endpoint returned HTTP \(status) for plugin '\(pluginId)'."
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

 let token = OAuthToken(
 accessToken: tokenResponse.access_token,
 refreshToken: tokenResponse.refresh_token,
 tokenType: tokenResponse.token_type,
 expiresIn: tokenResponse.expires_in,
 scope: tokenResponse.scope
 )

 logger.info("Token exchange successful for \(pluginId, privacy: .public)")
 return token
 }
}

// MARK: - PluginTransport Convenience Extension

extension PluginTransport {

 /// Returns the HTTP URL for this transport, or nil if not an HTTP transport.
 var httpURL: URL? {
 switch self {
 case .http(let url): return url
 default: return nil
 }
 }
}
