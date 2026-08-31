//
// BusinessPlugins.swift
// BridgeMind One — SaaS / Business tool plugin definitions
//
// SaaS plugins connect to remote service MCP servers over HTTP.
// Each requires either an API key from an environment variable or OAuth.
//
// SECURITY NOTE: API keys are read at runtime from the environment variable
// named in `apiKeyEnv`. The key value never appears in source code.
// OAuth tokens are stored in the system Keychain via CredentialStore.
//
// OAuth plugins follow the OAuth 2.0 Authorization Code + PKCE flow.
// The user is redirected to the provider's consent page in an external browser.
// BridgeMind One never sees or stores the user's raw credentials.
//

import Foundation

// MARK: - Apollo (Apollo.io)

/// Apollo.io — sales intelligence and engagement platform.
///
/// Requires Apollo API key in `BRIDGEMIND_APOLLO_API_KEY`.
///
/// Safety rules:
/// - Never auto-send emails or outreach sequences
/// - Respect rate limits — do not bulk-enrich without user approval
public struct ApolloPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "apollo",
 displayName: "Apollo",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.apollo.io")!),
 apiKeyEnv: "BRIDGEMIND_APOLLO_API_KEY",
 description: "Apollo.io — sales intelligence and engagement",
 safetyRules: [
 "Never auto-send emails or outreach sequences.",
 "Respect rate limits — do not bulk-enrich without user approval."
 ],
 warnings: [
 "Requires Apollo API key with appropriate plan tier.",
 "Enrichment calls count against monthly API quota."
 ]
 )

 private init() {}
}

// MARK: - Blender (Blender)

/// Blender — 3D modeling and animation tool.
///
/// Blender runs as a local stdio process via the Blender MCP addon.
/// No API key required.
///
/// Safety rules:
/// - Never run destructive operations (delete, overwrite) without user confirmation
/// - Validate all file paths before writing
public struct BlenderPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "blender",
 displayName: "Blender",
 type: .saas,
 authType: .none,
 transport: .stdio(command: "blender", arguments: ["--background", "--python", "mcp_server.py"]),
 description: "Blender — 3D modeling and animation",
 safetyRules: [
 "Never run destructive operations without user confirmation.",
 "Validate all file paths before writing."
 ],
 warnings: [
 "Requires Blender 3.6+ with MCP addon installed.",
 "Runs as a local stdio process."
 ]
 )

 private init() {}
}

// MARK: - Cloudflare

/// Cloudflare — DNS, CDN, and edge computing management.
///
/// Requires Cloudflare API token in `BRIDGEMIND_CLOUDFLARE_API_TOKEN`.
///
/// Safety rules:
/// - Never modify production DNS records without user approval
/// - Do not delete zones or purge cache without confirmation
public struct CloudflarePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "cloudflare",
 displayName: "Cloudflare",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.cloudflare.com")!),
 apiKeyEnv: "BRIDGEMIND_CLOUDFLARE_API_TOKEN",
 description: "Cloudflare — DNS, CDN, and edge management",
 safetyRules: [
 "Never modify production DNS records without user approval.",
 "Do not delete zones or purge cache without confirmation."
 ],
 warnings: [
 "Requires Cloudflare API token with Zone:Read + Zone:Edit permissions.",
 "Changes propagate globally — DNS modifications are irreversible during TTL."
 ]
 )

 private init() {}
}

// MARK: - fal (fal.ai)

/// fal.ai — AI image generation and media processing.
///
/// Requires fal.ai API key in `BRIDGEMIND_FAL_API_KEY`.
///
/// Safety rules:
/// - Never generate harmful, NSFW, or deceptive content
/// - Log all generation requests for audit
public struct FalPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "fal",
 displayName: "fal.ai",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.fal.ai")!),
 apiKeyEnv: "BRIDGEMIND_FAL_API_KEY",
 description: "fal.ai — AI image generation and media processing",
 safetyRules: [
 "Never generate harmful, NSFW, or deceptive content.",
 "Log all generation requests for audit."
 ],
 warnings: [
 "Requires fal.ai API key.",
 "Image generation is billed per request — monitor usage."
 ]
 )

 private init() {}
}

// MARK: - GitHub

/// GitHub — code repository and workflow management via GitHub REST / GraphQL API.
///
/// Requires GitHub personal access token in `BRIDGEMIND_GITHUB_TOKEN`.
/// Use OAuth scopes: `repo`, `read:org`, `workflow`.
///
/// Safety rules:
/// - Never force-push to protected branches
/// - Never merge pull requests without user approval
/// - Never delete repositories or releases without explicit confirmation
public struct GitHubPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "github",
 displayName: "GitHub",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.github.com")!),
 apiKeyEnv: "BRIDGEMIND_GITHUB_TOKEN",
 scopes: ["repo", "read:org", "workflow"],
 description: "GitHub — code repository and workflow management",
 safetyRules: [
 "Never force-push to protected branches.",
 "Never merge pull requests without user approval.",
 "Never delete repositories or releases without explicit confirmation."
 ],
 warnings: [
 "Requires GitHub PAT with repo and workflow scopes.",
 "Rate limits: 5,000 requests/hour for authenticated calls."
 ]
 )

 private init() {}
}

// MARK: - Gmail

/// Gmail — email reading, sending, and management via Gmail API.
///
/// Uses OAuth 2.0 with scopes: `gmail.readonly`, `gmail.send`, `gmail.modify`.
///
/// Safety rules:
/// - Never auto-send emails without explicit user confirmation
/// - Never read or archive emails without user authorization
/// - Never modify labels or apply filters without approval
public struct GmailPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "gmail",
 displayName: "Gmail",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["gmail.readonly", "gmail.send", "gmail.modify"],
 description: "Gmail — email reading, sending, and management",
 safetyRules: [
 "Never auto-send emails without explicit user confirmation.",
 "Never read or archive emails without user authorization.",
 "Never modify labels or apply filters without approval."
 ],
 warnings: [
 "Requires Google Cloud project with Gmail API enabled.",
 "OAuth consent screen must be configured and verified."
 ]
 )

 private init() {}
}

// MARK: - Google Ads

/// Google Ads — advertising campaign management via Google Ads API.
///
/// Requires Google Ads API developer token + OAuth 2.0.
/// OAuth scopes: `https://www.googleapis.com/auth/adwords`.
///
/// Safety rules:
/// - Never modify campaign budgets without user approval
/// - Never pause or resume campaigns without confirmation
/// - Log all mutations for billing audit
public struct GoogleAdsPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "googleads",
 displayName: "Google Ads",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["https://www.googleapis.com/auth/adwords"],
 description: "Google Ads — advertising campaign management",
 safetyRules: [
 "Never modify campaign budgets without user approval.",
 "Never pause or resume campaigns without confirmation.",
 "Log all mutations for billing audit."
 ],
 warnings: [
 "Requires Google Ads API developer token (standard or test access).",
 "OAuth must be performed with an MCC-linked account."
 ]
 )

 private init() {}
}

// MARK: - Higgsfield

/// Higgsfield — AI-powered creative and design tool.
///
/// Requires Higgsfield API key in `BRIDGEMIND_HIGGSFIELD_API_KEY`.
///
/// Safety rules:
/// - Never generate content that violates intellectual property rights
/// - Never auto-publish generated designs without review
public struct HiggsfieldPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "higgsfield",
 displayName: "Higgsfield",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.higgsfield.ai")!),
 apiKeyEnv: "BRIDGEMIND_HIGGSFIELD_API_KEY",
 description: "Higgsfield — AI-powered creative and design tool",
 safetyRules: [
 "Never generate content that violates intellectual property rights.",
 "Never auto-publish generated designs without review."
 ],
 warnings: [
 "Requires Higgsfield API key.",
 "Generation may be rate-limited based on plan tier."
 ]
 )

 private init() {}
}

// MARK: - Linear

/// Linear — issue tracking and project management.
///
/// Uses OAuth 2.0 with scopes: `read`, `write`.
///
/// Safety rules:
/// - Never close or resolve issues without user approval
/// - Never delete projects, cycles, or roadmaps without confirmation
public struct LinearPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "linear",
 displayName: "Linear",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["read", "write"],
 description: "Linear — issue tracking and project management",
 safetyRules: [
 "Never close or resolve issues without user approval.",
 "Never delete projects, cycles, or roadmaps without confirmation."
 ],
 warnings: [
 "Requires Linear OAuth app configured in Linear Settings > API.",
 "Write scope allows mutations — use with caution."
 ]
 )

 private init() {}
}

// MARK: - Meta Ads (Facebook)

/// Meta Ads — advertising campaign management via Meta Marketing API.
///
/// Uses OAuth 2.0 with scopes: `ads_management`, `ads_read`, `business_management`.
///
/// Safety rules:
/// - Never create or modify ad campaigns without explicit approval
/// - Never spend budget without user-defined caps
/// - Never access ad accounts not owned by the authenticated user
public struct MetaAdsPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "metaads",
 displayName: "Meta Ads",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["ads_management", "ads_read", "business_management"],
 description: "Meta Ads — advertising campaign management",
 safetyRules: [
 "Never create or modify ad campaigns without explicit approval.",
 "Never spend budget without user-defined caps.",
 "Never access ad accounts not owned by the authenticated user."
 ],
 warnings: [
 "Requires Meta Business Manager account with Ads API access.",
 "Ad spend changes are irreversible — implement hard spend caps."
 ]
 )

 private init() {}
}

// MARK: - Notion

/// Notion — workspace, page, and database management via Notion API.
///
/// Uses OAuth 2.0 with scopes depending on integration configuration.
///
/// Safety rules:
/// - Never delete pages, databases, or blocks without user confirmation
/// - Never share pages or databases with unauthorized users
public struct NotionPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "notion",
 displayName: "Notion",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 description: "Notion — workspace, page, and database management",
 safetyRules: [
 "Never delete pages, databases, or blocks without user confirmation.",
 "Never share pages or databases with unauthorized users."
 ],
 warnings: [
 "Requires Notion integration with appropriate workspace access.",
 "OAuth token grants full workspace access based on integration permissions."
 ]
 )

 private init() {}
}

// MARK: - QuickBooks

/// QuickBooks — accounting and financial data via Intuit QuickBooks API.
///
/// Uses OAuth 2.0 with scopes: `com.intuit.quickbooks.accounting`.
///
/// Safety rules:
/// - Never create or modify financial transactions without approval
/// - Never delete invoices or payments without explicit confirmation
/// - All financial mutations must be logged for audit compliance
public struct QuickBooksPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "quickbooks",
 displayName: "QuickBooks",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["com.intuit.quickbooks.accounting"],
 description: "QuickBooks — accounting and financial data",
 safetyRules: [
 "Never create or modify financial transactions without approval.",
 "Never delete invoices or payments without explicit confirmation.",
 "All financial mutations must be logged for audit compliance."
 ],
 warnings: [
 "Requires QuickBooks Online developer account.",
 "Financial data access is governed by OAuth scopes and Intuit's terms."
 ]
 )

 private init() {}
}

// MARK: - Resend

/// Resend — transactional email delivery service.
///
/// Requires Resend API key in `BRIDGEMIND_RESEND_API_KEY`.
///
/// Safety rules:
/// - Never auto-send emails without explicit user confirmation
/// - Never send to unverified recipient domains in production
/// - Log all outbound email metadata for audit
public struct ResendPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "resend",
 displayName: "Resend",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.resend.com")!),
 apiKeyEnv: "BRIDGEMIND_RESEND_API_KEY",
 description: "Resend — transactional email delivery",
 safetyRules: [
 "Never auto-send emails without explicit user confirmation.",
 "Never send to unverified recipient domains in production.",
 "Log all outbound email metadata for audit."
 ],
 warnings: [
 "Requires Resend API key.",
 "Sending to unverified addresses in production may be blocked."
 ]
 )

 private init() {}
}

// MARK: - RevenueCat

/// RevenueCat — in-app purchase and subscription management.
///
/// Requires RevenueCat API key in `BRIDGEMIND_REVENUECAT_API_KEY`.
///
/// Safety rules:
/// - Never grant or revoke entitlements without business approval
/// - Never issue refunds or cancellations without user authorization
public struct RevenueCatPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "revenuecat",
 displayName: "RevenueCat",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.revenuecat.com")!),
 apiKeyEnv: "BRIDGEMIND_REVENUECAT_API_KEY",
 description: "RevenueCat — in-app purchase and subscription management",
 safetyRules: [
 "Never grant or revoke entitlements without business approval.",
 "Never issue refunds or cancellations without user authorization."
 ],
 warnings: [
 "Requires RevenueCat API key with appropriate app access.",
 "Entitlement changes affect live users — test in sandbox first."
 ]
 )

 private init() {}
}

// MARK: - Sentry

/// Sentry — error tracking and performance monitoring.
///
/// Requires Sentry auth token in `BRIDGEMIND_SENTRY_AUTH_TOKEN`.
///
/// Safety rules:
/// - Never modify project settings or DSN without approval
/// - Never delete error events or performance data without confirmation
public struct SentryPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "sentry",
 displayName: "Sentry",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://sentry.io")!),
 apiKeyEnv: "BRIDGEMIND_SENTRY_AUTH_TOKEN",
 description: "Sentry — error tracking and performance monitoring",
 safetyRules: [
 "Never modify project settings or DSN without approval.",
 "Never delete error events or performance data without confirmation."
 ],
 warnings: [
 "Requires Sentry auth token with project:read scope.",
 "Sensitive PII may appear in error events — review before sharing."
 ]
 )

 private init() {}
}

// MARK: - Shopify

/// Shopify — e-commerce store management via Shopify Admin API.
///
/// Uses OAuth 2.0 with scopes: `read_products`, `write_products`, `read_orders`, `write_orders`.
///
/// Safety rules:
/// - Never process refunds or void transactions without approval
/// - Never modify store settings or pricing without user confirmation
/// - Never access orders outside the authenticated store's scope
public struct ShopifyPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "shopify",
 displayName: "Shopify",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["read_products", "write_products", "read_orders", "write_orders"],
 description: "Shopify — e-commerce store management",
 safetyRules: [
 "Never process refunds or void transactions without approval.",
 "Never modify store settings or pricing without user confirmation.",
 "Never access orders outside the authenticated store's scope."
 ],
 warnings: [
 "Requires Shopify Partner account and OAuth app configuration.",
 "Write scopes grant full product and order modification rights."
 ]
 )

 private init() {}
}

// MARK: - Slack

/// Slack — messaging and workspace collaboration via Slack Web API.
///
/// Uses OAuth 2.0 with scopes: `chat:write`, `channels:read`, `users:read`, `files:read`.
///
/// Safety rules:
/// - Never send messages to channels or users without explicit confirmation
/// - Never read private channel history without user authorization
/// - Never modify workspace settings or integrations without approval
public struct SlackPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "slack",
 displayName: "Slack",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["chat:write", "channels:read", "users:read", "files:read"],
 description: "Slack — messaging and workspace collaboration",
 safetyRules: [
 "Never send messages to channels or users without explicit confirmation.",
 "Never read private channel history without user authorization.",
 "Never modify workspace settings or integrations without approval."
 ],
 warnings: [
 "Requires Slack app with OAuth bot token and appropriate scopes.",
 "Message sending is rate-limited per Slack API policy."
 ]
 )

 private init() {}
}

// MARK: - Stripe

/// Stripe — payment processing and financial operations via Stripe API.
///
/// Requires Stripe secret key in `BRIDGEMIND_STRIPE_SECRET_KEY`.
///
/// Safety rules:
/// - Never create or modify charges without explicit user approval
/// - Never issue refunds without confirmation
/// - Never access or modify customer data without authorization
/// - All payment operations must be logged for compliance
public struct StripePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "stripe",
 displayName: "Stripe",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.stripe.com")!),
 apiKeyEnv: "BRIDGEMIND_STRIPE_SECRET_KEY",
 description: "Stripe — payment processing and financial operations",
 safetyRules: [
 "Never create or modify charges without explicit user approval.",
 "Never issue refunds without confirmation.",
 "Never access or modify customer data without authorization.",
 "All payment operations must be logged for compliance."
 ],
 warnings: [
 "Requires Stripe secret key (not publishable key).",
 "Live mode charges real money — test in sandbox mode first.",
 "PCI DSS compliance is Stripe's responsibility, but log retention is yours."
 ]
 )

 private init() {}
}

// MARK: - Supabase

/// Supabase — open-source Firebase alternative with Postgres, Auth, and Storage.
///
/// Requires Supabase service role key in `BRIDGEMIND_SUPABASE_SERVICE_ROLE_KEY`.
///
/// Safety rules:
/// - Never bypass Row Level Security (RLS) policies
/// - Never delete production database tables or data without confirmation
public struct SupabasePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "supabase",
 displayName: "Supabase",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.supabase.com")!),
 apiKeyEnv: "BRIDGEMIND_SUPABASE_SERVICE_ROLE_KEY",
 description: "Supabase — Postgres database, Auth, and Storage",
 safetyRules: [
 "Never bypass Row Level Security (RLS) policies.",
 "Never delete production database tables or data without confirmation."
 ],
 warnings: [
 "Requires Supabase project with service role key.",
 "Service role key has full database access — treat as highly sensitive."
 ]
 )

 private init() {}
}

// MARK: - Unity

/// Unity — game engine and real-time 3D development platform.
///
/// Unity MCP runs as a local stdio process via the Unity MCP package.
/// No API key required.
///
/// Safety rules:
/// - Never build or deploy without user confirmation
/// - Never delete project assets without backup confirmation
public struct UnityPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "unity",
 displayName: "Unity",
 type: .saas,
 authType: .none,
 transport: .stdio(command: "unity", arguments: ["-batchmode", "-quit", "-executeMethod", "MCPServer.Start"]),
 description: "Unity — game engine and real-time 3D development",
 safetyRules: [
 "Never build or deploy without user confirmation.",
 "Never delete project assets without backup confirmation."
 ],
 warnings: [
 "Requires Unity Editor with MCP package installed.",
 "Runs as a local stdio process."
 ]
 )

 private init() {}
}

// MARK: - Unreal

/// Unreal Engine — high-fidelity game and real-time experience development.
///
/// Unreal MCP runs as a local stdio process via the Unreal MCP plugin.
/// No API key required.
///
/// Safety rules:
/// - Never build or cook without user confirmation
/// - Never delete project assets without backup confirmation
public struct UnrealPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "unreal",
 displayName: "Unreal Engine",
 type: .saas,
 authType: .none,
 transport: .stdio(command: "UnrealEditor", arguments: ["-stdin", "-stdout", "-mcp"]),
 description: "Unreal Engine — high-fidelity game development",
 safetyRules: [
 "Never build or cook without user confirmation.",
 "Never delete project assets without backup confirmation."
 ],
 warnings: [
 "Requires Unreal Engine 5.x with MCP plugin enabled.",
 "Runs as a local stdio process."
 ]
 )

 private init() {}
}

// MARK: - Vercel

/// Vercel — frontend deployment and edge functions platform.
///
/// Requires Vercel API token in `BRIDGEMIND_VERCEL_API_TOKEN`.
///
/// Safety rules:
/// - Never deploy to production without explicit user approval
/// - Never delete deployments or projects without confirmation
public struct VercelPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "vercel",
 displayName: "Vercel",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.vercel.com")!),
 apiKeyEnv: "BRIDGEMIND_VERCEL_API_TOKEN",
 description: "Vercel — frontend deployment and edge functions",
 safetyRules: [
 "Never deploy to production without explicit user approval.",
 "Never delete deployments or projects without confirmation."
 ],
 warnings: [
 "Requires Vercel API token with deployment scope.",
 "Production deployments are publicly accessible."
 ]
 )

 private init() {}
}

// MARK: - vidIQ

/// vidIQ — YouTube analytics and SEO optimization tool.
///
/// Requires vidIQ API key in `BRIDGEMIND_VIDIQ_API_KEY`.
///
/// Safety rules:
/// - Never modify video metadata without user approval
/// - Never analyze competitor data for deceptive purposes
public struct VidIQPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "vidiq",
 displayName: "vidIQ",
 type: .saas,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.vidiq.com")!),
 apiKeyEnv: "BRIDGEMIND_VIDIQ_API_KEY",
 description: "vidIQ — YouTube analytics and SEO optimization",
 safetyRules: [
 "Never modify video metadata without user approval.",
 "Never analyze competitor data for deceptive purposes."
 ],
 warnings: [
 "Requires vidIQ API key.",
 "YouTube API rate limits apply per Google's quota system."
 ]
 )

 private init() {}
}

// MARK: - YouTube

/// YouTube — video management and analytics via YouTube Data API v3.
///
/// Uses OAuth 2.0 with scopes: `youtube.readonly`, `youtube.upload`, `youtube.force-ssl`.
///
/// Safety rules:
/// - Never upload, edit, or delete videos without explicit user approval
/// - Never modify channel settings without confirmation
/// - Never access private video data without authorization
public struct YouTubePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "youtube",
 displayName: "YouTube",
 type: .saas,
 authType: .oauth,
 transport: .oauth,
 scopes: ["youtube.readonly", "youtube.upload", "youtube.force-ssl"],
 description: "YouTube — video management and analytics",
 safetyRules: [
 "Never upload, edit, or delete videos without explicit user approval.",
 "Never modify channel settings without confirmation.",
 "Never access private video data without authorization."
 ],
 warnings: [
 "Requires Google Cloud project with YouTube Data API v3 enabled.",
 "Upload scope grants full channel management rights."
 ]
 )

 private init() {}
}
