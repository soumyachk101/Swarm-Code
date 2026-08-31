//
// AgentPlugins.swift
// BridgeMind One — Agent engine plugin definitions
//
// Agent engine plugins connect to remote LLM provider MCP servers.
// Each requires an API key set as an environment variable (never hard-coded).
//
// SECURITY NOTE: API keys are read at runtime from the environment variable
// named in apiKeyEnv. The key value never appears in source code.
// The user sets these via:
// export BRIDGEMIND_ANTHROPIC_API_KEY="sk-ant-..."
// export BRIDGEMIND_OPENAI_API_KEY="sk-..."
// export BRIDGEMIND_GOOGLE_API_KEY="..."
// etc.
//
// These env vars are consumed by the plugin's MCP server process, not by
// BridgeMind One directly. We inject them into the stdio environment block
// (for local plugins) or the HTTP transport delegates auth to the upstream
// MCP server which has already resolved the credentials.
//
// Plugin identities are defined as static constants on PluginIdentity
// in PluginDefinitions.swift. Safety rules are in the pluginSafetyRules
// dictionary in the same file.
//

import Foundation

// MARK: - Agent Plugin Metadata

/// Descriptive metadata for each agent engine plugin.
public struct AgentPlugin: Sendable, Equatable, Identifiable {

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

// MARK: - All Agent Plugins

public enum AgentPlugins: Sendable, CaseIterable, Equatable {

 /// Anthropic Claude — primary reasoning engine.
 /// Identity: PluginIdentity.claude
 /// Safety: All responses subject to Anthropic usage policies.
 /// Never bypass billing approvals. Honor prompt caching cost transparency.
 /// Do not send prompts containing other users' PII without redaction.
 case claude

 /// OpenAI Codex — code-specialized reasoning.
 /// Identity: PluginIdentity.codex
 /// Safety: Output must be reviewed before execution.
 /// Never execute generated code without sandboxing.
 case codex

 /// GitHub Copilot — code completion and generation.
 /// Identity: PluginIdentity.copilot
 /// Safety: Never auto-apply code suggestions without user review.
 /// Generated code subject to GitHub Copilot license terms.
 case copilot

 /// Cursor IDE — code agent and editor integration.
 /// Identity: PluginIdentity.cursor
 /// Safety: Never apply edits without explicit user confirmation.
 /// Sandbox all file-system modifications.
 case cursor

 /// Aider — open-source AI pair programming.
 /// Identity: PluginIdentity.aider
 /// Safety: Never commit generated code without review.
 /// Sandbox all git operations.
 case aider

 /// DeepSeek — high-performance reasoning.
 /// Identity: PluginIdentity.deepseek
 /// Safety: All output subject to DeepSeek usage policies.
 /// Never bypass content filters.
 case deepseek

 /// Google Gemini — multimodal reasoning.
 /// Identity: PluginIdentity.gemini
 /// Safety: Never send prompts containing PII without redaction.
 /// Honor Google's AI Principles and usage policies.
 case gemini

 /// xAI Grok — reasoning with real-time knowledge.
 /// Identity: PluginIdentity.grok
 /// Safety: All output subject to xAI usage policies.
 /// Never bypass content filters.
 case grok

 /// OpenCode — open-source AI coding assistant.
 /// Identity: PluginIdentity.opencode
 /// Safety: Never auto-apply code changes without review.
 /// Sandbox all file operations.
 case opencode

 /// Antigravity — experimental reasoning engine.
 /// Identity: PluginIdentity.antigravity
 /// Safety: No external data sent to third-party services.
 /// All computation runs locally within the sandbox.
 case antigravity

 /// Factory.ai Droid — autonomous code agent.
 /// Identity: PluginIdentity.droid
 /// Safety: Never execute code without explicit user approval.
 /// Never push changes without review.
 case droid

 // MARK: Metadata Access

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
 }
 }

 public var plugin: AgentPlugin {
 AgentPlugin(
 id: identity.id,
 identity: identity,
 description: identity.displayName,
 safetyRules: pluginSafetyRules[identity.id] ?? [],
 warnings: []
 )
 }

 public static let all: [PluginIdentity] = allCases.map(\.identity)
 public static let allPlugins: [AgentPlugin] = allCases.map(\.plugin)
}
