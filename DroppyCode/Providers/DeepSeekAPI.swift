import Foundation

/// Minimal OpenAI-compatible HTTP client for api.deepseek.com.
/// Chat streaming itself lives in DeepSeekSession; this covers the
/// lightweight calls (key validation, model catalog) the registry needs.
enum DeepSeekAPI {
    static let baseURL = URL(string: "https://api.deepseek.com")!
    static let chatURL = URL(string: "https://api.deepseek.com/chat/completions")!
    static let modelsURL = URL(string: "https://api.deepseek.com/models")!

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

    static let deepseekEfforts = ["low", "high", "max"]

    static func option(for id: String) -> ModelOption? {
        switch id {
        case "deepseek-v4-pro":
            return ModelOption(id: id, name: "V4 Pro", detail: "Best reasoning and coding quality", efforts: deepseekEfforts, defaultEffort: "high", isDefault: true)
        case "deepseek-flash", "deepseek-v4-flash":
            return ModelOption(id: id, name: "V4 Flash", detail: "Fast everyday chat and edits", efforts: deepseekEfforts, defaultEffort: "high")
        case "deepseek-v4-flash-vision-exp":
            return ModelOption(id: id, name: "V4 Flash Vision", detail: "Experimental, reads attached images", efforts: deepseekEfforts, defaultEffort: "high")
        case "deepseek-chat":
            return ModelOption(id: id, name: "Chat (legacy)", detail: "Legacy alias for V4 Flash", efforts: deepseekEfforts, defaultEffort: "high")
        case "deepseek-reasoner":
            return ModelOption(id: id, name: "Reasoner (legacy)", detail: "Legacy alias for V4 Flash thinking", efforts: deepseekEfforts, defaultEffort: "high")
        default:
            // Any other id the API ships (including future ones) still shows up
            // instead of vanishing. The models endpoint already scopes to DeepSeek,
            // so no name check is needed — "deepseek-flash" would have failed one.
            return ModelOption(id: id, name: id, efforts: deepseekEfforts, defaultEffort: "high")
        }
    }

    static func isVisionModel(_ id: String?) -> Bool {
        (id ?? "").localizedCaseInsensitiveContains("vision")
    }
}
