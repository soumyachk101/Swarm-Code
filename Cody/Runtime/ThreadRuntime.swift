import Foundation

/// One timeline row. A class, so a streaming row redraws without re-diffing the whole thread.
@MainActor
@Observable
final class TimelineEntry: Identifiable {
    enum Kind {
        case user
        case assistant
        case reasoning
        case tool
        case plan
        case todos
        case notice
        case turnEnd
    }

    let id: String
    /// Fixed for the row's lifetime, so grouping never observes streaming content.
    let kind: Kind
    let turnID: UUID?
    var item: TimelineItem

    init(_ item: TimelineItem) {
        id = item.id
        turnID = item.turnID
        kind = switch item.content {
        case .user: .user
        case .assistant: .assistant
        case .reasoning: .reasoning
        case .tool: .tool
        case .plan: .plan
        case .todos: .todos
        case .notice: .notice
        case .turnEnd: .turnEnd
        }
        self.item = item
    }
}

struct ComposerDraft: Equatable {
    var text = ""
    var attachments: [Attachment] = []

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

enum RuntimePhase: Equatable {
    case idle
    case starting
    case running
}

/// Owns a thread's live state: its timeline, its provider session and its pending requests.
@MainActor
@Observable
final class ThreadRuntime {
    let threadID: UUID

    private(set) var entries: [TimelineEntry] = []
    private(set) var turns: [TurnRecord] = []
    private(set) var usage: ContextUsage?
    private(set) var phase: RuntimePhase = .idle
    private(set) var approvals: [ApprovalRequest] = []
    private(set) var questions: [QuestionRequest] = []
    private(set) var turnStartedAt: Date?
    private(set) var diffRevision = 0

    var draft = ComposerDraft()
    var isTerminalVisible = false
    var isDiffVisible = false
    var diffSelection: UUID?

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private var session: (any ProviderSession)?
    @ObservationIgnored private var sessionSignature: SessionSignature?
    @ObservationIgnored private var entryIndex: [String: TimelineEntry] = [:]
    @ObservationIgnored private var pendingDeltas: [String: PendingDelta] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var currentTurnID: UUID?
    @ObservationIgnored private var resumeAnchor: String?
    @ObservationIgnored private var interruptWatchdog: Task<Void, Never>?

    private struct SessionSignature: Equatable {
        var provider: ProviderKind
        var directory: String
        var launchRuntimeMode: RuntimeMode?
        var launchEffort: String?
        var launchFast: Bool?
    }

    private enum DeltaKind {
        case message
        case reasoning
        case toolOutput
        case plan
    }

    private struct PendingDelta {
        var kind: DeltaKind
        var text: String
    }

    init(threadID: UUID, app: AppModel) {
        self.threadID = threadID
        self.app = app
        let document = Storage.loadDocument(threadID)
        turns = document.turns
        usage = document.usage
        entries = document.items.map(TimelineEntry.init)
        for entry in entries {
            entryIndex[entry.id] = entry
            endStreaming(entry)
            if case .tool(var call) = entry.item.content, call.status == .running {
                call.finish(.failed)
                entry.item.content = .tool(call)
            }
        }
        for index in turns.indices where turns[index].status == .running {
            turns[index].status = .interrupted
        }
    }

    var isRunning: Bool { phase != .idle }

    var thread: ChatThread? { app?.thread(threadID) }

    var sentPrompts: [String] {
        entries.compactMap { entry in
            if case .user(let message) = entry.item.content { return message.text }
            return nil
        }
    }

    var pendingPlanApproval: ApprovalRequest? {
        approvals.first { $0.kind == .plan }
    }

    // MARK: - Sending

    func send() {
        guard !draft.isEmpty, phase == .idle else { return }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draft.attachments
        if handleLocalCommand(text) {
            draft = ComposerDraft()
            return
        }
        draft = ComposerDraft()
        Task { await startTurn(text: text, attachments: attachments) }
    }

    func implementPlan(_ entryID: String) {
        guard phase == .idle, let entry = entryIndex[entryID], case .plan(var plan) = entry.item.content else { return }
        plan.state = .accepted
        entry.item.content = .plan(plan)
        app?.updateThread(threadID) { $0.interactionMode = .build }
        Task { await startTurn(text: "Implement the plan.", attachments: []) }
    }

    func dismissPlan(_ entryID: String) {
        guard let entry = entryIndex[entryID], case .plan(var plan) = entry.item.content else { return }
        plan.state = .dismissed
        entry.item.content = .plan(plan)
        scheduleSave()
    }

    private func handleLocalCommand(_ text: String) -> Bool {
        switch text {
        case "/plan":
            app?.updateThread(threadID) { $0.interactionMode = $0.interactionMode == .plan ? .build : .plan }
            return true
        case "/compact" where thread?.provider == .codex:
            compact()
            return true
        default:
            return false
        }
    }

    private func startTurn(text: String, attachments: [Attachment]) async {
        guard let app, let initialThread = app.thread(threadID), let project = app.project(initialThread.projectID) else { return }
        let turnIndex = (turns.map(\.index).max() ?? -1) + 1
        var turn = TurnRecord(index: turnIndex)
        let userItem = TimelineItem(turnID: turn.id, content: .user(UserMessage(text: text, attachments: attachments)))
        turn.userItemID = userItem.id
        turns.append(turn)
        currentTurnID = turn.id
        append(userItem)
        phase = .starting
        turnStartedAt = .now
        app.updateThread(threadID) {
            $0.updatedAt = .now
            $0.lastStatus = .running
        }
        scheduleSave()
        let isFirstTurn = turns.count == 1

        if initialThread.model == nil {
            await app.providers.loadCatalog(initialThread.provider)
            if let model = app.providers.defaultModel(for: initialThread.provider) {
                app.updateThread(threadID) {
                    $0.model = model.id
                    $0.effort = $0.effort ?? model.defaultEffort
                }
            }
        }

        let directory = initialThread.worktreePath ?? project.path
        let git = Git(directory)
        if await git.isRepository() {
            let ref = Git.checkpointRef(thread: threadID, turn: turnIndex, phase: "start")
            if (try? await git.captureCheckpoint(ref)) != nil {
                updateTurn(turn.id) { $0.baseCheckpoint = ref }
            }
        }
        // The user can stop a turn while it is still starting.
        guard currentTurnID == turn.id else { return }

        do {
            let session = try await ensureSession(directory: directory)
            guard currentTurnID == turn.id, let thread = app.thread(threadID) else { return }
            var prompt = text
            let files = attachments.filter { !$0.isImage }
            if !files.isEmpty {
                prompt += "\n\nAttached files:\n" + files.map { "- \($0.path)" }.joined(separator: "\n")
            }
            phase = .running
            try await session.send(TurnInput(
                text: prompt,
                images: thread.provider.supportsImages ? attachments.filter(\.isImage) : [],
                model: thread.model,
                effort: thread.effort,
                serviceTier: serviceTier(for: thread),
                runtimeMode: thread.runtimeMode,
                interactionMode: thread.interactionMode
            ))
            if isFirstTurn { generateTitle(from: text) }
        } catch {
            appendNotice(.error, error.localizedDescription)
            await finishTurn(status: .failed)
        }
    }

    /// Codex takes fast mode per turn as a service tier; models without a fast tier send none.
    private func serviceTier(for thread: ChatThread) -> String? {
        guard thread.provider == .codex,
              let tier = app?.providers.model(thread.model, for: thread.provider)?.fastTier else { return nil }
        return thread.fastMode ? tier : "default"
    }

    private func ensureSession(directory: String) async throws -> any ProviderSession {
        guard let app, let thread = app.thread(threadID) else { throw ProviderError.notRunning }
        let signature = SessionSignature(
            provider: thread.provider,
            directory: directory,
            launchRuntimeMode: thread.provider == .cursor || thread.provider == .grok ? thread.runtimeMode : nil,
            launchEffort: thread.provider == .claude ? thread.effort : nil,
            launchFast: thread.provider == .claude ? thread.fastMode : nil
        )
        if let session, session.isRunning, sessionSignature == signature { return session }
        session?.stop()
        session = nil

        guard let executable = app.providers.executable(for: thread.provider) else {
            throw ProviderError.notInstalled(thread.provider)
        }
        func makeSession(resumeID: String?) -> any ProviderSession {
            let configuration = SessionConfiguration(
                provider: thread.provider,
                executable: executable,
                workingDirectory: URL(fileURLWithPath: directory),
                environment: app.providers.environment(for: thread.provider),
                resumeID: resumeID,
                resumeAt: resumeID == nil ? nil : resumeAnchor,
                model: thread.model,
                effort: thread.effort,
                fastMode: thread.fastMode,
                runtimeMode: thread.runtimeMode,
                interactionMode: thread.interactionMode
            )
            let created: any ProviderSession = switch thread.provider {
            case .codex: CodexSession(configuration: configuration)
            case .claude: ClaudeSession(configuration: configuration)
            case .cursor, .opencode, .grok: ACPSession(configuration: configuration)
            }
            created.onEvent = { [weak self] event in self?.handle(event) }
            return created
        }

        var candidate = makeSession(resumeID: thread.providerSessionID)
        session = candidate
        sessionSignature = signature
        let sessionID: String
        do {
            sessionID = try await candidate.start()
        } catch where thread.providerSessionID != nil {
            candidate.stop()
            candidate = makeSession(resumeID: nil)
            session = candidate
            sessionID = try await candidate.start()
        }
        resumeAnchor = nil
        app.updateThread(threadID) { $0.providerSessionID = sessionID }
        return candidate
    }

    // MARK: - Controls

    func interrupt() {
        guard phase != .idle else { return }
        let turnID = currentTurnID
        Task {
            if let session {
                await session.interrupt()
            } else {
                await finishTurn(status: .interrupted)
            }
        }
        interruptWatchdog?.cancel()
        interruptWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.currentTurnID == turnID, turnID != nil else { return }
            self.session?.stop()
            self.session = nil
            self.sessionSignature = nil
            await self.finishTurn(status: .interrupted)
        }
    }

    func resolve(_ request: ApprovalRequest, option: ApprovalRequest.Option) {
        approvals.removeAll { $0.id == request.id }
        if request.kind == .plan, let itemID = request.toolItemID,
           let entry = entryIndex[itemID], case .plan(var plan) = entry.item.content {
            plan.state = option.role == .approve ? .accepted : .dismissed
            entry.item.content = .plan(plan)
            scheduleSave()
        }
        session?.resolveApproval(request.id, optionID: option.id)
    }

    func answer(_ request: QuestionRequest, answers: [String: [String]]) {
        questions.removeAll { $0.id == request.id }
        session?.answerQuestion(request.id, answers: answers)
    }

    func compact() {
        guard phase == .idle else { return }
        guard let session, session.isRunning else {
            appendNotice(.info, "Nothing to compact yet.")
            return
        }
        appendNotice(.info, "Compacting context.")
        Task {
            do {
                try await session.compact()
            } catch {
                appendNotice(.warning, error.localizedDescription)
            }
        }
    }

    /// Rewinds the conversation to before a turn, optionally restoring the files it changed.
    func revert(to turnID: UUID, restoreFiles: Bool) async {
        guard phase == .idle, let app, let thread = app.thread(threadID), let project = app.project(thread.projectID),
              let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        let removed = Array(turns[index...])
        let directory = thread.worktreePath ?? project.path

        switch thread.provider {
        case .codex:
            if let codex = try? await ensureSession(directory: directory) as? CodexSession {
                try? await codex.rollback(turns: removed.count)
            }
        case .claude:
            session?.stop()
            session = nil
            sessionSignature = nil
            if index == 0 {
                app.updateThread(threadID) { $0.providerSessionID = nil }
            } else {
                resumeAnchor = turns[index - 1].providerAnchor
            }
        default:
            return
        }

        if restoreFiles, let base = removed.first?.baseCheckpoint {
            do {
                try await Git(directory).restoreCheckpoint(base)
            } catch {
                appendNotice(.error, "Could not restore files: \(error.localizedDescription)")
            }
        }

        let removedIDs = Set(removed.map(\.id))
        if let userID = removed.first?.userItemID, let entry = entryIndex[userID], case .user(let message) = entry.item.content {
            draft = ComposerDraft(text: message.text, attachments: message.attachments)
        }
        entries.removeAll { entry in
            guard let turn = entry.item.turnID else { return false }
            return removedIDs.contains(turn)
        }
        entryIndex = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        turns.removeSubrange(index...)
        diffSelection = nil
        diffRevision += 1
        scheduleSave()
    }

    func stopSession() {
        session?.stop()
        session = nil
        sessionSignature = nil
    }

    // MARK: - Events

    private func handle(_ event: ProviderEvent) {
        switch event {
        case .sessionReady(let sessionID):
            app?.updateThread(threadID) { $0.providerSessionID = sessionID }
        case .turnStarted(let providerTurnID):
            phase = .running
            if let currentTurnID, let providerTurnID {
                updateTurn(currentTurnID) { $0.providerTurnID = providerTurnID }
            }
        case .messageDelta(let id, let text):
            queueDelta(id, .message, text)
        case .messageCompleted(let id, let text):
            flushDeltas()
            completeMessage(id, text: text)
        case .reasoningDelta(let id, let text):
            queueDelta(id, .reasoning, text)
        case .reasoningCompleted(let id, let text):
            flushDeltas()
            completeReasoning(id, text: text)
        case .toolStarted(let id, let call):
            flushDeltas()
            upsertTool(id, call)
        case .toolOutput(let id, let text):
            queueDelta(id, .toolOutput, text)
        case .toolUpdated(let id, let update):
            flushDeltas()
            applyToolUpdate(id, update)
        case .planDelta(let id, let text):
            queueDelta(id, .plan, text)
        case .planCompleted(let id, let markdown):
            flushDeltas()
            completePlan(id, markdown: markdown)
        case .todos(let steps):
            upsertTodos(steps)
        case .approval(let request):
            approvals.removeAll { $0.id == request.id }
            approvals.append(request)
            app?.threadNeedsAttention(threadID)
        case .question(let request):
            questions.removeAll { $0.id == request.id }
            questions.append(request)
            app?.threadNeedsAttention(threadID)
        case .requestResolved(let id):
            approvals.removeAll { $0.id == id }
            questions.removeAll { $0.id == id }
        case .usage(let usage):
            self.usage = usage
        case .diff(let diff):
            if let currentTurnID { updateTurn(currentTurnID) { $0.providerDiff = diff } }
        case .notice(let notice):
            appendNotice(notice.level, notice.message)
        case .modeChanged(let mode):
            app?.updateThread(threadID) { $0.interactionMode = mode }
        case .models(let list, _):
            if let provider = thread?.provider { app?.providers.updateCatalog(list, for: provider) }
        case .commands(let list):
            if let provider = thread?.provider { app?.providers.updateCommands(list, for: provider) }
        case .title(let title):
            // Provider titles are only a fallback; they must not replace the one Cody writes.
            guard turns.count <= 1, let app, let thread, !thread.hasCustomTitle,
                  app.textEngine(preferring: thread.provider) == nil else { break }
            app.updateThread(threadID) { $0.title = title }
        case .assistantMessageID(let anchor):
            if let currentTurnID { updateTurn(currentTurnID) { $0.providerAnchor = anchor } }
        case .turnCompleted(let status, let error):
            flushDeltas()
            if let error { appendNotice(.error, error) }
            Task { await finishTurn(status: status) }
        case .exited(let error):
            flushDeltas()
            session = nil
            sessionSignature = nil
            approvals.removeAll()
            questions.removeAll()
            if currentTurnID != nil {
                let name = thread?.provider.displayName ?? "The agent"
                appendNotice(.error, error ?? "\(name) stopped unexpectedly.")
                Task { await finishTurn(status: .failed) }
            }
        }
    }

    private func finishTurn(status: TurnStatus) async {
        interruptWatchdog?.cancel()
        interruptWatchdog = nil
        guard let turnID = currentTurnID, let turn = turns.first(where: { $0.id == turnID }) else {
            phase = .idle
            turnStartedAt = nil
            return
        }
        currentTurnID = nil
        flushDeltas()
        approvals.removeAll()
        questions.removeAll()
        for entry in entries where entry.item.turnID == turnID {
            endStreaming(entry)
            if case .tool(var call) = entry.item.content, call.status == .running {
                call.finish(status == .completed ? .completed : .failed)
                entry.item.content = .tool(call)
            }
        }
        updateTurn(turnID) {
            $0.status = status
            $0.completedAt = .now
        }

        var files: [DiffFile] = []
        if let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) {
            let git = Git(thread.worktreePath ?? project.path)
            if let base = turn.baseCheckpoint {
                let ref = Git.checkpointRef(thread: threadID, turn: turn.index, phase: "end")
                if (try? await git.captureCheckpoint(ref)) != nil {
                    updateTurn(turnID) { $0.endCheckpoint = ref }
                    if let patch = try? await git.diff(from: base, to: ref) {
                        files = DiffParser.parse(patch)
                    }
                }
            } else if let providerDiff = turns.first(where: { $0.id == turnID })?.providerDiff {
                files = DiffParser.parse(providerDiff)
            }
        }

        let summary = TurnSummary(
            turnID: turnID,
            status: status,
            duration: Date.now.timeIntervalSince(turn.startedAt),
            filesChanged: files.count,
            additions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions }
        )
        append(TimelineItem(turnID: turnID, content: .turnEnd(summary)))
        phase = .idle
        turnStartedAt = nil
        diffRevision += 1
        app?.turnFinished(threadID, status: status)
        scheduleSave()
    }

    // MARK: - Timeline mutations

    private func append(_ item: TimelineItem) {
        for entry in entries.suffix(6) { endStreaming(entry) }
        let entry = TimelineEntry(item)
        entries.append(entry)
        entryIndex[item.id] = entry
    }

    private func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        entryIndex[id] = nil
    }

    private func endStreaming(_ entry: TimelineEntry) {
        switch entry.item.content {
        case .assistant(var message) where message.isStreaming:
            message.isStreaming = false
            entry.item.content = .assistant(message)
        case .reasoning(var block) where block.isStreaming:
            block.isStreaming = false
            entry.item.content = .reasoning(block)
        case .plan(var plan) where plan.state == .drafting:
            plan.state = .proposed
            entry.item.content = .plan(plan)
        default:
            break
        }
    }

    private func queueDelta(_ id: String, _ kind: DeltaKind, _ text: String) {
        if entryIndex[id] == nil {
            switch kind {
            case .message:
                append(TimelineItem(id: id, turnID: currentTurnID, content: .assistant(AssistantMessage(text: "", isStreaming: true))))
            case .reasoning:
                append(TimelineItem(id: id, turnID: currentTurnID, content: .reasoning(ReasoningBlock(text: "", isStreaming: true))))
            case .plan:
                append(TimelineItem(id: id, turnID: currentTurnID, content: .plan(ProposedPlan(markdown: "", state: .drafting))))
            case .toolOutput:
                return
            }
        }
        guard !text.isEmpty else { return }
        pendingDeltas[id, default: PendingDelta(kind: kind, text: "")].text += text
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(45))
            self?.flushDeltas()
        }
    }

    private func flushDeltas() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingDeltas.isEmpty else { return }
        let deltas = pendingDeltas
        pendingDeltas.removeAll()
        for (id, delta) in deltas {
            guard let entry = entryIndex[id] else { continue }
            switch (delta.kind, entry.item.content) {
            case (.message, .assistant(var message)):
                message.text += delta.text
                entry.item.content = .assistant(message)
            case (.reasoning, .reasoning(var block)):
                block.text += delta.text
                entry.item.content = .reasoning(block)
            case (.toolOutput, .tool(var call)):
                call.appendOutput(delta.text)
                entry.item.content = .tool(call)
            case (.plan, .plan(var plan)):
                plan.markdown += delta.text
                entry.item.content = .plan(plan)
            default:
                break
            }
        }
        scheduleSave()
    }

    private func completeMessage(_ id: String, text: String) {
        guard let entry = entryIndex[id] else {
            guard !text.isEmpty else { return }
            append(TimelineItem(id: id, turnID: currentTurnID, content: .assistant(AssistantMessage(text: text))))
            return
        }
        guard case .assistant(var message) = entry.item.content else { return }
        if !text.isEmpty { message.text = text }
        message.isStreaming = false
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remove(id)
        } else {
            entry.item.content = .assistant(message)
        }
        scheduleSave()
    }

    private func completeReasoning(_ id: String, text: String) {
        guard let entry = entryIndex[id], case .reasoning(var block) = entry.item.content else {
            guard !text.isEmpty else { return }
            append(TimelineItem(id: id, turnID: currentTurnID, content: .reasoning(ReasoningBlock(text: text))))
            return
        }
        if !text.isEmpty { block.text = text }
        block.isStreaming = false
        if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remove(id)
        } else {
            entry.item.content = .reasoning(block)
        }
    }

    private func completePlan(_ id: String, markdown: String) {
        if let entry = entryIndex[id], case .plan(var plan) = entry.item.content {
            if !markdown.isEmpty { plan.markdown = markdown }
            plan.state = .proposed
            entry.item.content = .plan(plan)
        } else if !markdown.isEmpty {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .plan(ProposedPlan(markdown: markdown, state: .proposed))))
        }
        scheduleSave()
    }

    private func upsertTool(_ id: String, _ call: ToolCall) {
        guard let entry = entryIndex[id], case .tool(var existing) = entry.item.content else {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .tool(call)))
            return
        }
        if !call.title.isEmpty { existing.title = call.title }
        existing.detail = call.detail ?? existing.detail
        existing.kind = call.kind
        if !call.edits.isEmpty { existing.edits = call.edits }
        if existing.status == .running, call.status != .running { existing.finish(call.status) }
        entry.item.content = .tool(existing)
    }

    private func applyToolUpdate(_ id: String, _ update: ToolUpdate) {
        if entryIndex[id] == nil {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .tool(ToolCall(kind: update.kind ?? .other, title: update.title ?? "Tool"))))
        }
        guard let entry = entryIndex[id], case .tool(var call) = entry.item.content else { return }
        if let title = update.title, !title.isEmpty { call.title = title }
        if let detail = update.detail { call.detail = detail }
        if let kind = update.kind { call.kind = kind }
        if let edits = update.edits, !edits.isEmpty { call.edits = edits }
        if let output = update.output { call.setOutput(output) }
        if let exitCode = update.exitCode { call.exitCode = exitCode }
        if let status = update.status {
            if status == .running { call.status = .running } else { call.finish(status) }
        }
        entry.item.content = .tool(call)
        scheduleSave()
    }

    private func upsertTodos(_ steps: [TodoStep]) {
        if let entry = entries.last(where: { entry in
            guard entry.item.turnID == currentTurnID else { return false }
            if case .todos = entry.item.content { return true }
            return false
        }) {
            entry.item.content = .todos(steps)
        } else if !steps.isEmpty {
            append(TimelineItem(turnID: currentTurnID, content: .todos(steps)))
        }
    }

    private func appendNotice(_ level: Notice.Level, _ message: String) {
        append(TimelineItem(turnID: currentTurnID, content: .notice(Notice(level: level, message: message))))
        scheduleSave()
    }

    private func updateTurn(_ id: UUID, _ change: (inout TurnRecord) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        change(&turns[index])
    }

    private func generateTitle(from text: String) {
        guard let app, let thread = app.thread(threadID), !thread.hasCustomTitle else { return }
        app.updateThread(threadID) { $0.title = TextCleanup.singleLine(text, limit: 48) }
        guard let engine = app.textEngine(preferring: thread.provider) else { return }
        let threadID = threadID
        Task {
            guard let title = await TextGeneration.threadTitle(for: text, engine: engine) else { return }
            app.updateThread(threadID) { thread in
                if !thread.hasCustomTitle { thread.title = title }
            }
        }
    }

    // MARK: - Persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        var document = ThreadDocument(threadID: threadID)
        document.items = entries.map(\.item)
        document.turns = turns
        document.usage = usage
        guard let data = try? JSONEncoder.storage.encode(document) else { return }
        let url = Storage.threadURL(threadID)
        Task { await DiskWriter.shared.write(data, to: url) }
    }
}
