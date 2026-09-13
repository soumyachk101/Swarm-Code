import Foundation

/// Minimal OpenAI-compatible HTTP client for api.meta.ai.
/// Chat streaming itself lives in MetaSession; this covers the
/// lightweight calls (key validation, model catalog) the registry needs.
///
/// Reference: https://dev.meta.ai/docs/api-reference/
/// Base URL `https://api.meta.ai/v1`, bearer auth with `MODEL_API_KEY`.
/// Endpoints used here:
/// - `GET /v1/models` — list available models (also validates the key)
/// - `POST /v1/chat/completions` — OpenAI-compatible messages-array endpoint (see MetaSession)
/// The Responses API (`POST /v1/responses`) carries reasoning across turns via
/// encrypted replay, but Chat Completions keeps the agent loop OpenAI-compatible
/// and matches the rest of Droppy Code's native providers.
enum MetaAPI {
    static let baseURL = URL(string: "https://api.meta.ai/v1")!
    static let chatURL = URL(string: "https://api.meta.ai/v1/chat/completions")!
    static let modelsURL = URL(string: "https://api.meta.ai/v1/models")!
    static let statusURL = URL(string: "https://api.meta.ai/v1/status")!

    /// Muse Spark context window per https://dev.meta.ai/docs/models
    static let contextWindow = 1_048_576
    static let maxOutputTokens = 131_072

    /// True when the key lists models successfully.
    static func validate(apiKey: String) async -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        var request = URLRequest(url: modelsURL, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    static func listModels(apiKey: String) async throws -> [ModelOption] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }
        var request = URLRequest(url: modelsURL, timeoutInterval: 15)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = JSONValue.parse(data) else { return [] }
        let ids = (json["data"]?.array ?? []).compactMap { $0["id"]?.string }
        guard !ids.isEmpty else { return [] }
        return ids.compactMap(Self.option(for:)).sorted { lhs, rhs in
            (lhs.isDefault ? 0 : 1, lhs.id) < (rhs.isDefault ? 0 : 1, rhs.id)
        }
    }

    static let metaEfforts = ["minimal", "low", "medium", "high", "xhigh", "max"]

    static func option(for id: String) -> ModelOption? {
        switch id {
        case "muse-spark-1.3":
            return ModelOption(id: id, name: "Spark 1.3", detail: "Latest Muse Spark · best agentic coding · 1M context", efforts: metaEfforts, defaultEffort: "high", isDefault: true)
        case "muse-spark-1.3-contributor":
            return ModelOption(id: id, name: "Spark 1.3 Contributor", detail: "Same 1.3 checkpoint · discounted contributor tier", efforts: metaEfforts, defaultEffort: "high")
        case "muse-spark-1.2":
            return ModelOption(id: id, name: "Spark 1.2", detail: "Previous checkpoint · Standard tier · 1M context", efforts: metaEfforts, defaultEffort: "high")
        case "muse-spark-1.2-contributor":
            return ModelOption(id: id, name: "Spark 1.2 Contributor", detail: "1.2 checkpoint · discounted contributor tier", efforts: metaEfforts, defaultEffort: "high")
        case "muse-spark-1.1":
            return ModelOption(id: id, name: "Spark 1.1", detail: "Original checkpoint · Standard tier · 1M context", efforts: metaEfforts, defaultEffort: "high")
        default:
            // Any other id the API ships (including future Muse Spark checkpoints)
            // still shows up instead of vanishing. The models endpoint already
            // scopes to Meta, so no name check is needed.
            // Only accept plausible Muse Spark ids to avoid surfacing unrelated entries.
            guard id.lowercased().hasPrefix("muse-spark") || id.lowercased().hasPrefix("muse-") else { return nil }
            return ModelOption(id: id, name: id, efforts: metaEfforts, defaultEffort: "high")
        }
    }

    /// All Muse Spark models are multimodal (text, image, video, audio, PDF in).
    static func isVisionModel(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return true }
        return id.lowercased().contains("muse-spark") || id.lowercased().contains("muse")
    }
}
