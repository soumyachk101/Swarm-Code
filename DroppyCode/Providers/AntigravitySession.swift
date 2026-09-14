import Foundation

/// Drives Google's Antigravity CLI (`agy`) in headless streaming mode.
///
/// The CLI speaks newline-delimited JSON on stdio, much like Claude's
/// stream-json: Droppy Code holds one persistent process per thread with
/// `--input-format stream-json --output-format stream-json`, writes one
/// `{"event":"user","message":{"content":"…"}}` object per turn on stdin,
/// and reads `init` / `step_update` / `result` events on stdout.
///
/// Protocol reference: https://antigravity.google/docs/cli/headless/
/// Verified live against `agy 1.2.2` (models TSV, `/usage` and `/credits`
/// headless envelopes, tool step shapes, `denied_actions`).
@MainActor
final class AntigravitySession: ProviderSession {
    var onEvent: ((ProviderEvent) -> Void)?

    private let configuration: SessionConfiguration
    private var process: StdioProcess?
    private var readTask: Task<Void, Never>?
    private var initContinuation: CheckedContinuation<String, Error>?
    private var conversationID: String?
    private var runtimeMode: RuntimeMode
    private var interactionMode: InteractionMode
    private var model: String?
    private var effort: String?
    private var turnActive = false
    private var interruptRequested = false
    private var isStopping = false
    /// Resolves the cumulative session token total into per-turn spend.
    private var spendTracker = TokenSpendTracker()

    /// Reasoning efforts `agy --effort` accepts.
    static let efforts = ["low", "medium", "high"]

    init(configuration: SessionConfiguration) {
        self.configuration = configuration
        runtimeMode = configuration.runtimeMode
        interactionMode = configuration.interactionMode
        model = configuration.model
        effort = configuration.effort
    }

    var isRunning: Bool { process?.isRunning ?? false }

    private var workingDirectory: String { configuration.workingDirectory.path }

    // MARK: - Lifecycle

    func start() async throws -> String {
        guard let executable = configuration.executable else { throw ProviderError.notInstalled(configuration.provider) }
        var arguments = [
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--print-timeout", "30m",
        ]
        if let model, !model.isEmpty { arguments += ["--model", model] }
        if let effort, Self.efforts.contains(effort) { arguments += ["--effort", effort] }
        arguments += modeArguments(runtimeMode: configuration.runtimeMode, interaction: configuration.interactionMode)
        if let resumeID = configuration.resumeID, !resumeID.isEmpty {
            arguments += ["--conversation", resumeID]
        }

        let process = StdioProcess(
            executable: executable,
            arguments: arguments,
            directory: configuration.workingDirectory,
            environment: configuration.environment
        )
        self.process = process
        isStopping = false
        try process.start()
        let messages = process.messages
        readTask = Task { [weak self] in
            for await message in messages {
                guard let self else { return }
                self.handle(message)
            }
            self?.didClose()
        }
        return try await withCheckedThrowingContinuation { continuation in
            initContinuation = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                await self?.failStartAfterTimeout()
            }
        }
    }

    /// `agy --mode` only knows `accept-edits` and `plan`: the default review
    /// mode is the absence of the flag. Full access additionally approves
    /// every tool, since headless runs soft-deny unapproved actions instead
    /// of prompting.
    private func modeArguments(runtimeMode: RuntimeMode, interaction: InteractionMode) -> [String] {
        var arguments: [String] = []
        if interaction == .plan {
            arguments += ["--mode", "plan"]
        } else {
            switch runtimeMode {
            case .supervised:
                break
            case .autoAcceptEdits, .auto, .fullAccess:
                arguments += ["--mode", "accept-edits"]
            }
        }
        if runtimeMode == .fullAccess {
            arguments += ["--dangerously-skip-permissions"]
        }
        return arguments
    }

    private func failStartAfterTimeout() {
        guard let continuation = initContinuation else { return }
        initContinuation = nil
        process?.terminate()
        continuation.resume(throwing: ProviderError.failed("Antigravity did not answer. Is `agy` signed in? Run `agy` once in Terminal."))
    }

    func send(_ input: TurnInput) async throws {
        guard let process, process.isRunning else { throw ProviderError.notRunning }
        runtimeMode = input.runtimeMode
        interactionMode = input.interactionMode
        if let model = input.model, !model.isEmpty { self.model = model }
        if let effort = input.effort, !effort.isEmpty { self.effort = effort }
        // Stream-json only takes text blocks; anything else ends the session
        // with an error, so images never go on the wire (see supportsImages).
        turnActive = true
        interruptRequested = false
        onEvent?(.turnStarted(providerTurnID: nil))
        process.send(["event": "user", "message": ["content": .string(input.text)]])
    }

    func interrupt() async {
        guard turnActive else { return }
        interruptRequested = true
        // The stream has no interrupt request: stopping the process ends the
        // turn, and the conversation persists server-side for the next turn's
        // `--conversation` resume.
        process?.terminate()
    }

    func compact() async throws {
        throw ProviderError.failed("Antigravity manages its own context.")
    }

    func resolveApproval(_ requestID: String, optionID: String) {}
    func answerQuestion(_ requestID: String, answers: [String: [String]]) {}

    func stop() {
        isStopping = true
        process?.terminate()
    }

    // MARK: - Stream

    private func handle(_ message: JSONValue) {
        switch message["event"]?.string {
        case "init":
            guard let id = message["conversation_id"]?.string, !id.isEmpty else { return }
            conversationID = id
            if let continuation = initContinuation {
                initContinuation = nil
                continuation.resume(returning: id)
            }
            onEvent?(.sessionReady(sessionID: id))
        case "step_update":
            handleStep(message["step_update"] ?? .null)
        case "result":
            handleResult(message["result"] ?? .null)
        default:
            break
        }
    }

    private func handleStep(_ step: JSONValue) {
        let index = step["step_index"]?.int ?? 0
        switch step["step_type"]?.string {
        case "agent_response":
            guard let text = step["text_delta"]?.string, !text.isEmpty else { return }
            onEvent?(.messageDelta(id: "agy-message-\(index)", text: text))
        case "tool":
            guard let name = step["tool_name"]?.string ?? step["tool_info"]?["name"]?.string else { return }
            let id = "agy-tool-\(index)"
            let info = step["tool_info"] ?? .null
            switch step["state"]?.string {
            case "ERROR":
                let message = info["error"]?["message"]?.string ?? "The tool failed."
                onEvent?(.toolUpdated(id: id, update: ToolUpdate(output: message, status: .failed)))
            case "DONE":
                var update = ToolUpdate(status: .completed)
                if let output = info["output"]?.string, !output.isEmpty { update.output = output }
                onEvent?(.toolUpdated(id: id, update: update))
            default:
                onEvent?(.toolStarted(id: id, call: makeToolCall(name: name, parameters: info["parameters"] ?? .null)))
            }
        default:
            // `user_input` acknowledgements and `checkpoint` markers carry
            // nothing Droppy Code renders.
            break
        }
    }

    private func handleResult(_ result: JSONValue) {
        turnActive = false
        if let usage = result["usage"], !usage.isNull {
            // Totals are cumulative over the session (per the headless docs),
            // so the spend tracker resolves them into per-turn deltas.
            let used = usage["total_tokens"]?.int ?? ((usage["input_tokens"]?.int ?? 0) + (usage["output_tokens"]?.int ?? 0))
            if used > 0 {
                onEvent?(.usage(ContextUsage(usedTokens: used, windowTokens: nil)))
                let spend = spendTracker.spend(total: used)
                if spend > 0 { TokenLedger.shared.record(spend: spend) }
            }
        }
        let denied = (result["denied_actions"]?.array ?? []).compactMap { $0["display_name"]?.string ?? $0["action"]?.string }
        if !denied.isEmpty {
            let names = denied.joined(separator: ", ")
            onEvent?(.notice(Notice(
                level: .warning,
                message: "Antigravity held back \(names) without prompting. Use Full access or add an allow rule in the CLI's settings."
            )))
        }
        if let id = result["conversation_id"]?.string, !id.isEmpty {
            conversationID = id
            onEvent?(.sessionReady(sessionID: id))
        }
        if interruptRequested {
            onEvent?(.turnCompleted(status: .interrupted, error: nil))
        } else {
            switch result["status"]?.string {
            case "SUCCESS":
                onEvent?(.turnCompleted(status: .completed, error: nil))
            case "CANCELED", "INTERRUPTED":
                onEvent?(.turnCompleted(status: .interrupted, error: nil))
            default:
                let error = result["error"]?.string
                onEvent?(.turnCompleted(status: .failed, error: (error?.isEmpty == false ? error : "Antigravity stopped before finishing.")))
            }
        }
        interruptRequested = false
    }

    private func didClose() {
        if let continuation = initContinuation {
            initContinuation = nil
            let tail = process?.errorTail ?? ""
            continuation.resume(throwing: ProviderError.failed(authHint(in: tail) ?? (TextCleanup.lastLines(tail) ?? "Antigravity exited.")))
        }
        if turnActive {
            turnActive = false
            if interruptRequested {
                onEvent?(.turnCompleted(status: .interrupted, error: nil))
            } else {
                let tail = process?.errorTail ?? ""
                onEvent?(.turnCompleted(status: .failed, error: authHint(in: tail) ?? TextCleanup.lastLines(tail) ?? "Antigravity exited."))
            }
            interruptRequested = false
        }
        guard !isStopping else { return }
        onEvent?(.exited(error: TextCleanup.lastLines(process?.errorTail ?? "")))
    }

    private func authHint(in text: String) -> String? {
        let lowered = text.lowercased()
        guard lowered.contains("authentication required") || lowered.contains("not signed in")
            || lowered.contains("unauthenticated") || (lowered.contains("login") && lowered.contains("agy")) else { return nil }
        return "Antigravity is not signed in. Run `agy` once in Terminal to sign in."
    }

    // MARK: - Catalog

    /// `agy models` prints `slug<TAB>Name` rows on stdout (progress goes to
    /// stderr). The `/model` headless envelope reports the persisted default,
    /// which becomes the catalog's default entry.
    static func listModels(executable: URL, environment: [String: String]) async throws -> [ModelOption] {
        async let modelsFetch: ShellResult = try Shell.run(executable, ["models"], environment: environment, timeout: 30)
        async let defaultFetch: ShellResult = try Shell.run(executable, ["-p", "/model", "--output-format", "json"], environment: environment, timeout: 30)
        let models = try? await modelsFetch
        let current = try? await defaultFetch
        var currentID: String?
        if let stdout = current?.stdout, let json = JSONValue.parse(stdout) {
            currentID = json["command"]?["data"]?["id"]?.string
        }
        guard let output = models?.stdout, let text = String(data: output, encoding: .utf8) else {
            throw ShellError("`agy models` produced no output.")
        }
        var list: [ModelOption] = []
        for line in TextCleanup.stripANSI(text).components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let slug = parts.first, Self.isSlug(slug) else { continue }
            let name = parts.count > 1 && !parts[1].isEmpty ? parts[1] : slug
            list.append(ModelOption(id: slug, name: name, efforts: efforts, isDefault: slug == currentID))
        }
        guard !list.isEmpty else { throw ShellError("`agy models` listed no models.") }
        if !list.contains(where: \.isDefault), let first = list.first {
            list[list.startIndex] = ModelOption(
                id: first.id, name: first.name, detail: first.detail,
                efforts: first.efforts, defaultEffort: first.defaultEffort, isDefault: true
            )
        }
        return list
    }

    private static func isSlug(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first.isNumber else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
            && !text.contains(" ")
    }

    /// Sign-in state without spending tokens: `agy models` needs the cached
    /// Google session (or `GEMINI_API_KEY`) and fails loudly without one.
    static func authStatus(executable: URL, environment: [String: String]) async -> ProviderStatus.Auth {
        guard let result = try? await Shell.run(executable, ["models"], environment: environment, timeout: 20) else {
            return .unknown
        }
        let text = TextCleanup.stripANSI(result.output + result.errorOutput)
        let rows = text.components(separatedBy: .newlines).filter { isSlug($0.split(separator: "\t").first.map(String.init) ?? "") }
        if result.succeeded, !rows.isEmpty { return .signedIn(nil) }
        let lowered = text.lowercased()
        if lowered.contains("authentication required") || lowered.contains("not signed in")
            || lowered.contains("unauthenticated") || lowered.contains("sign in") || lowered.contains("login") {
            return .signedOut
        }
        return result.succeeded ? .signedIn(nil) : .unknown
    }

    // MARK: - Plan limits

    /// Model quotas (`/usage`: weekly + 5-hour buckets per model group) and
    /// the AI credit balance (`/credits`). Both are zero-token headless
    /// calls, so reading limits never spends quota itself.
    static func readPlanLimits(executable: URL, environment: [String: String]) async throws -> PlanLimits? {
        async let usageFetch: ShellResult = try Shell.run(executable, ["-p", "/usage", "--output-format", "json"], environment: environment, timeout: 30)
        async let creditsFetch: ShellResult = try Shell.run(executable, ["-p", "/credits", "--output-format", "json"], environment: environment, timeout: 30)
        let usage = try? await usageFetch
        let credits = try? await creditsFetch
        var windows: [PlanLimits.Window] = []
        if let usage, let data = String(data: usage.stdout, encoding: .utf8), let json = JSONValue.parse(data) {
            windows += parseUsage(json["command"]?["data"], fallback: json["response"]?.string)
        }
        if let credits, let data = String(data: credits.stdout, encoding: .utf8), let json = JSONValue.parse(data),
           let window = parseCredits(json["command"]?["data"], fallback: json["response"]?.string) {
            windows.append(window)
        }
        guard !windows.isEmpty else { return nil }
        return PlanLimits(planName: nil, windows: windows)
    }

    /// The structured envelope: groups of models sharing a weekly and a
    /// 5-hour bucket. `remaining_fraction` is what is left, so the usage
    /// panel's percent is the complement.
    private static func parseUsage(_ data: JSONValue?, fallback response: String?) -> [PlanLimits.Window] {
        var windows: [PlanLimits.Window] = []
        for group in data?["groups"]?.array ?? [] {
            let groupName = group["name"]?.string ?? "Models"
            for bucket in group["buckets"]?.array ?? [] {
                guard let remaining = bucket["remaining_fraction"]?.double else { continue }
                windows.append(PlanLimits.Window(
                    id: bucket["id"]?.string ?? "\(groupName)-\(windows.count)",
                    title: "\(groupName) · \(bucket["name"]?.string ?? "Limit")",
                    percent: max(0, min(100, (1 - remaining) * 100)),
                    resetsAt: bucket["reset_time"]?.string.flatMap(ISO8601DateFormatter().date(from:))
                ))
            }
        }
        if windows.isEmpty, let response { windows += parseUsageText(response) }
        return windows
    }

    /// Older CLIs without the structured envelope: `Group<TAB>Bucket<TAB>95%<TAB><ISO date>`
    /// rows, where the percent is what remains.
    private static func parseUsageText(_ response: String) -> [PlanLimits.Window] {
        var windows: [PlanLimits.Window] = []
        for line in response.components(separatedBy: .newlines) {
            let parts = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { continue }
            let percentText = parts[2].replacingOccurrences(of: "%", with: "")
            guard let remaining = Double(percentText) else { continue }
            let reset = parts.count >= 4 ? ISO8601DateFormatter().date(from: parts[3]) : nil
            windows.append(PlanLimits.Window(
                id: "usage-\(windows.count)",
                title: "\(parts[0]) · \(parts[1])",
                percent: max(0, min(100, 100 - remaining)),
                resetsAt: reset
            ))
        }
        return windows
    }

    private static func parseCredits(_ data: JSONValue?, fallback response: String?) -> PlanLimits.Window? {
        if let remaining = data?["remaining_credits"]?.int {
            return PlanLimits.Window(
                id: "ai-credits",
                title: "AI credits · \(remaining) remaining",
                percent: remaining > 0 ? 0 : 100,
                resetsAt: nil
            )
        }
        guard let response else { return nil }
        for line in response.components(separatedBy: .newlines) {
            let parts = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, parts[0].localizedCaseInsensitiveContains("credit"),
                  let remaining = Int(parts[1]) else { continue }
            return PlanLimits.Window(
                id: "ai-credits",
                title: "AI credits · \(remaining) remaining",
                percent: remaining > 0 ? 0 : 100,
                resetsAt: nil
            )
        }
        return nil
    }

    // MARK: - Tool mapping

    private func makeToolCall(name: String, parameters: JSONValue) -> ToolCall {
        let kind = Self.kind(of: name)
        var title: String?
        if kind == .command {
            title = parameters["CommandLine"]?.string ?? parameters["command"]?.string
        } else {
            title = Self.path(in: parameters).map { ToolTitles.relativePath($0, to: workingDirectory) }
            if title == nil {
                title = parameters["Query"]?.string ?? parameters["query"]?.string
                    ?? parameters["Url"]?.string ?? parameters["URL"]?.string ?? parameters["url"]?.string
            }
        }
        var call = ToolCall(kind: kind, title: title ?? Self.humanize(name))
        let detail = parameters.isNull ? nil : parameters.compactString
        if let detail, !detail.isEmpty, detail != "{}", detail.count <= 300 { call.detail = detail }
        return call
    }

    private static func kind(of name: String) -> ToolCall.Kind {
        switch name {
        case "run_command", "send_command_input", "command_status", "wait", "wait_5_seconds", "schedule":
            .command
        case "view_file", "read_resource", "read_browser_page", "capture_browser_screenshot", "capture_browser_console_logs":
            .read
        case "write_to_file", "replace_file_content", "multi_replace_file_content", "sed_file", "notebook_edit", "notebook_execution":
            .edit
        case "list_dir", "grep_search", "find_by_name", "list_resources", "list_browser_pages":
            .search
        case "search_web", "read_url_content", "open_browser_url", "browser_click_element", "browser_drag_pixel_to_pixel",
             "browser_get_dom", "browser_get_network_request", "browser_input", "browser_list_network_requests",
             "browser_mouse_down", "browser_mouse_up", "browser_move_mouse", "browser_press_key", "browser_refresh_page",
             "browser_resize_window", "browser_scroll", "browser_scroll_dom", "browser_select_option", "click_browser_pixel",
             "execute_browser_javascript":
            .web
        case "invoke_subagent", "browser_subagent", "define_subagent", "manage_subagents":
            .agent
        case "call_mcp_tool":
            .mcp
        default:
            .other
        }
    }

    private static func path(in parameters: JSONValue) -> String? {
        for key in ["FilePath", "DirectoryPath", "Path", "file", "path", "directory", "dir"] {
            if let value = parameters[key]?.string, !value.isEmpty { return value }
        }
        return nil
    }

    private static func humanize(_ name: String) -> String {
        let words = name.split(separator: "_").map(String.init)
        guard let first = words.first else { return name }
        return ([first.capitalized] + words.dropFirst()).joined(separator: " ")
    }
}
