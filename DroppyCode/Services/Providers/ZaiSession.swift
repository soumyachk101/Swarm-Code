import Foundation

/// Native Z.ai agent: talks to https://api.z.ai/api/coding/paas/v4/chat/completions
/// directly (OpenAI-compatible, the GLM Coding Plan endpoint) and executes coding
/// tools locally, so no CLI install is needed — just an API key in Settings → Providers → Z.ai.
@MainActor
final class ZaiSession: OpenAICompatibleSession {
    private static let config = Config(
        kind: .zai,
        title: "Z.ai",
        agentIdentity: { _ in "Z.ai GLM coding agent" },
        defaultModel: "glm-5.3",
        chatURL: ZaiAPI.chatURL,
        contextWindow: ZaiAPI.contextWindow,
        maxOutputTokens: ZaiAPI.maxOutputTokens,
        replaysReasoning: true,
        isVisionModel: ZaiAPI.isVisionModel
    )

    init(configuration: SessionConfiguration) {
        super.init(config: Self.config, configuration: configuration)
    }

    /// GLM asks for a `max_tokens` cap, an always-on thinking mode that keeps
    /// prior thinking, and `tool_stream` alongside the tools.
    override func applyProviderPayload(_ payload: inout [String: JSONValue], model: String, effort: String?, withTools: Bool) {
        if withTools { payload["tool_stream"] = true }
        payload["thinking"] = ["type": "enabled", "clear_thinking": false]
        payload["max_tokens"] = .int(ZaiAPI.maxOutputTokens)
        if let mapped = Self.reasoningEffort(effort) { payload["reasoning_effort"] = .string(mapped) }
    }

    static func reasoningEffort(_ effort: String?) -> String? {
        guard let effort, !effort.isEmpty else { return nil }
        switch effort {
        case "low": return "low"
        case "medium", "high": return "high"
        case "xhigh", "extra-high", "max": return "max"
        default: return nil
        }
    }

    override func friendlyError(_ message: String, statusCode: Int) -> String {
        let lower = message.lowercased()
        // A context-length message also says "limit", so it is read before the plan window.
        if lower.contains("context") && (lower.contains("length") || lower.contains("window") || lower.contains("token")) {
            return "The conversation no longer fits GLM-5.3's context window. Start a new thread or compact first."
        }
        if statusCode == 401 || lower.contains("token expired") || lower.contains("incorrect") {
            return "Z.ai rejected the API key. Check it in Settings → Providers → Z.ai."
        }
        // "usage limit" is what auto-continue listens for; it then reads the reset time from Z.ai's quota API.
        if statusCode == 429 || lower.contains("quota") || lower.contains("exhaust") || lower.contains("limit") {
            return "Your GLM Coding Plan usage limit is reached for this window. It refreshes on its own; the usage ring shows when. Details at z.ai/manage-apikey/subscription."
        }
        if lower.contains("balance") || lower.contains("insufficient") || lower.contains("1113") {
            return "This Z.ai key has no active Coding Plan. Subscribe at z.ai/subscribe, then try again."
        }
        if lower.contains("model") && lower.contains("not exist") {
            return "Z.ai no longer offers that model. Pick GLM-5.3 or GLM-5.3 Flash in the model picker."
        }
        return message.isEmpty ? "Z.ai stopped before finishing." : message
    }
}
