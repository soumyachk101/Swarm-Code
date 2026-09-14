import Foundation

// Hydra's heads are threads: each one has a timeline of its own, sits in its lead's
// floating panel while it works, and drops under the lead in the sidebar once dismissed,
// like any helper. Native heads run inside the lead's provider session and their
// timelines fill from the session's events; Droppy-run heads have sessions of their own.

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

    /// The pair a chat leads with: the one picked when Hydra was switched on, or the best
    /// fit for its provider and model now.
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
            maxHeads: pair?.maxHeads ?? HydraPair.defaultMaxHeads
        )
    }

    /// Switches Hydra on or off for a chat. Switching on applies the pair set up for the
    /// chat's provider: a pair that names a lead model moves the chat onto it, so the
    /// team the user set up is the team that runs.
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

    /// Sends out a head for `parentID`. A native head mirrors one the provider started, so
    /// its timeline only rehearses what the session reports; a Droppy-run head gets a
    /// session of its own on the pair's model and effort and is sent `prompt` at once.
    /// Either way the head works in the lead's checkout.
    @discardableResult
    func spawnHydraHead(
        from parentID: UUID,
        task: String,
        prompt: String?,
        attachments: [Attachment] = [],
        kind: HydraHeadInfo.Kind,
        origin: HydraHeadInfo.Origin,
        native: AgentSpawn? = nil,
        batchID: UUID? = nil
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

        let headRuntime = runtime(for: head.id)
        switch kind {
        case .native:
            // The brief, when the provider has said what it is; otherwise the timeline
            // starts on the working line and the brief slots in above once it arrives.
            headRuntime.rehearseTurn(prompt)
        case .droppy:
            headRuntime.draft = ComposerDraft(text: prompt ?? task, attachments: attachments)
            headRuntime.send()
        }
        return head
    }

    func updateHydraHead(_ id: UUID, _ change: (inout HydraHeadInfo) -> Void) {
        updateThread(id) { thread in
            guard var info = thread.hydra else { return }
            change(&info)
            thread.hydra = info
        }
    }

    /// A head is done: its status and report land on it, and its lead hears about it. A
    /// native head's result reaches the lead through the provider; a Droppy-run head's
    /// report is relayed by the lead's runtime, which waits for the rest of a batch.
    func finishHydraHead(_ id: UUID, status: TurnStatus, summary: String?) {
        guard let head = thread(id), let info = head.hydra, !info.isFinished else { return }
        let outcome: HydraHeadInfo.Status = switch status {
        case .completed: .completed
        case .failed: .failed
        case .interrupted: .stopped
        case .running: .running
        }
        updateHydraHead(id) {
            $0.status = outcome
            $0.summary = summary ?? $0.summary
            $0.finishedAt = .now
        }
        // Opt-in: a finished head leaves the panel on its own, for the sidebar under its
        // lead, instead of waiting for "Clear finished heads". Running heads stay put.
        if settings.hydraAutoClearFinished {
            updateThread(id) { $0.isInPanel = false }
            if let parentID = head.parentThreadID {
                updateThread(parentID) { $0.foldsHelpers = false }
                let leadRuntime = runtime(for: parentID)
                if leadRuntime.hydraSelectedHeadID == id { leadRuntime.hydraSelectedHeadID = nil }
            }
        }
        guard let parentID = head.parentThreadID else { return }
        let leadRuntime = runtime(for: parentID)
        leadRuntime.hydraHeadFinished(head.id, info: info, status: outcome, summary: summary)
    }

    /// A Droppy-run head's turn ended: its last reply is its report. Native heads finish
    /// through their provider's own events instead.
    func hydraHeadTurnFinished(_ head: ChatThread, status: TurnStatus) {
        guard let info = head.hydra, info.kind == .droppy else { return }
        let headRuntime = existingRuntime(for: head.id)
        let report = headRuntime?.entries.last(where: { $0.kind == .assistant }).flatMap { entry -> String? in
            guard case .assistant(let message) = entry.item.content else { return nil }
            return message.text
        } ?? ""
        // The head reported; a report arriving on an already-finished head (the user steered
        // it on from the panel) goes to the lead as a fresh one.
        if info.isFinished { updateHydraHead(head.id) { $0.status = .running } }
        finishHydraHead(head.id, status: status, summary: report)
        // The process goes; the head resumes its session if the user steers it again.
        headRuntime?.stopSession()
    }

    /// Stops a head where it runs: a Droppy-run head's own turn, a native head through
    /// the lead's session.
    func stopHydraHead(_ id: UUID) {
        guard let head = thread(id), let info = head.hydra, !info.isFinished else { return }
        switch info.kind {
        case .droppy:
            existingRuntime(for: id)?.interrupt()
        case .native:
            guard let parentID = head.parentThreadID, let nativeID = info.nativeID else { return }
            let leadRuntime = runtime(for: parentID)
            Task {
                let stopped = await leadRuntime.stopNativeHead(nativeID)
                if !stopped { self.updateHydraHead(id) { $0.canStop = false } }
            }
        }
    }

    /// Clears the panel: finished heads move under the lead in the sidebar, and the panel
    /// stays out of the way until the next head starts. Running heads keep working.
    func dismissHydraHeads(of parentID: UUID) {
        for head in hydraHeads(of: parentID) where head.hydra?.isFinished == true {
            updateThread(head.id) { $0.isInPanel = false }
        }
        let leadRuntime = runtime(for: parentID)
        leadRuntime.isHydraPanelHidden = true
        leadRuntime.hydraSelectedHeadID = nil
        updateThread(parentID) { $0.foldsHelpers = false }
    }

    /// What a head sent out from the queue is told about the main chat: the user's last
    /// request, the lead's latest reply and the files it has touched this turn. Read from
    /// the timeline, so it costs no model call.
    func hydraChatContext(for parentID: UUID) -> HydraPrompts.ChatContext {
        guard let leadRuntime = existingRuntime(for: parentID) else { return HydraPrompts.ChatContext() }
        var context = HydraPrompts.ChatContext()
        for entry in leadRuntime.entries.reversed() {
            switch entry.item.content {
            case .user(let message) where context.lastUserPrompt == nil && !message.isHydraReport:
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
