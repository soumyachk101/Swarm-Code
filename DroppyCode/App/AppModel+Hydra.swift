import Foundation

// Hydra's heads are threads: each one has a timeline of its own, sits in its lead's
// floating panel while it works, and drops under the lead in the sidebar once dismissed,
// like any helper. Native heads run inside the lead's provider session and their
// timelines fill from the session's events; Droppy-run heads have sessions of their own,
// each in a copy of the checkout made for it, and their work lands in the lead's checkout
// the moment they report.

extension AppModel {
    /// Whether a chat leads a team right now: Hydra on for the app. A chat keeps no
    /// switch of its own: with Hydra on in Settings it stays on in every chat until it
    /// is switched off there.
    func hydraIsOn(_ thread: ChatThread) -> Bool {
        settings.hydraEnabled && !thread.isHelper
    }

    /// Whether the provider runs heads inside its own session, with the pair's model and
    /// effort. Every other provider gets Droppy-run heads and the delegation block.
    static func hydraIsNative(_ provider: ProviderKind) -> Bool {
        provider == .claude || provider == .codex || provider == .copilot
    }

    /// The pair a chat leads with: the best fit for its provider and model now.
    func hydraPair(for thread: ChatThread) -> HydraPair? {
        if let pair = settings.hydraPair(thread.hydraPairID), pair.provider == thread.provider { return pair }
        return settings.hydraPair(for: thread.provider, model: thread.model)
    }

    /// What the heads run on while the chat leads, or nil with Hydra off. Without a pair
    /// the heads inherit the chat's own model and effort.
    func hydraLaunch(for thread: ChatThread) -> HydraLaunch? {
        guard hydraIsOn(thread) else { return nil }
        let pair = hydraPair(for: thread)
        return HydraLaunch(
            workerModel: pair?.workerModel,
            workerEffort: pair?.workerEffort,
            maxHeads: pair?.maxHeads ?? HydraPair.defaultMaxHeads,
            isolatesHeads: settings.hydraIsolateHeads
        )
    }

    /// Legacy per-chat switch, now unused. Kept so old callers still compile; Hydra is
    /// app-wide (see `hydraIsOn`) and the button only shows or hides the panel.
    func setHydra(_ on: Bool, for id: UUID) {
        guard let thread = thread(id) else { return }
        guard on else {
            updateThread(id) { $0.hydraEnabled = false }
            return
        }
        let pair = settings.hydraPair(for: thread.provider, model: thread.model)
        updateThread(id) {
            $0.hydraEnabled = true
            $0.hydraPairID = pair?.id
        }
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
        brief: @escaping @Sendable (HydraPersona, HydraPrompts.Workplace) -> String
    ) -> ChatThread? {
        guard let head = insertHydraHead(from: parentID, task: task, kind: .droppy, origin: origin, native: nil, batchID: batchID) else { return nil }
        Task { await startDroppyHead(head.id, attachments: attachments, brief: brief) }
        return head
    }

    private func insertHydraHead(
        from parentID: UUID,
        task: String,
        kind: HydraHeadInfo.Kind,
        origin: HydraHeadInfo.Origin,
        native: AgentSpawn?,
        batchID: UUID?
    ) -> ChatThread? {
        guard let parent = thread(parentID) else { return nil }
        let index = parent.hydraSpawnCount
        updateThread(parentID) { $0.hydraSpawnCount += 1 }
        let launch = hydraLaunch(for: parent)
        let persona = HydraRoster.persona(at: index)

        var head = ChatThread(
            projectID: parent.projectID,
            provider: parent.provider,
            model: native?.model ?? launch?.workerModel ?? parent.model,
            effort: launch?.workerEffort ?? parent.effort,
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
        let git = Git(checkout)
        guard await git.isRepository(), await git.hasCommits() else { return nil }
        let folder = project.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let name = info.persona.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let suffix = String(head.id.uuidString.lowercased().prefix(8))
        let path = Storage.worktreesDirectory.appendingPathComponent("\(folder)-\(name)-\(suffix)").path
        do {
            let tree = try await git.captureTree()
            let commit = try await git.commitTree(tree, message: "Droppy Code: \(info.persona.name)'s starting point")
            try await git.addDetachedWorktree(at: path, commit: commit)
            return (path, tree)
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
        // lead, instead of waiting for "Clear finished heads", and gives its copy of the
        // checkout back with it. Running heads stay put.
        if settings.hydraAutoClearFinished {
            updateThread(id) { $0.isInPanel = false }
            releaseHydraCopy(of: id)
            if let parentID = head.parentThreadID {
                updateThread(parentID) { $0.foldsHelpers = false }
                let leadRuntime = runtime(for: parentID)
                if leadRuntime.hydraSelectedHeadID == id { leadRuntime.hydraSelectedHeadID = nil }
            }
        }
        guard let parentID = head.parentThreadID, let finished = thread(id)?.hydra else { return }
        let leadRuntime = runtime(for: parentID)
        let copyPath = info.hasOwnCopy ? head.worktreePath : nil
        leadRuntime.hydraHeadFinished(head.id, info: finished, status: outcome, summary: summary, landing: landing, copyPath: copyPath)
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
        Task {
            // Only finished work lands: a stopped or failed head keeps its half-done edits
            // in its copy, where a later turn can carry on from them.
            var landing: HydraLanding?
            if status == .completed, info.hasOwnCopy { landing = await landHydraHead(head.id) }
            // The head reported; a report arriving on an already-finished head (the user
            // steered it on from the panel) goes to the lead as a fresh one.
            if thread(head.id)?.hydra?.isFinished == true { updateHydraHead(head.id) { $0.status = .running } }
            finishHydraHead(head.id, status: status, summary: report, landing: landing)
        }
    }

    /// Carries what changed in a head's copy since its base into the lead's checkout: the
    /// patch between the two trees, applied there, three-way where the checkout has moved
    /// on. What lands moves the base forward, so a head steered on later lands only what
    /// is new; a patch that will not apply is kept as a file and the base stays.
    private func landHydraHead(_ id: UUID) async -> HydraLanding {
        var landing = HydraLanding()
        guard let head = thread(id), let info = head.hydra, let base = info.baseTree, let copy = head.worktreePath,
              let parentID = head.parentThreadID, let lead = thread(parentID), let checkout = hydraCheckout(of: lead) else { return landing }
        do {
            let copyGit = Git(copy)
            let after = try await copyGit.captureTree()
            guard after != base else { return landing }
            let patch = try await copyGit.diff(from: base, to: after, binary: true)
            guard !patch.isEmpty else { return landing }
            landing.files = DiffParser.parse(patch).map { HydraLanding.File(path: $0.path, additions: $0.additions, deletions: $0.deletions) }
            do {
                landing.conflicts = try await Git(checkout).apply(patch)
                updateHydraHead(id) { $0.baseTree = after }
            } catch {
                let name = info.persona.name.replacingOccurrences(of: " ", with: "-").lowercased()
                let url = Storage.patchesDirectory.appendingPathComponent("\(name)-\(head.id.uuidString.lowercased().prefix(8)).patch")
                try patch.write(to: url, atomically: true, encoding: .utf8)
                landing.patchPath = url.path
                landing.error = error.localizedDescription
            }
            // The lead's changes tab and diff panel now show the head's work too.
            existingRuntime(for: parentID)?.noteDiffChanged()
        } catch {
            landing.error = error.localizedDescription
        }
        return landing
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
        // The session's tools are rooted in the copy; the next turn starts a fresh one.
        existingRuntime(for: id)?.stopSession()
        updateThread(id) {
            $0.worktreePath = nil
            $0.branch = nil
        }
        updateHydraHead(id) { $0.baseTree = nil }
        Task { try? await Git(project.path).removeWorktree(at: copy) }
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
