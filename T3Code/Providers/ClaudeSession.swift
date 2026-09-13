import Foundation

/// Drives Claude Code in headless stream-json mode, routing permission prompts to the app.
@MainActor
final class ClaudeSession: ProviderSession {
    var onEvent: ((ProviderEvent) -> Void)?

    private struct PendingTool {
        var name: String
        var input: JSONValue
        var suggestions: JSONValue?
    }

    private let configuration: SessionConfiguration
    private var process: StdioProcess?
    private var readTask: Task<Void, Never>?
    private var sessionID: String?
    private var permissionMode: String
    private var runtimeMode: RuntimeMode
    private var model: String?
    private var controlCounter = 0
    private var pendingControl: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingTools: [String: PendingTool] = [:]
    private var toolNames: [String: String] = [:]
    private var openText: [String: [String]] = [:]
    private var openThinking: [String: [String]] = [:]
    private var blockIDs: [Int: String] = [:]
    private var currentMessageID: String?
    private var turnActive = false
    private var interruptRequested = false
    private var isStopping = false

    init(configuration: SessionConfiguration) {
        self.configuration = configuration
        runtimeMode = configuration.runtimeMode
        permissionMode = Self.modeName(configuration.runtimeMode, configuration.interactionMode)
        model = configuration.model
    }

    var isRunning: Bool { process?.isRunning ?? false }

    private var workingDirectory: String { configuration.workingDirectory.path }

    func start() async throws -> String {
        let id = configuration.resumeID ?? UUID().uuidString.lowercased()
        var arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--permission-prompt-tool", "stdio",
            "--setting-sources", "user,project,local",
            "--allow-dangerously-skip-permissions", "--permission-mode", permissionMode,
        ]
        if let model = configuration.model, model != "default" { arguments += ["--model", model] }
        if let effort = configuration.effort, !effort.isEmpty { arguments += ["--effort", effort] }
        if let resumeID = configuration.resumeID {
            arguments += ["--resume", resumeID]
            if let anchor = configuration.resumeAt { arguments += ["--resume-session-at", anchor] }
        } else {
            arguments += ["--session-id", id]
        }

        let process = StdioProcess(
            executable: configuration.executable,
            arguments: arguments,
            directory: configuration.workingDirectory,
            environment: configuration.environment
        )
        self.process = process
        try process.start()
        let messages = process.messages
        readTask = Task { [weak self] in
            for await message in messages {
                guard let self else { return }
                self.handle(message)
            }
            self?.didClose()
        }

        sessionID = id
        let initialization = try await control(["subtype": "initialize", "hooks": .null])
        let models = (initialization["models"]?.array ?? []).compactMap { entry -> ModelOption? in
            guard let value = entry["value"]?.string else { return nil }
            return ModelOption(
                id: value,
                name: entry["displayName"]?.string ?? value,
                detail: entry["description"]?.string,
                efforts: (entry["supportedEffortLevels"]?.array ?? []).compactMap(\.string),
                isDefault: value == "default"
            )
        }
        if !models.isEmpty { onEvent?(.models(models, current: configuration.model)) }
        let commands = (initialization["commands"]?.array ?? []).compactMap { entry -> SlashCommand? in
            guard let name = entry["name"]?.string else { return nil }
            return SlashCommand(name: name, detail: entry["description"]?.string ?? "")
        }
        if !commands.isEmpty { onEvent?(.commands(commands)) }
        return id
    }

    func send(_ input: TurnInput) async throws {
        guard let process, process.isRunning else { throw ProviderError.notRunning }
        runtimeMode = input.runtimeMode
        let mode = Self.modeName(input.runtimeMode, input.interactionMode)
        if mode != permissionMode {
            _ = try? await control(["subtype": "set_permission_mode", "mode": .string(mode)])
            permissionMode = mode
        }
        if input.model != model {
            let wire = input.model == "default" ? nil : input.model
            _ = try? await control(["subtype": "set_model", "model": .optional(wire)])
            model = input.model
        }
        var content: [JSONValue] = []
        for image in input.images where image.isImage {
            guard let data = try? Data(contentsOf: image.url) else { continue }
            content.append([
                "type": "image",
                "source": ["type": "base64", "media_type": .string(image.mimeType), "data": .string(data.base64EncodedString())],
            ])
        }
        content.append(["type": "text", "text": .string(input.text)])
        writeUserMessage(.array(content))
    }

    func interrupt() async {
        guard turnActive else { return }
        interruptRequested = true
        for requestID in pendingTools.keys {
            sendToolResponse(requestID, ["behavior": "deny", "message": "The user stopped the turn.", "interrupt": true])
            onEvent?(.requestResolved(id: requestID))
        }
        pendingTools.removeAll()
        _ = try? await control(["subtype": "interrupt"])
    }

    func compact() async throws {
        guard let process, process.isRunning else { throw ProviderError.notRunning }
        writeUserMessage("/compact")
    }

    func resolveApproval(_ requestID: String, optionID: String) {
        guard let pending = pendingTools.removeValue(forKey: requestID) else { return }
        if optionID == "allow" || optionID == "always" {
            var response: [String: JSONValue] = ["behavior": "allow", "updatedInput": pending.input]
            if optionID == "always", let suggestions = pending.suggestions?.array {
                response["updatedPermissions"] = .array(suggestions.map(Self.sessionScoped))
            }
            sendToolResponse(requestID, .object(response))
            if pending.name == "ExitPlanMode" {
                onEvent?(.modeChanged(.build))
                let mode = Self.modeName(runtimeMode, .build)
                permissionMode = mode
                Task { _ = try? await self.control(["subtype": "set_permission_mode", "mode": .string(mode)]) }
            }
        } else {
            let message = pending.name == "ExitPlanMode"
                ? "The user wants to keep planning. Wait for their feedback before changing anything."
                : "The user declined this action."
            sendToolResponse(requestID, ["behavior": "deny", "message": .string(message)])
        }
        onEvent?(.requestResolved(id: requestID))
    }

    func answerQuestion(_ requestID: String, answers: [String: [String]]) {
        guard let pending = pendingTools.removeValue(forKey: requestID) else { return }
        var input = pending.input.object ?? [:]
        var mapped: [String: JSONValue] = [:]
        for (question, values) in answers {
            mapped[question] = .string(values.joined(separator: ", "))
        }
        input["answers"] = .object(mapped)
        sendToolResponse(requestID, ["behavior": "allow", "updatedInput": .object(input)])
        onEvent?(.requestResolved(id: requestID))
    }

    func stop() {
        isStopping = true
        process?.terminate()
    }

    // MARK: - Wire

    private func control(_ request: JSONValue) async throws -> JSONValue {
        guard let process else { throw ProviderError.notRunning }
        controlCounter += 1
        let requestID = "t3code-\(controlCounter)"
        return try await withCheckedThrowingContinuation { continuation in
            pendingControl[requestID] = continuation
            process.send(["type": "control_request", "request_id": .string(requestID), "request": request])
        }
    }

    private func writeUserMessage(_ content: JSONValue) {
        turnActive = true
        interruptRequested = false
        onEvent?(.turnStarted(providerTurnID: nil))
        process?.send([
            "type": "user",
            "session_id": "",
            "message": ["role": "user", "content": content],
            "parent_tool_use_id": .null,
        ])
    }

    private func sendToolResponse(_ requestID: String, _ response: JSONValue) {
        process?.send([
            "type": "control_response",
            "response": ["subtype": "success", "request_id": .string(requestID), "response": response],
        ])
    }

    private func handle(_ message: JSONValue) {
        let isTopLevel = message["parent_tool_use_id"]?.isNull ?? true
        switch message["type"]?.string {
        case "control_response":
            let response = message["response"] ?? .null
            guard let requestID = response["request_id"]?.string,
                  let continuation = pendingControl.removeValue(forKey: requestID) else { return }
            if response["subtype"]?.string == "error" {
                continuation.resume(throwing: ProviderError.failed(response["error"]?.string ?? "Claude rejected the request."))
            } else {
                continuation.resume(returning: response["response"] ?? .null)
            }
        case "control_request":
            handleControlRequest(message)
        case "control_cancel_request":
            if let requestID = message["request_id"]?.string, pendingTools.removeValue(forKey: requestID) != nil {
                onEvent?(.requestResolved(id: requestID))
            }
        case "system":
            handleSystem(message)
        case "stream_event":
            if isTopLevel { handleStreamEvent(message["event"] ?? .null) }
        case "assistant":
            if isTopLevel { handleAssistant(message) }
        case "user":
            if isTopLevel { handleToolResults(message) }
        case "result":
            handleResult(message)
        case "rate_limit_event":
            if message["rate_limit_info"]?["status"]?.string == "rejected" {
                onEvent?(.notice(Notice(level: .warning, message: "Claude hit a usage limit. The turn continues when the limit resets.")))
            }
        default:
            break
        }
    }

    private func handleSystem(_ message: JSONValue) {
        switch message["subtype"]?.string {
        case "init":
            if let id = message["session_id"]?.string, id != sessionID {
                sessionID = id
                onEvent?(.sessionReady(sessionID: id))
            }
        case "compact_boundary":
            onEvent?(.notice(Notice(level: .info, message: "Context compacted.")))
        default:
            break
        }
    }

    private func handleStreamEvent(_ event: JSONValue) {
        switch event["type"]?.string {
        case "message_start":
            currentMessageID = event["message"]?["id"]?.string ?? UUID().uuidString
            blockIDs.removeAll()
        case "content_block_start":
            guard let index = event["index"]?.int, let block = event["content_block"] else { return }
            let messageID = currentMessageID ?? "message"
            let id = "\(messageID)-\(index)"
            switch block["type"]?.string {
            case "text":
                blockIDs[index] = id
                openText[messageID, default: []].append(id)
                onEvent?(.messageDelta(id: id, text: block["text"]?.string ?? ""))
            case "thinking":
                blockIDs[index] = id
                openThinking[messageID, default: []].append(id)
                onEvent?(.reasoningDelta(id: id, text: block["thinking"]?.string ?? ""))
            case "tool_use":
                guard let toolID = block["id"]?.string, let name = block["name"]?.string else { return }
                toolNames[toolID] = name
                if let call = toolCall(name: name, input: [:]) {
                    onEvent?(.toolStarted(id: toolID, call: call))
                }
            default:
                break
            }
        case "content_block_delta":
            guard let index = event["index"]?.int, let id = blockIDs[index], let delta = event["delta"] else { return }
            switch delta["type"]?.string {
            case "text_delta":
                if let text = delta["text"]?.string { onEvent?(.messageDelta(id: id, text: text)) }
            case "thinking_delta":
                if let text = delta["thinking"]?.string { onEvent?(.reasoningDelta(id: id, text: text)) }
            default:
                break
            }
        default:
            break
        }
    }

    private func handleAssistant(_ message: JSONValue) {
        guard let body = message["message"], let content = body["content"]?.array else { return }
        let messageID = body["id"]?.string ?? UUID().uuidString
        if let uuid = message["uuid"]?.string { onEvent?(.assistantMessageID(uuid)) }
        for block in content {
            switch block["type"]?.string {
            case "text":
                let text = block["text"]?.string ?? ""
                let id = openText[messageID]?.isEmpty == false ? openText[messageID]!.removeFirst() : "\(messageID)-text-\(UUID().uuidString)"
                onEvent?(.messageCompleted(id: id, text: text))
            case "thinking":
                let text = block["thinking"]?.string ?? ""
                let id = openThinking[messageID]?.isEmpty == false ? openThinking[messageID]!.removeFirst() : "\(messageID)-thinking-\(UUID().uuidString)"
                onEvent?(.reasoningCompleted(id: id, text: text))
            case "tool_use":
                guard let toolID = block["id"]?.string, let name = block["name"]?.string else { continue }
                let input = block["input"] ?? [:]
                toolNames[toolID] = name
                if name == "TodoWrite" {
                    onEvent?(.todos(Self.todos(from: input)))
                } else if let call = toolCall(name: name, input: input) {
                    onEvent?(.toolStarted(id: toolID, call: call))
                    onEvent?(.toolUpdated(id: toolID, update: ToolUpdate(title: call.title, detail: call.detail, edits: call.edits, kind: call.kind)))
                }
            default:
                break
            }
        }
    }

    private func handleToolResults(_ message: JSONValue) {
        for block in message["message"]?["content"]?.array ?? [] where block["type"]?.string == "tool_result" {
            guard let toolID = block["tool_use_id"]?.string else { continue }
            let name = toolNames[toolID] ?? ""
            if ["AskUserQuestion", "ExitPlanMode", "EnterPlanMode", "TodoWrite", "ToolSearch"].contains(name) { continue }
            let isError = block["is_error"]?.bool ?? false
            let output = Self.resultText(block["content"])
            var status: ToolCall.Status = isError ? .failed : .completed
            if isError, output.localizedCaseInsensitiveContains("declined") || output.localizedCaseInsensitiveContains("doesn't want") {
                status = .declined
            }
            onEvent?(.toolUpdated(id: toolID, update: ToolUpdate(output: output, status: status)))
        }
    }

    private func handleResult(_ message: JSONValue) {
        turnActive = false
        if let usage = Self.contextUsage(message) { onEvent?(.usage(usage)) }
        for requestID in pendingTools.keys { onEvent?(.requestResolved(id: requestID)) }
        pendingTools.removeAll()
        openText.removeAll()
        openThinking.removeAll()
        let isError = message["is_error"]?.bool ?? (message["subtype"]?.string != "success")
        if interruptRequested {
            onEvent?(.turnCompleted(status: .interrupted, error: nil))
        } else if isError {
            let errors = (message["errors"]?.array ?? []).compactMap(\.string).joined(separator: "\n")
            let text = message["result"]?.string ?? errors
            onEvent?(.turnCompleted(status: .failed, error: text.isEmpty ? "Claude stopped before finishing." : text))
        } else {
            onEvent?(.turnCompleted(status: .completed, error: nil))
        }
        interruptRequested = false
    }

    private func handleControlRequest(_ message: JSONValue) {
        guard let requestID = message["request_id"]?.string, let request = message["request"] else { return }
        guard request["subtype"]?.string == "can_use_tool" else {
            process?.send([
                "type": "control_response",
                "response": ["subtype": "error", "request_id": .string(requestID), "error": "T3 Code does not support this request."],
            ])
            return
        }
        let name = request["tool_name"]?.string ?? "Tool"
        let input = request["input"] ?? [:]
        let toolUseID = request["tool_use_id"]?.string
        pendingTools[requestID] = PendingTool(name: name, input: input, suggestions: request["permission_suggestions"])

        switch name {
        case "AskUserQuestion":
            let questions = (input["questions"]?.array ?? []).compactMap { question -> QuestionRequest.Question? in
                guard let prompt = question["question"]?.string else { return nil }
                return QuestionRequest.Question(
                    id: prompt,
                    header: question["header"]?.string ?? "",
                    prompt: prompt,
                    choices: (question["options"]?.array ?? []).compactMap { option in
                        option["label"]?.string.map { QuestionRequest.Choice(label: $0, detail: option["description"]?.string) }
                    },
                    allowsMultiple: question["multiSelect"]?.bool ?? false,
                    allowsOther: true,
                    isSecret: false
                )
            }
            onEvent?(.question(QuestionRequest(id: requestID, questions: questions)))
        case "ExitPlanMode":
            onEvent?(.planCompleted(id: toolUseID ?? requestID, markdown: input["plan"]?.string ?? ""))
            onEvent?(.approval(ApprovalRequest(
                id: requestID,
                kind: .plan,
                title: "Implement this plan",
                options: [
                    .init(id: "allow", title: "Implement plan", role: .approve),
                    .init(id: "deny", title: "Keep planning", role: .decline),
                ],
                toolItemID: toolUseID
            )))
        default:
            let call = toolCall(name: name, input: input) ?? ToolCall(kind: .other, title: name)
            let kind: ApprovalRequest.Kind = switch call.kind {
            case .command: .command
            case .edit: .fileChange
            default: .tool
            }
            var options: [ApprovalRequest.Option] = [.init(id: "allow", title: "Approve", role: .approve)]
            if let suggestions = request["permission_suggestions"]?.array, !suggestions.isEmpty {
                options.append(.init(id: "always", title: "Approve for session", role: .approveAlways))
            }
            options.append(.init(id: "deny", title: "Decline", role: .decline))
            onEvent?(.approval(ApprovalRequest(
                id: requestID,
                kind: kind,
                title: call.title,
                detail: call.kind == .command ? request["description"]?.string : call.detail,
                reason: request["decision_reason"]?.string,
                options: options,
                toolItemID: toolUseID
            )))
        }
    }

    private func didClose() {
        let waiting = Array(pendingControl.values)
        pendingControl.removeAll()
        let tail = process?.errorTail ?? ""
        for continuation in waiting {
            continuation.resume(throwing: ProviderError.failed(TextCleanup.lastLines(tail) ?? "Claude exited."))
        }
        for requestID in pendingTools.keys { onEvent?(.requestResolved(id: requestID)) }
        pendingTools.removeAll()
        turnActive = false
        guard !isStopping else { return }
        onEvent?(.exited(error: TextCleanup.lastLines(tail)))
    }

    // MARK: - Mapping

    private func toolCall(name: String, input: JSONValue) -> ToolCall? {
        func path(_ key: String) -> String? {
            input[key]?.string.map { ToolTitles.relativePath($0, to: workingDirectory) }
        }
        switch name {
        case "TodoWrite", "AskUserQuestion", "ExitPlanMode", "EnterPlanMode", "ToolSearch":
            return nil
        case "Bash":
            return ToolCall(kind: .command, title: input["command"]?.string ?? "Shell command", detail: input["description"]?.string)
        case "BashOutput", "KillShell", "KillBash", "Monitor", "TaskOutput", "TaskStop":
            return ToolCall(kind: .command, title: name)
        case "Read":
            return ToolCall(kind: .read, title: path("file_path") ?? "Read file")
        case "Write":
            var call = ToolCall(kind: .edit, title: path("file_path") ?? "Write file")
            if let file = path("file_path"), let content = input["content"]?.string {
                call.edits = [FileEdit(path: file, old: "", new: content)]
            }
            return call
        case "Edit":
            var call = ToolCall(kind: .edit, title: path("file_path") ?? "Edit file")
            if let file = path("file_path") {
                call.edits = [FileEdit(path: file, old: input["old_string"]?.string ?? "", new: input["new_string"]?.string ?? "")]
            }
            return call
        case "MultiEdit":
            var call = ToolCall(kind: .edit, title: path("file_path") ?? "Edit file")
            if let file = path("file_path") {
                call.edits = (input["edits"]?.array ?? []).map {
                    FileEdit(path: file, old: $0["old_string"]?.string ?? "", new: $0["new_string"]?.string ?? "")
                }
            }
            return call
        case "NotebookEdit":
            return ToolCall(kind: .edit, title: path("notebook_path") ?? "Edit notebook")
        case "Glob":
            return ToolCall(kind: .search, title: input["pattern"]?.string ?? "Find files", detail: path("path"))
        case "Grep":
            return ToolCall(kind: .search, title: input["pattern"]?.string ?? "Search", detail: path("path"))
        case "LS":
            return ToolCall(kind: .search, title: path("path") ?? "List files")
        case "WebFetch":
            return ToolCall(kind: .web, title: input["url"]?.string ?? "Fetch page")
        case "WebSearch":
            return ToolCall(kind: .web, title: input["query"]?.string ?? "Search the web")
        case "Task", "Agent":
            return ToolCall(kind: .agent, title: input["description"]?.string ?? "Subagent", detail: input["subagent_type"]?.string)
        case "Skill":
            return ToolCall(kind: .other, title: "Skill · \(input["skill"]?.string ?? input["command"]?.string ?? "")")
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "__", omittingEmptySubsequences: true)
                let server = parts.count > 1 ? String(parts[1]) : "MCP"
                let tool = parts.count > 2 ? parts[2...].joined(separator: "__") : name
                return ToolCall(kind: .mcp, title: "\(server) · \(tool)", detail: input.isNull ? nil : input.compactString)
            }
            return ToolCall(kind: .other, title: name)
        }
    }

    private static func todos(from input: JSONValue) -> [TodoStep] {
        (input["todos"]?.array ?? []).compactMap { todo in
            guard let text = todo["content"]?.string else { return nil }
            let status: TodoStep.Status = switch todo["status"]?.string {
            case "completed": .done
            case "in_progress": .active
            default: .pending
            }
            return TodoStep(text: text, status: status)
        }
    }

    private static func resultText(_ content: JSONValue?) -> String {
        guard let content else { return "" }
        if let text = content.string { return text }
        return (content.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    }

    private static func contextUsage(_ message: JSONValue) -> ContextUsage? {
        guard let usage = message["usage"] else { return nil }
        let last = usage["iterations"]?.array?.last ?? usage
        let used = (last["input_tokens"]?.int ?? 0)
            + (last["cache_read_input_tokens"]?.int ?? 0)
            + (last["cache_creation_input_tokens"]?.int ?? 0)
            + (last["output_tokens"]?.int ?? 0)
        guard used > 0 else { return nil }
        let window = message["modelUsage"]?.object?.values.compactMap { $0["contextWindow"]?.int }.max()
        return ContextUsage(usedTokens: used, windowTokens: window)
    }

    private static func sessionScoped(_ suggestion: JSONValue) -> JSONValue {
        guard var object = suggestion.object else { return suggestion }
        object["destination"] = "session"
        return .object(object)
    }

    static func modeName(_ runtime: RuntimeMode, _ interaction: InteractionMode) -> String {
        if interaction == .plan { return "plan" }
        switch runtime {
        case .supervised: return "default"
        case .autoAcceptEdits: return "acceptEdits"
        case .auto: return "auto"
        case .fullAccess: return "bypassPermissions"
        }
    }
}
