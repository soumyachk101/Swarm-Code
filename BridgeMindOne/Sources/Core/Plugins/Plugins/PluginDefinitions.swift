//
// PluginDefinitions.swift
// BridgeMind One — All 24 plugin identity definitions
//
// Extends the existing PluginIdentity type (from OAuthFlows.swift) with
// static plugin identity constants matching the original binary strings.
//
// Each identity carries:
// - Stable machine-readable id (e.g. "bridgemind_plugins__github")
// - Human-readable displayName
// - PluginType (.builtin, .remote, .local)
// - PluginAuthType (.none, .apiKey, .oauth)
// - mcpURL: endpoint for remote MCP servers
// - apiKeyEnv: environment variable for API-key plugins
// - scopes: OAuth scopes for OAuth plugins
//
// SECURITY NOTE: API keys and OAuth tokens are NEVER stored in source code.
// They are resolved at runtime from environment variables (apiKeyEnv) or from
// the system Keychain via CredentialStore (oauth). See CredentialStore.swift.

import Foundation

// MARK: - PluginType

/// Classification of plugin categories.
public enum PluginType: String, Codable, Equatable, CaseIterable, Sendable {
 case builtin // Built into BridgeMind One, no external server
 case remote // Remote MCP server reachable over HTTP/HTTPS
 case local // Local stdio MCP server (child process)

 public var displayName: String {
 switch self {
 case .builtin: return "Built-in"
 case .remote: return "Remote"
 case .local: return "Local"
 }
 }
}

// MARK: - PluginAuthType

/// Authentication mechanism required by a plugin.
public enum PluginAuthType: String, Codable, Equatable, CaseIterable, Sendable {
 case none // No authentication required
 case apiKey // Simple API key from environment variable
 case oauth // Full OAuth 2.0 authorization code + PKCE

 public var displayName: String {
 switch self {
 case .none: return "None"
 case .apiKey: return "API Key"
 case .oauth: return "OAuth 2.0"
 }
 }
}

// MARK: - All 24 Plugin Identities

public extension PluginIdentity {

 // ─── Agent Engine Plugins ────────────────────────────────────

 /// Anthropic Claude — primary reasoning engine
 /// Safety: All responses subject to Anthropic usage policies.
 /// Never bypass billing approvals. Honor prompt caching cost transparency.
 static let claude = PluginIdentity(
 id: "bridgemind_plugins__claude",
 displayName: "Claude",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://api.anthropic.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_ANTHROPIC_API_KEY"
 )

 /// OpenAI Codex — code-specialized reasoning
 /// Safety: Output must be reviewed before execution.
 /// Never execute generated code without sandboxing.
 static let codex = PluginIdentity(
 id: "bridgemind_plugins__codex",
 displayName: "Codex",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://api.openai.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_OPENAI_API_KEY"
 )

 /// GitHub Copilot — code completion and generation
 /// Safety: Never auto-apply code suggestions without user review.
 /// Generated code subject to GitHub Copilot license terms.
 static let copilot = PluginIdentity(
 id: "bridgemind_plugins__copilot",
 displayName: "GitHub Copilot",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://api.githubcopilot.com/mcp")!
 )

 /// Cursor IDE — code agent and editor integration
 /// Safety: Never apply edits without explicit user confirmation.
 /// Sandbox all file-system modifications.
 static let cursor = PluginIdentity(
 id: "bridgemind_plugins__cursor",
 displayName: "Cursor",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://api.cursor.com/mcp")!
 )

 /// Aider — open-source AI pair programming
 /// Safety: Never commit generated code without review.
 /// Sandbox all git operations.
 static let aider = PluginIdentity(
 id: "bridgemind_plugins__aider",
 displayName: "Aider",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://aider.chat/mcp")!
 )

 /// DeepSeek — high-performance reasoning
 /// Safety: All output subject to DeepSeek usage policies.
 /// Never bypass content filters.
 static let deepseek = PluginIdentity(
 id: "bridgemind_plugins__deepseek",
 displayName: "DeepSeek",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://api.deepseek.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_DEEPSEEK_API_KEY"
 )

 /// Google Gemini — multimodal reasoning
 /// Safety: Never send prompts containing PII without redaction.
 /// Honor Google's AI Principles and usage policies.
 static let gemini = PluginIdentity(
 id: "bridgemind_plugins__gemini",
 displayName: "Gemini",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://generativelanguage.googleapis.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_GOOGLE_API_KEY"
 )

 /// xAI Grok — reasoning with real-time knowledge
 /// Safety: All output subject to xAI usage policies.
 /// Never bypass content filters.
 static let grok = PluginIdentity(
 id: "bridgemind_plugins__grok",
 displayName: "Grok",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://api.x.ai/mcp")!,
 apiKeyEnv: "BRIDGEMIND_XAI_API_KEY"
 )

 /// OpenCode — open-source AI coding assistant
 /// Safety: Never auto-apply code changes without review.
 /// Sandbox all file operations.
 static let opencode = PluginIdentity(
 id: "bridgemind_plugins__opencode",
 displayName: "OpenCode",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "https://opencode.dev/mcp")!
 )

 /// Antigravity — experimental reasoning engine
 /// Safety: No external data sent to third-party services.
 /// All computation runs locally within the sandbox.
 static let antigravity = PluginIdentity(
 id: "bridgemind_plugins__antigravity",
 displayName: "Antigravity",
 type: .builtin,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:8080/mcp")!
 )

 /// Factory.ai Droid — autonomous code agent
 /// Safety: Never execute code without explicit user approval.
 /// Never push changes without review.
 static let droid = PluginIdentity(
 id: "bridgemind_plugins__droid",
 displayName: "Droid",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://docs.factory.ai/mcp")!
 )

 // ─── SaaS / Business Plugins ─────────────────────────────────

 /// Apollo.io — sales intelligence and engagement
 /// Safety: Never auto-send emails or outreach sequences.
 /// Respect rate limits — do not bulk-enrich without user approval.
 static let apollo = PluginIdentity(
 id: "bridgemind_plugins__apollo",
 displayName: "Apollo",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.apollo.io/mcp")!,
 apiKeyEnv: "BRIDGEMIND_APOLLO_API_KEY"
 )

 /// Blender — 3D modeling and animation
 /// Safety: Never run destructive operations without user confirmation.
 /// Validate all file paths before writing.
 static let blender = PluginIdentity(
 id: "bridgemind_plugins__blender",
 displayName: "Blender",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:9876")!
 )

 /// Cloudflare — DNS, CDN, and edge computing management
 /// Safety: Never modify production DNS records without user approval.
 /// Do not delete zones or purge cache without confirmation.
 static let cloudflare = PluginIdentity(
 id: "bridgemind_plugins__cloudflare",
 displayName: "Cloudflare",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.cloudflare.com/mcp")!
 )

 /// fal.ai — AI image generation and media processing
 /// Safety: Never generate harmful, NSFW, or deceptive content.
 /// Log all generation requests for audit.
 static let fal = PluginIdentity(
 id: "bridgemind_plugins__fal",
 displayName: "fal.ai",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.fal.ai/mcp")!,
 apiKeyEnv: "BRIDGEMIND_FAL_API_KEY"
 )

 /// GitHub — code repository and workflow management
 /// Safety: Never force-push to protected branches.
 /// Never merge pull requests without user approval.
 /// Never delete repositories or releases without explicit confirmation.
 static let github = PluginIdentity(
 id: "bridgemind_plugins__github",
 displayName: "GitHub",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://api.github.com/mcp")!
 )

 /// Gmail — email reading, sending, and management
 /// Safety: Never auto-send emails without explicit user confirmation.
 /// Never read or archive emails without user authorization.
 /// Never modify labels or apply filters without approval.
 static let gmail = PluginIdentity(
 id: "bridgemind_plugins__gmail",
 displayName: "Gmail",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://gmail.googleapis.com/gmail/v1/")!,
 scopes: [
 "https://www.googleapis.com/auth/gmail.readonly",
 "https://www.googleapis.com/auth/gmail.send",
 "https://www.googleapis.com/auth/gmail.modify"
 ]
 )

 /// Google Ads — advertising campaign management
 /// Safety: Never modify campaign budgets without user approval.
 /// Never pause or resume campaigns without confirmation.
 /// Log all mutations for billing audit.
 static let googleads = PluginIdentity(
 id: "bridgemind_plugins__googleads",
 displayName: "Google Ads",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://googleads.googleapis.com/v25/")!,
 scopes: ["https://www.googleapis.com/auth/adwords"]
 )

 /// Higgsfield — AI-powered creative and design tool
 /// Safety: Never generate content that violates intellectual property rights.
 /// Never auto-publish generated designs without review.
 static let higgsfield = PluginIdentity(
 id: "bridgemind_plugins__higgsfield",
 displayName: "Higgsfield",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.higgsfield.ai/mcp")!,
 apiKeyEnv: "BRIDGEMIND_HIGGSFIELD_API_KEY"
 )

 /// Linear — issue tracking and project management
 /// Safety: Never close or resolve issues without user approval.
 /// Never delete projects, cycles, or roadmaps without confirmation.
 static let linear = PluginIdentity(
 id: "bridgemind_plugins__linear",
 displayName: "Linear",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.linear.app/mcp")!
 )

 /// Meta Ads — advertising campaign management via Meta Marketing API
 /// Safety: Never create or modify ad campaigns without explicit approval.
 /// Never spend budget without user-defined caps.
 /// Never access ad accounts not owned by the authenticated user.
 static let metaads = PluginIdentity(
 id: "bridgemind_plugins__metaads",
 displayName: "Meta Ads",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.facebook.com/ads")!
 )

 /// Notion — workspace, page, and database management
 /// Safety: Never delete pages, databases, or blocks without user confirmation.
 /// Never share pages or databases with unauthorized users.
 static let notion = PluginIdentity(
 id: "bridgemind_plugins__notion",
 displayName: "Notion",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.notion.com/mcp")!
 )

 /// QuickBooks — accounting and financial data
 /// Safety: Never create or modify financial transactions without approval.
 /// Never delete invoices or payments without explicit confirmation.
 /// All financial mutations must be logged for audit compliance.
 static let quickbooks = PluginIdentity(
 id: "bridgemind_plugins__quickbooks",
 displayName: "QuickBooks",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://quickbooks.api.intuit.com/v3/company/")!,
 scopes: ["com.intuit.quickbooks.accounting"]
 )

 /// Resend — transactional email delivery
 /// Safety: Never auto-send emails without explicit user confirmation.
 /// Never send to unverified recipient domains in production.
 /// Log all outbound email metadata for audit.
 static let resend = PluginIdentity(
 id: "bridgemind_plugins__resend",
 displayName: "Resend",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.resend.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_RESEND_API_KEY"
 )

 /// RevenueCat — in-app purchase and subscription management
 /// Safety: Never grant or revoke entitlements without business approval.
 /// Never issue refunds or cancellations without user authorization.
 static let revenuecat = PluginIdentity(
 id: "bridgemind_plugins__revenuecat",
 displayName: "RevenueCat",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.revenuecat.ai/mcp")!,
 apiKeyEnv: "BRIDGEMIND_REVENUECAT_API_KEY"
 )

 /// Sentry — error tracking and performance monitoring
 /// Safety: Never modify project settings or DSN without approval.
 /// Never delete error events or performance data without confirmation.
 static let sentry = PluginIdentity(
 id: "bridgemind_plugins__sentry",
 displayName: "Sentry",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.sentry.dev/mcp")!
 )

 /// Shopify — e-commerce store management
 /// Safety: Never process refunds or void transactions without approval.
 /// Never modify store settings or pricing without user confirmation.
 /// Never access orders outside the authenticated store's scope.
 static let shopify = PluginIdentity(
 id: "bridgemind_plugins__shopify",
 displayName: "Shopify",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.shopify.com/mcp")!
 )

 /// Slack — messaging and workspace collaboration
 /// Safety: Never send messages to channels or users without explicit confirmation.
 /// Never read private channel history without user authorization.
 /// Never modify workspace settings or integrations without approval.
 static let slack = PluginIdentity(
 id: "bridgemind_plugins__slack",
 displayName: "Slack",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://slack.com/api/")!
 )

 /// Stripe — payment processing and financial operations
 /// Safety: Never create or modify charges without explicit user approval.
 /// Never issue refunds without confirmation.
 /// Never access or modify customer data without authorization.
 /// All payment operations must be logged for compliance.
 static let stripe = PluginIdentity(
 id: "bridgemind_plugins__stripe",
 displayName: "Stripe",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.stripe.com")!,
 apiKeyEnv: "BRIDGEMIND_STRIPE_SECRET_KEY"
 )

 /// Supabase — open-source Firebase alternative with Postgres, Auth, Storage
 /// Safety: Never bypass Row Level Security (RLS) policies.
 /// Never delete production database tables or data without confirmation.
 static let supabase = PluginIdentity(
 id: "bridgemind_plugins__supabase",
 displayName: "Supabase",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.supabase.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_SUPABASE_SERVICE_ROLE_KEY"
 )

 /// Unity — game engine and real-time 3D development
 /// Safety: Never build or deploy without user confirmation.
 /// Never delete project assets without backup confirmation.
 static let unity = PluginIdentity(
 id: "bridgemind_plugins__unity",
 displayName: "Unity",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:8000")!
 )

 /// Unreal Engine — high-fidelity game and real-time experience development
 /// Safety: Never build or cook without user confirmation.
 /// Never delete project assets without backup confirmation.
 static let unreal = PluginIdentity(
 id: "bridgemind_plugins__unreal",
 displayName: "Unreal Engine",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:8000")!
 )

 /// Vercel — frontend deployment and edge functions
 /// Safety: Never deploy to production without explicit user approval.
 /// Never delete deployments or projects without confirmation.
 static let vercel = PluginIdentity(
 id: "bridgemind_plugins__vercel",
 displayName: "Vercel",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.vercel.com")!
 )

 /// vidIQ — YouTube analytics and SEO optimization
 /// Safety: Never modify video metadata without user approval.
 /// Never analyze competitor data for deceptive purposes.
 static let vidiq = PluginIdentity(
 id: "bridgemind_plugins__vidiq",
 displayName: "vidIQ",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.vidiq.com/mcp")!,
 apiKeyEnv: "BRIDGEMIND_VIDIQ_API_KEY"
 )

 /// YouTube — video management and analytics via YouTube Data API v3
 /// Safety: Never upload, edit, or delete videos without explicit user approval.
 /// Never modify channel settings without confirmation.
 /// Never access private video data without authorization.
 static let youtube = PluginIdentity(
 id: "bridgemind_plugins__youtube",
 displayName: "YouTube",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://www.googleapis.com/youtube/v3/")!,
 scopes: [
 "https://www.googleapis.com/auth/youtube",
 "https://www.googleapis.com/auth/youtube.readonly",
 "https://www.googleapis.com/auth/youtube.upload"
 ]
 )
}

// MARK: - Plugin Collections

/// Convenience groupings of the 24 plugin identities.
public enum AllPlugins: Sendable, CaseIterable, Equatable {

 // ─── Agent Engine Plugins (11) ───────────────────────────────

 case claude, codex, copilot, cursor, aider, deepseek, gemini, grok, opencode, antigravity, droid

 // ─── SaaS / Business Plugins (13) ────────────────────────────

 case apollo, blender, cloudflare, fal, github, gmail, googleads, higgsfield, linear
 case metaads, notion, quickbooks, resend, revenuecat, sentry, shopify, slack
 case stripe, supabase, unity, unreal, vercel, vidiq, youtube

 // MARK: Identity Lookup

 public var identity: PluginIdentity {
 switch self {
 case .claude: return .claude
 case .codex: return .codex
 case .copilot: return .copilot
 case .cursor: return .cursor
 case .aider: return .aider
 case .deepseek: return .deepseek
 case .gemini: return .gemini
 case .grok: return .grok
 case .opencode: return .opencode
 case .antigravity: return .antigravity
 case .droid: return .droid
 case .apollo: return .apollo
 case .blender: return .blender
 case .cloudflare: return .cloudflare
 case .fal: return .fal
 case .github: return .github
 case .gmail: return .gmail
 case .googleads: return .googleads
 case .higgsfield: return .higgsfield
 case .linear: return .linear
 case .metaads: return .metaads
 case .notion: return .notion
 case .quickbooks: return .quickbooks
 case .resend: return .resend
 case .revenuecat: return .revenuecat
 case .sentry: return .sentry
 case .shopify: return .shopify
 case .slack: return .slack
 case .stripe: return .stripe
 case .supabase: return .supabase
 case .unity: return .unity
 case .unreal: return .unreal
 case .vercel: return .vercel
 case .vidiq: return .vidiq
 case .youtube: return .youtube
 }
 }

 // MARK: Grouped Collections

 /// All 24 plugin identities.
 public static let all: [PluginIdentity] = allCases.map(\.identity)

 /// Agent engine plugins only (11).
 public static let agents: [PluginIdentity] = allCases
 .filter { [.claude, .codex, .copilot, .cursor, .aider, .deepseek, .gemini, .grok, .opencode, .antigravity, .droid].contains($0) }
 .map(\.identity)

 /// SaaS / business tool plugins only (13).
 public static let businessPlugins: [PluginIdentity] = allCases
 .filter { ![.claude, .codex, .copilot, .cursor, .aider, .deepseek, .gemini, .grok, .opencode, .antigravity, .droid].contains($0) }
 .map(\.identity)

 /// Plugins requiring OAuth authentication.
 public static let oauthPlugins: [PluginIdentity] {
 all.filter { $0.authType == .oauth }
 }

 /// Plugins using API key authentication.
 public static let apiKeyPlugins: [PluginIdentity] {
 all.filter { $0.authType == .apiKey }
 }

 /// Plugins with no authentication (built-in / local).
 public static let noAuthPlugins: [PluginIdentity] {
 all.filter { $0.authType == .none }
 }

 /// Lookup a plugin by its stable identifier.
 public static func byId(_ id: String) -> PluginIdentity? {
 allCases.first { $0.identity.id == id }?.identity
 }
}
