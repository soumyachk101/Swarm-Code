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
    /// True from init until a history that was not prefetched has been decoded and installed.
    private(set) var isLoadingHistory = false

    var draft = ComposerDraft()
    var isTerminalVisible = false
    var isDiffVisible = false
    /// Which corner of the chat pane the helper panel this thread spawned sits in.
    var subagentPanelDock: PanelDockCorner = .bottomTrailing
    /// The same for the Hydra panel.
    var hydraPanelDock: PanelDockCorner = .bottomTrailing
    /// The head whose timeline the Hydra panel shows.
    var hydraSelectedHeadID: UUID?
    /// The head popped out of the Hydra panel into a second panel of its own, if any, and
    /// the corner that panel sits in.
    var hydraPoppedHeadID: UUID?
    var hydraPoppedPanelDock: PanelDockCorner = .bottomLeading
    /// Heads whose automatic panel the user closed, so they stay in the team panel while
    /// the others fill the room.
    var hydraAutoPopHeld: Set<UUID> = []
    /// The order the user gave the panels inside their corners by dragging; a panel not
    /// listed comes after the listed ones, in the built-in order: helper, team, popped
    /// head, usage, heads popped out automatically.
    var panelStackOrder: [FloatingPanelID] = []
    /// Heads whose automatic panel the user dragged: they keep that corner and count
    /// against its room.
    var hydraAutoPanelDocks: [UUID: PanelDockCorner] = [:]
    /// The Hydra panel was dismissed; the next head to start brings it back.
    var isHydraPanelHidden = false
    /// Heads by the tool row that stands for them in this timeline, so the row can show
    /// who was sent out.
    private(set) var hydraToolHeads: [String: UUID] = [:]
    /// Heads by the provider's own id for them, for the events that come from inside them.
    @ObservationIgnored private var hydraNativeHeads: [String: UUID] = [:]
    /// Reports from Droppy-run heads waiting for the lead to be idle.
    @ObservationIgnored private var hydraPendingReports: [HydraReport] = []
    /// The reports' turn is on its way (see `flushHydraReports`): a head finishing in the
    /// meantime joins it rather than starting a turn of its own.
    @ObservationIgnored private var hydraFlushScheduled = false
    /// The landing under way in this lead's checkout (see `AppModel.landHydraHead`); the
    /// next head's waits behind it, so two never write the same files at once.
    @ObservationIgnored var hydraLanding: Task<Void, Never>?
    /// Delegations still in flight: the heads of each batch report together.
    @ObservationIgnored private var hydraBatches: [UUID: HydraBatch] = [:]
    /// Delegated tasks past the pair's limit, sent out as heads finish.
    @ObservationIgnored private var hydraWaiting: [(delegation: HydraDelegation, batchID: UUID)] = []
    /// How many times heads have gone out for the user's current request; a message of
    /// the user's own starts the count over.
    @ObservationIgnored private var hydraDelegationRounds = 0
    /// How many turns of the user's current request were spent telling the lead its block
    /// could not be read or was held back. Each such message is a turn the lead answers,
    /// and a lead that answers with the same block again would be told again, without end:
    /// past `maxRefusedBlocks` the block is simply dropped and the turn ends. Starts over
    /// with the rounds, on a message of the user's own.
    @ObservationIgnored private var hydraRefusedBlocks = 0
    /// A Droppy-run head's time for one turn (see `HydraBudget`): past it, the head is
    /// stopped and its next turn is its report.
    @ObservationIgnored private var headBudget: Task<Void, Never>?
    @ObservationIgnored private var headBudgetSpent = false
    @ObservationIgnored private var headReportsNext = false
    /// The team's finished work is on its way to the remote (see `AppModel.autoMergeHydraWork`).
    var isHydraMerging = false
    /// What the merge is doing right now, in words, for the timeline: gathering the
    /// team's files, writing the commit, pushing, opening the merge request, merging.
    var hydraMergeStage: String?
    /// When the merge under way began, so the timeline can show how long it has been at it.
    var hydraMergeStartedAt: Date?
    /// A native head's progress while it runs (its provider's note, its tool count, its
    /// spend), kept here rather than on the thread record: the provider reports it many
    /// times a second, and a write to a thread re-renders everything that lists threads.
    /// Only the panel row that shows this head follows these; they land on the record
    /// once the head finishes (see `AppModel.finishHydraHead`).
    var hydraActivity: String?
    var hydraToolCalls = 0
    var hydraTokens = 0
    /// When the head last did anything (a tool, a word of its reply or its reasoning),
    /// and how many file edits its tools have made: what the watchdog reads to tell a
    /// head that is thinking from one that has stalled (see `AppModel.startHydraWatchdog`).
    /// Not observed: it moves with every flush of every head, and the one view that
    /// reads it (the lead's working pill) is redrawn by the watchdog's label instead.
    @ObservationIgnored var hydraLastEventAt: Date?
    var hydraEditCount = 0
    /// How long the head has been quiet, in seconds; zero before it has done anything.
    var hydraIdleSeconds: TimeInterval { hydraLastEventAt.map { Date.now.timeIntervalSince($0) } ?? 0 }

    /// The head's record with its live progress on top, for the views that show it.
    func hydraLiveInfo(_ stored: HydraHeadInfo) -> HydraHeadInfo {
        guard stored.status == .running else { return stored }
        var info = stored
        if let activity = hydraActivity { info.activity = activity }
        info.toolCalls = max(info.toolCalls, hydraToolCalls)
        info.tokens = max(info.tokens, hydraTokens)
        return info
    }

    private struct HydraBatch {
        var pending: Set<UUID>
        var reports: [HydraReport] = []
    }
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
    /// Which session the runtime is listening to. Every session made carries the count it
    /// was made under, and its events are dropped once the count has moved on: a CLI that
    /// closes long after it was let go used to end the turn that replaced it, take down
    /// the live session with it and leave its process running with nothing holding it.
    @ObservationIgnored private var sessionEpoch = 0
    @ObservationIgnored private var entryIndex: [String: TimelineEntry] = [:]
    @ObservationIgnored private var pendingDeltas: [String: PendingDelta] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Bumped by anything that changes what `saveNow` writes, so the periodic save
    /// during a quiet stretch finds nothing new and does no work.
    @ObservationIgnored private var saveRevision = 0
    @ObservationIgnored private var lastSavedRevision = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var historyLoad: Task<Void, Never>?
    @ObservationIgnored private var currentTurnID: UUID?
    @ObservationIgnored private var resumeAnchor: String?
    @ObservationIgnored private var interruptWatchdog: Task<Void, Never>?
    /// Working-tree snapshots taken as command tools start, by tool id, and
    /// the diffs being settled as they finish (see `watchCommand`).
    @ObservationIgnored private var commandTrees: [String: Task<String?, Never>] = [:]
    @ObservationIgnored private var commandSettles: [String: Task<Void, Never>] = [:]
    /// Snapshots run one after another: each is several git processes over the whole
    /// checkout, and a turn can have many commands in flight at once.
    @ObservationIgnored private var treeCaptures: Task<String?, Never>?
    /// The tree a command left behind, with the count below as it stood when it was taken.
    /// While that count has not moved, nothing can have changed the working tree since, so
    /// the next command takes it as its own "before" and snapshots nothing.
    @ObservationIgnored private var settledTree: (tree: String, epoch: Int)?
    /// Bumped by anything that could write a file: a command starting, a tool that edits.
    @ObservationIgnored private var treeEpoch = 0
    /// The row a turn's todo list lives on, so each update finds it without scanning the
    /// timeline.
    @ObservationIgnored private var todosEntryID: String?
    /// Paths the lead's native heads changed during this turn. Their tools arrive as
    /// `.agentEvent` and are rehearsed onto the heads' own timelines, so without this the
    /// lead's turn would count none of their work and a merge would take a fraction of it.
    @ObservationIgnored private var hydraTouched: Set<String> = []
    /// Snapshots around a native head's shell commands, by head and tool (see
    /// `watchHydraCommand`).
    @ObservationIgnored private var hydraCommandTrees: [String: Task<String?, Never>] = [:]

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
        /// Providers that run heads natively define them at launch, so the team restarts
        /// the session when Hydra is switched or its pair changes.
        var hydra: HydraLaunch?
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
        if let document = DocumentPrefetch.shared.take(threadID) {
            install(document)
        } else {
            // The file is read and decoded off the main thread so the click that
            // opens the chat paints at once; the runtime shows an empty history
            // until it lands.
            isLoadingHistory = true
            historyLoad = Task.detached(priority: .userInitiated) { [threadID] in
                let document = Storage.decodeDocument(threadID) ?? ThreadDocument(threadID: threadID)
                await self.finishLoad(document)
            }
        }
    }

    private func install(_ document: ThreadDocument) {
        turns = document.turns + turns
        usage = usage ?? document.usage
        followUps = document.followUps.filter { !$0.isEmpty } + followUps
        // Thinking with no text is nothing to show or keep: Claude Code redacts its
        // reasoning and streams only empty deltas, which older builds stored as blank
        // entries. They are dropped here and never created below. Threads stored before
        // the app flattened model prose on the way in are cleaned as they are read, so
        // no reply from any earlier build can put an em dash back on screen.
        let loaded = document.items.filter { !$0.isEmptyReasoning }.map { TimelineEntry($0.cleanedOfEmDashes) }
        for entry in loaded {
            entryIndex[entry.id] = entry
            endStreaming(entry)
            if case .tool(var call) = entry.item.content, call.status == .running {
                call.finish(.failed)
                entry.item.content = .tool(call)
            }
        }
        entries = loaded + entries
        for index in turns.indices where turns[index].status == .running {
            turns[index].status = .interrupted
        }
        // The load above normalizes what it read (streaming flags cleared, running
        // tools failed), so memory already differs from disk.
        saveRevision += 1
    }

    private func finishLoad(_ document: ThreadDocument) {
        guard isLoadingHistory else { return }
        install(document)
        isLoadingHistory = false
        historyLoad = nil
    }

    /// Anything that continues the history (a new turn) waits for it first.
    func ensureLoaded() async {
        if let historyLoad { await historyLoad.value }
    }

    var isRunning: Bool { phase != .idle }

    var thread: ChatThread? { app?.thread(threadID) }

    /// Whether any head of this lead, native or Droppy-run, is still at work. The native
    /// ones run inside the lead's own session, so a turn with heads at work is never
    /// interrupted on the user's behalf by a new message: only the Stop button and
    /// Escape stop it, and those are the user stopping the lead on purpose.
    var hasWorkingHeads: Bool {
        (app?.runningHydraHeads(of: threadID) ?? 0) > 0
    }

    /// Whether any native head of this lead is still at work: those are the ones stopping
    /// the lead's turn would take down. A Droppy-run head lives in a thread of its own and
    /// reports to whatever turn the lead is on, so it survives the lead being stopped.
    var hasWorkingNativeHeads: Bool {
        guard let app else { return false }
        return app.runningHydraHeads(of: threadID) > app.runningDroppyHeads(of: threadID)
    }

    var sentPrompts: [String] {
        entries.compactMap { entry in
            if case .user(let message) = entry.item.content, !message.isFromHydra, !message.isHydraBrief { return message.text }
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
        // With every message going to a head, the lead stays idle for the reports.
        if dispatchSentHead(text: text, attachments: attachments) { return }
        Task { await ensureLoaded(); await startTurn(text: text, attachments: attachments) }
    }

    func sendHydraBrief(_ text: String, attachments: [Attachment]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
              phase == .idle else { return }
        draft = ComposerDraft()
        // The head's clock starts with its brief, so one that never answers counts as quiet.
        hydraLastEventAt = .now
        Task { await ensureLoaded(); await startTurn(text: text, attachments: attachments, hydraBrief: true) }
    }

    // MARK: - Follow-up queue

    /// Whether the chat box can queue a message: while a turn runs, and while heads are
    /// out with the lead waiting on them. Return sends to the idle lead at once; the
    /// queue is for what should wait until the heads have reported.
    var canQueue: Bool {
        isRunning || hasWorkingHeads
    }

    /// Instantly queues the composer's draft as a follow-up while a turn runs or heads are
    /// at work. The prompt, pics and other attachments included, is sent as a direct user
    /// chat message once the running turn (or the heads' report) finishes. Stacks up:
    /// every queued prompt runs in order. With nothing to queue behind, the draft simply
    /// goes out: the queue chord is never a dead key.
    func queueDraftAsFollowUp() {
        guard !draft.isEmpty else { return }
        guard canQueue else {
            send()
            return
        }
        enqueueFollowUp(text: draft.text, attachments: draft.attachments)
        draft = ComposerDraft()
    }

    /// Draft captured by Return while a turn runs: stop the turn, then send this
    /// right away instead of queueing it behind the queue.
    @ObservationIgnored private var pendingSend: PendingSend?
    /// A queued follow-up's turn is on its way to an idle lead (see
    /// `flushFollowUpsIfIdle`): a second prompt queued in the meantime waits its
    /// turn rather than starting one of its own, so two never double-send.
    @ObservationIgnored private var followUpFlushScheduled = false

    private struct PendingSend {
        var text: String
        var attachments: [Attachment]
    }

    /// Interrupts the running turn and sends the draft as soon as the stop
    /// lands, instead of queueing it as a follow-up. The composer clears at
    /// once; the message goes out when the turn fully stops (or immediately,
    /// if the turn finished on its own in the meantime). With heads at work the
    /// turn is left alone and the draft queues instead: see `hasWorkingHeads`.
    func interruptAndSend() {
        guard !draft.isEmpty, phase != .idle else { return }
        // With every message going to a head, Return while the lead works sends the
        // draft to a head and leaves the lead's turn alone.
        if dispatchSentHead(text: draft.text, attachments: draft.attachments) {
            draft = ComposerDraft()
            return
        }
        // Heads at work are never stopped by a new message. The native ones run inside
        // the lead's own session, so interrupting the turn would kill them mid-task and
        // throw away minutes of their work. The draft goes to a Droppy-run head of its
        // own when the settings allow it, else it waits as a follow-up behind the
        // running turn; either way nothing is interrupted.
        if hasWorkingHeads {
            enqueueFollowUp(text: draft.text, attachments: draft.attachments)
            draft = ComposerDraft()
            return
        }
        pendingSend = PendingSend(text: draft.text, attachments: draft.attachments)
        draft = ComposerDraft()
        interrupt()
    }

    /// Pairs the dragged follow-up onto another so they go out as one message: both
    /// carry the target's bundle (or a fresh one), and the dragged prompt moves to sit
    /// right after the bundle's last prompt.
    func bundleFollowUp(_ id: UUID, onto target: UUID) {
        guard id != target,
              let targetIndex = followUps.firstIndex(where: { $0.id == target }),
              followUps.firstIndex(where: { $0.id == id }) != nil else { return }
        let bundle = followUps[targetIndex].bundleID ?? UUID()
        followUps[targetIndex].bundleID = bundle
        var dragged = followUps.remove(at: followUps.firstIndex(where: { $0.id == id })!)
        dragged.bundleID = bundle
        // The target still carries the bundle, so this always finds at least it.
        let insertAt = (followUps.lastIndex(where: { $0.bundleID == bundle }) ?? (followUps.count - 1)) + 1
        followUps.insert(dragged, at: min(insertAt, followUps.count))
        saveRevision += 1
        scheduleSave()
    }

    /// Drops a prompt from its bundle when neither neighbour shares it, and dissolves
    /// a bundle left with a single prompt.
    private func unbundleIfSeparated(_ id: UUID) {
        guard let index = followUps.firstIndex(where: { $0.id == id }),
              let bundle = followUps[index].bundleID else { return }
        let prevShares = index > 0 && followUps[index - 1].bundleID == bundle
        let nextShares = index + 1 < followUps.count && followUps[index + 1].bundleID == bundle
        guard !prevShares && !nextShares else { return }
        followUps[index].bundleID = nil
        let remaining = followUps.filter { $0.bundleID == bundle }
        if remaining.count == 1, let lone = followUps.firstIndex(where: { $0.id == remaining[0].id }) {
            followUps[lone].bundleID = nil
        }
    }

    /// Clears any bundle held by only one prompt.
    private func tidyBundles() {
        var counts: [UUID: Int] = [:]
        for prompt in followUps {
            if let bundle = prompt.bundleID { counts[bundle, default: 0] += 1 }
        }
        for index in followUps.indices {
            if let bundle = followUps[index].bundleID, counts[bundle] == 1 {
                followUps[index].bundleID = nil
            }
        }
    }

    /// The merged prompt for the bundle starting at `index`, without removing it.
    private func mergedBundle(startingAt index: Int) -> FollowUpPrompt {
        let first = followUps[index]
        guard let bundle = first.bundleID else { return first }
        var end = index
        while end + 1 < followUps.count, followUps[end + 1].bundleID == bundle { end += 1 }
        let members = followUps[index...end]
        let texts = members.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var merged = first
        merged.text = texts.joined(separator: "\n\n")
        merged.attachments = members.flatMap { $0.attachments }
        merged.bundleID = nil
        return merged
    }

    /// Removes the prompt at `index` and every following adjacent prompt with the same
    /// non-nil bundle, returning them as one merged prompt.
    private func takeBundle(startingAt index: Int) -> FollowUpPrompt {
        let merged = mergedBundle(startingAt: index)
        let bundle = followUps[index].bundleID
        if let bundle {
            var end = index
            while end + 1 < followUps.count, followUps[end + 1].bundleID == bundle { end += 1 }
            followUps.removeSubrange(index...end)
        } else {
            followUps.remove(at: index)
        }
        return merged
    }

    /// Sends a queued follow-up right away instead of waiting its turn: the running turn
    /// stops and the prompt goes out as soon as the stop lands, exactly as Return does with
    /// the draft; idle, it simply sends. The rest of the queue waits for the new turn.
    /// With native heads at work nothing stops, as with Return: the prompt goes to a head
    /// of its own when the settings allow it, else it stays at the front of the queue.
    /// Droppy-run heads live on through a stop, so with only those out the turn stops for
    /// the prompt as it would with none: "now" means now.
    func sendFollowUpNow(_ id: UUID) {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }
        var start = index
        if let bundle = followUps[index].bundleID {
            while start > 0, followUps[start - 1].bundleID == bundle { start -= 1 }
        }
        let prompt = takeBundle(startingAt: start)
        saveRevision += 1
        scheduleSave()
        guard !prompt.isEmpty else { return }
        if phase == .idle {
            if handleLocalCommand(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)) { return }
            Task { await ensureLoaded(); await startTurn(text: prompt.text, attachments: prompt.attachments) }
        } else if pendingSend == nil {
            // Native heads at work are never stopped for a queued prompt: they run inside
            // the lead's session and an interrupt would kill them. The prompt goes to a
            // Droppy-run head when the settings allow it, else back to the front of the
            // queue to wait for the turn, and the lead keeps working.
            if hasWorkingNativeHeads {
                if !dispatchQueuedHead(prompt) {
                    followUps.insert(prompt, at: 0)
                    saveRevision += 1
                    scheduleSave()
                }
                return
            }
            pendingSend = PendingSend(text: prompt.text, attachments: prompt.attachments)
            interrupt()
        } else {
            // Return already has a message going out the moment the turn stops; this one
            // goes right behind it.
            followUps.insert(prompt, at: 0)
            saveRevision += 1
            scheduleSave()
        }
    }

    func enqueueFollowUp(text: String, attachments: [Attachment]) {
        let prompt = FollowUpPrompt(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            attachments: attachments
        )
        guard !prompt.isEmpty else { return }
        // With Hydra on, a task queued behind a running turn goes to a head right away,
        // with a note on what the lead is doing, instead of waiting its turn.
        if phase != .idle, dispatchQueuedHead(prompt) { return }
        followUps.append(prompt)
        saveRevision += 1
        scheduleSave()
        // An idle lead takes the next queued message at once, even with heads still
        // out: the queue only ever waits behind a running turn, never behind an
        // idle lead. Without this a prompt queued while the lead is idle (steered
        // behind heads at work) sits until the next turn ends, which may be never.
        flushFollowUpsIfIdle()
    }

    /// Hands a queued prompt to a Droppy-run head, when the app and the chat allow it and
    /// the pair has room for one more. Returns whether the head went out.
    private func dispatchQueuedHead(_ prompt: FollowUpPrompt) -> Bool {
        guard let app, app.settings.hydraQueueHeads || app.settings.hydraAlwaysHeads else { return false }
        return dispatchHead(prompt, origin: .queued)
    }

    /// Hands a message the user sent, idle lead or not, to a Droppy-run head, when every
    /// message goes to heads and the pair has room. The local commands stay with the chat.
    /// Returns whether the head went out; if not, the message goes the ordinary way.
    private func dispatchSentHead(text: String, attachments: [Attachment]) -> Bool {
        guard let app, app.settings.hydraAlwaysHeads else { return false }
        let prompt = FollowUpPrompt(text: text.trimmingCharacters(in: .whitespacesAndNewlines), attachments: attachments)
        guard !prompt.isEmpty, prompt.text != "/plan", prompt.text != "/compact" else { return false }
        return dispatchHead(prompt, origin: .sent)
    }

    /// Sends a prompt out as a Droppy-run head with a note on what the lead is doing, or
    /// that it is idle. Returns whether the head went out.
    private func dispatchHead(_ prompt: FollowUpPrompt, origin: HydraHeadInfo.Origin) -> Bool {
        guard let app, let thread, let launch = app.hydraLaunch(for: thread),
              launch.hasRoom(running: app.runningDroppyHeads(of: threadID)) else { return false }
        let task = TextCleanup.singleLine(prompt.text, limit: 60)
        let context = app.hydraChatContext(for: threadID)
        let leadIsWorking = phase != .idle
        let text = prompt.text
        return app.spawnDroppyHead(from: threadID, task: task, origin: origin, attachments: prompt.attachments) { persona, workplace in
            HydraPrompts.queuedHeadPrompt(persona: persona, task: text, context: context, workplace: workplace, leadIsWorking: leadIsWorking)
        } != nil
    }

    /// Follow-ups queued while the heads were all busy go out as heads once one frees up,
    /// as long as the lead is still at work; an idle lead takes them itself, in order.
    private func dispatchQueuedFollowUps() {
        guard phase != .idle else { return }
        while !followUps.isEmpty {
            let merged = mergedBundle(startingAt: 0)
            guard dispatchQueuedHead(merged) else { break }
            _ = takeBundle(startingAt: 0)
            saveRevision += 1
            scheduleSave()
        }
    }

    /// Sends the next queued follow-up to an idle lead at once, even with heads still
    /// out. A turn the user stopped waits for them instead (see `drainFollowUps`).
    private func flushFollowUpsIfIdle() {
        guard phase == .idle, !followUpFlushScheduled, !followUps.isEmpty,
              thread?.lastStatus != .interrupted else { return }
        followUpFlushScheduled = true
        Task { await startQueuedFollowUpTurn() }
    }

    /// The turn `flushFollowUpsIfIdle` scheduled. Something that started first (the
    /// heads' reports, or the user's own word) owns the queue now: its end drains it.
    private func startQueuedFollowUpTurn() async {
        followUpFlushScheduled = false
        guard phase == .idle else { return }
        // The queue drains exactly as after a completed turn: in order, skipping
        // prompts that emptied while queued.
        _ = drainFollowUps(after: .completed)
    }

    func removeFollowUp(_ id: UUID) {
        followUps.removeAll { $0.id == id }
        tidyBundles()
        saveRevision += 1
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
        unbundleIfSeparated(id)
        saveRevision += 1
        scheduleSave()
        return true
    }

    func updateFollowUp(_ id: UUID, text: String, attachments: [Attachment]) {
        guard let index = followUps.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, attachments.isEmpty {
            followUps.remove(at: index)
            tidyBundles()
        } else {
            followUps[index].text = text
            followUps[index].attachments = attachments
        }
        saveRevision += 1
        scheduleSave()
    }

    /// Sends the next queued follow-up as a direct user message. Only runs when idle after a
    /// completed turn: an interrupted turn means the user hit stop, so the queue waits for them.
    /// Returns whether a turn starts.
    private func drainFollowUps(after status: TurnStatus) -> Bool {
        guard status == .completed, phase == .idle, !followUps.isEmpty else { return false }
        var next = takeBundle(startingAt: 0)
        saveRevision += 1
        // Skip prompts that emptied while queued (an attachment file deleted on disk still counts,
        // so only the text+attachment check applies).
        while next.isEmpty, !followUps.isEmpty {
            next = takeBundle(startingAt: 0)
            saveRevision += 1
        }
        guard !next.isEmpty else {
            scheduleSave()
            return false
        }
        scheduleSave()
        if handleLocalCommand(next.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return drainFollowUps(after: status)
        }
        Task { await ensureLoaded(); await startTurn(text: next.text, attachments: next.attachments) }
        return true
    }

    func implementPlan(_ entryID: String) {
        guard phase == .idle, let entry = entryIndex[entryID], case .plan(var plan) = entry.item.content else { return }
        plan.state = .accepted
        entry.item.content = .plan(plan)
        saveRevision += 1
        app?.updateThread(threadID) { $0.interactionMode = .build }
        Task { await ensureLoaded(); await startTurn(text: "Implement the plan.", attachments: []) }
    }

    func dismissPlan(_ entryID: String) {
        guard let entry = entryIndex[entryID], case .plan(var plan) = entry.item.content else { return }
        plan.state = .dismissed
        entry.item.content = .plan(plan)
        saveRevision += 1
        scheduleSave()
    }

    private func handleLocalCommand(_ text: String) -> Bool {
        switch text {
        case "/plan":
            app?.updateThread(threadID) { $0.interactionMode = $0.interactionMode == .plan ? .build : .plan }
            return true
        case "/compact" where thread?.provider == .codex || thread?.provider == .copilot || thread?.provider == .deepseek || thread?.provider == .meta || thread?.provider == .pi:
            compact()
            return true
        default:
            return false
        }
    }

    /// Starts a turn on `text`. `hydraHeads` marks the message as heads reporting back to
    /// their lead rather than the user's own words; `hydraBrief` marks it as the lead's
    /// brief to a head, shown as a pill rather than a plain bubble.
    private func startTurn(text: String, attachments: [Attachment], hydraHeads: [Int]? = nil, hydraBrief: Bool = false) async {
        guard let app, let initialThread = app.thread(threadID), let project = app.project(initialThread.projectID) else { return }
        let turnIndex = (turns.map(\.index).max() ?? -1) + 1
        var turn = TurnRecord(index: turnIndex)
        let userItem = TimelineItem(turnID: turn.id, content: .user(UserMessage(text: text, attachments: attachments, hydraHeads: hydraHeads, hydraBrief: hydraBrief ? true : nil)))
        turn.userItemID = userItem.id
        turns.append(turn)
        saveRevision += 1
        currentTurnID = turn.id
        append(userItem)
        phase = .starting
        turnStartedAt = .now
        app.updateThread(threadID) {
            $0.updatedAt = .now
            $0.lastStatus = .running
        }
        // A settled thread put back to work is open again.
        app.reopenIfSettled(threadID)
        if hydraHeads == nil {
            hydraDelegationRounds = 0
            hydraRefusedBlocks = 0
        }
        // A finished head told more from the panel is at work again: its lead's team
        // counts it, and its next report goes out as a fresh one.
        if let info = initialThread.hydra, info.kind == .droppy, info.isFinished {
            app.updateHydraHead(threadID) {
                $0.status = .running
                $0.finishedAt = nil
            }
        }
        // A Droppy-run head gets so long for a turn, on any provider. The API sessions
        // stop themselves a little sooner from inside the turn; this is the backstop, and
        // the only stop a CLI head has.
        let isFinalReport = headReportsNext
        headReportsNext = false
        if initialThread.hydra?.kind == .droppy {
            let allowance = isFinalReport
                ? HydraBudget.reportSeconds
                : HydraBudget.maxSeconds + (initialThread.provider.isAPIKeyBased ? 90 : 0)
            headBudget?.cancel()
            headBudget = Task { [weak self] in
                try? await Task.sleep(for: .seconds(allowance))
                guard let self, !Task.isCancelled, self.currentTurnID == turn.id, self.phase != .idle else { return }
                self.headBudgetSpent = !isFinalReport
                self.interrupt()
            }
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
        let checkpointRef = Git.checkpointRef(thread: threadID, turn: turnIndex, phase: "start")
        // Anything could have happened in the checkout since the last turn, so no snapshot
        // from it stands any more. The heads' files are not cleared here: a native head
        // works on after the lead's reply ends, and what it changed then belongs to the
        // next turn, which takes it up at its end (see `finishTurn`).
        settledTree = nil
        treeEpoch += 1
        // The checkpoint is several git processes over the whole checkout. It runs while
        // the session starts rather than in front of it, and both are waited for before a
        // word reaches the model, so nothing the agent does can slip past the snapshot.
        let checkpoint = Task.detached(priority: .userInitiated) { () -> Bool in
            guard await git.isRepository() else { return false }
            return (try? await git.captureCheckpoint(checkpointRef)) != nil
        }

        do {
            // The session starts alongside the checkpoint. It is picked up from the
            // runtime afterwards rather than handed back as a value, because a session is
            // not Sendable and this task is one of its own.
            let start = Task { () async throws -> Void in _ = try await self.ensureSession(directory: directory) }
            if await checkpoint.value {
                updateTurn(turn.id) { $0.baseCheckpoint = checkpointRef }
            }
            try await start.value
            // The user can stop a turn while it is still starting.
            guard currentTurnID == turn.id, let session, let thread = app.thread(threadID) else { return }
            var prompt = text
            let files = attachments.filter { !$0.isImage }
            if !files.isEmpty {
                prompt += "\n\nAttached files:\n" + files.map { "- \($0.path)" }.joined(separator: "\n")
            }
            // A lead whose heads are Droppy-run is told how to ask Droppy Code for them. A
            // session that keeps that policy in its system prompt (the API providers, and
            // the providers with heads of their own sending them out elsewhere) gets only
            // the note on its team in front of a message; every other CLI gets the policy
            // in front of every message, having nowhere else to keep it.
            if let launch = app.hydraLaunch(for: thread), !launch.runsNatively {
                let team = HydraPrompts.teamStatus(app.hydraTeam(of: threadID).compactMap(\.hydra))
                let canDelegate = hydraDelegationRounds < HydraPrompts.maxDelegationRounds
                if Self.keepsHydraPolicyInSystemPrompt(thread.provider) {
                    prompt = (hydraHeads == nil ? HydraPrompts.fallbackTurnNote(team: team) : HydraPrompts.fallbackReportNote(team: team, canDelegate: canDelegate)) + prompt
                } else if hydraHeads == nil {
                    prompt = HydraPrompts.fallbackPreamble(launch, team: team) + prompt
                } else {
                    prompt = HydraPrompts.fallbackReportPreamble(launch, team: team, canDelegate: canDelegate) + prompt
                }
            }
            phase = .running
            try await session.send(TurnInput(
                text: prompt,
                images: thread.provider.supportsImages ? attachments.filter(\.isImage) : [],
                model: thread.model,
                effort: thread.effort,
                serviceTier: serviceTier(for: thread),
                fastMode: thread.fastMode,
                runtimeMode: thread.runtimeMode,
                interactionMode: thread.interactionMode,
                isFinalReport: isFinalReport
            ))
            if isFirstTurn { generateTitle(from: text) }
        } catch {
            appendNotice(.error, error.localizedDescription)
            await finishTurn(status: .failed)
        }
    }

    /// Whether the provider's session carries the lead's Hydra policy from launch: the API
    /// sessions put it in their system prompt, and the providers with heads of their own
    /// define the heads, or the policy for Droppy-run ones, at launch. Such a session takes
    /// the team as part of its signature, so a change to the team restarts it.
    private static func keepsHydraPolicyInSystemPrompt(_ provider: ProviderKind) -> Bool {
        AppModel.hydraIsNative(provider) || provider.isAPIKeyBased
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
        // A pair that sends its heads out on another provider names their model from that
        // provider's catalogue, which this chat may never have loaded. The lead's brief
        // names the model, and the brief is part of the session's signature, so the
        // catalogue loads first rather than the session restarting once it has.
        if app.hydraIsOn(thread), let pair = app.hydraPair(for: thread), app.hydraHeadsProvider(of: pair) != thread.provider {
            await app.providers.loadCatalog(app.hydraHeadsProvider(of: pair))
        }
        // Providers with heads of their own define them at launch (or, with the heads
        // sent out elsewhere, the policy for asking Droppy Code for them); the API
        // providers put the lead's Hydra policy in their system prompt. Either way the
        // team is part of the session, and a change to it restarts one.
        let hydra = Self.keepsHydraPolicyInSystemPrompt(thread.provider) ? app.hydraLaunch(for: thread) : nil
        let signature = SessionSignature(
            provider: thread.provider,
            directory: directory,
            launchRuntimeMode: thread.provider == .cursor || thread.provider == .grok || thread.provider == .devin || thread.provider == .antigravity ? thread.runtimeMode : copilotLaunchMode,
            launchEffort: thread.provider == .claude || thread.provider == .antigravity ? thread.effort : nil,
            launchFast: thread.provider == .claude ? thread.fastMode : nil,
            launchModel: thread.provider == .antigravity ? thread.model : nil,
            launchInteraction: thread.provider == .antigravity ? thread.interactionMode : nil,
            hydra: hydra
        )
        if let session, session.isRunning, sessionSignature == signature { return session }
        releaseSession(stop: true)
        // The session the heads lived in is gone, and so are they.
        stopNativeHeads()

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
                    apiKey: app.settings.apiKey(for: thread.provider),
                    hydra: hydra,
                    transcript: apiTranscript(),
                    isHydraHead: thread.hydra?.kind == .droppy
                )
                let created: any ProviderSession = switch thread.provider {
                case .deepseek: DeepSeekSession(configuration: configuration)
                case .meta: MetaSession(configuration: configuration)
                default: DeepSeekSession(configuration: configuration)
                }
                // Only the session the runtime still holds is listened to.
                let epoch = sessionEpoch
                created.onEvent = { [weak self] event in
                    guard let self, self.sessionEpoch == epoch else { return }
                    self.handle(event)
                }
                return created
            }
            var candidate = makeAPISession(resumeID: thread.providerSessionID)
            session = candidate
            sessionSignature = signature
            let sessionID: String
            do {
                sessionID = try await candidate.start()
            } catch where thread.providerSessionID != nil {
                // The session that would not resume is let go of entirely, handler and
                // all, before the one that starts over takes its place.
                releaseSession(stop: true)
                candidate = makeAPISession(resumeID: nil)
                session = candidate
                sessionSignature = signature
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
                interactionMode: thread.interactionMode,
                hydra: hydra
            )
            let created: any ProviderSession = switch thread.provider {
            case .codex: CodexSession(configuration: configuration)
            case .claude: ClaudeSession(configuration: configuration)
            case .antigravity: AntigravitySession(configuration: configuration)
            case .copilot: CopilotSession(configuration: configuration)
            case .commandcode: CommandCodeSession(configuration: configuration)
            case .pi: PiSession(configuration: configuration)
            case .cursor, .opencode, .grok, .devin: ACPSession(configuration: configuration)
            case .deepseek: DeepSeekSession(configuration: configuration)
            case .meta: MetaSession(configuration: configuration)
            }
            // Only the session the runtime still holds is listened to.
            let epoch = sessionEpoch
            created.onEvent = { [weak self] event in
                guard let self, self.sessionEpoch == epoch else { return }
                self.handle(event)
            }
            return created
        }

        var candidate = makeSession(resumeID: thread.providerSessionID)
        session = candidate
        sessionSignature = signature
        let sessionID: String
        do {
            sessionID = try await candidate.start()
        } catch where thread.providerSessionID != nil {
            // The session that would not resume is let go of entirely, handler and all,
            // before the one that starts over takes its place.
            releaseSession(stop: true)
            candidate = makeSession(resumeID: nil)
            session = candidate
            sessionSignature = signature
            sessionID = try await candidate.start()
        }
        resumeAnchor = nil
        app.updateThread(threadID) { $0.providerSessionID = sessionID }
        return candidate
    }

    /// The conversation before the current turn as plain exchanges, for an API session
    /// that starts over: it keeps its history in memory only, so this is how a head
    /// steered on after its session went, or any chat reopened later, still knows what
    /// was said and done. Tool calls stay out; the replies say what they did. Bounded, so
    /// a long thread does not send its whole past with every relaunch.
    private func apiTranscript() -> [TranscriptMessage] {
        // One pass to collect the exchanges, then the runs are joined rather than
        // appended into one another: repeated `+=` on array elements copies the whole
        // reply for every fragment, which is quadratic on fragmented history.
        let exclude = currentTurnID
        var fragments: [(assistant: Bool, text: String)] = []
        fragments.reserveCapacity(entries.count)
        for entry in entries where entry.item.turnID != exclude {
            switch entry.item.content {
            case .user(let message) where !message.text.isEmpty:
                fragments.append((assistant: false, text: message.text))
            case .assistant(let message) where !message.text.isEmpty:
                fragments.append((assistant: true, text: message.text))
            default:
                break
            }
        }
        var transcript: [TranscriptMessage] = []
        transcript.reserveCapacity(fragments.count)
        var index = 0
        while index < fragments.count {
            if !fragments[index].assistant {
                transcript.append(TranscriptMessage(role: .user, text: fragments[index].text))
                index += 1
                continue
            }
            // The status lines a turn streams between its tools read as one reply.
            let runStart = index
            while index < fragments.count, fragments[index].assistant { index += 1 }
            let joined = fragments[runStart..<index].map(\.text).joined(separator: "\n\n")
            transcript.append(TranscriptMessage(role: .assistant, text: joined))
        }
        var kept = Array(transcript.suffix(40))
        var budget = 60_000
        for index in kept.indices.reversed() {
            let length = kept[index].text.count
            if length <= budget {
                budget -= length
            } else if budget > 200 {
                kept[index].text = "…" + String(kept[index].text.suffix(budget))
                budget = 0
            } else {
                kept.removeSubrange(...index)
                break
            }
        }
        return kept
    }

    // MARK: - Controls

    func interrupt() {
        guard phase != .idle else { return }
        let turnID = currentTurnID
        interruptWatchdog?.cancel()
        interruptWatchdog = nil
        // Nothing has been sent yet: the provider has no turn of its own to stop, and
        // asking it would do nothing at all, leaving the watchdog to kill a session that
        // is only just starting. The turn ends here instead, and the message it was about
        // to send never goes.
        if phase == .starting {
            currentTurnID = nil
            Task { await finishTurn(status: .interrupted, turnID: turnID) }
            return
        }
        Task {
            if let session {
                await session.interrupt()
            } else {
                await finishTurn(status: .interrupted)
            }
        }
        interruptWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled, self.currentTurnID == turnID, turnID != nil else { return }
            self.releaseSession(stop: true)
            await self.finishTurn(status: .interrupted)
        }
    }

    func resolve(_ request: ApprovalRequest, option: ApprovalRequest.Option) {
        approvals.removeAll { $0.id == request.id }
        if request.kind == .plan, let itemID = request.toolItemID,
           let entry = entryIndex[itemID], case .plan(var plan) = entry.item.content {
            plan.state = option.role == .approve ? .accepted : .dismissed
            entry.item.content = .plan(plan)
            saveRevision += 1
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
            releaseSession(stop: true)
            if index == 0 {
                app.updateThread(threadID) { $0.providerSessionID = nil }
            } else {
                resumeAnchor = turns[index - 1].providerAnchor
            }
        default:
            // A provider that cannot rewind a conversation of its own starts a new one:
            // the files, the timeline and the draft are put back all the same, and the
            // next turn opens from the shortened history rather than the one that was
            // reverted away.
            releaseSession(stop: true)
            resumeAnchor = nil
            app.updateThread(threadID) { $0.providerSessionID = nil }
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
        saveRevision += 1
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

    /// Lets a session go: from here on it drives nothing, whatever it still has to say as
    /// it closes. Its handler is cleared a turn of the loop later, because a session that
    /// is ending usually says so from inside that very handler.
    private func releaseSession(stop: Bool) {
        sessionEpoch += 1
        sessionSignature = nil
        guard let old = session else { return }
        session = nil
        if stop { old.stop() }
        Task { old.onEvent = nil }
    }

    func stopSession() {
        releaseSession(stop: true)
        stopNativeHeads()
        // A turn cut off here has events its save timer has not written yet, and the timer
        // may not outlive the runtime.
        if phase != .idle { saveNow() }
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
            if call.kind == .command { watchCommand(id, call) }
        case .toolOutput(let id, let text):
            queueDelta(id, .toolOutput, text)
        case .toolUpdated(let id, let update):
            flushDeltas()
            applyToolUpdate(id, update)
            if let entry = entryIndex[id], case .tool(let call) = entry.item.content,
               call.kind == .command, call.status != .running {
                settleCommand(id)
            }
            if let status = update.status, status != .running, let headID = hydraToolHeads[id] {
                hydraToolFinished(headID, status: status, output: update.output)
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
            saveRevision += 1
            // The turn just spent from the account, so the balance read before it is stale.
            if let provider = thread?.provider { app?.providers.invalidateCredits(provider) }
        case .diff(let diff):
            if let currentTurnID { updateTurn(currentTurnID) { $0.providerDiff = diff } }
        case .notice(let notice):
            appendNotice(notice.level, notice.message)
        case .usageLimit(let resetsAt):
            app?.autoContinue.noteLimit(threadID, resetsAt: resetsAt)
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
            releaseSession(stop: false)
            approvals.removeAll()
            questions.removeAll()
            stopNativeHeads()
            if currentTurnID != nil {
                let name = thread?.provider.displayName ?? "The agent"
                appendNotice(.error, error ?? "\(name) stopped unexpectedly.")
                Task { await finishTurn(status: .failed) }
            }
        case .agentStarted(let spawn):
            hydraAgentStarted(spawn)
        case .agentEvent(let agentID, let event):
            hydraAgentEvent(agentID, event)
        case .agentProgress(let agentID, let summary, let lastTool, let tokens, let toolCalls):
            guard let headID = hydraNativeHeads[agentID], let headRuntime = app?.runtime(for: headID) else { break }
            if let summary, !summary.isEmpty { headRuntime.hydraActivity = summary } else if let lastTool { headRuntime.hydraActivity = lastTool }
            if let tokens { headRuntime.hydraTokens = tokens }
            if let toolCalls { headRuntime.hydraToolCalls = toolCalls }
            headRuntime.hydraLastEventAt = .now
        case .agentFinished(let agentID, let status, let summary):
            hydraAgentFinished(agentID, status: status, summary: summary)
        }
    }

    /// Closes the running turn. `turnID` names the turn when the caller has already taken
    /// it out of `currentTurnID`, as a stop during the start of a turn does, so that the
    /// message on its way can no longer be sent.
    private func finishTurn(status: TurnStatus, turnID explicitTurnID: UUID? = nil) async {
        interruptWatchdog?.cancel()
        interruptWatchdog = nil
        headBudget?.cancel()
        headBudget = nil
        guard let turnID = explicitTurnID ?? currentTurnID, let turn = turns.first(where: { $0.id == turnID }) else {
            phase = .idle
            turnStartedAt = nil
            drainPendingSend()
            return
        }
        // Command diffs land before the turn's own summary counts them, and
        // while the turn is still current so the snapshots can be compared. The heads'
        // commands settle with them: their files are part of this turn's work.
        for id in Array(commandTrees.keys) { settleCommand(id) }
        for key in Array(hydraCommandTrees.keys) { settleHydraCommand(key) }
        for task in commandSettles.values { await task.value }
        commandSettles.removeAll()
        currentTurnID = nil
        flushDeltas()
        approvals.removeAll()
        questions.removeAll()
        // One pass over the turn's rows: they are closed, and the files their tools
        // reported are collected for the summary below rather than scanned for again.
        var reportedEdits: [FileEdit] = []
        for entry in entries where entry.item.turnID == turnID {
            endStreaming(entry)
            guard case .tool(var call) = entry.item.content else { continue }
            if call.status == .running {
                call.finish(status == .completed ? .completed : .failed)
                entry.item.content = .tool(call)
                saveRevision += 1
            }
            reportedEdits.append(contentsOf: call.edits)
        }
        updateTurn(turnID) {
            $0.status = status
            $0.completedAt = .now
        }

        var files: [DiffFile] = []
        if let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) {
            let git = Git(thread.worktreePath ?? project.path)
            let providerDiff = turns.first(where: { $0.id == turnID })?.providerDiff
            // Parsed off the main actor, and only once: a turn's patch can be large, and
            // this lands exactly as the reply appears.
            var providerFiles: [DiffFile] = []
            if let providerDiff { providerFiles = await Self.parseDiff(providerDiff) }
            if let base = turn.baseCheckpoint {
                let ref = Git.checkpointRef(thread: threadID, turn: turn.index, phase: "end")
                if (try? await git.captureCheckpoint(ref)) != nil {
                    updateTurn(turnID) { $0.endCheckpoint = ref }
                    if let patch = try? await git.diff(from: base, to: ref) {
                        files = await Self.parseDiff(patch)
                    }
                }
            } else {
                files = providerFiles
            }

            // Only files this thread's agent edited count, never edits made elsewhere in the repository meanwhile.
            let root = thread.worktreePath ?? project.path
            var touched = Set<String>()
            // A path outside the checkout is no part of the turn: the agent writes to its
            // own notes and settings too, and git cannot stage a file it does not hold.
            for edit in reportedEdits {
                if let path = TouchedPaths.relative(edit.path, root: root) { touched.insert(path) }
            }
            for file in providerFiles { touched.insert(file.path) }
            // What the lead's native heads changed, which their own timelines carry: this
            // turn takes it, whether it came during the turn or between the last and this.
            touched.formUnion(hydraTouched)
            hydraTouched.removeAll()
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
        // The turn's own events shared one save every few seconds; whatever they left is
        // written here, so a finished turn is always on disk.
        saveNow()
        settleForegroundHeads(after: status)
        // The Return-while-running message jumps the queue: it goes right away
        // and anything queued waits for it. A reply that ends in a delegation block
        // sends the heads out instead, and their reports come back as a message of
        // their own; the lead is free meanwhile, so the next queued prompt starts on
        // it at once rather than waiting out the heads, and the reports follow that
        // turn. Either way the app hears whether a next turn is on its way, so
        // "finished" only sounds when nothing is.
        var continues: Bool
        if pendingSend != nil {
            continues = drainPendingSend()
        } else if status == .completed, case let delegation = spawnDelegatedHeads(for: turnID), delegation != .none {
            continues = true
            if delegation == .headsOut { _ = drainFollowUps(after: status) }
        } else if status == .completed, flushHydraReports() {
            continues = true
        } else {
            continues = drainFollowUps(after: status)
        }
        // Reports that came in while this turn ran are heard whatever became of it. Only a
        // turn the user stopped is left alone, as their queued messages are: they are in
        // charge of the chat then, and the reports go out with their next word.
        if !continues, status != .interrupted, flushHydraReports() { continues = true }
        // Heads still out will report, and the lead will work again: the job is not
        // finished until it has heard from all of them.
        if !continues, status == .completed, let app, app.runningDroppyHeads(of: threadID) > 0 { continues = true }
        // A head stopped for its budget writes its report as its next turn, so its lead
        // hears what it managed rather than only that it was stopped.
        if headBudgetSpent {
            headBudgetSpent = false
            if status == .interrupted, thread?.hydra?.kind == .droppy {
                headReportsNext = true
                Task { await ensureLoaded(); await startTurn(text: HydraBudget.finalNote, attachments: []) }
                continues = true
            }
        }
        app?.turnFinished(threadID, status: status, continues: continues)
        // The job is done: the lead has answered, every head is back and nothing is
        // waiting. With the setting on, the work goes out and lands by itself, whether
        // heads took part or the lead did it all; a job that changed no file is let be.
        // Native heads are not in the batches: they run on inside the lead's session after
        // the lead's reply ends, and report in a turn of their own later. A merge while any
        // head is still at work would commit its half-done files and then, the head having
        // finished before the next turn began, never come back for the rest.
        if !continues, status == .completed,
           hydraPendingReports.isEmpty, hydraBatches.isEmpty, hydraWaiting.isEmpty,
           let app, let thread, app.hydraIsOn(thread), app.settings.hydraAutoMerge,
           app.runningHydraHeads(of: threadID) == 0 {
            Task { await app.autoMergeHydraWork(of: threadID) }
        }
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
        Task { await ensureLoaded(); await startTurn(text: pending.text, attachments: pending.attachments) }
        return true
    }

    // MARK: - Hydra

    /// The auto-merge has landed these turns' work: the next merge starts from what came
    /// after them, rather than offering the same files again.
    func markHydraMerged(_ turnIDs: [UUID]) {
        let ids = Set(turnIDs)
        var changed = false
        for index in turns.indices where ids.contains(turns[index].id) && !turns[index].hydraMerged {
            turns[index].hydraMerged = true
            changed = true
        }
        guard changed else { return }
        saveRevision += 1
        saveNow()
    }

    /// The turns whose work has not been merged yet, oldest first.
    var hydraUnmergedTurns: [TurnRecord] {
        turns.filter { !$0.hydraMerged }
    }

    /// The head a tool row in this timeline sent out, if any.
    func hydraHead(forTool toolID: String) -> UUID? {
        hydraToolHeads[toolID]
    }

    /// Captures-only mapping of a tool row to its head thread.
    func rehearseHydraHead(toolID: String, headID: UUID) {
        hydraToolHeads[toolID] = headID
    }

    /// A head the provider started inside this session, or more said about one already
    /// known: a name for the tool call that spawned it, its brief.
    private func hydraAgentStarted(_ spawn: AgentSpawn) {
        guard let app, let thread, app.hydraIsOn(thread) else { return }
        if let headID = hydraNativeHeads[spawn.id] {
            let named = !spawn.description.isEmpty && spawn.description != "Subagent"
            app.updateThread(headID) { head in
                guard var info = head.hydra else { return }
                if named, info.task != spawn.description {
                    info.task = spawn.description
                    head.title = "\(info.persona.name) · \(TextCleanup.singleLine(spawn.description, limit: 60))"
                }
                if info.toolUseID == nil { info.toolUseID = spawn.toolUseID }
                head.hydra = info
            }
            if let toolUseID = spawn.toolUseID { hydraToolHeads[toolUseID] = headID }
            if let prompt = spawn.prompt, let headRuntime = app.existingRuntime(for: headID), headRuntime.sentPrompts.isEmpty {
                headRuntime.rehearseBrief(prompt)
            }
            return
        }
        guard let head = app.spawnNativeHead(from: threadID, spawn: spawn) else { return }
        hydraNativeHeads[spawn.id] = head.id
        if let toolUseID = spawn.toolUseID { hydraToolHeads[toolUseID] = head.id }
    }

    /// An event from inside a head's transcript, rehearsed on the head's own timeline.
    private func hydraAgentEvent(_ agentID: String, _ event: ProviderEvent) {
        guard let app else { return }
        // A head heard from before it was announced: on Claude the agent id is the tool
        // call that spawned it, so the row already names its task.
        if hydraNativeHeads[agentID] == nil, let entry = entryIndex[agentID], case .tool(let call) = entry.item.content, call.kind == .agent {
            hydraAgentStarted(AgentSpawn(id: agentID, taskID: nil, toolUseID: agentID, description: call.title, prompt: nil, model: nil, isBackground: false))
        }
        guard let headID = hydraNativeHeads[agentID], let headRuntime = app.existingRuntime(for: headID) else { return }
        switch event {
        case .turnStarted:
            // A head briefed again by its lead works another turn.
            if !headRuntime.isRunning {
                headRuntime.rehearseTurn(nil)
                app.updateHydraHead(headID) {
                    $0.status = .running
                    $0.finishedAt = nil
                }
            }
        case .turnCompleted(let status, _):
            hydraAgentFinished(agentID, status: status, summary: nil)
        case .toolStarted(let toolID, let call):
            headRuntime.hydraToolCalls += 1
            headRuntime.hydraActivity = ToolPresentation.label(for: call)
            headRuntime.hydraLastEventAt = .now
            noteHydraEdits(call.edits)
            if call.kind == .command { watchHydraCommand("\(agentID)-\(toolID)", call) }
            headRuntime.rehearse(event)
        case .toolUpdated(let toolID, let update):
            if let edits = update.edits { noteHydraEdits(edits) }
            if let status = update.status, status != .running { settleHydraCommand("\(agentID)-\(toolID)") }
            headRuntime.rehearse(event)
        case .usage, .sessionReady, .models, .commands, .title, .assistantMessageID:
            break
        default:
            headRuntime.rehearse(event)
        }
    }

    /// A head finished: its timeline closes and its status lands, and the tool row that
    /// sent it out completes if the provider left it running in the background.
    private func hydraAgentFinished(_ agentID: String, status: TurnStatus, summary: String?) {
        guard let app, let headID = hydraNativeHeads[agentID] else { return }
        app.finishHydraHead(headID, status: status, summary: summary)
        if let headRuntime = app.existingRuntime(for: headID), headRuntime.isRunning {
            headRuntime.rehearse(.turnCompleted(status: status, error: nil))
        }
    }

    /// The tool call that sent out a foreground head has returned: the head is done, and
    /// the result is its report. A background head's call returns at once and says
    /// nothing about the head, which the provider ends on its own.
    private func hydraToolFinished(_ headID: UUID, status: ToolCall.Status, output: String?) {
        guard let app, let head = app.thread(headID), let info = head.hydra, info.kind == .native, !info.isBackground, !info.isFinished,
              let nativeID = info.nativeID else { return }
        let outcome: TurnStatus = switch status {
        case .completed: .completed
        case .declined: .interrupted
        default: .failed
        }
        hydraAgentFinished(nativeID, status: outcome, summary: output)
    }

    /// The lead's turn is over, so any foreground head still marked as working went with
    /// it: a stopped turn stopped them, a finished one finished them. Background heads
    /// outlive the turn and end on the provider's word.
    private func settleForegroundHeads(after status: TurnStatus) {
        guard let app else { return }
        for (nativeID, headID) in hydraNativeHeads {
            guard let head = app.thread(headID), let info = head.hydra, !info.isBackground, !info.isFinished else { continue }
            hydraAgentFinished(nativeID, status: status == .completed ? .completed : .interrupted, summary: nil)
        }
    }

    /// The session the heads ran in has stopped: whichever were still running are done.
    private func stopNativeHeads() {
        guard let app else { return }
        for headID in hydraNativeHeads.values {
            guard let head = app.thread(headID), head.hydra?.isFinished == false else { continue }
            app.finishHydraHead(headID, status: .interrupted, summary: nil)
            if let headRuntime = app.existingRuntime(for: headID), headRuntime.isRunning {
                headRuntime.rehearse(.turnCompleted(status: .interrupted, error: nil))
            }
        }
        hydraNativeHeads.removeAll()
    }

    /// Asks the session to stop a native head. Returns whether it could.
    func stopNativeHead(_ nativeID: String) async -> Bool {
        guard let session else { return false }
        return await session.stopAgent(nativeID)
    }

    /// The app finished a head of this lead's (see `AppModel.finishHydraHead`): a native
    /// head's tool row completes; a Droppy-run head's report goes to the lead, once its
    /// batch is complete. A head reporting again (steered on from the panel) replaces
    /// any report of its own still waiting.
    func hydraHeadFinished(_ headID: UUID, info: HydraHeadInfo, status: HydraHeadInfo.Status, summary: String?, landing: HydraLanding? = nil, copyPath: String? = nil) {
        switch info.kind {
        case .native:
            guard let toolID = info.toolUseID, let entry = entryIndex[toolID], case .tool(let call) = entry.item.content, call.status == .running else { return }
            let outcome: ToolCall.Status = status == .completed ? .completed : .failed
            applyToolUpdate(toolID, ToolUpdate(output: summary, status: outcome))
            // A head back with the lead idle and a prompt still queued (steered
            // behind the team while the lead sat idle) lets the lead take it now
            // rather than holding it until some later turn ends.
            flushFollowUpsIfIdle()
        case .droppy:
            let report = HydraReport(
                headIndex: info.index, task: info.task, origin: info.origin, status: status, text: summary ?? "",
                landing: landing, copyPath: copyPath, elapsed: Date.now.timeIntervalSince(info.startedAt), toolCalls: info.toolCalls
            )
            hydraPendingReports.removeAll { $0.headIndex == info.index }
            if let batchID = info.batchID, hydraBatches[batchID] != nil {
                hydraBatches[batchID]?.pending.remove(headID)
                hydraBatches[batchID]?.reports.removeAll { $0.headIndex == info.index }
                hydraBatches[batchID]?.reports.append(report)
            } else {
                hydraPendingReports.append(report)
            }
            // A finished head makes room: for a task still waiting in a batch first, then
            // for whatever the user queued while every head was busy.
            spawnWaitingHeads()
            dispatchQueuedFollowUps()
            settleBatches()
            // An idle lead hears at once; one the user stopped waits for their next word.
            if phase == .idle, thread?.lastStatus != .interrupted { flushHydraReports() }
            // After the reports: whatever is still queued behind an idle lead goes
            // next, rather than waiting out the heads still at work.
            flushFollowUpsIfIdle()
        }
    }

    /// A batch with every head back and nothing left to send out hands its reports over.
    private func settleBatches() {
        for (batchID, batch) in hydraBatches where batch.pending.isEmpty && !hydraWaiting.contains(where: { $0.batchID == batchID }) {
            hydraBatches[batchID] = nil
            hydraPendingReports += batch.reports.sorted { $0.headIndex < $1.headIndex }
        }
    }

    /// Sends the reports waiting on an idle lead as one message. Returns whether a turn
    /// starts. The reports stay put until the turn takes them: heads finishing together
    /// then go out as one message, instead of each starting a turn the next one cuts short.
    @discardableResult
    private func flushHydraReports() -> Bool {
        guard phase == .idle, !hydraFlushScheduled, !flushableHydraReports().isEmpty else { return false }
        hydraFlushScheduled = true
        Task { await startHydraReportTurn() }
        return true
    }

    /// The reports an idle lead can hear now: every one waiting. A delegation's reports
    /// only get here once its whole batch is back (see `settleBatches`), and a head the
    /// user queued or sent out directly has nothing to do with a batch; neither waits on
    /// another delegation still out, which can mean waiting out a job of twenty minutes.
    private func flushableHydraReports() -> [HydraReport] {
        hydraPendingReports.sorted { $0.headIndex < $1.headIndex }
    }

    /// The turn `flushHydraReports` scheduled. A lead no longer idle (the user got a word
    /// in first) keeps the reports waiting for the end of that turn instead.
    private func startHydraReportTurn() async {
        // Cleared first and the reports left where they are: a turn that cannot run now
        // must be able to be asked for again, by the next head to finish or by the end of
        // whatever the lead is doing instead.
        hydraFlushScheduled = false
        guard phase == .idle, let app else { return }
        let reports = flushableHydraReports()
        guard !reports.isEmpty else { return }
        let sent = Set(reports.map(\.headIndex))
        hydraPendingReports.removeAll { sent.contains($0.headIndex) }
        let stillWorking = app.workingHydraHeadNames(of: threadID, excluding: sent)
        let text = HydraPrompts.reportMessage(reports, stillWorking: stillWorking, reviewsHeads: app.settings.hydraReviewHeads)
        await ensureLoaded()
        await startTurn(text: text, attachments: [], hydraHeads: reports.map(\.headIndex))
    }

    /// How many tasks one delegation block may send out. Well past what a lead writes in
    /// practice, and the pair's cap still decides how many run at a time.
    private static let maxDelegatedTasks = 32

    /// How many times one request may tell the lead that its block was unreadable or held
    /// back, each in a turn of its own. Enough for a lead to fix a malformed block and to
    /// hear once that its rounds are spent; past it a reply that still ends in a block is
    /// treated as a plain reply, so no chat ever loops turn after turn on the same refusal.
    private static let maxRefusedBlocks = 3

    /// What a reply's delegation block led to, for the end of the turn.
    private enum DelegationOutcome {
        /// No block, or nothing came of it.
        case none
        /// Heads went out; the lead is free until they report.
        case headsOut
        /// The lead is being told something instead, in a turn of its own already on its way.
        case turnStarted
    }

    /// A reply on any provider may end in a delegation block: its tasks go out as
    /// Droppy-run heads, up to the pair's limit at a time, and the block leaves the reply.
    /// A block Droppy Code cannot read leaves the reply as well, and the lead hears so in
    /// a turn of its own: a block never stays in a reply doing nothing.
    private func spawnDelegatedHeads(for turnID: UUID) -> DelegationOutcome {
        guard let app, let thread, let launch = app.hydraLaunch(for: thread),
              let entry = entries.last(where: { $0.turnID == turnID && $0.kind == .assistant }),
              case .assistant(var message) = entry.item.content else { return .none }
        guard let delegations = HydraPrompts.delegations(in: message.text) else {
            guard HydraPrompts.hasDelegationBlock(in: message.text) else { return .none }
            message.text = HydraPrompts.withoutDelegationBlock(message.text)
            if message.text.isEmpty { message.text = "Asking for heads." }
            entry.item.content = .assistant(message)
            saveRevision += 1
            scheduleSave()
            return refuseBlock(HydraPrompts.unreadableBlockMessage(reason: nil), dropped: "Its delegation block could not be read, and it had been told so already.")
        }
        message.text = HydraPrompts.withoutDelegationBlock(message.text)
        // An empty block is the lead saying it did the work itself: the block leaves the
        // reply, a one-line note says no heads went out, and no turn is spent on it.
        if delegations.isEmpty {
            if message.text.isEmpty { message.text = "Done, with no heads." }
            entry.item.content = .assistant(message)
            saveRevision += 1
            scheduleSave()
            appendHydraNote("No heads went out: the lead did this itself.")
            return .none
        }
        // One request gets so many rounds of heads; past that the lead hears why none went
        // out and finishes by itself, so no request chains heads without end.
        guard hydraDelegationRounds < HydraPrompts.maxDelegationRounds else {
            if message.text.isEmpty { message.text = "Asking for more heads." }
            entry.item.content = .assistant(message)
            saveRevision += 1
            scheduleSave()
            return refuseBlock(HydraPrompts.heldBackMessage(count: delegations.count), dropped: "This request has had all \(HydraPrompts.maxDelegationRounds) of its rounds of heads, and the lead had been told so already.")
        }
        hydraDelegationRounds += 1
        if message.text.isEmpty { message.text = "Sending out heads." }
        entry.item.content = .assistant(message)
        saveRevision += 1
        let batchID = UUID()
        hydraBatches[batchID] = HydraBatch(pending: [])
        // The pair's cap paces these out through `hydraWaiting`, so the ceiling is only on
        // how many tasks one block may hold. A lead that writes more than that hears which
        // ones did not go out, rather than losing the tail of its own list in silence.
        hydraWaiting += delegations.prefix(Self.maxDelegatedTasks).map { (delegation: $0, batchID: batchID) }
        if delegations.count > Self.maxDelegatedTasks {
            let dropped = delegations.count - Self.maxDelegatedTasks
            appendHydraNote("""
                Not every task went out
                \(Self.maxDelegatedTasks) of the \(delegations.count) tasks in that block went to heads. The last \(dropped) did not: ask for them again once these report back.
                """)
        }
        spawnWaitingHeads(launch: launch)
        settleBatches()
        scheduleSave()
        return hydraBatches.isEmpty && hydraWaiting.isEmpty ? .none : .headsOut
    }

    /// Tells the lead, in a turn of its own, that the block its reply ended in sent no heads
    /// out, and why: `message` is what it hears. Only so many times per request (see
    /// `maxRefusedBlocks`): a lead that keeps answering with the same block would otherwise
    /// be answered with the same refusal, turn after turn, for as long as the app runs. Past
    /// the cap the block is dropped with a note in the timeline saying `dropped`, and the
    /// turn ends as a plain reply would.
    private func refuseBlock(_ message: String, dropped: String) -> DelegationOutcome {
        guard hydraRefusedBlocks < Self.maxRefusedBlocks else {
            appendHydraNote("No heads went out\n\(dropped) The block was dropped from the reply.")
            return .none
        }
        hydraRefusedBlocks += 1
        Task { await ensureLoaded(); await startTurn(text: message, attachments: [], hydraHeads: []) }
        return .turnStarted
    }

    /// Sends out delegated tasks still waiting, as far as the pair's cap allows; without
    /// a pair, or an uncapped one, all of them.
    private func spawnWaitingHeads(launch: HydraLaunch? = nil) {
        guard let app, let thread, !hydraWaiting.isEmpty else { return }
        let launch = launch ?? app.hydraLaunch(for: thread)
        while !hydraWaiting.isEmpty, launch?.hasRoom(running: app.runningDroppyHeads(of: threadID)) ?? true {
            let next = hydraWaiting.removeFirst()
            let delegation = next.delegation
            // The lead's announced name is authoritative: resolving it here pins the
            // spawned head to exactly that roster name. Unknown or already-taken names
            // resolve to nil and the head goes out next in order, as before.
            let preferredIndex = delegation.name.flatMap(HydraRoster.index(named:))
            guard let head = app.spawnDroppyHead(from: threadID, task: delegation.task, origin: .delegated, batchID: next.batchID, preferredIndex: preferredIndex, brief: { persona, workplace in
                HydraPrompts.delegatedHeadPrompt(persona: persona, delegation: delegation, workplace: workplace)
            }) else { continue }
            hydraBatches[next.batchID, default: HydraBatch(pending: [])].pending.insert(head.id)
        }
    }

    // MARK: - Timeline mutations

    /// A note from Hydra in the timeline, with no turn behind it: what it merged, what it
    /// could not. Its first line is its title.
    func appendHydraNote(_ text: String) {
        append(TimelineItem(turnID: nil, content: .user(UserMessage(text: text, hydraHeads: []))))
        app?.updateThread(threadID) { $0.updatedAt = .now }
        scheduleSave()
    }

    private func append(_ item: TimelineItem) {
        for entry in entries.suffix(6) { endStreaming(entry) }
        let entry = TimelineEntry(item)
        entries.append(entry)
        entryIndex[item.id] = entry
        saveRevision += 1
    }

    private func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        entryIndex[id] = nil
        saveRevision += 1
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
        // The copy in `flushDeltas` below is O(n) in the row's text: as the reply
        // grows the flush waits longer, so long replies flush half or a third as
        // often with no visible effect. The copy itself cannot go away while the
        // row's content is a value-typed enum behind an observed property.
        flushTask = Task { [weak self] in
            let delay = Self.flushDelay(for: self?.pendingFlushLength(), scrolling: ScrollActivity.shared.isScrolling)
            try? await Task.sleep(for: .milliseconds(delay))
            self?.flushDeltas()
        }
    }

    /// The text the next flush will write onto its row, used to pace the flush:
    /// short replies refresh fast, long ones less often.
    private func pendingFlushLength() -> Int {
        var longest = 0
        for (id, delta) in pendingDeltas {
            switch delta.kind {
            case .toolOutput:
                continue
            default:
                break
            }
            switch entryIndex[id]?.item.content {
            case .assistant(let message):
                longest = max(longest, message.text.count + delta.text.count)
            case .reasoning(let block):
                longest = max(longest, block.text.count + delta.text.count)
            case .plan(let plan):
                longest = max(longest, plan.markdown.count + delta.text.count)
            default:
                break
            }
        }
        return longest
    }

    /// How long to wait before flushing deltas onto their rows: 45 ms up to 4 KB,
    /// 90 ms up to 32 KB, 150 ms beyond.
    private nonisolated static func flushDelay(for length: Int?, scrolling: Bool) -> Int {
        let paced = switch length ?? 0 {
        case ..<4_096: 45
        case ..<32_768: 90
        default: 150
        }
        // Under a scrolling reader the row is not being read: it takes at most six
        // flushes a second then, so the frames of the scroll are not spent laying the
        // streaming text out again (in the chat and in every head panel at once).
        return scrolling ? max(paced, 160) : paced
    }

    private func flushDeltas() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingDeltas.isEmpty else { return }
        let deltas = pendingDeltas
        pendingDeltas.removeAll()
        var heard = false
        for (id, delta) in deltas {
            guard let entry = entryIndex[id] else { continue }
            switch (delta.kind, entry.item.content) {
            case (.message, .assistant(var message)):
                message.text += delta.text
                entry.item.content = .assistant(message)
                saveRevision += 1
                heard = true
            case (.reasoning, .reasoning(var block)):
                block.text += delta.text
                entry.item.content = .reasoning(block)
                saveRevision += 1
                heard = true
            case (.toolOutput, .tool(var call)):
                call.appendOutput(delta.text)
                entry.item.content = .tool(call)
                saveRevision += 1
                heard = true
            case (.plan, .plan(var plan)):
                plan.markdown += delta.text
                entry.item.content = .plan(plan)
                saveRevision += 1
            default:
                break
            }
        }
        // Once per flush, not per word: a head still talking is a head still at work.
        if heard { noteHydraHeadEvent() }
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
            saveRevision += 1
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
            saveRevision += 1
        }
        scheduleSave()
    }

    private func completePlan(_ id: String, markdown: String) {
        let markdown = TextCleanup.withoutEmDashes(markdown)
        if let entry = entryIndex[id], case .plan(var plan) = entry.item.content {
            if !markdown.isEmpty { plan.markdown = markdown }
            plan.state = .proposed
            entry.item.content = .plan(plan)
            saveRevision += 1
        } else if !markdown.isEmpty {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .plan(ProposedPlan(markdown: markdown, state: .proposed))))
        }
        scheduleSave()
    }

    private func upsertTool(_ id: String, _ call: ToolCall) {
        noteToolMayWrite(call.kind)
        var call = call
        call.edits = Self.capped(call.edits)
        guard let entry = entryIndex[id], case .tool(var existing) = entry.item.content else {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .tool(call)))
            noteHydraHeadEvent(edits: call.edits.count, tool: true)
            return
        }
        if !call.title.isEmpty { existing.title = call.title }
        existing.detail = call.detail ?? existing.detail
        existing.kind = call.kind
        // Edits count once, when they first land on the call.
        let landed = !call.edits.isEmpty && existing.edits.isEmpty ? call.edits.count : 0
        if !call.edits.isEmpty { existing.edits = call.edits }
        if existing.status == .running, call.status != .running { existing.finish(call.status) }
        entry.item.content = .tool(existing)
        saveRevision += 1
        noteHydraHeadEvent(edits: landed)
    }

    /// Something happened on this runtime's own timeline, and it is a head's: its
    /// watchdog clock restarts and the edits that landed count (see
    /// `AppModel.startHydraWatchdog`). A Droppy-run head counts its tools here, where
    /// its own session reports them; a native head's count comes with its lead's events
    /// (see `hydraAgentEvent`), which also rehearse here, so it is not counted twice.
    private func noteHydraHeadEvent(edits: Int = 0, tool: Bool = false) {
        guard let info = thread?.hydra else { return }
        hydraLastEventAt = .now
        hydraEditCount += edits
        if tool, info.kind == .droppy { hydraToolCalls += 1 }
    }

    /// A tool that is not plainly a read can have written a file, which makes the tree a
    /// command left behind no answer for what is on disk now. Commands keep their own
    /// count in `watchCommand`, which knows whether this one can write at all.
    private func noteToolMayWrite(_ kind: ToolCall.Kind?) {
        guard let kind, kind != .read, kind != .search, kind != .web, kind != .command else { return }
        settledTree = nil
        treeEpoch += 1
    }

    private func applyToolUpdate(_ id: String, _ update: ToolUpdate) {
        noteToolMayWrite(update.kind)
        if entryIndex[id] == nil {
            append(TimelineItem(id: id, turnID: currentTurnID, content: .tool(ToolCall(kind: update.kind ?? .other, title: update.title ?? "Tool"))))
        }
        guard let entry = entryIndex[id], case .tool(var call) = entry.item.content else { return }
        if let title = update.title, !title.isEmpty { call.title = title }
        if let detail = update.detail { call.detail = detail }
        if let kind = update.kind { call.kind = kind }
        var landed = 0
        if let edits = update.edits, !edits.isEmpty {
            if call.edits.isEmpty { landed = edits.count }
            call.edits = Self.capped(edits)
        }
        if let output = update.output { call.setOutput(output) }
        if let exitCode = update.exitCode { call.exitCode = exitCode }
        if let status = update.status {
            if status == .running { call.status = .running } else { call.finish(status) }
        }
        entry.item.content = .tool(call)
        saveRevision += 1
        noteHydraHeadEvent(edits: landed)
        scheduleSave()
    }

    // MARK: - Command edits

    /// Agents that edit files from the shell (python heredocs, sed -i, patch)
    /// never report an edit, so a command's row gets its edits from the
    /// working tree instead: a snapshot as it starts, another as it finishes,
    /// and the diff between the two. Git-backed projects only.
    private func watchCommand(_ id: String, _ call: ToolCall) {
        // A command that cannot write needs no snapshots at all: reading the checkout is
        // most of what an agent runs, and each snapshot is seconds of git on a big tree.
        guard commandTrees[id] == nil, ShellCommandKind.mayWriteFiles(call.title), let git = repositoryGit else { return }
        if let settled = settledTree, settled.epoch == treeEpoch {
            commandTrees[id] = Task<String?, Never> { settled.tree }
        } else {
            commandTrees[id] = captureTree(git)
        }
        settledTree = nil
        treeEpoch += 1
    }

    private func settleCommand(_ id: String) {
        guard let before = commandTrees.removeValue(forKey: id), let git = repositoryGit else { return }
        let epoch = treeEpoch
        commandSettles[id] = Task { [weak self] in
            guard let base = await before.value, let self else { return }
            guard let after = await captureTree(git).value else { return }
            // Nothing else started or ran alongside while the snapshot was taken, so it
            // still stands for the working tree and the next command starts from it.
            if treeEpoch == epoch, commandTrees.isEmpty, hydraCommandTrees.isEmpty { settledTree = (after, epoch) }
            guard base != after, let patch = try? await git.diff(from: base, to: after), !patch.isEmpty else { return }
            let edits = await Self.fileEdits(from: patch)
            guard !edits.isEmpty, let entry = entryIndex[id], case .tool(var call) = entry.item.content else { return }
            // A provider that did report its edits keeps them.
            guard call.edits.allSatisfy({ $0.diff == nil }) else { return }
            call.edits = edits
            entry.item.content = .tool(call)
            saveRevision += 1
            noteHydraHeadEvent(edits: edits.count)
            scheduleSave()
        }
    }

    /// One working-tree snapshot at a time for this thread, each waiting for the one
    /// before it: they are heavy, and a turn's commands would otherwise run several at
    /// once, with eight heads doing the same in the same checkout.
    private func captureTree(_ git: Git) -> Task<String?, Never> {
        let previous = treeCaptures
        let capture = Task { () -> String? in
            _ = await previous?.value
            return await Task.detached(priority: .utility) { try? await git.captureTree() }.value
        }
        treeCaptures = capture
        return capture
    }

    /// Files a native head reported editing. They land on the head's own timeline, but the
    /// work is done in the lead's checkout and counts as the lead's turn.
    private func noteHydraEdits(_ edits: [FileEdit]) {
        guard !edits.isEmpty, let root = workingRoot else { return }
        for edit in edits {
            if let path = TouchedPaths.relative(edit.path, root: root) { hydraTouched.insert(path) }
        }
    }

    /// A native head's shell command, watched exactly as the lead's own are and for the
    /// same reason: agents edit from the shell without reporting it. What changed goes to
    /// the turn's files rather than onto a row, because the row lives in the head's
    /// runtime and it is the lead's turn that a merge takes its files from.
    private func watchHydraCommand(_ key: String, _ call: ToolCall) {
        guard hydraCommandTrees[key] == nil, ShellCommandKind.mayWriteFiles(call.title), let git = repositoryGit else { return }
        if let settled = settledTree, settled.epoch == treeEpoch {
            hydraCommandTrees[key] = Task<String?, Never> { settled.tree }
        } else {
            hydraCommandTrees[key] = captureTree(git)
        }
        settledTree = nil
        treeEpoch += 1
    }

    private func settleHydraCommand(_ key: String) {
        guard let before = hydraCommandTrees.removeValue(forKey: key), let git = repositoryGit else { return }
        let epoch = treeEpoch
        // Kept with the lead's own settles, so the turn waits for them before it counts
        // its files.
        commandSettles[key] = Task { [weak self] in
            guard let base = await before.value, let self else { return }
            guard let after = await captureTree(git).value else { return }
            if treeEpoch == epoch, commandTrees.isEmpty, hydraCommandTrees.isEmpty { settledTree = (after, epoch) }
            guard base != after, let paths = try? await git.changedPaths(from: base, to: after) else { return }
            hydraTouched.formUnion(paths.filter { !$0.isEmpty })
        }
    }

    /// The folder this thread's agent works in: its own copy of the checkout, or the
    /// project itself.
    private var workingRoot: String? {
        guard let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) else { return nil }
        return thread.worktreePath ?? project.path
    }

    private var repositoryGit: Git? {
        guard let currentTurnID, let turn = turns.first(where: { $0.id == currentTurnID }), turn.baseCheckpoint != nil,
              let app, let thread = app.thread(threadID), let project = app.project(thread.projectID) else { return nil }
        return Git(thread.worktreePath ?? project.path)
    }

    /// How much of a patch an edit carries. Past it the edit is stats only, so neither the
    /// timeline nor the thread file grows by the whole of a written file.
    private nonisolated static let editDiffLimit = 200_000

    /// Edits as a provider reported them, with an outsized patch dropped: a Write tool
    /// hands over the entire new file, which can be megabytes, and every save would then
    /// write all of it again. The same cap the edits taken from a command's diff have.
    private static func capped(_ edits: [FileEdit]) -> [FileEdit] {
        edits.map { edit in
            guard let diff = edit.diff, diff.utf8.count > editDiffLimit else { return edit }
            var capped = edit
            capped.diff = nil
            return capped
        }
    }

    /// One edit per file in a multi-file patch, with the file's own section as its diff.
    @concurrent
    private nonisolated static func fileEdits(from patch: String) async -> [FileEdit] {
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
            let diff = section.utf8.count <= editDiffLimit ? section : nil
            return FileEdit(path: file.path, diff: diff, additions: file.additions, deletions: file.deletions)
        }
    }

    private func upsertTodos(_ steps: [TodoStep]) {
        // The row is remembered rather than searched for: a turn rewrites its list many
        // times, and the timeline behind it can hold thousands of rows.
        if let id = todosEntryID, let entry = entryIndex[id], entry.item.turnID == currentTurnID {
            entry.item.content = .todos(steps)
            saveRevision += 1
        } else if let entry = entries.last(where: { entry in
            guard entry.item.turnID == currentTurnID else { return false }
            if case .todos = entry.item.content { return true }
            return false
        }) {
            todosEntryID = entry.id
            entry.item.content = .todos(steps)
            saveRevision += 1
        } else if !steps.isEmpty {
            let item = TimelineItem(turnID: currentTurnID, content: .todos(steps))
            todosEntryID = item.id
            append(item)
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
        saveRevision += 1
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
        guard phase != .idle else {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                self?.saveNow()
            }
            return
        }
        // A running turn fires this after nearly every event it streams, and every save
        // rewrites the whole thread file, which runs to megabytes. While the turn runs its
        // events share one save every few seconds: the timer already running writes
        // whatever the thread holds by then, and `finishTurn` saves what is left.
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        // A save before the history is installed would write an empty thread over the file.
        guard !isLoadingHistory else { return }
        saveTask?.cancel()
        saveTask = nil
        // The periodic save fires every few seconds while a turn runs, even when the
        // turn's events changed nothing since the last write: skip the snapshot then.
        // `finishTurn` and friends still land on disk, as their mutations bump the
        // revision before the save below.
        guard saveRevision != lastSavedRevision else { return }
        lastSavedRevision = saveRevision
        var document = ThreadDocument(threadID: threadID)
        document.items = entries.map(\.item)
        document.turns = turns
        document.usage = usage
        document.followUps = followUps
        let url = Storage.threadURL(threadID)
        // Two saves of the same thread are written by separate tasks and can reach the
        // writer in either order; the revision keeps the newer one on disk.
        let revision = DiskWriter.nextRevision(for: url)
        Task { await DiskWriter.shared.encodeAndWrite(document, to: url, revision: revision) }
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
            saveRevision += 1
            append(userItem)
        } else {
            turns.append(turn)
            saveRevision += 1
        }
        currentTurnID = turn.id
        phase = .running
        turnStartedAt = .now
        app?.updateThread(threadID) {
            $0.updatedAt = .now
            $0.lastStatus = .running
        }
    }

    /// The brief a head was given, once the provider says what it was: a user message at
    /// the top of a timeline that started without one.
    func rehearseBrief(_ text: String) {
        guard let turn = turns.last, turn.userItemID == nil else { return }
        let userItem = TimelineItem(turnID: turn.id, content: .user(UserMessage(text: text)))
        updateTurn(turn.id) { $0.userItemID = userItem.id }
        let entry = TimelineEntry(userItem)
        entries.insert(entry, at: 0)
        entryIndex[userItem.id] = entry
        saveRevision += 1
        scheduleSave()
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
