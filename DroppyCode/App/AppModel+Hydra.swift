import Foundation

// Hydra's heads are threads: each one has a timeline of its own, sits in its lead's
// floating panel while it works, and drops under the lead in the sidebar once dismissed,
// like any helper. Native heads run inside the lead's provider session and their
// timelines fill from the session's events; Droppy-run heads have sessions of their own,
// each in a copy of the checkout made for it, and their work lands in the lead's checkout
// the moment they report.

/// What a head changed in its copy since the tree it started from: the patch itself, the
/// files it touches, and the tree the copy holds now, which becomes the head's new base
/// once the patch lands.
private struct HydraPatch: Sendable {
    var text: String
    var files: [HydraLanding.File]
    var droppedBuildOutputFiles: Int
    var after: String
}

private enum HydraPatchFilter {
    struct Result: Sendable {
        var text: String
        var droppedBuildOutputFiles: Int
    }

    static func removingBuildOutput(from patch: String) -> Result {
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        var sections: [[Substring]] = []
        var current: [Substring] = []

        for line in lines {
            if line.hasPrefix("diff --git ") {
                if !current.isEmpty { sections.append(current) }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty { sections.append(current) }

        guard !sections.isEmpty else { return Result(text: patch, droppedBuildOutputFiles: 0) }

        var kept: [[Substring]] = []
        var droppedBuildOutputFiles = 0
        for section in sections {
            if let path = bPath(in: String(section[0])), TouchedPaths.isBuildOutput(path) {
                droppedBuildOutputFiles += 1
            } else {
                kept.append(section)
            }
        }

        // The patch's closing newline belonged to whichever section came last; when that
        // one was dropped the kept text has none, and `git apply` wants one.
        var text = kept.map { $0.joined(separator: "\n") }.joined(separator: "\n")
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        return Result(text: text, droppedBuildOutputFiles: droppedBuildOutputFiles)
    }

    private static func bPath(in header: String) -> String? {
        let prefix = "diff --git "
        guard header.hasPrefix(prefix) else { return nil }
        var index = header.index(header.startIndex, offsetBy: prefix.count)
        guard readPath(from: header, index: &index) != nil,
              let bPath = readPath(from: header, index: &index), bPath.hasPrefix("b/") else { return nil }
        return String(bPath.dropFirst(2))
    }

    private static func readPath(from line: String, index: inout String.Index) -> String? {
        while index < line.endIndex, line[index].isWhitespace {
            index = line.index(after: index)
        }
        guard index < line.endIndex else { return nil }

        if line[index] == "\"" {
            index = line.index(after: index)
            var path = ""
            while index < line.endIndex {
                let character = line[index]
                index = line.index(after: index)
                if character == "\"" { return path }
                if character == "\\", index < line.endIndex {
                    let escaped = line[index]
                    index = line.index(after: index)
                    let decoded: String
                    switch escaped {
                    case "a": decoded = "\u{7}"
                    case "b": decoded = "\u{8}"
                    case "t": decoded = "\t"
                    case "n": decoded = "\n"
                    case "v": decoded = "\u{b}"
                    case "f": decoded = "\u{c}"
                    case "r": decoded = "\r"
                    case "\\", "\"": decoded = String(escaped)
                    default: decoded = String(escaped)
                    }
                    path.append(decoded)
                } else {
                    path.append(character)
                }
            }
            return nil
        }

        let start = index
        while index < line.endIndex, !line[index].isWhitespace {
            index = line.index(after: index)
        }
        return String(line[start..<index])
    }
}

/// One capture of a checkout's working tree, shared by the heads sent out together.
/// Capturing means `git add -A` and `write-tree` over the whole project, seconds on a big
/// repository, and the heads of one delegation block ask for it within milliseconds of
/// each other: without this each head would pay for its own and the last one would start
/// half a minute after the first. A capture stands for a few seconds only, and a landing
/// into the checkout throws it away, so no head ever starts from a stale tree.
@MainActor
private enum HydraTreeCache {
    private struct Capture {
        var tree: String
        var commit: String
        var capturedAt: Date
    }

    /// How long a capture stands in for the checkout: long enough for one batch to go out
    /// on it, short enough that the next head sees the checkout as it is.
    private static let lifetime: TimeInterval = 3

    private static var captures: [String: Capture] = [:]
    /// Captures under way, so heads asking at the same moment wait for the one running
    /// rather than each starting another.
    private static var inFlight: [String: Task<(tree: String, commit: String), any Error>] = [:]

    static func capture(of checkout: String, with git: Git) async throws -> (tree: String, commit: String) {
        if let ready = captures[checkout], Date.now.timeIntervalSince(ready.capturedAt) < lifetime {
            return (ready.tree, ready.commit)
        }
        if let running = inFlight[checkout] { return try await running.value }
        let task = Task { () async throws -> (tree: String, commit: String) in
            let tree = try await git.captureTree()
            // The commit is the heads' starting point and no branch ever sees it, so it
            // carries no head's name: several heads share this one.
            let commit = try await git.commitTree(tree, message: "Droppy Code: a Hydra head's starting point")
            return (tree, commit)
        }
        inFlight[checkout] = task
        defer { inFlight[checkout] = nil }
        let made = try await task.value
        captures[checkout] = Capture(tree: made.tree, commit: made.commit, capturedAt: .now)
        return made
    }

    /// The checkout changed under the capture: the next head captures it afresh.
    static func invalidate(_ checkout: String) {
        captures[checkout] = nil
    }
}

extension AppModel {
    /// Whether a chat leads a team right now: Hydra on for the app (the master) and on
    /// for this chat's own switch. Helpers lead no team of their own.
    func hydraIsOn(_ thread: ChatThread) -> Bool {
        settings.hydraEnabled && thread.hydraEnabled && !thread.isHelper
    }

    /// Whether the provider has heads of its own: it runs them inside its session, with
    /// the pair's model and effort, and keeps the lead's Hydra policy in its system prompt.
    /// Every other provider gets Droppy-run heads and the delegation block. Whether a given
    /// chat's heads actually run natively is `HydraLaunch.runsNatively`: a pair that sends
    /// the heads out on another provider makes them Droppy-run here too.
    static func hydraIsNative(_ provider: ProviderKind) -> Bool {
        provider == .claude || provider == .codex || provider == .copilot
    }

    /// The pair a chat leads with: the one picked for it in the composer's model picker,
    /// for as long as the chat stays on that pair's provider. A chat with none leads its
    /// heads on its own model and effort; no pair applies to a chat on its own.
    func hydraPair(for thread: ChatThread) -> HydraPair? {
        guard let pair = settings.hydraPair(thread.hydraPairID), pair.provider == thread.provider else { return nil }
        return pair
    }

    /// The provider a pair's heads go out on, as far as this Mac can run it: a heads'
    /// provider that is not installed or is switched off would only fail every head, so the
    /// heads stay on the lead's provider until it is.
    func hydraHeadsProvider(of pair: HydraPair) -> ProviderKind {
        guard let provider = pair.workerProvider, provider != pair.provider,
              providers.status(provider).isInstalled, settings.isEnabled(provider) else { return pair.provider }
        return provider
    }

    /// What the heads run on while the chat leads, or nil with Hydra off. Without a pair
    /// the heads inherit the chat's own model and effort, and go out without a cap.
    func hydraLaunch(for thread: ChatThread) -> HydraLaunch? {
        guard hydraIsOn(thread) else { return nil }
        let pair = hydraPair(for: thread)
        let headsProvider = pair.map(hydraHeadsProvider) ?? thread.provider
        let elsewhere = headsProvider != thread.provider
        // A pair's heads' model and effort are its heads' provider's words: with the heads
        // kept on the lead's provider because that one cannot run here, they mean nothing,
        // and the heads inherit the chat's own model and effort instead.
        let keepsModel = pair.map { !$0.sendsHeadsElsewhere || elsewhere } ?? true
        var label: String?
        if elsewhere {
            let model = providers.model(pair?.workerModel, for: headsProvider) ?? providers.defaultModel(for: headsProvider)
            label = "\(model?.shortName ?? pair?.workerModel ?? "the default model") on \(headsProvider.displayName)"
        }
        return HydraLaunch(
            headsProvider: headsProvider,
            runsNatively: !elsewhere && Self.hydraIsNative(thread.provider),
            headsLabel: label,
            workerModel: keepsModel ? pair?.workerModel : nil,
            workerEffort: keepsModel ? pair?.workerEffort : nil,
            maxHeads: pair?.maxHeads,
            isolatesHeads: settings.hydraIsolateHeads,
            autoMerges: settings.hydraAutoMerge,
            reviewsHeads: settings.hydraReviewHeads
        )
    }

    /// The per-chat Hydra switch: off kills heads for that chat only, on restores them
    /// (with the app-wide switch on). Each flip also saves the choice as the default
    /// new threads start with.
    func setHydra(_ on: Bool, for id: UUID) {
        guard let thread = thread(id) else { return }
        guard on else {
            updateThread(id) { $0.hydraEnabled = false }
            settings.hydraDefaultEnabled = false
            return
        }
        let pair = settings.hydraPair(for: thread.provider, model: thread.model)
        updateThread(id) {
            $0.hydraEnabled = true
            $0.hydraPairID = pair?.id
        }
        settings.hydraDefaultEnabled = true
        guard let pair else { return }
        if let lead = pair.orchestratorModel, lead != thread.model, providers.model(lead, for: thread.provider) != nil {
            updateThread(id) {
                $0.model = lead
                $0.effort = pair.orchestratorEffort ?? $0.effort
            }
        } else if let effort = pair.orchestratorEffort {
            updateThread(id) { $0.effort = effort }
        }
    }

    /// The heads a lead still shows in its panel, in the order they were sent out.
    func hydraHeads(of parentID: UUID) -> [ChatThread] {
        threads
            .filter { $0.parentThreadID == parentID && $0.isInPanel && !$0.isArchived && $0.isHydraHead }
            .sorted { ($0.hydra?.index ?? 0) < ($1.hydra?.index ?? 0) }
    }

    /// How many of a lead's Droppy-run heads are still at work.
    func runningDroppyHeads(of parentID: UUID) -> Int {
        hydraHeads(of: parentID).count { $0.hydra?.kind == .droppy && $0.hydra?.status == .running }
    }

    /// How many of a lead's heads are still at work, native and Droppy-run alike. A native
    /// head lives inside the lead's own session, so this is what says whether stopping the
    /// lead's turn would take heads down with it.
    func runningHydraHeads(of parentID: UUID) -> Int {
        hydraHeads(of: parentID).count { $0.hydra?.status == .running }
    }

    /// Every head a lead has sent out, in the panel or not, in the order they went.
    func hydraTeam(of parentID: UUID) -> [ChatThread] {
        threads
            .filter { $0.parentThreadID == parentID && !$0.isArchived && $0.isHydraHead }
            .sorted { ($0.hydra?.index ?? 0) < ($1.hydra?.index ?? 0) }
    }

    /// The names of a lead's Droppy-run heads still at work, other than `excluding`.
    func workingHydraHeadNames(of parentID: UUID, excluding: Set<Int> = []) -> [String] {
        hydraHeads(of: parentID)
            .filter { $0.hydra?.kind == .droppy && $0.hydra?.status == .running && !excluding.contains($0.hydra?.index ?? -1) }
            .compactMap { $0.hydra?.persona.name }
    }

    /// The checkout a lead works in: its worktree, else the project folder.
    private func hydraCheckout(of lead: ChatThread) -> String? {
        lead.worktreePath ?? project(lead.projectID)?.path
    }

    // MARK: - Sending heads out

    /// Sends out a head that mirrors one the provider started inside the lead's session.
    /// Its timeline only rehearses what the session reports, and it works wherever the
    /// lead does.
    @discardableResult
    func spawnNativeHead(from parentID: UUID, spawn: AgentSpawn) -> ChatThread? {
        guard let head = insertHydraHead(from: parentID, task: spawn.description, kind: .native, origin: .delegated, native: spawn, batchID: nil) else { return nil }
        // The brief, when the provider has said what it is; otherwise the timeline starts
        // on the working line and the brief slots in above once it arrives.
        runtime(for: head.id).rehearseTurn(spawn.prompt)
        return head
    }

    /// Sends out a head with a session of its own, on the pair's model and effort. With
    /// isolation on and a git repository to copy, the head first gets a worktree of its
    /// own, made from the lead's checkout as it is; otherwise it works in the checkout
    /// itself. `brief` writes the prompt once it is known where the head works.
    @discardableResult
    func spawnDroppyHead(
        from parentID: UUID,
        task: String,
        origin: HydraHeadInfo.Origin,
        attachments: [Attachment] = [],
        batchID: UUID? = nil,
        preferredIndex: Int? = nil,
        brief: @escaping @Sendable (HydraPersona, HydraPrompts.Workplace) -> String
    ) -> ChatThread? {
        guard let head = insertHydraHead(from: parentID, task: task, kind: .droppy, origin: origin, native: nil, batchID: batchID, preferredIndex: preferredIndex) else { return nil }
        Task { await startDroppyHead(head.id, attachments: attachments, brief: brief) }
        return head
    }

    private func insertHydraHead(
        from parentID: UUID,
        task: String,
        kind: HydraHeadInfo.Kind,
        origin: HydraHeadInfo.Origin,
        native: AgentSpawn?,
        batchID: UUID?,
        preferredIndex: Int? = nil
    ) -> ChatThread? {
        guard let parent = thread(parentID) else { return nil }
        // A lead with no heads left starts the roster over. The count would otherwise
        // climb for the life of the chat, and a lead that has sent out twenty-five heads
        // over a morning would name its next one "Hank 2" with one head in the panel.
        let sequential = hydraTeam(of: parentID).isEmpty ? 0 : parent.hydraSpawnCount
        // A delegation that announced its head by name is authoritative: the spawned head
        // carries exactly the announced roster name, so "Sent Gus" never spawns Otto.
        // The pin holds only while no head on the team already carries that index: two
        // heads sharing one index would merge each other's reports, so a reused or
        // unknown name falls back to the next head in order. The spawn count still moves
        // forward either way, so ordering and future names never shift for a pin.
        let taken = Set(hydraTeam(of: parentID).compactMap { $0.hydra?.index })
        let pinned = preferredIndex.flatMap { $0 >= 0 && !taken.contains($0) ? $0 : nil }
        let index = pinned ?? sequential
        updateThread(parentID) { $0.hydraSpawnCount = max(sequential + 1, parent.hydraSpawnCount + 1) }
        let launch = hydraLaunch(for: parent)
        let persona = HydraRoster.persona(at: index)

        // A Droppy-run head goes out on the pair's heads' provider, which may not be the
        // lead's: there it runs the pair's model or that provider's default, and the lead's
        // model and effort mean nothing to it. A native head lives in the lead's session.
        let headsProvider = kind == .droppy ? launch?.headsProvider ?? parent.provider : parent.provider
        let elsewhere = headsProvider != parent.provider
        var head = ChatThread(
            projectID: parent.projectID,
            provider: headsProvider,
            model: native?.model ?? launch?.workerModel ?? (elsewhere ? providers.defaultModel(for: headsProvider)?.id : parent.model),
            effort: launch?.workerEffort ?? (elsewhere ? nil : parent.effort),
            runtimeMode: parent.runtimeMode,
            fastMode: false
        )
        head.parentThreadID = parentID
        head.isInPanel = true
        head.worktreePath = parent.worktreePath
        head.branch = parent.branch
        head.title = task.isEmpty ? persona.name : "\(persona.name) · \(TextCleanup.singleLine(task, limit: 60))"
        head.hasCustomTitle = true
        var info = HydraHeadInfo(index: index, task: task, kind: kind, origin: origin)
        info.nativeID = native?.id
        info.nativeTaskID = native?.taskID
        info.toolUseID = native?.toolUseID
        info.batchID = batchID
        info.isBackground = native?.isBackground ?? true
        info.canStop = kind == .droppy || native?.taskID != nil || parent.provider == .codex
        head.hydra = info
        insertThread(head)

        // A new head brings the panel back and takes the stage.
        let leadRuntime = runtime(for: parentID)
        leadRuntime.isHydraPanelHidden = false
        leadRuntime.hydraSelectedHeadID = head.id
        updateThread(parentID) { $0.foldsHelpers = false }
        return head
    }

    /// Gives a Droppy-run head its copy of the checkout, then its brief.
    private func startDroppyHead(_ id: UUID, attachments: [Attachment], brief: @Sendable (HydraPersona, HydraPrompts.Workplace) -> String) async {
        guard let head = thread(id), let info = head.hydra, let parentID = head.parentThreadID, let lead = thread(parentID),
              let checkout = hydraCheckout(of: lead) else { return }
        // A head on another provider than its lead, with no model chosen for it, runs that
        // provider's default: the catalogue it comes from may not have loaded yet.
        if head.provider != lead.provider, head.model == nil {
            await providers.loadCatalog(head.provider)
            if let model = providers.defaultModel(for: head.provider)?.id {
                updateThread(id) { $0.model = model }
            }
        }
        var workplace = HydraPrompts.Workplace.shared(path: checkout)
        if settings.hydraIsolateHeads, let copy = await makeHydraCopy(for: head, of: checkout) {
            updateThread(id) {
                $0.worktreePath = copy.path
                $0.branch = nil
            }
            updateHydraHead(id) { $0.baseTree = copy.tree }
            workplace = .ownCopy(path: copy.path)
        }
        // Stopped while its copy was being made: it never starts.
        guard thread(id)?.hydra?.status == .running else { return }
        let headRuntime = runtime(for: id)
        headRuntime.draft = ComposerDraft(text: brief(info.persona, workplace), attachments: attachments)
        headRuntime.send()
    }

    /// A worktree for `head` holding the checkout exactly as it is, uncommitted and
    /// untracked work included: a tree of the working files, committed on top of HEAD
    /// where no branch will ever see it, and checked out detached. Nil where the project
    /// cannot be copied (no git, no commits yet) or git refuses; the head then works in
    /// the checkout itself.
    private func makeHydraCopy(for head: ChatThread, of checkout: String) async -> (path: String, tree: String)? {
        guard let info = head.hydra, let project = project(head.projectID) else { return nil }
        // A head's work landing in the checkout right now finishes first, so the copy
        // starts from the checkout whole rather than half-way through a patch.
        if let parentID = head.parentThreadID { await existingRuntime(for: parentID)?.hydraLanding?.value }
        let git = Git(checkout)
        guard await git.isRepository(), await git.hasCommits() else { return nil }
        let folder = project.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let name = info.persona.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let suffix = String(head.id.uuidString.lowercased().prefix(8))
        let path = Storage.worktreesDirectory.appendingPathComponent("\(folder)-\(name)-\(suffix)").path
        do {
            // The heads of one delegation block start within milliseconds of each other
            // and want the same checkout, so they share one capture of it (see
            // `HydraTreeCache`); only the worktree itself is made per head.
            let capture = try await HydraTreeCache.capture(of: checkout, with: git)
            try await git.addDetachedWorktree(at: path, commit: capture.commit)
            return (path, capture.tree)
        } catch {
            try? FileManager.default.removeItem(atPath: path)
            return nil
        }
    }

    func updateHydraHead(_ id: UUID, _ change: (inout HydraHeadInfo) -> Void) {
        updateThread(id) { thread in
            guard var info = thread.hydra else { return }
            change(&info)
            thread.hydra = info
        }
    }

    // MARK: - Reporting back

    /// A head is done: its status and report land on it, and its lead hears about it. A
    /// native head's result reaches the lead through the provider; a Droppy-run head's
    /// report is relayed by the lead's runtime, which waits for the rest of a batch.
    func finishHydraHead(_ id: UUID, status: TurnStatus, summary: String?, landing: HydraLanding? = nil) {
        guard let head = thread(id), let info = head.hydra, !info.isFinished else { return }
        let outcome: HydraHeadInfo.Status = switch status {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .stopped
        case .running: .running
        }
        // The progress a native head reported while it ran lands on the record now, once.
        let live = existingRuntime(for: id)
        updateHydraHead(id) {
            $0.status = outcome
            $0.summary = summary ?? $0.summary
            $0.finishedAt = .now
            if let landing { $0.landing = landing }
            if let live {
                if let activity = live.hydraActivity { $0.activity = activity }
                $0.toolCalls = max($0.toolCalls, live.hydraToolCalls)
                $0.tokens = max($0.tokens, live.hydraTokens)
            }
        }
        // Opt-in: a finished head leaves the panel on its own, for the sidebar under its
        // lead, instead of waiting for "Clear finished heads". Running heads stay put.
        if settings.hydraAutoClearFinished {
            updateThread(id) { $0.isInPanel = false }
            if let parentID = head.parentThreadID {
                updateThread(parentID) { $0.foldsHelpers = false }
                let leadRuntime = runtime(for: parentID)
                if leadRuntime.hydraSelectedHeadID == id { leadRuntime.hydraSelectedHeadID = nil }
                if leadRuntime.hydraPoppedHeadID == id { leadRuntime.hydraPoppedHeadID = nil }
            }
        }
        guard let parentID = head.parentThreadID, let finished = thread(id)?.hydra else { return }
        let leadRuntime = runtime(for: parentID)
        let copyPath = info.hasOwnCopy ? head.worktreePath : nil
        leadRuntime.hydraHeadFinished(head.id, info: finished, status: outcome, summary: summary, landing: landing, copyPath: copyPath)
        // The copy goes back only once the lead has the report, and only from a head that
        // finished: a head that was stopped or that failed hands its report the path to
        // its copy, where its half-done work is, and that folder has to still be there
        // when the lead reads it. Those copies go when the heads are cleared by hand, or
        // when the head is steered on for another turn.
        if settings.hydraAutoClearFinished, outcome == .completed {
            releaseHydraCopy(of: id)
        }
    }

    /// A Droppy-run head's turn ended: its last reply is its report, and the work in its
    /// copy lands in the lead's checkout before the lead hears of it. Native heads finish
    /// through their provider's own events instead.
    func hydraHeadTurnFinished(_ head: ChatThread, status: TurnStatus) {
        guard let info = head.hydra, info.kind == .droppy else { return }
        let headRuntime = existingRuntime(for: head.id)
        var report = headRuntime?.entries.last(where: { $0.kind == .assistant }).flatMap { entry -> String? in
            guard case .assistant(let message) = entry.item.content else { return nil }
            return message.text
        } ?? ""
        // A head that failed before it could answer reports the error it hit.
        if report.isEmpty, status == .failed, let notice = headRuntime?.entries.last(where: { $0.kind == .notice }),
           case .notice(let note) = notice.item.content {
            report = note.message
        }
        if let headRuntime {
            let tools = headRuntime.entries.count { $0.kind == .tool }
            updateHydraHead(head.id) { $0.toolCalls = tools }
        }
        // An API session is memory only, and keeping it is what lets the head be steered
        // on with its brief and its work still in mind; a process goes, and resumes by id.
        if !head.provider.isAPIKeyBased { headRuntime?.stopSession() }
        // A head that died at the door, before a tool ran (the agent's own store locked
        // while several started at once, or its process gone before a word), is started
        // again on its brief after a short pause rather than reported as failed: the lead
        // never hears of a head that only stumbled on the way out. Two more goes, then it
        // reports the failure.
        if status == .failed, Self.isLaunchFailure(report), let headRuntime,
           headRuntime.entries.contains(where: { $0.kind == .tool }) == false,
           hydraHeadRetries[head.id, default: 0] < 2,
           let brief = headRuntime.entries.first(where: { $0.kind == .user }).flatMap({ entry -> String? in
               guard case .user(let message) = entry.item.content else { return nil }
               return message.text
           }) {
            hydraHeadRetries[head.id, default: 0] += 1
            let attempt = hydraHeadRetries[head.id, default: 0]
            let pause = Double(attempt) * 2 + Double(info.index % 4) * 0.5
            Task {
                try? await Task.sleep(for: .seconds(pause))
                // Stopped from the panel, or steered on by hand, meanwhile: leave it.
                guard let headRuntime = existingRuntime(for: head.id), !headRuntime.isRunning,
                      thread(head.id)?.hydra?.status == .running else { return }
                headRuntime.draft = ComposerDraft(text: brief, attachments: [])
                headRuntime.send()
            }
            return
        }
        Task {
            // Only finished work lands: a stopped or failed head keeps its half-done edits
            // in its copy, where a later turn can carry on from them.
            var landing: HydraLanding?
            if status == .completed, info.hasOwnCopy { landing = await landHydraHead(head.id) }
            // Landing takes seconds, and minutes behind a queue or a lead mid-turn. The
            // user may have steered the head on from the panel in that time: it is at work
            // again, so it is not finished. Marking it so would hand the lead a report for
            // a turn still running and give back the copy the head's tools are writing
            // into. It reports again when this new turn ends.
            guard existingRuntime(for: head.id)?.isRunning != true else { return }
            // The head reported; a report arriving on an already-finished head (the user
            // steered it on from the panel) goes to the lead as a fresh one.
            if thread(head.id)?.hydra?.isFinished == true { updateHydraHead(head.id) { $0.status = .running } }
            finishHydraHead(head.id, status: status, summary: report, landing: landing)
        }
    }

    /// Whether a head's failure report is the agent failing to get going at all, rather
    /// than anything about the task: its store locked, no session, or the process gone.
    private static func isLaunchFailure(_ report: String) -> Bool {
        let text = report.lowercased()
        return ["database is locked", "database locked", "sqlite_busy", "did not start a session", "the agent exited", "stopped unexpectedly"]
            .contains { text.contains($0) }
    }

    /// Carries what changed in a head's copy since its base into the lead's checkout: the
    /// patch between the two trees, applied there, three-way where the checkout has moved
    /// on. What lands moves the base forward, so a head steered on later lands only what
    /// is new; a patch that will not apply is kept as a file and the base stays.
    ///
    /// The patch is read from the head's own copy, which nothing else is touching, so
    /// heads finishing together prepare theirs side by side. Writing into the checkout is
    /// the part that goes one at a time: two patches at once would leave the later one
    /// judged against files the earlier was still changing. A patch over a file the lead
    /// is editing this very turn waits for the lead to come to rest first (see
    /// `waitForSettledCheckout`); the others do not wait for it.
    private func landHydraHead(_ id: UUID) async -> HydraLanding {
        guard let parentID = thread(id)?.parentThreadID else { return HydraLanding() }
        var landing = HydraLanding()
        let prepared: HydraPatch
        do {
            guard let made = try await prepareHydraPatch(id) else { return landing }
            prepared = made
        } catch {
            landing.error = error.localizedDescription
            return landing
        }
        landing.files = prepared.files
        landing.droppedBuildOutputFiles = prepared.droppedBuildOutputFiles
        await waitForSettledCheckout(parentID, paths: prepared.files.map(\.path))
        let leadRuntime = runtime(for: parentID)
        let previous = leadRuntime.hydraLanding
        let applied = Task<HydraLanding, Never> {
            await previous?.value
            return await self.applyHydraHead(id, landing: landing, patch: prepared)
        }
        leadRuntime.hydraLanding = Task { _ = await applied.value }
        return await applied.value
    }

    /// A head's work as a patch against the tree its copy started from, with the files it
    /// touches. Nil where the head changed nothing or has no copy to compare.
    private func prepareHydraPatch(_ id: UUID) async throws -> HydraPatch? {
        guard let head = thread(id), let info = head.hydra, let base = info.baseTree, let copy = head.worktreePath else { return nil }
        let copyGit = Git(copy)
        let after = try await copyGit.captureTree()
        guard after != base else { return nil }
        let text = try await copyGit.diff(from: base, to: after, binary: true)
        guard !text.isEmpty else { return nil }
        // A binary patch runs to megabytes, and parsing it counts every line: off the
        // main actor, so the chat keeps streaming while a head lands.
        return await Task.detached(priority: .utility) {
            let filtered = HydraPatchFilter.removingBuildOutput(from: text)
            guard !filtered.text.isEmpty else { return nil }
            let files = DiffParser.parse(filtered.text).map {
                HydraLanding.File(path: $0.path, additions: $0.additions, deletions: $0.deletions)
            }
            return HydraPatch(
                text: filtered.text,
                files: files,
                droppedBuildOutputFiles: filtered.droppedBuildOutputFiles,
                after: after
            )
        }.value
    }

    /// Waits for the lead's checkout to be a safe place to write: the lead is not in the
    /// middle of a turn that has already edited one of `paths` (a three-way merge would
    /// leave conflict markers in a file the lead is still writing), and the team's work is
    /// not on its way to the remote. Gives up after half an hour and lands anyway, so a
    /// head's work is never lost to a lead that never comes to rest.
    private func waitForSettledCheckout(_ parentID: UUID, paths: [String]) async {
        guard let leadRuntime = existingRuntime(for: parentID) else { return }
        let wanted = Set(paths)
        let deadline = Date.now.addingTimeInterval(30 * 60)
        while Date.now < deadline {
            let busy = leadRuntime.phase != .idle && !wanted.isEmpty
                && !wanted.isDisjoint(with: hydraChatContext(for: parentID).touchedPaths)
            guard busy || leadRuntime.isHydraMerging else { return }
            // A cancelled task's sleep throws at once, without suspending: swallowing
            // that would turn this into a tight loop on the main actor for the rest of
            // the half hour, with the whole app frozen behind it. The landing goes ahead
            // instead, as it does at the deadline.
            guard (try? await Task.sleep(for: .milliseconds(250))) != nil else { return }
        }
    }

    private func applyHydraHead(_ id: UUID, landing: HydraLanding, patch: HydraPatch) async -> HydraLanding {
        var landing = landing
        guard let head = thread(id), let info = head.hydra,
              let parentID = head.parentThreadID, let lead = thread(parentID), let checkout = hydraCheckout(of: lead) else { return landing }
        let checkoutGit = Git(checkout)
        // A rebase or a merge is half done in the checkout: a patch laid on top of that
        // would be impossible to tell from the operation's own conflicts, and resolving
        // either would lose the other. The work waits as a patch file instead.
        guard !(await checkoutGit.hasOperationInProgress()) else {
            landing.patchPath = keepHydraPatch(patch.text, of: info, headID: head.id)
            landing.error = "a rebase or merge is underway in the checkout"
            noteHydraLanding(landing, of: info, to: parentID)
            return landing
        }
        do {
            landing.conflicts = try await checkoutGit.apply(patch.text)
            // Only a clean landing moves the base. With conflict markers in the checkout
            // the work is not settled, so the head keeps its whole diff: steered on, it
            // offers all of it again rather than leaving the unresolved part to nobody.
            if landing.conflicts.isEmpty { updateHydraHead(id) { $0.baseTree = patch.after } }
        } catch {
            landing.patchPath = keepHydraPatch(patch.text, of: info, headID: head.id)
            landing.error = error.localizedDescription
        }
        // The checkout has moved, so the next head captures it afresh rather than starting
        // from the tree this patch just changed.
        HydraTreeCache.invalidate(checkout)
        // The lead's changes tab and diff panel now show the head's work too.
        existingRuntime(for: parentID)?.noteDiffChanged()
        noteHydraLanding(landing, of: info, to: parentID)
        return landing
    }

    /// Keeps a patch that could not be applied as a file beside the others, and hands back
    /// where it went; nil when even that failed.
    private func keepHydraPatch(_ text: String, of info: HydraHeadInfo, headID: UUID) -> String? {
        let slug = info.persona.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let url = Storage.patchesDirectory.appendingPathComponent("\(slug)-\(headID.uuidString.lowercased().prefix(8)).patch")
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url.path
    }

    /// A landing that did not go cleanly says so in the lead's timeline: conflict markers
    /// and kept patches are otherwise only a few words in a head's row, and the lead is
    /// told not to look at git status, so nobody would see them.
    private func noteHydraLanding(_ landing: HydraLanding, of info: HydraHeadInfo, to parentID: UUID) {
        guard let leadRuntime = existingRuntime(for: parentID) else { return }
        let name = info.persona.name
        if !landing.conflicts.isEmpty {
            let files = landing.conflicts.map { "`\($0)`" }.joined(separator: ", ")
            leadRuntime.appendHydraNote("""
            \(name)'s work landed with conflict markers in \(landing.conflicts.count == 1 ? "1 file" : "\(landing.conflicts.count) files").
            \(files)

            The checkout had moved on where \(name) was working, so the merge was three-way. Resolve the markers before the work goes out; a merge refuses while they are there.
            """)
        }
        if let path = landing.patchPath {
            let files = landing.files.map { "`\($0.path)`" }.joined(separator: ", ")
            leadRuntime.appendHydraNote("""
            \(name)'s work did not land and was kept as a patch.
            \(files)

            \(landing.error.map { "Why it did not land: \($0).\n\n" } ?? "")Apply it with `git apply --3way \(path)` and settle what conflicts.
            """)
        }
    }

    // MARK: - Stopping and clearing

    /// Stops a head where it runs: a Droppy-run head's own turn, a native head through
    /// the lead's session.
    func stopHydraHead(_ id: UUID) {
        guard let head = thread(id), let info = head.hydra, !info.isFinished else { return }
        switch info.kind {
        case .droppy:
            if let headRuntime = existingRuntime(for: id), headRuntime.isRunning {
                headRuntime.interrupt()
            } else {
                // Not started yet, its copy still being made: it never will.
                finishHydraHead(id, status: .interrupted, summary: nil)
            }
        case .native:
            guard let parentID = head.parentThreadID, let nativeID = info.nativeID else { return }
            let leadRuntime = runtime(for: parentID)
            Task {
                let stopped = await leadRuntime.stopNativeHead(nativeID)
                if !stopped { self.updateHydraHead(id) { $0.canStop = false } }
            }
        }
    }

    /// Stops every head of a lead's still at work.
    func stopAllHydraHeads(of parentID: UUID) {
        for head in hydraHeads(of: parentID) where head.hydra?.status == .running {
            stopHydraHead(head.id)
        }
    }

    /// Clears the panel: finished heads move under the lead in the sidebar, and the panel
    /// stays out of the way until the next head starts. Running heads keep working.
    func dismissHydraHeads(of parentID: UUID) {
        clearFinishedHydraHeads(of: parentID)
        let leadRuntime = runtime(for: parentID)
        leadRuntime.isHydraPanelHidden = true
        leadRuntime.hydraSelectedHeadID = nil
        leadRuntime.hydraPoppedHeadID = nil
    }

    /// Finished heads leave the panel for the sidebar, and give their copies back.
    func clearFinishedHydraHeads(of parentID: UUID) {
        for head in hydraHeads(of: parentID) where head.hydra?.isFinished == true {
            updateThread(head.id) { $0.isInPanel = false }
            releaseHydraCopy(of: head.id)
        }
        updateThread(parentID) { $0.foldsHelpers = false }
    }

    /// Removes the copy of the checkout a head worked in. Its work has landed, or its
    /// patch is kept; a head talked to afterwards works in the checkout itself.
    func releaseHydraCopy(of id: UUID) {
        guard let head = thread(id), let info = head.hydra, info.hasOwnCopy, let copy = head.worktreePath,
              let project = project(head.projectID) else { return }
        // A head back at work keeps its copy: `git worktree remove --force` on the folder
        // its tools are writing into would take the work with it.
        guard existingRuntime(for: id)?.isRunning != true else { return }
        // Work that never landed lives only in the copy, and the head's report points the
        // lead at it. It is kept as a patch before the folder goes.
        let unlanded = info.status != .completed || info.landing == nil
        let base = info.baseTree
        let name = info.persona.name
        // The session's tools are rooted in the copy; the next turn starts a fresh one.
        existingRuntime(for: id)?.stopSession()
        updateThread(id) {
            $0.worktreePath = nil
            $0.branch = nil
        }
        updateHydraHead(id) { $0.baseTree = nil }
        Task {
            if unlanded, let base { await self.keepHydraCopyAsPatch(id, name: name, copy: copy, base: base) }
            try? await Git(project.path).removeWorktree(at: copy)
        }
    }

    /// Writes what a head changed in its copy but never landed to a patch file, and tells
    /// the lead where it went. Nothing to keep where the copy holds no changes of its own.
    private func keepHydraCopyAsPatch(_ id: UUID, name: String, copy: String, base: String) async {
        let copyGit = Git(copy)
        guard let after = try? await copyGit.captureTree(), after != base,
              let patch = try? await copyGit.diff(from: base, to: after, binary: true), !patch.isEmpty else { return }
        let slug = name.replacingOccurrences(of: " ", with: "-").lowercased()
        let url = Storage.patchesDirectory.appendingPathComponent("\(slug)-\(id.uuidString.lowercased().prefix(8))-unlanded.patch")
        guard (try? patch.write(to: url, atomically: true, encoding: .utf8)) != nil else { return }
        guard let parentID = thread(id)?.parentThreadID, let leadRuntime = existingRuntime(for: parentID) else { return }
        leadRuntime.appendHydraNote("""
        \(name)'s unfinished work was kept as a patch before its copy was cleared.
        \(url.path)

        Nothing of it had landed in your checkout. Apply it with `git apply --3way \(url.path)` if you still want it.
        """)
    }

    /// Heads whose copies are gone from disk (deleted by hand, say) work in the checkout
    /// from now on, instead of failing every tool call.
    func sweepHydraCopies() {
        // Copies deleted from disk still hold their names in the registry until pruned.
        for project in projects {
            Task { await Git(project.path).pruneWorktrees() }
        }
        for head in threads where head.hydra?.hasOwnCopy == true {
            guard let copy = head.worktreePath, !FileManager.default.fileExists(atPath: copy) else { continue }
            updateThread(head.id) {
                $0.worktreePath = nil
                $0.branch = nil
            }
            updateHydraHead(head.id) { $0.baseTree = nil }
        }
    }

    /// What a head sent out from the queue is told about the main chat: the user's last
    /// request, the lead's latest reply and the files it has touched this turn. Read from
    /// the timeline, so it costs no model call.
    func hydraChatContext(for parentID: UUID) -> HydraPrompts.ChatContext {
        guard let leadRuntime = existingRuntime(for: parentID) else { return HydraPrompts.ChatContext() }
        var context = HydraPrompts.ChatContext()
        for entry in leadRuntime.entries.reversed() {
            switch entry.item.content {
            case .user(let message) where context.lastUserPrompt == nil && !message.isFromHydra:
                context.lastUserPrompt = message.text
            case .assistant(let message) where context.lastReply == nil:
                context.lastReply = message.text
            default:
                break
            }
            if context.lastUserPrompt != nil, context.lastReply != nil { break }
        }
        let currentTurn = leadRuntime.turns.last?.id
        var touched: [String] = []
        for entry in leadRuntime.entries where entry.kind == .tool && entry.item.turnID == currentTurn {
            guard case .tool(let call) = entry.item.content else { continue }
            for edit in call.edits where !edit.path.isEmpty && !touched.contains(edit.path) {
                touched.append(edit.path)
            }
        }
        context.touchedPaths = touched
        return context
    }
}
