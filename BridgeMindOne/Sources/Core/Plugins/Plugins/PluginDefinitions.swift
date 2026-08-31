//
// PluginDefinitions.swift
// BridgeMind One — All 24 plugin identity definitions + MCPPluginProvider protocol
//
// Each plugin is a struct with a static `descriptor` property.
// Plugin descriptions come from the original binary strings and are preserved verbatim.
// Safety rules and warnings are extracted from the original binary and annotated per plugin.
//
// SECURITY NOTE: API keys and OAuth tokens are NEVER stored in source code.
// They are resolved at runtime from environment variables (apiKeyEnv) or from the
// system Keychain via CredentialStore (oauth). See CredentialStore.swift for details.
//

import Foundation

// MARK: - Plugin Descriptor (concrete value type)

/// Immutable identity for one plugin. Stored, compared, and passed around as a value.
/// This is the type used in arrays, dictionaries, and the plugin registry.
public struct PluginDescriptor: Sendable, Equatable, Codable, Identifiable {

 public let id: String
 public let displayName: String
 public let type: PluginType
 public let authType: PluginAuthType
 public let transport: PluginTransport
 public let apiKeyEnv: String?
 public let scopes: [String]?
 public let description: String
 public let safetyRules: [String]
 public let warnings: [String]

 public init(
 id: String,
 displayName: String,
 type: PluginType,
 authType: PluginAuthType,
 transport: PluginTransport,
 apiKeyEnv: String? = nil,
 scopes: [String]? = nil,
 description: String,
 safetyRules: [String] = [],
 warnings: [String] = []
 ) {
 self.id = id
 self.displayName = displayName
 self.type = type
 self.authType = authType
 self.transport = transport
 self.apiKeyEnv = apiKeyEnv
 self.scopes = scopes
 self.description = description
 self.safetyRules = safetyRules
 self.warnings = warnings
 }
}

// MARK: - Plugin Transport Model

/// Determines how the plugin MCP server is reached.
public enum PluginTransport: Sendable, Codable, Equatable, CaseIterable {
 /// Local server launched as a child process; communicates over stdin/stdout.
 case stdio(command: String, arguments: [String] = [])
 /// Remote server at a fixed HTTPS endpoint; communicates over HTTP/SSE.
 case http(URL)
 /// OAuth-based server; transport is created after the OAuth flow completes.
 case oauth
 /// Built into BridgeMind One; no external process or network call needed.
 case builtin

 public var requiresNetwork: Bool {
 switch self {
 case .http, .oauth: return true
 case .stdio, .builtin: return false
 }
 }
}

// MARK: - PluginType

public enum PluginType: String, Sendable, Codable, Equatable, CaseIterable {
 case agent // LLM agent engine (Claude, Codex, Gemini, …)
 case saas // Business / SaaS integration (GitHub, Slack, Stripe, …)

 public var displayName: String {
 switch self {
 case .agent: return "Agent Engine"
 case .saas: return "Business Tool"
 }
 }
}

// MARK: - PluginAuthType

public enum PluginAuthType: String, Sendable, Codable, Equatable, CaseIterable {
 case none // No authentication — local or built-in plugin
 case apiKey // Simple API key from environment variable
 case oauth // Full OAuth 2.0 authorization code + PKCE flow

 public var displayName: String {
 switch self {
 case .none: return "No Auth"
 case .apiKey: return "API Key"
 case .oauth: return "OAuth 2.0"
 }
 }
}

// MARK: - MCPPluginProvider Protocol

/// Namespace-scoped contract that every plugin struct satisfies.
///
/// Conforming structs are zero-cost namespaces containing only a static `descriptor`.
/// This avoids existential boxing of static properties and keeps each plugin definition
/// as a compile-time constant.
public protocol MCPPluginProvider: Sendable, Equatable {
 /// The plugin's descriptor — compile-time constant.
 static var descriptor: PluginDescriptor { get }
}

// MARK: - PluginRuntimeState

/// Tracks the runtime state of a single plugin instance (stored in DB / memory).
public struct PluginRuntimeState: Sendable, Codable, Equatable {
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

// MARK: - PluginValidationResult

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

// MARK: - PluginCollection

/// Registry of all 24 plugins, grouped by category.
public enum PluginCollection: Sendable, Equatable, CaseIterable {

 // MARK: Agent Engine Plugins

 case claude, codex, copilot, cursor, aider, deepSeek, gemini, grok, openCode, antigravity, droid

 // MARK: SaaS Plugins

 case apollo, blender, cloudflare, fal, github, gmail, googleAds, higgsfield, linear, metaAds
 case notion, quickBooks, resend, revenueCat, sentry, shopify, slack, stripe, supabase
 case unity, unreal, vercel, vidIQ, youtube

 // MARK: Descriptor lookup

 public var descriptor: PluginDescriptor {
 switch self {
 case .claude: ClaudePlugin.descriptor
 case .codex: CodexPlugin.descriptor
 case .copilot: CopilotPlugin.descriptor
 case .cursor: CursorPlugin.descriptor
 case .aider: AiderPlugin.descriptor
 case .deepSeek: DeepSeekPlugin.descriptor
 case .gemini: GeminiPlugin.descriptor
 case .grok: GrokPlugin.descriptor
 case .openCode: OpenCodePlugin.descriptor
 case .antigravity: AntigravityPlugin.descriptor
 case .droid: DroidPlugin.descriptor
 case .apollo: ApolloPlugin.descriptor
 case .blender: BlenderPlugin.descriptor
 case .cloudflare: CloudflarePlugin.descriptor
 case .fal: FalPlugin.descriptor
 case .github: GitHubPlugin.descriptor
 case .gmail: GmailPlugin.descriptor
 case .googleAds: GoogleAdsPlugin.descriptor
 case .higgsfield: HiggsfieldPlugin.descriptor
 case .linear: LinearPlugin.descriptor
 case .metaAds: MetaAdsPlugin.descriptor
 case .notion: NotionPlugin.descriptor
 case .quickBooks: QuickBooksPlugin.descriptor
 case .resend: ResendPlugin.descriptor
 case .revenueCat: RevenueCatPlugin.descriptor
 case .sentry: SentryPlugin.descriptor
 case .shopify: ShopifyPlugin.descriptor
 case .slack: SlackPlugin.descriptor
 case .stripe: StripePlugin.descriptor
 case .supabase: SupabasePlugin.descriptor
 case .unity: UnityPlugin.descriptor
 case .unreal: UnrealPlugin.descriptor
 case .vercel: VercelPlugin.descriptor
 case .vidIQ: VidIQPlugin.descriptor
 case .youtube: YouTubePlugin.descriptor
 }
 }

 // MARK: Grouped access

 /// All 24 plugins as descriptors.
 public static let all: [PluginDescriptor] = Self.allCases.map(\.descriptor)

 /// Agent engine plugins only.
 public static var agents: [PluginDescriptor] {
 allCases.filter { $0.descriptor.type == .agent }.map(\.descriptor)
 }

 /// SaaS / business tool plugins only.
 public static var saas: [PluginDescriptor] {
 allCases.filter { $0.descriptor.type == .saas }.map(\.descriptor)
 }

 /// Plugins that require an API key environment variable.
 public static var apiKeyPlugins: [PluginDescriptor] {
 allCases.filter { $0.descriptor.authType == .apiKey }.map(\.descriptor)
 }

 /// Plugins that use OAuth.
 public static var oauthPlugins: [PluginDescriptor] {
 allCases.filter { $0.descriptor.authType == .oauth }.map(\.descriptor)
 }

 /// Plugins that use local stdio transport.
 public static var localPlugins: [PluginDescriptor] {
 allCases.filter {
 switch $0.descriptor.transport {
 case .stdio: return true
 default: return false
 }
 }.map(\.descriptor)
 }

 /// Lookup by stable identifier.
 public static func byId(_ id: String) -> PluginDescriptor? {
 allCases.first { $0.descriptor.id == id }?.descriptor
 }
}
