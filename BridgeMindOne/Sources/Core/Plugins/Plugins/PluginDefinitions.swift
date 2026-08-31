//
// PluginDefinitions.swift
// All 24 MCP plugin definitions with authentic metadata from the binary
//

import Foundation

// MARK: - Plugin Provider Protocol

public protocol MCPPluginProvider: Sendable {
 var identity: PluginIdentity { get }
 var safetyRules: [String] { get }
 var description: String { get }
}

// MARK: - All 24 Plugin Definitions

public extension PluginIdentity {
 // MARK: - Agent Engines
 static let claude = PluginIdentity(
 id: "bridgemind_plugins__claude",
 displayName: "Claude",
 type: .builtin,
 authType: .none
 )

 static let codex = PluginIdentity(
 id: "bridgemind_plugins__codex",
 displayName: "Codex",
 type: .builtin,
 authType: .none
 )

 static let copilot = PluginIdentity(
 id: "bridgemind_plugins__copilot",
 displayName: "GitHub Copilot",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://api.githubcopilot.com/mcp/")!
 )

 static let cursor = PluginIdentity(
 id: "bridgemind_plugins__cursor",
 displayName: "Cursor",
 type: .builtin,
 authType: .none
 )

 static let aider = PluginIdentity(
 id: "bridgemind_plugins__aider",
 displayName: "Aider",
 type: .builtin,
 authType: .none
 )

 static let deepseek = PluginIdentity(
 id: "bridgemind_plugins__deepseek",
 displayName: "DeepSeek",
 type: .builtin,
 authType: .none
 )

 static let gemini = PluginIdentity(
 id: "bridgemind_plugins__gemini",
 displayName: "Gemini",
 type: .builtin,
 authType: .none
 )

 static let grok = PluginIdentity(
 id: "bridgemind_plugins__grok",
 displayName: "Grok",
 type: .builtin,
 authType: .none
 )

 static let opencode = PluginIdentity(
 id: "bridgemind_plugins__opencode",
 displayName: "OpenCode",
 type: .builtin,
 authType: .none
 )

 static let antigravity = PluginIdentity(
 id: "bridgemind_plugins__antigravity",
 displayName: "Antigravity",
 type: .builtin,
 authType: .none
 )

 static let droid = PluginIdentity(
 id: "bridgemind_plugins__droid",
 displayName: "Droid",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://docs.factory.ai")!
 )

 // MARK: - SaaS / Business Plugins
 static let apollo = PluginIdentity(
 id: "bridgemind_plugins__apollo",
 displayName: "Apollo",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.apollo.io/mcp")!
 )

 static let blender = PluginIdentity(
 id: "bridgemind_plugins__blender",
 displayName: "Blender",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:9876")!
 )

 static let cloudflare = PluginIdentity(
 id: "bridgemind_plugins__cloudflare",
 displayName: "Cloudflare",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.cloudflare.com/mcp")!
 )

 static let fal = PluginIdentity(
 id: "bridgemind_plugins__fal",
 displayName: "fal.ai",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.fal.ai/mcp")!
 )

 static let github = PluginIdentity(
 id: "bridgemind_plugins__github",
 displayName: "GitHub",
 type: .remote,
 authType: .oauth
 )

 static let gmail = PluginIdentity(
 id: "bridgemind_plugins__gmail",
 displayName: "Gmail",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://gmail.googleapis.com/gmail/v1/")!,
 scopes: ["https://www.googleapis.com/auth/gmail.readonly",
 "https://www.googleapis.com/auth/gmail.send"]
 )

 static let googleAds = PluginIdentity(
 id: "bridgemind_plugins__googleads",
 displayName: "Google Ads",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://googleads.googleapis.com/v25/")!,
 scopes: ["https://www.googleapis.com/auth/adwords"]
 )

 static let higgsfield = PluginIdentity(
 id: "bridgemind_plugins__higgsfield",
 displayName: "Higgsfield",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.higgsfield.ai/mcp")!
 )

 static let linear = PluginIdentity(
 id: "bridgemind_plugins__linear",
 displayName: "Linear",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.linear.app/mcp")!
 )

 static let metaAds = PluginIdentity(
 id: "bridgemind_plugins__metaads",
 displayName: "Meta Ads",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.facebook.com/ads")!
 )

 static let notion = PluginIdentity(
 id: "bridgemind_plugins__notion",
 displayName: "Notion",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.notion.com/mcp")!
 )

 static let quickbooks = PluginIdentity(
 id: "bridgemind_plugins__quickbooks",
 displayName: "QuickBooks",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://quickbooks.api.intuit.com/v3/company/")!,
 scopes: ["com.intuit.quickbooks.accounting"]
 )

 static let resend = PluginIdentity(
 id: "bridgemind_plugins__resend",
 displayName: "Resend",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.resend.com/mcp")!,
 apiKeyEnv: "RESEND_API_KEY"
 )

 static let revenueCat = PluginIdentity(
 id: "bridgemind_plugins__revenuecat",
 displayName: "RevenueCat",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.revenuecat.ai/mcp")!
 )

 static let sentry = PluginIdentity(
 id: "bridgemind_plugins__sentry",
 displayName: "Sentry",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.sentry.dev/mcp")!
 )

 static let shopify = PluginIdentity(
 id: "bridgemind_plugins__shopify",
 displayName: "Shopify",
 type: .remote,
 authType: .oauth
 )

 static let slack = PluginIdentity(
 id: "bridgemind_plugins__slack",
 displayName: "Slack",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://slack.com/api/")!
 )

 static let stripe = PluginIdentity(
 id: "bridgemind_plugins__stripe",
 displayName: "Stripe",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.stripe.com")!,
 apiKeyEnv: "STRIPE_API_KEY"
 )

 static let supabase = PluginIdentity(
 id: "bridgemind_plugins__supabase",
 displayName: "Supabase",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.supabase.com/mcp")!
 )

 static let unity = PluginIdentity(
 id: "bridgemind_plugins__unity",
 displayName: "Unity",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:8000")!
 )

 static let unreal = PluginIdentity(
 id: "bridgemind_plugins__unreal",
 displayName: "Unreal",
 type: .local,
 authType: .none,
 mcpURL: URL(string: "http://127.0.0.1:8000")!
 )

 static let vercel = PluginIdentity(
 id: "bridgemind_plugins__vercel",
 displayName: "Vercel",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://mcp.vercel.com")!
 )

 static let vidiq = PluginIdentity(
 id: "bridgemind_plugins__vidiq",
 displayName: "vidIQ",
 type: .remote,
 authType: .apiKey,
 mcpURL: URL(string: "https://mcp.vidiq.com/mcp")!
 )

 static let youtube = PluginIdentity(
 id: "bridgemind_plugins__youtube",
 displayName: "YouTube",
 type: .remote,
 authType: .oauth,
 mcpURL: URL(string: "https://www.googleapis.com/youtube/v3/")!,
 scopes: ["https://www.googleapis.com/auth/youtube",
 "https://www.googleapis.com/auth/youtube.readonly",
 "https://www.googleapis.com/auth/youtube.upload"]
 )
}

// MARK: - Plugin Collections

public enum AllPlugins {
 public static let allIdentities: [PluginIdentity] = [
 .claude, .codex, .copilot, .cursor, .aider, .deepseek, .gemini, .grok, .opencode, .antigravity, .droid,
 .apollo, .blender, .cloudflare, .fal, .github, .gmail, .googleAds, .higgsfield, .linear,
 .metaAds, .notion, .quickbooks, .resend, .revenueCat, .sentry, .shopify, .slack,
 .stripe, .supabase, .unity, .unreal, .vercel, .vidiq, .youtube
 ]

 public static let agentEngines: [PluginIdentity] = [
 .claude, .codex, .copilot, .cursor, .aider, .deepseek, .gemini, .grok, .opencode, .antigravity, .droid
 ]

 public static let businessPlugins: [PluginIdentity] = [
 .apollo, .blender, .cloudflare, .fal, .github, .gmail, .googleAds, .higgsfield, .linear,
 .metaAds, .notion, .quickbooks, .resend, .revenueCat, .sentry, .shopify, .slack,
 .stripe, .supabase, .unity, .unreal, .vercel, .vidiq, .youtube
 ]

 public static let oauthPlugins: [PluginIdentity] = {
 allIdentities.filter { $0.authType == .oauth }
 }()

 public static let apiKeyPlugins: [PluginIdentity] = {
 allIdentities.filter { $0.authType == .apiKey }
 }()

 public static let localPlugins: [PluginIdentity] = {
 allIdentities.filter { $0.type == .local }
 }()
}
