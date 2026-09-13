import Foundation

/// Drives `codex app-server` over JSON-RPC.
@MainActor
final class CodexSession: ProviderSession {
    var onEvent: ((ProviderEvent) -> Void)?

    private enum PendingRequest {
        case decision(RPCID, payloads: [String: JSONValue])
        case permissions(RPCID, requested: JSONValue)
        case question(RPCID)
    }

    private struct PolicySettings {
        var approvalPolicy: JSONValue
        var sandbox: JSONValue
        var sandboxPolicy: JSONValue
        var reviewer: JSONValue
    }

    private let configuration: SessionConfiguration
    private var connection: JSONRPCConnection?
    private var threadID: String?
    private var turnID: String?
    private var activeModel: String?
    private var pendingRequests: [String: PendingRequest] = [:]
    private var isStopping = false

    init(configuration: SessionConfiguration) {
        self.configuration = configuration
    }

    var isRunning: Bool {
        guard let connection else { return false }
        return !connection.isClosed
    }

    private var workingDirectory: String { configuration.workingDirectory.path }

    func start() async throws -> String {
        let connection = try await Self.connect(
            executable: configuration.executable,
            directory: configuration.workingDirectory,
            environment: configuration.environment
        ) { [weak self] connection in
            connection.onNotification = { self?.handleNotification($0, $1) }
            connection.onRequest = { self?.handleRequest($0, $1, $2) }
            connection.onClose = { self?.handleClose($0) }
        }
        self.connection = connection

        let policy = policySettings(configuration.runtimeMode)
        var params: [String: JSONValue] = [
            "cwd": .string(workingDirectory),
            "approvalPolicy": policy.approvalPolicy,
            "sandbox": policy.sandbox,
            "approvalsReviewer": policy.reviewer,
        ]
        if let model = configuration.model { params["model"] = .string(model) }

        if let resumeID = configuration.resumeID {
            var resume = params
            resume["threadId"] = .string(resumeID)
            resume["excludeTurns"] = true
            if let result = try? await connection.request("thread/resume", .object(resume)),
               let id = result["thread"]?["id"]?.string {
                threadID = id
                activeModel = result["model"]?.string
                return id
            }
        }
        let result = try await connection.request("thread/start", .object(params))
        guard let id = result["thread"]?["id"]?.string else {
            throw ProviderError.failed("Codex did not start a thread.")
        }
        threadID = id
        activeModel = result["model"]?.string
        return id
    }

    func send(_ input: TurnInput) async throws {
        guard let connection, !connection.isClosed, let threadID else { throw ProviderError.notRunning }
        var content: [JSONValue] = [["type": "text", "text": .string(input.text)]]
        for image in input.images where image.isImage {
            content.append(["type": "localImage", "path": .string(image.path)])
        }
        let policy = policySettings(input.runtimeMode)
        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array(content),
            "approvalPolicy": policy.approvalPolicy,
            "approvalsReviewer": policy.reviewer,
            "sandboxPolicy": policy.sandboxPolicy,
            "summary": "auto",
        ]
        let effort = input.effort.flatMap { $0.isEmpty ? nil : $0 }
        if let effort { params["effort"] = .string(effort) }
        if let tier = input.serviceTier { params["serviceTierForTurn"] = .string(tier) }
        if let model = input.model ?? activeModel {
            params["model"] = .string(model)
            params["collaborationMode"] = [
                "mode": input.interactionMode == .plan ? "plan" : "default",
                "settings": [
                    "model": .string(model),
                    "reasoning_effort": .optional(effort),
                    "developer_instructions": .null,
                ],
            ]
        }
        let result = try await connection.request("turn/start", .object(params))
        if let id = result["turn"]?["id"]?.string { turnID = id }
    }

    func interrupt() async {
        guard let connection, let threadID, let turnID else { return }
        _ = try? await connection.request("turn/interrupt", [
            "threadId": .string(threadID),
            "turnId": .string(turnID),
        ])
    }

    func compact() async throws {
        guard let connection, let threadID else { throw ProviderError.notRunning }
        _ = try await connection.request("thread/compact/start", ["threadId": .string(threadID)])
    }

    /// Drops the most recent turns from Codex's own history.
    func rollback(turns: Int) async throws {
        guard let connection, let threadID, turns > 0 else { return }
        _ = try await connection.request("thread/rollback", [
            "threadId": .string(threadID),
            "numTurns": .int(turns),
        ])
    }

    func resolveApproval(_ requestID: String, optionID: String) {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return }
        switch pending {
        case .decision(let id, let payloads):
            connection?.respond(to: id, result: ["decision": payloads[optionID] ?? "cancel"])
        case .permissions(let id, let requested):
            if optionID == "turn" || optionID == "session" {
                connection?.respond(to: id, result: ["permissions": requested, "scope": .string(optionID)])
            } else {
                connection?.respond(to: id, result: ["permissions": [:], "scope": "turn"])
            }
        case .question(let id):
            connection?.respond(to: id, result: ["answers": [:]])
        }
        onEvent?(.requestResolved(id: requestID))
    }

    func answerQuestion(_ requestID: String, answers: [String: [String]]) {
        guard case .question(let id)? = pendingRequests.removeValue(forKey: requestID) else { return }
        var payload: [String: JSONValue] = [:]
        for (questionID, values) in answers {
            payload[questionID] = ["answers": .array(values.map(JSONValue.string))]
        }
        connection?.respond(to: id, result: ["answers": .object(payload)])
        onEvent?(.requestResolved(id: requestID))
    }

    func stop() {
        isStopping = true
        connection?.close()
    }

    // MARK: - Catalog

    static func listModels(executable: URL, environment: [String: String]) async throws -> [ModelOption] {
        let connection = try await connect(
            executable: executable,
            directory: FileManager.default.temporaryDirectory,
            environment: environment,
            configure: { _ in }
        )
        defer { connection.close() }
        var models: [ModelOption] = []
        var cursor: JSONValue = .null
        for _ in 0..<10 {
            var params: [String: JSONValue] = [:]
            if !cursor.isNull { params["cursor"] = cursor }
            let result = try await connection.request("model/list", .object(params))
            for model in result["data"]?.array ?? [] where model["hidden"]?.bool != true {
                guard let id = model["id"]?.string else { continue }
                models.append(ModelOption(
                    id: id,
                    name: model["displayName"]?.string ?? id,
                    detail: model["description"]?.string,
                    efforts: (model["supportedReasoningEfforts"]?.array ?? []).compactMap { $0["reasoningEffort"]?.string },
                    defaultEffort: model["defaultReasoningEffort"]?.string,
                    isDefault: model["isDefault"]?.bool ?? false,
                    fastTier: fastTier(in: model["serviceTiers"]?.array ?? [])
                ))
            }
            cursor = result["nextCursor"] ?? .null
            if cursor.isNull { break }
        }
        return models
    }

    /// The account's rate-limit windows, such as the 5-hour and weekly limits, or a monthly one on some plans.
    static func readPlanLimits(executable: URL, environment: [String: String]) async throws -> PlanLimits? {
        let connection = try await connect(
            executable: executable,
            directory: FileManager.default.temporaryDirectory,
            environment: environment,
            configure: { _ in }
        )
        defer { connection.close() }
        let result = try await connection.request("account/rateLimits/read", ["excludeResetCreditDetails": true])
        var snapshots: [JSONValue] = []
        if let byID = result["rateLimitsByLimitId"]?.object, !byID.isEmpty {
            snapshots = byID.keys.sorted().compactMap { byID[$0] }
        } else if let snapshot = result["rateLimits"], !snapshot.isNull {
            snapshots = [snapshot]
        }
        var plan: String?
        var windows: [PlanLimits.Window] = []
        for snapshot in snapshots {
            plan = plan ?? snapshot["planType"]?.string
            let name = snapshots.count > 1 ? snapshot["limitName"]?.string : nil
            for key in ["primary", "secondary"] {
                guard let window = snapshot[key], let percent = window["usedPercent"]?.double else { continue }
                var title = PlanLimitsReader.windowTitle(minutes: window["windowDurationMins"]?.int)
                if let name { title += " · \(name)" }
                windows.append(PlanLimits.Window(
                    id: "\(snapshot["limitId"]?.string ?? "codex")-\(key)",
                    title: title,
                    percent: percent,
                    resetsAt: window["resetsAt"]?.double.map { Date(timeIntervalSince1970: $0) }
                ))
            }
        }
        guard !windows.isEmpty else { return nil }
        return PlanLimits(planName: PlanLimitsReader.planName(plan), windows: windows)
    }

    /// The tier Codex offers for faster responses on a model, if any.
    private static func fastTier(in tiers: [JSONValue]) -> String? {
        tiers.lazy.compactMap { tier -> String? in
            guard let id = tier["id"]?.string else { return nil }
            let label = "\(id) \(tier["name"]?.string ?? "")".lowercased()
            return label.contains("fast") || label.contains("priority") ? id : nil
        }.first
    }

    private static func connect(
        executable: URL,
        directory: URL,
        environment: [String: String],
        configure: (JSONRPCConnection) -> Void
    ) async throws -> JSONRPCConnection {
        let process = StdioProcess(executable: executable, arguments: ["app-server"], directory: directory, environment: environment)
        let connection = JSONRPCConnection(process: process, sendsVersion: false)
        configure(connection)
        try connection.start()
        _ = try await connection.request("initialize", [
            "clientInfo": ["name": "cody", "title": "Cody", "version": .string(AppInfo.version)],
            "capabilities": ["experimentalApi": true],
        ])
        connection.notify("initialized")
        return connection
    }

    // MARK: - Notifications

    private func handleNotification(_ method: String, _ params: JSONValue) {
        if let eventThread = params["threadId"]?.string, let threadID, eventThread != threadID { return }
        switch method {
        case "turn/started":
            turnID = params["turn"]?["id"]?.string
            onEvent?(.turnStarted(providerTurnID: turnID))
        case "item/started":
            if let item = params["item"] { itemStarted(item) }
        case "item/completed":
            if let item = params["item"] { itemCompleted(item) }
        case "item/agentMessage/delta":
            if let id = params["itemId"]?.string, let delta = params["delta"]?.string {
                onEvent?(.messageDelta(id: id, text: delta))
            }
        case "item/reasoning/summaryTextDelta", "item/reasoning/textDelta":
            if let id = params["itemId"]?.string, let delta = params["delta"]?.string {
                onEvent?(.reasoningDelta(id: id, text: delta))
            }
        case "item/reasoning/summaryPartAdded":
            if let id = params["itemId"]?.string, let index = params["summaryIndex"]?.int, index > 0 {
                onEvent?(.reasoningDelta(id: id, text: "\n\n"))
            }
        case "item/commandExecution/outputDelta":
            if let id = params["itemId"]?.string, let delta = params["delta"]?.string {
                onEvent?(.toolOutput(id: id, text: delta))
            }
        case "item/plan/delta":
            if let id = params["itemId"]?.string, let delta = params["delta"]?.string {
                onEvent?(.planDelta(id: id, text: delta))
            }
        case "turn/plan/updated":
            let steps = (params["plan"]?.array ?? []).compactMap { step -> TodoStep? in
                guard let text = step["step"]?.string else { return nil }
                let status: TodoStep.Status = switch step["status"]?.string {
                case "completed": .done
                case "inProgress": .active
                default: .pending
                }
                return TodoStep(text: text, status: status)
            }
            onEvent?(.todos(steps))
        case "turn/diff/updated":
            if let diff = params["diff"]?.string { onEvent?(.diff(diff)) }
        case "thread/tokenUsage/updated":
            if let usage = params["tokenUsage"], let last = usage["last"] {
                let used = last["totalTokens"]?.int ?? 0
                onEvent?(.usage(ContextUsage(usedTokens: used, windowTokens: usage["modelContextWindow"]?.int)))
            }
        case "error":
            if params["willRetry"]?.bool == true {
                let message = Self.errorMessage(params["error"])
                onEvent?(.notice(Notice(level: .warning, message: "\(message) Retrying.")))
            }
        case "turn/completed":
            let turn = params["turn"]
            let status: TurnStatus = switch turn?["status"]?.string {
            case "interrupted": .interrupted
            case "failed": .failed
            default: .completed
            }
            let error = turn?["error"].flatMap { $0.isNull ? nil : Self.errorMessage($0) }
            turnID = nil
            onEvent?(.turnCompleted(status: status, error: error))
        case "serverRequest/resolved":
            if let raw = params["requestId"], let id = RPCID(raw), pendingRequests.removeValue(forKey: id.key) != nil {
                onEvent?(.requestResolved(id: id.key))
            }
        case "thread/compacted":
            onEvent?(.notice(Notice(level: .info, message: "Context compacted.")))
        default:
            break
        }
    }

    private func itemStarted(_ item: JSONValue) {
        guard let id = item["id"]?.string else { return }
        switch item["type"]?.string {
        case "agentMessage":
            onEvent?(.messageDelta(id: id, text: item["text"]?.string ?? ""))
        case "reasoning":
            onEvent?(.reasoningDelta(id: id, text: ""))
        case "plan":
            onEvent?(.planDelta(id: id, text: item["text"]?.string ?? ""))
        case "userMessage", "hookPrompt", "functionCallOutput", "contextCompaction":
            break
        default:
            if let call = toolCall(from: item) { onEvent?(.toolStarted(id: id, call: call)) }
        }
    }

    private func itemCompleted(_ item: JSONValue) {
        guard let id = item["id"]?.string else { return }
        switch item["type"]?.string {
        case "agentMessage":
            onEvent?(.messageCompleted(id: id, text: item["text"]?.string ?? ""))
        case "reasoning":
            let summary = (item["summary"]?.array ?? []).compactMap(\.string).joined(separator: "\n\n")
            let content = (item["content"]?.array ?? []).compactMap(\.string).joined(separator: "\n\n")
            onEvent?(.reasoningCompleted(id: id, text: summary.isEmpty ? content : summary))
        case "plan":
            onEvent?(.planCompleted(id: id, markdown: item["text"]?.string ?? ""))
        case "userMessage", "hookPrompt", "functionCallOutput", "contextCompaction":
            break
        default:
            if let call = toolCall(from: item) {
                onEvent?(.toolStarted(id: id, call: call))
                onEvent?(.toolUpdated(id: id, update: toolUpdate(from: item)))
            }
        }
    }

    private func toolCall(from item: JSONValue) -> ToolCall? {
        switch item["type"]?.string {
        case "commandExecution":
            let command = ToolTitles.unwrapShell(item["command"]?.string ?? "")
            let actions = item["commandActions"]?.array ?? []
            let kinds = Set(actions.compactMap { $0["type"]?.string })
            if kinds == ["read"], let path = actions.first?["path"]?.string {
                return ToolCall(kind: .read, title: ToolTitles.relativePath(path, to: workingDirectory), detail: command)
            }
            if !kinds.isEmpty, kinds.isSubset(of: ["search", "listFiles"]) {
                return ToolCall(kind: .search, title: command)
            }
            return ToolCall(kind: .command, title: command)
        case "fileChange":
            let paths = (item["changes"]?.array ?? []).compactMap { $0["path"]?.string }
            let title = paths.count == 1 ? ToolTitles.relativePath(paths[0], to: workingDirectory) : "Edit \(paths.count) files"
            return ToolCall(kind: .edit, title: title)
        case "mcpToolCall":
            let server = item["server"]?.string ?? "MCP"
            let tool = item["tool"]?.string ?? "tool"
            let arguments = item["arguments"].map(\.compactString)
            return ToolCall(kind: .mcp, title: "\(server) · \(tool)", detail: arguments == "null" ? nil : arguments)
        case "dynamicToolCall":
            return ToolCall(kind: .other, title: item["tool"]?.string ?? "Tool")
        case "webSearch":
            return ToolCall(kind: .web, title: item["query"]?.string ?? "Web search")
        case "collabAgentToolCall":
            return ToolCall(kind: .agent, title: item["prompt"]?.string ?? "Agent", detail: item["tool"]?.string)
        case "subAgentActivity":
            return ToolCall(kind: .agent, title: item["agentPath"]?.string ?? "Subagent")
        case "imageView":
            return ToolCall(kind: .read, title: ToolTitles.relativePath(item["path"]?.string ?? "Image", to: workingDirectory))
        case "imageGeneration":
            return ToolCall(kind: .other, title: item["revisedPrompt"]?.string ?? "Generate image")
        case "enteredReviewMode", "exitedReviewMode":
            return ToolCall(kind: .other, title: "Review", detail: item["review"]?.string)
        default:
            return nil
        }
    }

    private func toolUpdate(from item: JSONValue) -> ToolUpdate {
        var update = ToolUpdate()
        let rawStatus = item["status"]?.string
        switch item["type"]?.string {
        case "commandExecution":
            update.output = item["aggregatedOutput"]?.string
            update.exitCode = item["exitCode"]?.int
            update.status = Self.toolStatus(rawStatus, exitCode: update.exitCode)
        case "fileChange":
            let changes: [JSONValue] = item["changes"]?.array ?? []
            let edits = changes.map { (change: JSONValue) -> FileEdit in
                let diff: String? = change["diff"]?.string
                let stats = ToolTitles.diffStats(diff ?? "")
                let path = ToolTitles.relativePath(change["path"]?.string ?? "", to: workingDirectory)
                return FileEdit(path: path, diff: diff, additions: stats.additions, deletions: stats.deletions)
            }
            update.edits = edits
            update.status = Self.toolStatus(rawStatus, exitCode: nil)
        case "mcpToolCall":
            if let message = item["error"]?["message"]?.string {
                update.output = message
            } else if let content = item["result"]?["content"]?.array {
                update.output = content.compactMap { $0["text"]?.string }.joined(separator: "\n")
            }
            update.status = Self.toolStatus(rawStatus, exitCode: nil)
        case "webSearch", "imageView", "enteredReviewMode", "exitedReviewMode":
            update.status = .completed
        default:
            update.status = Self.toolStatus(rawStatus, exitCode: nil)
        }
        return update
    }

    private static func toolStatus(_ raw: String?, exitCode: Int?) -> ToolCall.Status {
        switch raw {
        case "inProgress": return .running
        case "failed", "interrupted": return .failed
        case "declined": return .declined
        default:
            if let exitCode, exitCode != 0 { return .failed }
            return .completed
        }
    }

    static func errorMessage(_ error: JSONValue?) -> String {
        guard let error else { return "Codex reported an error." }
        let raw = error["message"]?.string ?? error.displayText
        if let nested = JSONValue.parse(raw),
           let message = nested["error"]?["message"]?.string ?? nested["message"]?.string {
            return message
        }
        return raw
    }

    // MARK: - Requests

    private func handleRequest(_ id: RPCID, _ method: String, _ params: JSONValue) {
        switch method {
        case "item/commandExecution/requestApproval":
            let (options, payloads) = decisionOptions(params["availableDecisions"]?.array, command: true)
            pendingRequests[id.key] = .decision(id, payloads: payloads)
            let command = params["command"]?.string.map(ToolTitles.unwrapShell) ?? "Command"
            onEvent?(.approval(ApprovalRequest(
                id: id.key,
                kind: .command,
                title: command,
                detail: params["cwd"]?.string.map { ToolTitles.relativePath($0, to: workingDirectory) },
                reason: params["reason"]?.string,
                options: options,
                toolItemID: params["itemId"]?.string
            )))
        case "item/fileChange/requestApproval":
            let (options, payloads) = decisionOptions(nil, command: false)
            pendingRequests[id.key] = .decision(id, payloads: payloads)
            onEvent?(.approval(ApprovalRequest(
                id: id.key,
                kind: .fileChange,
                title: "Apply file changes",
                detail: params["grantRoot"]?.string,
                reason: params["reason"]?.string,
                options: options,
                toolItemID: params["itemId"]?.string
            )))
        case "item/permissions/requestApproval":
            let requested = params["permissions"] ?? [:]
            pendingRequests[id.key] = .permissions(id, requested: requested)
            onEvent?(.approval(ApprovalRequest(
                id: id.key,
                kind: .permissions,
                title: Self.describePermissions(requested),
                detail: nil,
                reason: params["reason"]?.string,
                options: [
                    .init(id: "turn", title: "Allow once", role: .approve),
                    .init(id: "session", title: "Allow for session", role: .approveAlways),
                    .init(id: "decline", title: "Decline", role: .decline),
                ],
                toolItemID: params["itemId"]?.string
            )))
        case "item/tool/requestUserInput":
            let questions = (params["questions"]?.array ?? []).compactMap { question -> QuestionRequest.Question? in
                guard let questionID = question["id"]?.string else { return nil }
                return QuestionRequest.Question(
                    id: questionID,
                    header: question["header"]?.string ?? "",
                    prompt: question["question"]?.string ?? "",
                    choices: (question["options"]?.array ?? []).compactMap { option in
                        option["label"]?.string.map { QuestionRequest.Choice(label: $0, detail: option["description"]?.string) }
                    },
                    allowsMultiple: false,
                    allowsOther: question["isOther"]?.bool ?? false,
                    isSecret: question["isSecret"]?.bool ?? false
                )
            }
            pendingRequests[id.key] = .question(id)
            onEvent?(.question(QuestionRequest(id: id.key, questions: questions)))
        case "mcpServer/elicitation/request":
            connection?.respond(to: id, result: ["action": "decline"])
            let server = params["serverName"]?.string ?? "An MCP server"
            onEvent?(.notice(Notice(level: .warning, message: "\(server) asked for input, which Cody cannot show yet.")))
        default:
            connection?.respond(to: id, errorCode: -32601, message: "Cody does not support \(method).")
        }
    }

    private func decisionOptions(_ available: [JSONValue]?, command: Bool) -> ([ApprovalRequest.Option], [String: JSONValue]) {
        let decisions = available ?? ["accept", "acceptForSession", "decline", "cancel"]
        var options: [ApprovalRequest.Option] = []
        var payloads: [String: JSONValue] = [:]
        for decision in decisions {
            if let name = decision.string {
                let option: ApprovalRequest.Option? = switch name {
                case "accept": .init(id: name, title: "Approve", role: .approve)
                case "acceptForSession": .init(id: name, title: "Approve for session", role: .approveAlways)
                case "decline": .init(id: name, title: "Decline", role: .decline)
                case "cancel": .init(id: name, title: "Stop turn", role: .cancel)
                default: nil
                }
                if let option {
                    options.append(option)
                    payloads[name] = decision
                }
            } else if command, decision["acceptWithExecpolicyAmendment"] != nil {
                options.append(.init(id: "amend", title: "Always allow", role: .approveAlways))
                payloads["amend"] = decision
            }
        }
        let order: [ApprovalRequest.Option.Role] = [.approve, .approveAlways, .decline, .cancel]
        options.sort { (order.firstIndex(of: $0.role) ?? 0) < (order.firstIndex(of: $1.role) ?? 0) }
        return (options, payloads)
    }

    private static func describePermissions(_ permissions: JSONValue) -> String {
        var parts: [String] = []
        if let write = permissions["fileSystem"]?["write"]?.array, !write.isEmpty {
            parts.append("Write to " + write.compactMap(\.string).joined(separator: ", "))
        }
        if let read = permissions["fileSystem"]?["read"]?.array, !read.isEmpty {
            parts.append("Read " + read.compactMap(\.string).joined(separator: ", "))
        }
        if permissions["network"]?["enabled"]?.bool == true {
            parts.append("Network access")
        }
        return parts.isEmpty ? "Additional permissions" : parts.joined(separator: " · ")
    }

    private func handleClose(_ tail: String) {
        let resolved = Array(pendingRequests.keys)
        pendingRequests.removeAll()
        for key in resolved { onEvent?(.requestResolved(id: key)) }
        guard !isStopping else { return }
        onEvent?(.exited(error: TextCleanup.lastLines(tail)))
    }

    private func policySettings(_ mode: RuntimeMode) -> PolicySettings {
        switch mode {
        case .supervised:
            PolicySettings(approvalPolicy: "untrusted", sandbox: "read-only", sandboxPolicy: ["type": "readOnly"], reviewer: "user")
        case .autoAcceptEdits:
            PolicySettings(approvalPolicy: "on-request", sandbox: "workspace-write", sandboxPolicy: ["type": "workspaceWrite"], reviewer: "user")
        case .auto:
            PolicySettings(approvalPolicy: "on-request", sandbox: "workspace-write", sandboxPolicy: ["type": "workspaceWrite"], reviewer: "auto_review")
        case .fullAccess:
            PolicySettings(approvalPolicy: "never", sandbox: "danger-full-access", sandboxPolicy: ["type": "dangerFullAccess"], reviewer: "user")
        }
    }
}
