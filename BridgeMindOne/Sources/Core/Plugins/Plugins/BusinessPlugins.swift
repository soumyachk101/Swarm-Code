//
// BusinessPlugins.swift
// BridgeMind One — SaaS / Business tool plugin definitions
//
// SaaS plugins connect to remote service MCP servers over HTTP.
// Each requires either an API key from an environment variable or OAuth.
//
// SECURITY NOTE: API keys are read at runtime from the environment variable
// named in apiKeyEnv. The key value never appears in source code.
// OAuth tokens are stored in the system Keychain via CredentialStore.
//
// OAuth plugins follow the OAuth 2.0 Authorization Code + PKCE flow.
// The user is redirected to the provider's consent page in an external browser.
// BridgeMind One never sees or stores the user's raw credentials.
//
// Plugin identities are defined as static constants on PluginIdentity
// in PluginDefinitions.swift. Safety rules are in the pluginSafetyRules
// dictionary in the same file.
//

import Foundation

// MARK: - Business Plugin Metadata

/// Descriptive metadata for each SaaS / business tool plugin.
public struct BusinessPlugin: Sendable, Equatable, Identifiable {

 public let id: String
 public let identity: PluginIdentity
 public let description: String
 public let safetyRules: [String]
 public let warnings: [String]

 public init(
 id: String,
 identity: PluginIdentity,
 description: String,
 safetyRules: [String] = [],
 warnings: [String] = []
 ) {
 self.id = id
 self.identity = identity
 self.description = description
 self.safetyRules = safetyRules
 self.warnings = warnings
 }
}

// MARK: - All Business Plugins

public enum BusinessPlugins: Sendable, CaseIterable, Equatable {

 // MARK: Apollo (Apollo.io)

 /// Apollo.io — sales intelligence and engagement platform.
 /// Identity: PluginIdentity.apollo
 /// Safety: Never auto-send emails or outreach sequences.
 /// Respect rate limits — do not bulk-enrich without user approval.
 case apollo

 // MARK: Blender

 /// Blender — 3D modeling and animation tool.
 /// Identity: PluginIdentity.blender
 /// Safety: Never run destructive operations without user confirmation.
 /// Validate all file paths before writing.
 case blender

 // MARK: Cloudflare

 /// Cloudflare — DNS, CDN, and edge computing management.
 /// Identity: PluginIdentity.cloudflare
 /// Safety: Never modify production DNS records without user approval.
 /// Do not delete zones or purge cache without confirmation.
 case cloudflare

 // MARK: fal (fal.ai)

 /// fal.ai — AI image generation and media processing.
 /// Identity: PluginIdentity.fal
 /// Safety: Never generate harmful, NSFW, or deceptive content.
 /// Log all generation requests for audit.
 case fal

 // MARK: GitHub

 /// GitHub — code repository and workflow management.
 /// Identity: PluginIdentity.github
 /// Safety: Never force-push to protected branches.
 /// Never merge pull requests without user approval.
 /// Never delete repositories or releases without explicit confirmation.
 case github

 // MARK: Gmail

 /// Gmail — email reading, sending, and management.
 /// Identity: PluginIdentity.gmail
 /// Safety: Never auto-send emails without explicit user confirmation.
 /// Never read or archive emails without user authorization.
 /// Never modify labels or apply filters without approval.
 case gmail

 // MARK: Google Ads

 /// Google Ads — advertising campaign management.
 /// Identity: PluginIdentity.googleads
 /// Safety: Never modify campaign budgets without user approval.
 /// Never pause or resume campaigns without confirmation.
 /// Log all mutations for billing audit.
 case googleads

 // MARK: Higgsfield

 /// Higgsfield — AI-powered creative and design tool.
 /// Identity: PluginIdentity.higgsfield
 /// Safety: Never generate content that violates intellectual property rights.
 /// Never auto-publish generated designs without review.
 case higgsfield

 // MARK: Linear

 /// Linear — issue tracking and project management.
 /// Identity: PluginIdentity.linear
 /// Safety: Never close or resolve issues without user approval.
 /// Never delete projects, cycles, or roadmaps without confirmation.
 case linear

 // MARK: Meta Ads (Facebook)

 /// Meta Ads — advertising campaign management via Meta Marketing API.
 /// Identity: PluginIdentity.metaads
 /// Safety: Never create or modify ad campaigns without explicit approval.
 /// Never spend budget without user-defined caps.
 /// Never access ad accounts not owned by the authenticated user.
 case metaads

 // MARK: Notion

 /// Notion — workspace, page, and database management.
 /// Identity: PluginIdentity.notion
 /// Safety: Never delete pages, databases, or blocks without user confirmation.
 /// Never share pages or databases with unauthorized users.
 case notion

 // MARK: QuickBooks

 /// QuickBooks — accounting and financial data.
 /// Identity: PluginIdentity.quickbooks
 /// Safety: Never create or modify financial transactions without approval.
 /// Never delete invoices or payments without explicit confirmation.
 /// All financial mutations must be logged for audit compliance.
 case quickbooks

 // MARK: Resend

 /// Resend — transactional email delivery.
 /// Identity: PluginIdentity.resend
 /// Safety: Never auto-send emails without explicit user confirmation.
 /// Never send to unverified recipient domains in production.
 /// Log all outbound email metadata for audit.
 case resend

 // MARK: RevenueCat

 /// RevenueCat — in-app purchase and subscription management.
 /// Identity: PluginIdentity.revenuecat
 /// Safety: Never grant or revoke entitlements without business approval.
 /// Never issue refunds or cancellations without user authorization.
 case revenuecat

 // MARK: Sentry

 /// Sentry — error tracking and performance monitoring.
 /// Identity: PluginIdentity.sentry
 /// Safety: Never modify project settings or DSN without approval.
 /// Never delete error events or performance data without confirmation.
 case sentry

 // MARK: Shopify

 /// Shopify — e-commerce store management.
 /// Identity: PluginIdentity.shopify
 /// Safety: Never process refunds or void transactions without approval.
 /// Never modify store settings or pricing without user confirmation.
 /// Never access orders outside the authenticated store's scope.
 case shopify

 // MARK: Slack

 /// Slack — messaging and workspace collaboration.
 /// Identity: PluginIdentity.slack
 /// Safety: Never send messages to channels or users without explicit confirmation.
 /// Never read private channel history without user authorization.
 /// Never modify workspace settings or integrations without approval.
 case slack

 // MARK: Stripe

 /// Stripe — payment processing and financial operations.
 /// Identity: PluginIdentity.stripe
 /// Safety: Never create or modify charges without explicit user approval.
 /// Never issue refunds without confirmation.
 /// Never access or modify customer data without authorization.
 /// All payment operations must be logged for compliance.
 case stripe

 // MARK: Supabase

 /// Supabase — open-source Firebase alternative with Postgres, Auth, Storage.
 /// Identity: PluginIdentity.supabase
 /// Safety: Never bypass Row Level Security (RLS) policies.
 /// Never delete production database tables or data without confirmation.
 case supabase

 // MARK: Unity

 /// Unity — game engine and real-time 3D development.
 /// Identity: PluginIdentity.unity
 /// Safety: Never build or deploy without user confirmation.
 /// Never delete project assets without backup confirmation.
 case unity

 // MARK: Unreal Engine

 /// Unreal Engine — high-fidelity game and real-time experience development.
 /// Identity: PluginIdentity.unreal
 /// Safety: Never build or cook without user confirmation.
 /// Never delete project assets without backup confirmation.
 case unreal

 // MARK: Vercel

 /// Vercel — frontend deployment and edge functions.
 /// Identity: PluginIdentity.vercel
 /// Safety: Never deploy to production without explicit user approval.
 /// Never delete deployments or projects without confirmation.
 case vercel

 // MARK: vidIQ

 /// vidIQ — YouTube analytics and SEO optimization.
 /// Identity: PluginIdentity.vidiq
 /// Safety: Never modify video metadata without user approval.
 /// Never analyze competitor data for deceptive purposes.
 case vidiq

 // MARK: YouTube

 /// YouTube — video management and analytics via YouTube Data API v3.
 /// Identity: PluginIdentity.youtube
 /// Safety: Never upload, edit, or delete videos without explicit user approval.
 /// Never modify channel settings without confirmation.
 /// Never access private video data without authorization.
 case youtube

 // MARK: Metadata Access

 public var identity: PluginIdentity {
 switch self {
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

 public var plugin: BusinessPlugin {
 BusinessPlugin(
 id: identity.id,
 identity: identity,
 description: identity.displayName,
 safetyRules: pluginSafetyRules[identity.id] ?? [],
 warnings: []
 )
 }

 public static let all: [PluginIdentity] = allCases.map(\.identity)
 public static let allPlugins: [BusinessPlugin] = allCases.map(\.plugin)
}
