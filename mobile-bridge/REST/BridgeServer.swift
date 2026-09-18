import Foundation
import Network

@MainActor
final class BridgeServer: NSObject {
    static let shared = BridgeServer()

    // MARK: - Subsystems

    private(set) var wsServer: WSServer?
    private(set) var restServer: RESTServer?
    private(set) var discovery = BridgeDiscovery()
    private(set) var pairing = BridgePairingManager()

    // MARK: - Dependencies

    private(set) var appModel: AppModel?
    private(set) var isRunning = false
    private var observer: BridgeObserver?

    // MARK: - Lifecycle

    func start(appModel: AppModel) {
        guard !isRunning else { return }
        self.appModel = appModel

        wsServer = WSServer(port: 8765, bridge: self)
        wsServer?.start()

        restServer = RESTServer(port: 8766, bridge: self)
        restServer?.start()

        discovery.start(port: 8765) { _ in }

        observer = BridgeObserver(appModel: appModel, bridge: self)
        observer?.start()

        isRunning = true
        NSLog("Bridge: started")
    }

    func stop() {
        observer?.stop()
        wsServer?.stop()
        restServer?.stop()
        discovery.stop()
        pairing.revoke()
        appModel = nil
        isRunning = false
        NSLog("Bridge: stopped")
    }

    // MARK: - Public API

    var connectedClients: Int { wsServer?.clientCount ?? 0 }

    func newPairingCode() -> String {
        pairing.generateCode()
    }

    // MARK: - Outbound

    func broadcast(_ event: BridgeEvent) {
        wsServer?.broadcast(event)
    }

    func broadcastToThread(_ threadID: UUID, _ event: BridgeEvent) {
        wsServer?.broadcast(event)
    }

    // MARK: - Inbound messages

    func handleClientMessage(_ event: BridgeEvent) {
        guard let appModel else { return }
        switch event {
        case .pair(let code):
            handlePair(code)
        case .sendMessage(let threadID, let content):
            appModel.submitPrompt(threadID, content: content)
        case .approve(let threadID, let actionID):
            appModel.approveAction(threadID, actionID: actionID)
        case .reject(let threadID, let actionID):
            appModel.rejectAction(threadID, actionID: actionID)
        case .createThread(let projectID, let prompt):
            appModel.createThread(projectID: projectID, initialPrompt: prompt)
        case .switchModel(let threadID, let model):
            appModel.switchModel(threadID, to: model)
        default:
            break
        }
    }

    private func handlePair(_ code: String) {
        guard let token = pairing.validateAndIssueToken(code) else {
            broadcast(BridgeEvent.pairFailed(reason: "Invalid or expired code"))
            return
        }
        broadcast(BridgeEvent.paired(sessionToken: token))
    }

    // MARK: - REST data providers (used by RESTServer)

    func serveStatus() -> Data {
        guard let appModel else { return jsonResponse(["error": "not ready"], status: 503) }
        let info: [String: Any] = [
            "status": "ok",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "threadCount": appModel.threads.count,
            "paired": pairing.currentCode != nil,
            "connectedClients": connectedClients,
        ]
        return jsonResponse(info)
    }

    func serveThreadList() -> Data {
        guard let appModel else { return jsonResponse(["error": "not ready"], status: 503) }

        let summaries: [[String: Any]] = appModel.threads.map { thread in
            let project = appModel.project(thread.projectID)
            let preview = latestPreview(for: thread.id)
            return [
                "id": thread.id.uuidString,
                "projectID": thread.projectID.uuidString,
                "projectName": project?.name ?? "Unknown",
                "title": thread.title,
                "provider": thread.provider.rawValue,
                "model": thread.model ?? "",
                "lastStatus": thread.lastStatus.map(\.rawValue) ?? "",
                "hasUnread": thread.hasUnread,
                "updatedAt": ISO8601DateFormatter().string(from: thread.updatedAt),
                "messageCount": timelineCount(for: thread.id),
                "lastMessagePreview": preview ?? "",
            ]
        }
        return jsonResponse(summaries)
    }

    func serveThreadDetail(_ threadID: UUID) -> Data {
        guard let appModel else { return jsonResponse(["error": "not ready"], status: 503) }
        guard let thread = appModel.thread(threadID) else {
            return jsonResponse(["error": "thread not found"], status: 404)
        }
        let project = appModel.project(thread.projectID)
        let document = Storage.loadDocument(threadID)

        let entries: [[String: Any]] = document.timeline.map { item in
            var dict: [String: Any] = [
                "id": item.id,
                "kind": kindString(from: item.content),
                "date": ISO8601DateFormatter().string(from: item.date),
            ]
            switch item.content {
            case .user(let msg):
                dict["text"] = msg.text
            case .assistant(let msg):
                dict["text"] = msg.text
            case .reasoning(let block):
                dict["text"] = block.text
            case .tool(let call):
                dict["name"] = call.toolName
                dict["input"] = call.input ?? ""
                dict["output"] = call.output ?? ""
                dict["error"] = call.error ?? ""
            case .plan(let plan):
                dict["text"] = plan.markdown
            case .todos(let steps):
                dict["text"] = steps.map { "\($0.isDone ? "✓" : "○") \($0.title)" }.joined(separator: "\n")
            case .notice(let notice):
                dict["text"] = notice.text
            case .turnEnd(let summary):
                dict["summary"] = summary?.summary ?? ""
            }
            return dict
        }

        let detail: [String: Any] = [
            "id": thread.id.uuidString,
            "projectID": thread.projectID.uuidString,
            "projectPath": project?.path ?? "",
            "title": thread.title,
            "provider": thread.provider.rawValue,
            "model": thread.model ?? "",
            "runtimeMode": thread.runtimeMode.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: thread.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: thread.updatedAt),
            "entries": entries,
            "approvals": [] as [[String: Any]],
            "diffRevision": 0,
        ]
        return jsonResponse(detail)
    }

    func serveModels() -> Data {
        let models: [String: Any] = [
            "providers": [
                "claude": ["id": "claude", "models": ["claude-sonnet-4", "claude-opus-4"]],
                "codex": ["id": "codex", "models": ["gpt-4o", "o1-preview"]],
                "deepseek": ["id": "deepseek", "models": ["deepseek-chat"]],
            ]
        ]
        return jsonResponse(models)
    }

    // MARK: - Private helpers

    private func kindString(from content: TimelineItem.Content) -> String {
        switch content {
        case .user: return "user"
        case .assistant: return "assistant"
        case .reasoning: return "reasoning"
        case .tool: return "tool"
        case .plan: return "plan"
        case .todos: return "todos"
        case .notice: return "notice"
        case .turnEnd: return "turnEnd"
        }
    }

    private func latestPreview(for threadID: UUID) -> String? {
        let doc = Storage.loadDocument(threadID)
        for item in doc.timeline.reversed() {
            switch item.content {
            case .user(let msg): return String(msg.text.prefix(80))
            case .assistant(let msg): return String(msg.text.prefix(80))
            case .tool(let call): return "[\(call.toolName)]"
            default: continue
            }
        }
        return nil
    }

    private func timelineCount(for threadID: UUID) -> Int {
        Storage.loadDocument(threadID).timeline.count
    }

    private func jsonResponse(_ value: Any, status: Int = 200) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else {
            return Data(#"{"error":"encoding failed"}"#.utf8)
        }
        var response = "HTTP/1.1 \(status == 200 ? "OK" : "Not Found")\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(data.count)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        var packet = Data(response.utf8)
        packet.append(data)
        return packet
    }
}
