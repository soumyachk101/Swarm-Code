//
// AgentPlugins.swift
// BridgeMind One — Agent engine plugin definitions
//
// Agent engine plugins connect to remote LLM provider MCP servers over HTTP.
// Each requires an API key set as an environment variable (never hard-coded).
//
// SECURITY NOTE: API keys are read at runtime from the environment variable
// named in `apiKeyEnv`. The key value never appears in source code.
// The user sets these via:
// export BRIDGEMIND_ANTHROPIC_API_KEY="sk-ant-..."
// export BRIDGEMIND_OPENAI_API_KEY="sk-..."
// export BRIDGEMIND_GOOGLE_API_KEY="..."
// etc.
//
// These env vars are consumed by the plugin's MCP server process, not by
// BridgeMind One directly. We inject them into the stdio environment block
// (for stdio plugins) or the HTTP transport receives them from the upstream
// MCP server which has already resolved them.
//

import Foundation

// MARK: - Claude (Anthropic)

/// Anthropic Claude — primary reasoning engine.
///
/// The Claude MCP server connects to the Anthropic Messages API.
/// Requires an Anthropic API key in the `BRIDGEMIND_ANTHROPIC_API_KEY` environment variable.
///
/// Safety rules (from original binary):
/// - All responses subject to Anthropic usage policies
/// - Never bypass billing approvals
/// - Honor prompt caching cost transparency
/// - Do not send prompts containing other users' PII without redaction
public struct ClaudePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "claude",
 displayName: "Claude",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.anthropic.com")!),
 apiKeyEnv: "BRIDGEMIND_ANTHROPIC_API_KEY",
 description: "Anthropic Claude — primary reasoning engine",
 safetyRules: [
 "All responses subject to Anthropic usage policies.",
 "Never bypass billing approvals.",
 "Honor prompt caching cost transparency.",
 "Do not send prompts containing other users' PII without redaction."
 ],
 warnings: [
 "Requires an active Anthropic API key with Messages API access.",
 "Prompt caching may incur additional costs — monitor via the Anthropic console."
 ]
 )

 // Prevent instantiation
 private init() {}
}

// MARK: - Codex (OpenAI)

/// OpenAI Codex — code-specialized reasoning via OpenAI's API.
///
/// Requires an OpenAI API key in `BRIDGEMIND_OPENAI_API_KEY`.
///
/// Safety rules:
/// - Output must be reviewed before execution
/// - Never execute generated code without sandboxing
public struct CodexPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "codex",
 displayName: "Codex",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.openai.com")!),
 apiKeyEnv: "BRIDGEMIND_OPENAI_API_KEY",
 description: "OpenAI Codex — code-specialized reasoning",
 safetyRules: [
 "Output must be reviewed before execution.",
 "Never execute generated code without sandboxing."
 ],
 warnings: [
 "Requires OpenAI API key with GPT-4o or o1 model access.",
 "Generated code should always be reviewed before use."
 ]
 )

 private init() {}
}

// MARK: - Copilot (GitHub)

/// GitHub Copilot — code completion and generation via GitHub's Copilot API.
///
/// Requires a GitHub Copilot API key in `BRIDGEMIND_GITHUB_COPILOT_API_KEY`.
///
/// Safety rules:
/// - Never auto-apply code suggestions without user review
/// - Generated code is subject to GitHub Copilot license terms
public struct CopilotPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "copilot",
 displayName: "GitHub Copilot",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.githubcopilot.com")!),
 apiKeyEnv: "BRIDGEMIND_GITHUB_COPILOT_API_KEY",
 description: "GitHub Copilot — code completion and generation",
 safetyRules: [
 "Never auto-apply code suggestions without user review.",
 "Generated code is subject to GitHub Copilot license terms."
 ],
 warnings: [
 "Requires a GitHub Copilot subscription.",
 "API access is rate-limited per Copilot policy."
 ]
 )

 private init() {}
}

// MARK: - Cursor

/// Cursor IDE — code agent and editor integration.
///
/// Requires a Cursor API key in `BRIDGEMIND_CURSOR_API_KEY`.
///
/// Safety rules:
/// - Never apply edits without explicit user confirmation
/// - Sandbox all file-system modifications
public struct CursorPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "cursor",
 displayName: "Cursor",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.cursor.com")!),
 apiKeyEnv: "BRIDGEMIND_CURSOR_API_KEY",
 description: "Cursor IDE — code agent and editor integration",
 safetyRules: [
 "Never apply edits without explicit user confirmation.",
 "Sandbox all file-system modifications."
 ],
 warnings: [
 "Requires a Cursor API key with agent permissions.",
 "File modifications are applied to the active workspace."
 ]
 )

 private init() {}
}

// MARK: - Aider

/// Aider — open-source AI pair programming tool.
///
/// Aider runs as a local stdio process. It uses the OpenAI API (or compatible)
/// and reads the key from the standard environment.
///
/// Safety rules:
/// - Never commit generated code without review
/// - Sandbox all git operations
public struct AiderPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "aider",
 displayName: "Aider",
 type: .agent,
 authType: .apiKey,
 transport: .stdio(command: "aider", arguments: ["--mcp"]),
 apiKeyEnv: "OPENAI_API_KEY",
 description: "Aider — open-source AI pair programming",
 safetyRules: [
 "Never commit generated code without review.",
 "Sandbox all git operations."
 ],
 warnings: [
 "Requires OpenAI-compatible API key.",
 "Runs as a local stdio process — ensure aider is installed."
 ]
 )

 private init() {}
}

// MARK: - DeepSeek

/// DeepSeek — high-performance reasoning via DeepSeek's API.
///
/// Requires a DeepSeek API key in `BRIDGEMIND_DEEPSEEK_API_KEY`.
///
/// Safety rules:
/// - All output subject to DeepSeek usage policies
/// - Never bypass content filters
public struct DeepSeekPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "deepseek",
 displayName: "DeepSeek",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.deepseek.com")!),
 apiKeyEnv: "BRIDGEMIND_DEEPSEEK_API_KEY",
 description: "DeepSeek — high-performance reasoning",
 safetyRules: [
 "All output subject to DeepSeek usage policies.",
 "Never bypass content filters."
 ],
 warnings: [
 "Requires DeepSeek API key.",
 "Check DeepSeek's rate limits and model availability."
 ]
 )

 private init() {}
}

// MARK: - Gemini (Google)

/// Google Gemini — multimodal reasoning via the Google AI API.
///
/// Requires a Google API key in `BRIDGEMIND_GOOGLE_API_KEY`.
///
/// Safety rules:
/// - Never send prompts containing PII without redaction
/// - Honor Google's AI Principles and usage policies
public struct GeminiPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "gemini",
 displayName: "Gemini",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://generativelanguage.googleapis.com")!),
 apiKeyEnv: "BRIDGEMIND_GOOGLE_API_KEY",
 description: "Google Gemini — multimodal reasoning",
 safetyRules: [
 "Never send prompts containing PII without redaction.",
 "Honor Google's AI Principles and usage policies."
 ],
 warnings: [
 "Requires Google AI API key.",
 "Multimodal inputs (images, PDFs) may incur higher costs."
 ]
 )

 private init() {}
}

// MARK: - Grok (xAI)

/// xAI Grok — reasoning with real-time knowledge via xAI's API.
///
/// Requires an xAI API key in `BRIDGEMIND_XAI_API_KEY`.
///
/// Safety rules:
/// - All output subject to xAI usage policies
/// - Never bypass content filters
public struct GrokPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "grok",
 displayName: "Grok",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.x.ai")!),
 apiKeyEnv: "BRIDGEMIND_XAI_API_KEY",
 description: "xAI Grok — reasoning with real-time knowledge",
 safetyRules: [
 "All output subject to xAI usage policies.",
 "Never bypass content filters."
 ],
 warnings: [
 "Requires xAI API key.",
 "Real-time search may return unverified information."
 ]
 )

 private init() {}
}

// MARK: - OpenCode

/// OpenCode — open-source AI coding assistant.
///
/// Requires an OpenAI-compatible API key in `BRIDGEMIND_OPENAI_API_KEY`.
///
/// Safety rules:
/// - Never auto-apply code changes without review
/// - Sandbox all file operations
public struct OpenCodePlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "opencode",
 displayName: "OpenCode",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.openai.com")!),
 apiKeyEnv: "BRIDGEMIND_OPENAI_API_KEY",
 description: "OpenCode — open-source AI coding assistant",
 safetyRules: [
 "Never auto-apply code changes without review.",
 "Sandbox all file operations."
 ],
 warnings: [
 "Requires OpenAI-compatible API key.",
 "Ensure the OpenCode server is running and reachable."
 ]
 )

 private init() {}
}

// MARK: - Antigravity

/// Antigravity — experimental reasoning engine built into BridgeMind One.
///
/// This is a built-in plugin; no external API key or network call is required.
///
/// Safety rules:
/// - No external data sent to third-party services
/// - All computation runs locally within the sandbox
public struct AntigravityPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "antigravity",
 displayName: "Antigravity",
 type: .agent,
 authType: .none,
 transport: .builtin,
 description: "Antigravity — experimental reasoning engine",
 safetyRules: [
 "No external data sent to third-party services.",
 "All computation runs locally within the sandbox."
 ],
 warnings: [
 "Experimental — behavior may change between releases."
 ]
 )

 private init() {}
}

// MARK: - Droid (Factory.ai)

/// Factory.ai Droid — autonomous code agent.
///
/// Requires a Factory.ai API key in `BRIDGEMIND_DROID_API_KEY`.
///
/// Safety rules:
/// - Never execute code without explicit user approval
/// - Never push changes without review
public struct DroidPlugin: MCPPluginProvider {

 public static let descriptor = PluginDescriptor(
 id: "droid",
 displayName: "Droid",
 type: .agent,
 authType: .apiKey,
 transport: .http(URL(string: "https://api.factory.ai")!),
 apiKeyEnv: "BRIDGEMIND_DROID_API_KEY",
 description: "Factory.ai Droid — autonomous code agent",
 safetyRules: [
 "Never execute code without explicit user approval.",
 "Never push changes without review."
 ],
 warnings: [
 "Requires Factory.ai API key.",
 "Autonomous execution requires explicit per-action approval."
 ]
 )

 private init() {}
}
