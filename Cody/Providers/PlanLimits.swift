import Foundation

/// A provider's subscription limits: each rolling window, how much of it is used and when it resets.
struct PlanLimits: Sendable, Equatable {
    struct Window: Sendable, Equatable, Identifiable {
        var id: String
        var title: String
        var percent: Double
        var resetsAt: Date?
    }

    var planName: String?
    var windows: [Window]
}

@MainActor
enum PlanLimitsReader {
    /// Only Codex and Claude report plan limits. Cursor, OpenCode and Grok expose none.
    static func exposesLimits(_ provider: ProviderKind) -> Bool {
        provider == .codex || provider == .claude
    }

    static func read(_ provider: ProviderKind, executable: URL, environment: [String: String]) async -> PlanLimits? {
        switch provider {
        case .codex: try? await CodexSession.readPlanLimits(executable: executable, environment: environment)
        case .claude: await readClaude(executable: executable, environment: environment)
        case .cursor, .opencode, .grok: nil
        }
    }

    static func windowTitle(minutes: Int?) -> String {
        guard let minutes else { return "Usage limit" }
        switch minutes {
        case 300: return "5-hour limit"
        case 1_440: return "Daily"
        case 10_080: return "Weekly"
        case 40_320...44_640: return "Monthly"
        default:
            return minutes % 1_440 == 0 ? "\(minutes / 1_440)-day limit" : "\(max(1, minutes / 60))-hour limit"
        }
    }

    static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    // MARK: - Claude

    /// Claude reports limits through the `get_usage` control request, so a short-lived session asks for them.
    private static func readClaude(executable: URL, environment: [String: String]) async -> PlanLimits? {
        let process = StdioProcess(
            executable: executable,
            arguments: ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose"],
            directory: FileManager.default.temporaryDirectory,
            environment: environment
        )
        do {
            try process.start()
        } catch {
            return nil
        }
        // Ending the process finishes the message stream, which is what bounds a request that never answers.
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(20))
            process.terminate()
        }
        defer {
            watchdog.cancel()
            process.terminate()
        }
        process.send(["type": "control_request", "request_id": "cody-init", "request": ["subtype": "initialize", "hooks": .null]])
        for await message in process.messages {
            guard message["type"]?.string == "control_response" else { continue }
            let response = message["response"] ?? .null
            switch response["request_id"]?.string {
            case "cody-init":
                process.send(["type": "control_request", "request_id": "cody-usage", "request": ["subtype": "get_usage"]])
            case "cody-usage":
                return parseClaude(response["response"] ?? .null)
            default:
                continue
            }
        }
        return nil
    }

    private static func parseClaude(_ usage: JSONValue) -> PlanLimits? {
        let limits = usage["rate_limits"]?["limits"]?.array ?? []
        let windows = limits.enumerated().compactMap { index, limit -> PlanLimits.Window? in
            guard let percent = limit["percent"]?.double else { return nil }
            let kind = limit["kind"]?.string ?? ""
            let group = planName(limit["group"]?.string) ?? "Usage"
            let scope = limit["scope"]?["model"]?["display_name"]?.string
            let title = switch kind {
            case "session": "5-hour limit"
            case "weekly_all": "Weekly · all models"
            default: scope.map { "\(group) · \($0)" } ?? group
            }
            return PlanLimits.Window(
                id: "\(kind)-\(index)",
                title: title,
                percent: percent,
                resetsAt: limit["resets_at"]?.string.flatMap(parseDate)
            )
        }
        guard !windows.isEmpty else { return nil }
        return PlanLimits(planName: planName(usage["subscription_type"]?.string), windows: windows)
    }

    /// Claude writes microsecond timestamps, which the ISO 8601 parser does not take, so the fraction is dropped.
    private static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
