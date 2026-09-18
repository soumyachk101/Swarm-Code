import Foundation

/// Watches AppModel's observable state and pushes live updates to the Bridge Server,
/// which streams them to connected mobile clients over WebSocket.
///
/// This is the "outbound pipeline": AppModel → BridgeObserver → BridgeServer → WebSocket → Mobile.
@MainActor
final class BridgeObserver: @unchecked Sendable {
    private weak var appModel: AppModel?
    private weak var bridge: BridgeServer?
    private var listTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var seenEntries: Set<String> = []

    init(appModel: AppModel, bridge: BridgeServer) {
        self.appModel = appModel
        self.bridge = bridge
    }

    func start() {
        observeThreadList()
        observeTimelineStream()
    }

    func stop() {
        listTask?.cancel()
        streamTask?.cancel()
    }

    // MARK: - Thread list changes

    private func observeThreadList() {
        listTask = Task { [weak self] in
            while !(self?.listTask?.isCancelled ?? true) {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let model = self.appModel else { continue }
                self.bridge?.broadcast(BridgeEvent.threadUpdated(UUID()))
            }
        }
    }

    // MARK: - Timeline streaming

    private func observeTimelineStream() {
        streamTask = Task { [weak self] in
            while !(self?.streamTask?.isCancelled ?? true) {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let model = self.appModel else { continue }

                for thread in model.threads {
                    guard let runtime = model.existingRuntime(for: thread.id) else { continue }
                    for entry in runtime.entries {
                        let key = "\(thread.id.uuidString):\(entry.id)"
                        guard !self.seenEntries.contains(key) else { continue }
                        self.seenEntries.insert(key)

                        let event: BridgeEvent? = switch entry.item.content {
                        case .user(let msg):
                            .messageDelta(threadID: thread.id, content: msg.text, isTool: false)
                        case .assistant(let msg):
                            .messageDelta(threadID: thread.id, content: msg.text, isTool: false)
                        case .reasoning(let block):
                            .thinkingDelta(threadID: thread.id, content: block.text)
                        case .tool(let call):
                            .toolCall(threadID: thread.id, tool: call.toolName, input: call.input ?? "")
                        case .plan(let plan):
                            .messageDelta(threadID: thread.id, content: "**Plan**: \(plan.markdown)", isTool: false)
                        case .todos(let steps):
                            .messageDelta(
                                threadID: thread.id,
                                content: steps.map { "\($0.isDone ? "✓" : "○") \($0.title)" }.joined(separator: "\n"),
                                isTool: false
                            )
                        case .notice(let notice):
                            .messageDelta(threadID: thread.id, content: notice.text, isTool: false)
                        case .turnEnd:
                            .messageComplete(threadID: thread.id, messageID: entry.id)
                        }
                        if let event {
                            self.bridge?.broadcast(event)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - AppSettings: Bridge toggle

extension AppSettings {
    /// When true, the bridge server starts with Swarm Code and advertises itself
    /// on the local network. Default: off, so the app behaves exactly as before.
    var bridgeEnabled: Bool {
        get { defaults.bool(forKey: "bridgeEnabled") }
        set { defaults.set(newValue, forKey: "bridgeEnabled") }
    }

    /// The port the bridge listens on. Advanced users can change this if
    /// something else on the LAN already uses 8765.
    var bridgePort: Int16 {
        get { Int16(defaults.integer(forKey: "bridgePort")) }
        set { defaults.set(Int(newValue), forKey: "bridgePort") }
    }
}
