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
// Transport instances are @unchecked Sendable (per MCPStdioTransport contract).
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

// MARK: - Plugin Transport Factory

/// Creates the appropriate MCP transport instance for a given plugin descriptor.
///
/// SECURITY: For API-key plugins, the environment variable is injected into
/// the child process environment (stdio) or the transport reads it at
/// request time. The raw key is never logged or exposed to the app layer.
public enum PluginTransportFactory: Sendable {

 /// Build and return a transport ready for connection.
 @discardableResult
 public static func create(
 for descriptor: PluginDescriptor,
 credentialStore: CredentialStore? = nil
 ) async throws -> MCPTransport {
 switch descriptor.transport {

 // ── HTTP transport (remote MCP server) ──────────────────────────
 case .http(let url):
 return try await createHTTPTransport(url: url, descriptor: descriptor, credentialStore: credentialStore)

 // ── Stdio transport (local MCP server process) ──────────────────
 case .stdio(let command, let arguments):
 return try createStdioTransport(command: command, arguments: arguments, descriptor: descriptor)

 // ── OAuth transport ─────────────────────────────────────────────
 case .oauth:
 throw PluginRegistryError.transportCreationFailed(
 "OAuth transport must be created after completing the authorization code flow. "
 + "Call initiateOAuthFlow(_:) first, then connect the returned transport."
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
 url: URL,
 descriptor: PluginDescriptor,
 credentialStore: CredentialStore?
 ) async throws -> MCPHTTPTransport {
 // Resolve bearer token: for OAuth plugins, read from Keychain.
 // For API-key plugins, the upstream MCP server handles auth — we just connect.
 var bearerToken: String? = nil

 if descriptor.authType == .oauth, let store = credentialStore {
 let token = try await store.retrieveToken(for: PluginIdentity(
 id: descriptor.id,
 displayName: descriptor.displayName,
 type: descriptor.type == .agent ? .remote : .remote,
 authType: .oauth
 ))
 bearerToken = token?.accessToken
 }

 // Resolve session ID from environment if set
 let sessionID = ProcessInfo.processInfo.environment["BRIDGEMIND_MCP_SESSION_ID_\(descriptor.id.uppercased())"]
 ?? nil

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
 env[apiKeyEnv] = keyValue
 }

 let config = MCPStdioTransport.Configuration(
 executable: command,
 arguments: arguments,
 workingDirectory: nil,
 environment: env,
 requestTimeout: .seconds(30),
 stderrLogHandler: { line in
 // Route plugin stderr through the shared logger
 Logger(subsystem: "com.bridgemind.mcp.plugin.\(descriptor.id)",
 category: "stderr")
 .debug("\(line, privacy: .public)")
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
///
/// Thread safety: This is an actor. All state mutations are serialized.
/// The actor boundary is crossed at every public method call.
///
/// SECURITY: Never log raw API keys or OAuth tokens. Token references are
/// logged as redacted strings (e.g. "token:***abc").
public actor PluginRegistry {

 // MARK: Dependencies

 private let database: DatabaseManager
 private let credentialStore: CredentialStore

 // MARK: Runtime State

 /// Active transports keyed by plugin id.
 /// An entry exists only while the plugin is connected.
 private var transports: [String: any MCPTransport] = [:]

 /// Runtime state cached in memory (mirrors the DB for fast access).
 private var states: [String: PluginRuntimeState] = [:]

 /// Pending OAuth continuations keyed by plugin id.
 private var oauthContinuations: [String: CheckedContinuation<OAuthToken, Error>] = [:]

 // MARK: Logging

 private let logger = Logger(subsystem: "com.bridgemind.one", category: "PluginRegistry")

 // MARK: Initialization

 public init(
 database: DatabaseManager,
 credentialStore: CredentialStore
 ) {
 self.database = database
 self.credentialStore = credentialStore

 // Load persisted states from DB on startup
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
 /// 3. Create the appropriate transport.
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
 // Disconnect the transport before throwing
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

 logger.info("Plugin connected successfully: \(pluginId, privacy: .public)")
 return descriptor
 }

 /// Disconnect a plugin and release its transport.
 public func disconnect(pluginId: String) async {
 logger.info("Disconnecting plugin: \(pluginId, privacy: .public)")

 guard let transport = transports[pluginId] else {
 logger.warning("Plugin not connected: \(pluginId, privacy: .public)")
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
 let connectedIds = transports.keys
 await withTaskGroup(of: Void.self) { group in
 for id in connectedIds {
 group.addTask { [weak self] in
 await self?.disconnect(pluginId: id)
 }
 }
 }
 logger.info("All plugins disconnected (\(connectedIds.count))")
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

 /// Disable a plugin. If connected, disconnect first.
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

 // MARK: - Transport Access

 /// Return the active transport for a plugin, or nil if not connected.
 public func transport(for pluginId: String) -> (any MCPTransport)? {
 transports[pluginId]
 }

 /// Return true if the plugin is currently connected.
 public func isConnected(_ pluginId: String) -> Bool {
 transports[pluginId] != nil
 }

 // MARK: - OAuth Flow

 /// Initiate the OAuth 2.0 authorization code + PKCE flow for a plugin.
 ///
 /// Steps:
 /// 1. Generate PKCE challenge (code_verifier + code_challenge).
 /// 2. Discover the provider's OAuth metadata (authorization endpoint, token endpoint).
 /// 3. Build the authorization URL and hand it to the delegate for user presentation.
 /// 4. Wait for the authorization code callback.
 /// 5. Exchange the code + verifier for an access token.
 /// 6. Store the token in Keychain via CredentialStore.
 ///
 /// - Parameter pluginId: The plugin identifier.
 /// - Parameter delegate: Handles presenting the authorization URL to the user.
 /// - Returns: The obtained OAuthToken.
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

 guard let scopes = descriptor.scopes else {
 throw PluginRegistryError.invalidConfiguration(
 "Plugin '\(pluginId)' has no OAuth scopes configured."
 )
 }

 // ── 1. Generate PKCE challenge ─────────────────────────────────
 let pkce = PKCEChallenge()

 // ── 2. Discover OAuth metadata ─────────────────────────────────
 // The MCP server running at the plugin's endpoint should expose a
 // .well-known/oauth-authorization-server endpoint or we use the
 // well-known provider URLs per vendor.
 let discovery: OAuthDiscovery

 if let httpURL = descriptor.transport.httpURL {
 // Try fetching discovery from the MCP server's well-known endpoint
 let discoveryURL = httpURL.appendingPathComponent(".well-known/oauth-authorization-server")
 discovery = try await fetchDiscoveryDocument(from: discoveryURL) ?? fallbackDiscovery(for: pluginId)
 } else {
 discovery = fallbackDiscovery(for: pluginId)
 }

 // ── 3. Build authorization URL ─────────────────────────────────
 let stateValue = UUID().uuidString
 let authURL = buildAuthorizationURL(
 discovery: discovery,
 scopes: scopes,
 codeChallenge: pkce.codeChallenge,
 codeChallengeMethod: pkce.method,
 state: stateValue
 )

 // ── 4. Present to user and await callback ──────────────────────
 return try await withCheckedThrowingContinuation { continuation in
 // Store the continuation and PKCE verifier for the callback
 self.oauthContinuations[pluginId] = continuation

 Task {
 do {
 let authorizationCode = try await delegate.handleAuthorizationURL(authURL)

 // ── 5. Exchange code for token ───────────────────────────────
 let token = try await exchangeCodeForToken(
 code: authorizationCode,
 verifier: pkce.codeVerifier,
 discovery: discovery
 )

 // ── 6. Persist token ──────────────────────────────────────────
 let identity = PluginIdentity(
 id: descriptor.id,
 displayName: descriptor.displayName,
 type: descriptor.type == .agent ? .remote : .oauth,
 authType: .oauth
 )

 try await credentialStore.storeToken(token, for: identity)

 self.logger.info("OAuth token stored for \(pluginId, privacy: .public)")
 self.oauthContinuations.removeValue(forKey: pluginId)

 continuation.resume(returning: token)
 } catch {
 self.logger.error("OAuth flow failed for \(pluginId): \(error.localizedDescription, privacy: .public)")
 self.oauthContinuations.removeValue(forKey: pluginId)
 continuation.resume(throwing: error)
 }
 }
 }
 }

 /// Handle the OAuth callback (redirect) received after user authorization.
 /// This is called by the app's OAuth callback handler with the full URL.
 public func handleOAuthCallback(url: URL, pluginId: String) async throws -> OAuthToken {
 logger.info("OAuth callback received for: \(pluginId, privacy: .public)")

 guard let continuation = oauthContinuations[pluginId] else {
 throw PluginRegistryError.oauthFlowFailed(
 "No pending OAuth flow for plugin '\(pluginId)'. Call initiateOAuthFlow(_:) first."
 )
 }

 // Extract authorization code from the callback URL
 guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
 let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
 let state = components.queryItems?.first(where: { $0.name == "state" })?.value else {
 throw PluginRegistryError.oauthFlowFailed("Invalid OAuth callback URL — missing code or state.")
 }

 continuation.resume(returning: code as! OAuthToken)

 // Note: The actual token exchange happens in initiateOAuthFlow's continuation.
 // The callback just passes the code through.
 throw PluginRegistryError.oauthFlowFailed(
 "OAuth callback handled — waiting for token exchange completion."
 )
 }

 // MARK: - Tool Catalog Validation

 /// Connect to a plugin and fetch its tool catalog, then validate it.
 public func validateToolCatalog(
 for descriptor: PluginDescriptor,
 transport: any MCPTransport
 ) async throws -> PluginValidationResult {
 logger.debug("Validating tool catalog for \(descriptor.id, privacy: .public)…")

 // The transport must already be connected at this point.
 guard transports[descriptor.id] != nil || descriptor.transport == .builtin else {
 throw PluginRegistryError.invalidConfiguration(
 "Transport for '\(descriptor.id)' must be connected before validating tools."
 )
 }

 // Build and send a tools/list JSON-RPC request.
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

 // Sanity checks on tool definitions
 for toolValue in toolsArray {
 guard case .object(let toolDict) = toolValue else {
 return PluginValidationResult(
 valid: false,
 toolsCount: 0,
 error: "Tool entry is not a JSON object."
 )
 }

 guard toolDict["name"]?.stringValue != nil else {
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

 /// Check whether a tool call violates a plugin's safety rules.
 /// Call this before executing any tool call.
 ///
 /// - Parameters:
 /// - pluginId: The plugin identifier.
 /// - toolName: The name of the tool being called.
 /// - arguments: The arguments being passed to the tool.
 /// - Returns: nil if safe, or a descriptive violation string.
 public func checkSafetyViolation(
 pluginId: String,
 toolName: String,
 arguments: [String: JSONValue]
 ) -> String? {
 guard let descriptor = PluginCollection.byId(pluginId) else {
 return "Unknown plugin: \(pluginId)"
 }

 // Rule: Never auto-send emails
 if descriptor.safetyRules.contains(where: { $0.contains("Never auto-send") }),
 toolName.lowercased().contains("send") && toolName.lowercased().contains("email") {
 return descriptor.safetyRules.first(where: { $0.contains("Never auto-send") })
 }

 // Rule: Never bypass billing
 if descriptor.safetyRules.contains(where: { $0.contains("bypass billing") }),
 toolName.lowercased().contains("bill") || toolName.lowercased().contains("payment") {
 return descriptor.safetyRules.first(where: { $0.contains("bypass billing") })
 }

 // Rule: Never merge/force-push without approval
 if descriptor.safetyRules.contains(where: { $0.contains("without user approval") }),
 (toolName.lowercased().contains("merge") || toolName.lowercased().contains("push")) {
 return descriptor.safetyRules.first(where: { $0.contains("without user approval") })
 }

 // Rule: Never destructive without confirmation
 if descriptor.safetyRules.contains(where: { $0.contains("destructive") || $0.contains("delete") }),
 toolName.lowercased().contains("delete") || toolName.lowercased().contains("remove") {
 return descriptor.safetyRules.first(where: { $0.contains("without user confirmation") || $0.contains("without approval") })
 }

 return nil
 }

 // MARK: - State Queries

 /// Return the cached runtime state for a plugin.
 public func state(for pluginId: String) -> PluginRuntimeState {
 states[pluginId] ?? PluginRuntimeState(pluginId: pluginId)
 }

 /// Return runtime states for all known plugins.
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
 return try? JSONDecoder().decode(OAuthDiscovery.self, from: data)
 } catch {
 logger.debug("Discovery document not available at \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
 return nil
 }
 }

 private func fallbackDiscovery(for pluginId: String) -> OAuthDiscovery {
 // Known provider endpoints keyed by plugin id.
 // SECURITY: These are public well-known endpoints, not secrets.
 let wellKnownURLs: [String: URL] = [
 "google": URL(string: "https://accounts.google.com")!,
 "github": URL(string: "https://github.com")!,
 "slack": URL(string: "https://slack.com")!,
 "notion": URL(string: "https://api.notion.com")!,
 "linear": URL(string: "https://linear.app")!,
 "stripe": URL(string: "https://connect.stripe.com")!,
 "metaads": URL(string: "https://facebook.com")!,
 "shopify": URL(string: "https://shopify.com")!,
 "supabase": URL(string: "https://supabase.com")!,
 "youtube": URL(string: "https://accounts.google.com")!
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

 var queryItems = [
 URLQueryItem(name: "client_id", value: "bridgemind-one"),
 URLQueryItem(name: "redirect_uri", value: "\(AppConfig.appIdentifier)://oauth/callback"),
 URLQueryItem(name: "response_type", value: "code"),
 URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
 URLQueryItem(name: "state", value: state),
 URLQueryItem(name: "code_challenge", value: codeChallenge),
 URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod)
 ]

 components.queryItems = queryItems
 return components.url ?? discovery.authorizationEndpoint
 }

 private func exchangeCodeForToken(
 code: String,
 verifier: String,
 discovery: OAuthDiscovery
 ) async throws -> OAuthToken {
 // Build the token request body
 let body: [String: String] = [
 "grant_type": "authorization_code",
 "code": code,
 "redirect_uri": "\(AppConfig.appIdentifier)://oauth/callback",
 "client_id": "bridgemind-one",
 "code_verifier": verifier
 ]

 var request = URLRequest(url: discovery.tokenEndpoint)
 request.httpMethod = "POST"
 request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

 let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
 request.httpBody = bodyString.data(using: .utf8)

 let (data, response) = try await URLSession.shared.data(for: request)
 guard let httpResponse = response as? HTTPURLResponse,
 (200...299).contains(httpResponse.statusCode) else {
 throw PluginRegistryError.oauthFlowFailed(
 "Token endpoint returned HTTP \(response.expectedStatusCode)"
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

// MARK: - Extensions

private extension HTTPURLResponse {
 var expectedStatusCode: Int { statusCode }
}
