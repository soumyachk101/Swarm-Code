import AppKit
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

/// Entries compare by identity: a row observes its entry's content itself, so the same
/// object always means the same row, and a rebuilt timeline can skip the rows whose
/// entries it already shows.
extension TimelineEntry: Equatable {
    nonisolated static func == (lhs: TimelineEntry, rhs: TimelineEntry) -> Bool {
        lhs === rhs
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
    /// Queued steering prompts. Enqueued while a turn runs, each one is sent as a
    /// direct user chat message once the running turn finishes, in order.
    private(set) var followUps: [FollowUpPrompt] = []

    var draft = ComposerDraft()
    var isTerminalVisible = false
    var isDiffVisible = false
    /// Where the helper panel this thread spawned was dragged to, as its top-left corner in
    /// the chat pane; nil while it sits docked in the bottom-right corner beside the chat box.
    var subagentPanelOrigin: CGPoint?
    var diffSelection: UUID?
    /// The view the changes popover should open on: a tool row's label, a turn's Review
    /// button, or nil for the changes tab. Held weakly so a row that leaves the screen
    /// never keeps a view alive.
    @ObservationIgnored var diffAnchor: WeakView?
    /// The side of `diffAnchor` the popover hangs from. Anchors are plain, unflipped
    /// views, so `.minY` is below (a tool row, as its chevron promises) and `.maxY` is
    /// above (a Review button, at the foot of its turn).
    @ObservationIgnored var diffAnchorEdge: NSRectEdge = .maxY
    /// Bumped by `showDiff(on:edge:turn:focusEdits:)`, so the popover moves to the new
    /// anchor even when it is already open somewhere else.
    private(set) var diffOpenRequest = 0
    /// The edits a tapped tool row asked to see, patches included. The popover leaves
    /// their cards expanded and scrolls to the first of them, and falls back to a patch
    /// when the turn's diff has nothing for it; empty for the tab and the Review button,
    /// which open the whole selection.
    private(set) var diffFocusEdits: [FileEdit] = []
    /// Bumped whenever `diffFocusEdits` changes, so the popover reloads its file list
    /// even when a second row names the same file with a different patch.
    private(set) var diffFocusRevision = 0

    /// Opens the changes popover on `anchor` (a tool row or a Review button), hanging
    /// from its `edge`, showing `turn`'s changes, or the whole thread's for nil.
    /// `focusEdits` are the tapped row's own edits, so the file it reports is what the
    /// popover opens on even when the turn's diff cannot show it yet.
    func showDiff(on anchor: NSView, edge: NSRectEdge = .maxY, turn: UUID?, focusEdits: [FileEdit] = []) {
        diffAnchor = WeakView(anchor)
        diffAnchorEdge = edge
        if diffSelection != turn { diffSelection = turn }
        setDiffFocus(focusEdits)
        if !isDiffVisible { isDiffVisible = true }
        diffOpenRequest += 1
    }

    /// Drops the edits a tapped tool row focused, so the openers that show a whole
    /// selection (the changes tab, ⌘D) never open on some earlier row's file.
    func clearDiffFocus() {
        setDiffFocus([])
    }

    private func setDiffFocus(_ edits: [FileEdit]) {
        let focus = edits.filter { !$0.path.isEmpty }
        guard focus != diffFocusEdits else { return }
        diffFocusEdits = focus
        diffFocusRevision += 1
    }

    /// The changes tab, the toolbar button, ⌘D and the palette: they show the whole
    /// selection, so any file a tapped tool row focused is dropped first and the
    /// popover opens at the top of the list rather than on some earlier row's file.
    func toggleDiff() {
        clearDiffFocus()
        if !isDiffVisible { diffAnchor = nil }
        isDiffVisible.toggle()
    }

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
    /// Working-tree snapshots taken as command tools start, by tool id, and
    /// the diffs being settled as they finish (see `watchCommand`).
    @ObservationIgnored private var commandTrees: [String: Task<String?, Never>] = [:]
    @ObservationIgnored private var commandSettles: [String: Task<Void, Never>] = [:]

    private struct SessionSignature: Equatable {
        var provider: ProviderKind
        var directory: String
        var launchRuntimeMode: RuntimeMode?
        var launchEffort: String?
        var launchFast: Bool?
        /// Antigravity pins model, effort, mode and plan state at launch
        /// (`--model`, `--effort`, `--mode`), so any of them restarts it.
        var launchModel: String?
        var launchInteraction: InteractionMode?
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
        followUps = document.followUps.filter { !$0.isEmpty }
        // Thinking with no text is nothing to show or keep: Claude Code redacts its
        // reasoning and streams only empty deltas, which older builds stored as blank
        // entries. They are dropped here and never created below. Threads stored before
        // the app flattened model prose on the way in are cleaned as they are read, so
        // no reply from any earlier build can put an em dash back on screen.
        entries = document.items.filter { !$0.isEmptyReasoning }.map { TimelineEntry($0.cleanedOfEmDashes) }
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

    // MARK: - Follow-up queue

    /// Instantly queues the composer's draft as a follow-up while a turn runs. The prompt,
    /// pics and other attachments included, is sent as a direct user chat message once the
    /// running turn finishes. Stacks up: every queued prompt runs in order.
    func queueDraftAsFollowUp() {
        guard !draft.isEmpty, phase != .idle else { return }
        enqueueFollowUp(text: draft.text, attachments: draft.attachments)
        draft = ComposerDraft()
    }

    /// Draft captured by Return while a turn runs: stop the turn, then send this
    /// right away instead of queueing it behind the queue.
    @ObservationIgnored private var pendingSend: PendingSend?

    private struct PendingSend {
        var text: String
        var attachments: [Attachment]
    }

    /// Interrupts the running turn and sends the draft as soon as the stop
    /// lands, instead of queueing it as a follow-up. The composer clears at
    /// once; the message goes out when the turn fully stops (or immediately,
    /// if the turn finished on its own in the meantime).
    func interruptAndSend() {
        guard !draft.isEmpty, phase != .idle else { return }
        pendingSend = PendingSend(text: draft.text, attachments: draft.attachments)
        draft = ComposerDraft()
        interrupt()
    }

    /// Sends a queued follow-up right away instead of waiting its turn: the running turn
    /// stops and the prompt goes out as soon as the stop lands, exactly as Return does with
    /// the draft; idle, it simply sends. The rest of the queue waits for the new turn.
    func sendFollowUpNow(_ id: UUID) {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }
        let prompt = followUps.remove(at: index)
        scheduleSave()
        guard !prompt.isEmpty else { return }
        if phase == .idle {
            if handleLocalCommand(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)) { return }
            Task { await startTurn(text: prompt.text, attachments: prompt.attachments) }
        } else if pendingSend == nil {
            pendingSend = PendingSend(text: prompt.text, attachments: prompt.attachments)
            interrupt()
        } else {
            // Return already has a message going out the moment the turn stops; this one
            // goes right behind it.
            followUps.insert(prompt, at: 0)
            scheduleSave()
        }
    }

    func enqueueFollowUp(text: String, attachments: [Attachment]) {
        let prompt = FollowUpPrompt(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            attachments: attachments
        )
        guard !prompt.isEmpty else { return }
        followUps.append(prompt)
        scheduleSave()
    }

    func removeFollowUp(_ id: UUID) {
        followUps.removeAll { $0.id == id }
        scheduleSave()
    }

    /// Moves a queued follow-up next to another one, for drag reordering. A no-op
    /// when it is already there, so hovering the same half never churns.
    /// Moves a follow-up to sit right before or after `target`; returns whether the queue changed.
    @discardableResult
    func moveFollowUp(_ id: UUID, to target: UUID, placeAfter: Bool) -> Bool {
        guard id != target,
              let from = followUps.firstIndex(where: { $0.id == id }),
              let to = followUps.firstIndex(where: { $0.id == target }) else { return false }
        var dest = to + (placeAfter ? 1 : 0)
        if from < dest { dest -= 1 }
        guard from != dest else { return false }
        let prompt = followUps.remove(at: from)
        followUps.insert(prompt, at: dest)
        scheduleSave()
        return true
    }

    func updateFollowUp(_ id: UUID, text: String, attachments: [Attachment]) {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, attachments.isEmpty {
            followUps.remove(at: index)
        } else {
            followUps[index].text = text
            followUps[index].attachments = attachments
        }
        scheduleSave()
    }

    /// Sends the next queued follow-up as a direct user message. Only runs when idle after a
    /// completed turn: an interrupted turn means the user hit stop, so the queue waits for them.
    /// Returns whether a turn starts.
    private func drainFollowUps(after status: TurnStatus) -> Bool {
        guard status == .completed, phase == .idle, !followUps.isEmpty else { return false }
        var next = followUps.removeFirst()
        // Skip prompts that emptied while queued (an attachment file deleted on disk still counts,
        // so only the text+attachment check applies).
        while next.isEmpty, !followUps.isEmpty {
            next = followUps.removeFirst()
        }
        guard !next.isEmpty else {
            scheduleSave()
            return false
        }
        scheduleSave()
        if handleLocalCommand(next.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return drainFollowUps(after: status)
        }
        Task { await startTurn(text: next.text, attachments: next.attachments) }
        return true
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
        case "/compact" where thread?.provider == .codex || thread?.provider == .copilot || thread?.provider == .deepseek || thread?.provider == .meta:
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
        // Copilot switches modes live, except that Auto's assisted-approval judge is a
        // session flag: entering or leaving Auto resumes the session with it set right.
        let copilotLaunchMode: RuntimeMode? = thread.provider == .copilot && thread.runtimeMode == .auto ? .auto : nil
        let signature = SessionSignature(
            provider: thread.provider,
            directory: directory,
            launchRuntimeMode: thread.provider == .cursor || thread.provider == .grok || thread.provider == .devin || thread.provider == .antigravity ? thread.runtimeMode : copilotLaunchMode,
            launchEffort: thread.provider == .claude || thread.provider == .antigravity ? thread.effort : nil,
            launchFast: thread.provider == .claude ? thread.fastMode : nil,
            launchModel: thread.provider == .antigravity ? thread.model : nil,
            launchInteraction: thread.provider == .antigravity ? thread.interactionMode : nil
        )
        if let session, session.isRunning, sessionSignature == signature { return session }
        session?.stop()
        session = nil

        if thread.provider.isAPIKeyBased {
            guard !app.settings.apiKey(for: thread.provider).isEmpty else {
                throw ProviderError.notInstalled(thread.provider)
            }
            func makeAPISession(resumeID: String?) -> any ProviderSession {
                let configuration = SessionConfiguration(
                    provider: thread.provider,
                    executable: nil,
                    workingDirectory: URL(fileURLWithPath: directory),
                    environment: app.providers.environment(for: thread.provider),
                    resumeID: resumeID,
                    resumeAt: resumeID == nil ? nil : resumeAnchor,
                    model: thread.model,
                    effort: thread.effort,
                    fastMode: thread.fastMode,
                    runtimeMode: thread.runtimeMode,
                    interactionMode: thread.interactionMode,
                    apiKey: app.settings.apiKey(for: thread.provider)
                )
                let created: any ProviderSession = switch thread.provider {
                case .deepseek: DeepSeekSession(configuration: configuration)
                case .meta: MetaSession(configuration: configuration)
                default: DeepSeekSession(configuration: configuration)
                }
                created.onEvent = { [weak self] event in self?.handle(event) }
                return created
            }
            var candidate = makeAPISession(resumeID: thread.providerSessionID)
            session = candidate
            sessionSignature = signature
            let sessionID: String
            do {
                sessionID = try await candidate.start()
            } catch where thread.providerSessionID != nil {
                candidate.stop()
                candidate = makeAPISession(resumeID: nil)
                session = candidate
                sessionID = try await candidate.start()
            }
            resumeAnchor = nil
            app.updateThread(threadID) { $0.providerSessionID = sessionID }
            return candidate
        }

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
            case .antigravity: AntigravitySession(configuration: configuration)
            case .copilot: CopilotSession(configuration: configuration)
            case .cursor, .opencode, .grok, .devin: ACPSession(configuration: configuration)
            case .deepseek: DeepSeekSession(configuration: configuration)
            case .meta: MetaSession(configuration: configuration)
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
        case .copilot:
            if let copilot = try? await ensureSession(directory: directory) as? CopilotSession {
                do {
                    try await copilot.rollback(turns: removed.count)
                } catch {
                    appendNotice(.warning, "Copilot kept its own history: \(error.localizedDescription)")
                }
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

    struct ChangeStats: Equatable {
        var files: Int
        var additions: Int
        var deletions: Int
    }

    /// The files this thread's agent changed across every turn, or nil when it changed none.
    private(set) var changeStats: ChangeStats?

    @ObservationIgnored private var changeStatsRevision: Int?

    /// Runs once per diff revision: showing the thread again (switching threads, reopening the
    /// window) reuses what the last run found instead of running git and the parser again.
    func refreshChangeStats() async {
        let revision = diffRevision
        guard changeStatsRevision != revision else { return }
        guard let app, let thread = app.thread(threadID), app.project(thread.projectID) != nil else { return }
        let touched = Set(turns.flatMap { $0.touchedPaths ?? [] })
        guard !touched.isEmpty else {
            if changeStats != nil { changeStats = nil }
            changeStatsRevision = revision
            return
        }
        let files = await parsedDiff(selection: nil).filter { TouchedPaths.matches($0, touched: touched) }
        guard revision == diffRevision else { return }
        let stats = files.isEmpty ? nil : ChangeStats(
            files: files.count,
            additions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions }
        )
        if stats != changeStats { changeStats = stats }
        changeStatsRevision = revision
    }

    /// Parsed patches by diff revision and turn selection, shared by the changes tab and the
    /// diff panel. Opening the panel, resizing it between docked and floating, or coming back
    /// to a thread reuses the parse; only a new revision runs git again. Concurrent callers
    /// share one run.
    @ObservationIgnored private var diffCache: [String: Task<[DiffFile], Never>] = [:]

    private func diffCacheKey(_ selection: UUID?) -> String {
        "\(diffRevision)-\(selection?.uuidString ?? "all")"
    }

    func hasCachedDiff(selection: UUID?) -> Bool {
        diffCache[diffCacheKey(selection)] != nil
    }

    func parsedDiff(selection: UUID?) async -> [DiffFile] {
        let key = diffCacheKey(selection)
        if let task = diffCache[key] { return await task.value }
        guard let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) else { return [] }
        let git = Git(thread.worktreePath ?? project.path)
        let turns = turns
        let revisionPrefix = "\(diffRevision)-"
        diffCache = diffCache.filter { $0.key.hasPrefix(revisionPrefix) }
        let task = Task { () -> [DiffFile] in
            var patch = ""
            if let selection, let turn = turns.first(where: { $0.id == selection }) {
                if let base = turn.baseCheckpoint, let end = turn.endCheckpoint {
                    patch = (try? await git.diff(from: base, to: end)) ?? ""
                } else {
                    patch = turn.providerDiff ?? ""
                }
            } else {
                let captured = turns.filter { $0.baseCheckpoint != nil && $0.endCheckpoint != nil }
                if let first = captured.first?.baseCheckpoint, let last = captured.last?.endCheckpoint {
                    patch = (try? await git.diff(from: first, to: last)) ?? ""
                } else {
                    patch = turns.compactMap(\.providerDiff).joined(separator: "\n")
                }
            }
            return await Self.parseDiff(patch)
        }
        diffCache[key] = task
        return await task.value
    }

    @concurrent
    private nonisolated static func parseDiff(_ patch: String) async -> [DiffFile] {
        DiffParser.parse(patch)
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
            if call.kind == .command { watchCommand(id) }
        case .toolOutput(let id, let text):
            queueDelta(id, .toolOutput, text)
        case .toolUpdated(let id, let update):
            flushDeltas()
            applyToolUpdate(id, update)
            if let entry = entryIndex[id], case .tool(let call) = entry.item.content,
               call.kind == .command, call.status != .running {
                settleCommand(id)
            }
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
            // The turn just spent from the account, so the balance read before it is stale.
            if let provider = thread?.provider { app?.providers.invalidateCredits(provider) }
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
            // Provider titles are only a fallback; they must not replace the one Droppy Code writes.
            guard turns.count <= 1, let app, let thread, !thread.hasCustomTitle,
                  app.textEngine(preferring: thread.provider) == nil else { break }
            app.updateThread(threadID) { $0.title = TextCleanup.withoutEmDashes(title) }
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
            drainPendingSend()
            return
        }
        // Command diffs land before the turn's own summary counts them, and
        // while the turn is still current so the snapshots can be compared.
        for id in Array(commandTrees.keys) { settleCommand(id) }
        for task in commandSettles.values { await task.value }
        commandSettles.removeAll()
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

            // Only files this thread's agent edited count, never edits made elsewhere in the repository meanwhile.
            let root = thread.worktreePath ?? project.path
            var touched = Set<String>()
            for entry in entries where entry.kind == .tool && entry.item.turnID == turnID {
                if case .tool(let call) = entry.item.content {
                    for edit in call.edits { touched.insert(TouchedPaths.normalize(edit.path, root: root)) }
                }
            }
            if let providerDiff = turns.first(where: { $0.id == turnID })?.providerDiff {
                for file in DiffParser.parse(providerDiff) { touched.insert(file.path) }
            }
            let touchedPaths = touched.sorted()
            updateTurn(turnID) { $0.touchedPaths = touchedPaths }
            files = files.filter { TouchedPaths.matches($0, touched: touched) }
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
        scheduleSave()
        // The Return-while-running message jumps the queue: it goes right away
        // and anything queued waits for it. Either way the app hears whether a
        // next turn is on its way, so "finished" only sounds when nothing is.
        let continues = pendingSend != nil ? drainPendingSend() : drainFollowUps(after: status)
        app?.turnFinished(threadID, status: status, continues: continues)
    }

    /// Sends the message captured by Return while a turn ran, once the stop
    /// lands. Runs for any finish status: if the turn completed on its own in
    /// the meantime, the message still goes right away. Returns whether a turn starts.
    @discardableResult
    private func drainPendingSend() -> Bool {
        guard phase == .idle, let pending = pendingSend else { return false }
        pendingSend = nil
        let text = pending.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pending.attachments.isEmpty else {
            scheduleSave()
            return false
        }
        if handleLocalCommand(text) { return false }
        Task { await startTurn(text: pending.text, attachments: pending.attachments) }
        return true
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
                // Not until there is something to read: a redacted thinking block
                // only ever sends empty deltas and would leave a blank entry behind.
                guard !text.isEmpty else { return }
                append(TimelineItem(id: id, turnID: currentTurnID, content: .reasoning(ReasoningBlock(text: "", isStreaming: true))))
            case .plan:
                append(TimelineItem(id: id, turnID: currentTurnID, content: .plan(ProposedPlan(markdown: "", state: .drafting))))
            case .toolOutput:
                return
            }
        }
        guard !text.isEmpty else { return }
        // Prose is flattened as it streams, so a reply can never render an em dash.
        // Tool output is process text, not the model's own writing, and passes through.
        let prose = kind == .toolOutput ? text : TextCleanup.withoutEmDashes(text)
        pendingDeltas[id, default: PendingDelta(kind: kind, text: "")].text += prose
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
        let text = TextCleanup.withoutEmDashes(text)
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
        let text = TextCleanup.withoutEmDashes(text)
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
        scheduleSave()
    }

    private func completePlan(_ id: String, markdown: String) {
        let markdown = TextCleanup.withoutEmDashes(markdown)
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

    // MARK: - Command edits

    /// Agents that edit files from the shell (python heredocs, sed -i, patch)
    /// never report an edit, so a command's row gets its edits from the
    /// working tree instead: a snapshot as it starts, another as it finishes,
    /// and the diff between the two. Git-backed projects only.
    private func watchCommand(_ id: String) {
        guard commandTrees[id] == nil, let git = repositoryGit else { return }
        commandTrees[id] = Task.detached(priority: .utility) { try? await git.captureTree() }
    }

    private func settleCommand(_ id: String) {
        guard let before = commandTrees.removeValue(forKey: id), let git = repositoryGit else { return }
        commandSettles[id] = Task { [weak self] in
            guard let base = await before.value, let after = try? await git.captureTree(), base != after,
                  let patch = try? await git.diff(from: base, to: after), !patch.isEmpty else { return }
            let edits = Self.fileEdits(from: patch)
            guard let self, !edits.isEmpty, let entry = entryIndex[id], case .tool(var call) = entry.item.content else { return }
            // A provider that did report its edits keeps them.
            guard call.edits.allSatisfy({ $0.diff == nil }) else { return }
            call.edits = edits
            entry.item.content = .tool(call)
            scheduleSave()
        }
    }

    private var repositoryGit: Git? {
        guard let currentTurnID, let turn = turns.first(where: { $0.id == currentTurnID }), turn.baseCheckpoint != nil,
              let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) else { return nil }
        return Git(thread.worktreePath ?? project.path)
    }

    /// One edit per file in a multi-file patch, with the file's own section as its diff.
    private static func fileEdits(from patch: String) -> [FileEdit] {
        var sections: [String] = []
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                sections.append(String(line))
            } else if !sections.isEmpty {
                sections[sections.count - 1] += "\n" + line
            }
        }
        return sections.compactMap { section in
            guard let file = DiffParser.parse(section).first else { return nil }
            // Huge sections are stats only, so the thread file stays small.
            let diff = section.utf8.count <= 200_000 ? section : nil
            return FileEdit(path: file.path, diff: diff, additions: file.additions, deletions: file.deletions)
        }
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
        scheduleSave()
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
        document.followUps = followUps
        let url = Storage.threadURL(threadID)
        Task { await DiskWriter.shared.encodeAndWrite(document, to: url) }
    }
}

// MARK: - Rehearsal

extension ThreadRuntime {
    /// Starts a turn with no provider behind it, for the website captures: the user message
    /// lands, the working line appears, and `rehearse(_:)` then feeds the events a provider
    /// would. `touchedPaths` and `providerDiff` give the turn a diff for the changes tab.
    func rehearseTurn(_ text: String?, touchedPaths: [String] = [], providerDiff: String? = nil) {
        let turnIndex = (turns.map(\.index).max() ?? -1) + 1
        var turn = TurnRecord(index: turnIndex)
        turn.touchedPaths = touchedPaths.isEmpty ? nil : touchedPaths
        turn.providerDiff = providerDiff
        if let text {
            let userItem = TimelineItem(turnID: turn.id, content: .user(UserMessage(text: text)))
            turn.userItemID = userItem.id
            turns.append(turn)
            append(userItem)
        } else {
            turns.append(turn)
        }
        currentTurnID = turn.id
        phase = .running
        turnStartedAt = .now
        app?.updateThread(threadID) {
            $0.updatedAt = .now
            $0.lastStatus = .running
        }
    }

    /// One provider event, through the same path a live session's events take.
    func rehearse(_ event: ProviderEvent) {
        handle(event)
    }

    /// Tells the changes tab and the diff panel that the turn's diff changed.
    func noteDiffChanged() {
        diffRevision += 1
    }
}
