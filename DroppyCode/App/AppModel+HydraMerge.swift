import AppKit
import Foundation

// With "Merge when the team is done" on, a Hydra lead's finished job lands by itself: the
// files the lead and its heads changed go out as a commit on a branch of their own, the
// branch is pushed, a merge request is opened and merged with the forge's CLI, and the
// checkout is brought up to date. The checkout never changes branch for any of it: the
// commit is built from a snapshot of the working tree, so nothing running in the checkout
// meanwhile is disturbed, and nothing uncommitted that is not the team's goes along.

extension AppModel {
    /// Lands a lead's finished work, when the setting says so. Runs once per finished job;
    /// what happened lands in the lead's timeline as a note from Hydra.
    func autoMergeHydraWork(of leadID: UUID) async {
        guard settings.hydraAutoMerge, let lead = thread(leadID), hydraIsOn(lead), let project = project(lead.projectID),
              let runtime = existingRuntime(for: leadID), !runtime.isHydraMerging else { return }
        runtime.isHydraMerging = true
        defer { runtime.isHydraMerging = false }
        // A head's work still going into the checkout finishes first: the snapshot the
        // commit is built from must hold the patch whole or not at all. Landings that have
        // not started yet wait for the merge instead (see `waitForSettledCheckout`).
        await runtime.hydraLanding?.value

        let checkout = lead.worktreePath ?? project.path
        let git = Git(checkout)
        guard await git.isRepository(), await git.hasCommits() else { return }
        guard await git.remoteURL() != nil else {
            note(leadID, "Hydra did not merge: no remote.", "The team's work is in the checkout; there is no origin to push it to.")
            return
        }
        guard !(await git.hasOperationInProgress()) else {
            note(leadID, "Hydra did not merge: a rebase or merge is underway.", "The team's work is in the checkout; finish that first and merge by hand.")
            return
        }

        // What the team touched, and only that, so a sibling's uncommitted work in the
        // same checkout stays behind.
        let work = await hydraWork(of: leadID, runtime: runtime, checkout: checkout, git: git)
        let sorted = work.paths
        guard !sorted.isEmpty else { return }
        // A head's landing can leave conflict markers behind (see `Git.apply`), and a lead
        // told not to look at git status may answer without settling them. Those markers
        // must never reach the remote: the job stays in the checkout until they are gone.
        let conflicted = await Self.pathsWithConflictMarkers(sorted, in: checkout)
        guard conflicted.isEmpty else {
            let files = conflicted.map { "`\($0)`" }.joined(separator: ", ")
            note(leadID, "Hydra did not merge: conflict markers in \(conflicted.count == 1 ? "a file" : "\(conflicted.count) files").", "\(files) still \(conflicted.count == 1 ? "holds" : "hold") conflict markers from a head's landing. Resolve them, then ask for the merge again.")
            return
        }

        do {
            let head = try await git.commitHash()
            let tree = try await git.captureTree(paths: sorted)
            // Everything the team did is committed already, or was merged before.
            guard try await tree != git.treeHash(of: "HEAD") else { return }

            let patch = (try? await git.diff(from: head, to: tree)) ?? ""
            // A whole job's patch is big and parsing it counts every line: off the main
            // actor, so the chat stays live while the work goes out.
            let files = await Task.detached(priority: .utility) { DiffParser.parse(patch) }.value
            let message = await commitMessage(for: lead, files: files, patch: patch, directory: checkout)
            let subject = TextCleanup.singleLine(message, limit: 72)

            let status = await git.status()
            let target = await git.defaultBranch()
            let current = status?.branch
            // On the default branch the commit goes to a branch of its own, made and pushed
            // without ever being checked out; on any other branch it is that branch's.
            let ownBranch = current == nil || current == target
            let branch = ownBranch ? Self.hydraBranchName(for: lead) : current!
            let commit = try await git.commitWork(tree, parent: head, message: message)
            // Writing the branch to a commit built on `head` drops anything committed
            // since: a minute passes here, and the user may have committed in a terminal.
            // HEAD is read again so the user gets told in plain words when that happened,
            // and the move itself names the value it expects, so git refuses the write
            // outright if the branch shifts in the moment between the two.
            guard try await git.commitHash() == head else {
                note(leadID, "Hydra did not merge: the checkout moved while it worked.", "A commit landed on `\(current ?? target)` while the team's work was being prepared, and moving the branch now would orphan it. The work is still in the checkout; ask for the merge again.")
                return
            }
            // A branch of its own must not exist yet; the checkout's own branch must still
            // be where it was read.
            try await git.updateRef("refs/heads/\(branch)", to: commit, expecting: ownBranch ? nil : head)
            if !ownBranch {
                // The branch moved under the checkout: the index catches up, the working
                // tree already has the content.
                try await git.resetIndex(paths: sorted)
            }
            try await git.pushBranch(branch)

            let body = mergeRequestBody(for: lead, files: files, runtime: runtime)
            guard let url = try await git.createPullRequest(title: subject, body: body, source: branch, target: target),
                  let link = MergeRequestLink(url: url) else {
                note(leadID, "Hydra pushed \(branch) but could not open a merge request.", "Open one for `\(branch)` into `\(target)` and merge it from there.")
                return
            }
            do {
                try await git.mergePullRequest(link)
            } catch {
                note(leadID, "Hydra opened \(link.label) but could not merge it.", "\(url.absoluteString)\n\n\(error.localizedDescription)\n\nMerge it from the link once it is ready; the branch `\(branch)` has the team's work.")
                return
            }

            // The work is on the default branch now, so these turns are spent: the next
            // job merges what comes after them and never this again.
            runtime.markHydraMerged(work.turnIDs)

            var lines = ["\(url.absoluteString)", "", Self.filesLine(files) + " landed on `\(target)` from `\(branch)`."]
            if work.dropped > 0 {
                lines.append("\(work.dropped == 1 ? "One file" : "\(work.dropped) files") the team wrote outside the checkout stayed where they are; only the project's own files can go out.")
            }
            if ownBranch {
                let synced = await syncDefaultBranch(git, from: head, target: target, ownPaths: sorted)
                lines.append(synced ? "The checkout is up to date." : "The checkout was left as it was: `\(target)` moved on in other ways meanwhile, or the team's files changed again; `git pull` when it suits you.")
            } else if lead.worktreePath != nil {
                // The lead worked in a worktree: the project's own checkout follows when it can.
                let main = Git(project.path)
                if await main.status()?.branch == target, await main.dirtyPaths().isEmpty, !(await main.hasOperationInProgress()) {
                    if (try? await main.pullFastForward()) != nil { lines.append("The project checkout is up to date.") }
                }
            }
            note(leadID, "Hydra merged \(link.label).", lines.joined(separator: "\n"))
            existingRuntime(for: leadID)?.noteDiffChanged()
        } catch {
            note(leadID, "Hydra could not merge the team's work.", "\(error.localizedDescription)\n\nThe work is still in the checkout.")
        }
    }

    /// The files a lead's job changed, gathered three ways because no one way sees them
    /// all:
    ///
    /// - the turns of this job, meaning the ones no merge has taken yet, and the paths
    ///   they reported;
    /// - the heads that worked alongside those turns: what a Droppy-run head landed, and,
    ///   for a head the provider runs inside the lead's own session, the edits its own
    ///   timeline reported. A native head works in this very checkout and lands nothing,
    ///   so without its timeline its files are simply missing and the branch goes out
    ///   half-written;
    /// - and, where the first of those turns left a checkpoint, whatever else the checkout
    ///   holds that it did not then, less whatever was already uncommitted at the time.
    ///   That catches the edits no tool reported, a head writing through a shell say, and
    ///   costs nothing for a file whose content matches HEAD anyway.
    ///
    /// Paths outside the checkout are dropped rather than passed on: a lead writes to its
    /// own memory files, and `git add -A -- <path>` on one of those fails outright and
    /// takes the whole merge with it.
    private func hydraWork(of leadID: UUID, runtime: ThreadRuntime, checkout: String, git: Git) async -> (paths: [String], turnIDs: [UUID], dropped: Int) {
        let turns = runtime.hydraUnmergedTurns
        let startedAt = turns.first?.startedAt
        var reported: [String] = turns.flatMap { $0.touchedPaths ?? [] }
        for head in hydraTeam(of: leadID) {
            guard let info = head.hydra else { continue }
            // A head that had already finished before this job began went out with the
            // merge before it; with nothing merged yet, every head still counts.
            if let startedAt, let finished = info.finishedAt, finished < startedAt { continue }
            reported += (info.landing?.files ?? []).map(\.path)
            for entry in self.runtime(for: head.id).entries {
                guard case .tool(let call) = entry.item.content else { continue }
                reported += call.edits.map(\.path)
            }
        }

        var paths = Set<String>()
        var outside = Set<String>()
        for path in reported where !path.isEmpty {
            if let relative = TouchedPaths.relative(path, root: checkout) {
                paths.insert(relative)
            } else {
                outside.insert(path)
            }
        }

        if let base = turns.first?.baseCheckpoint,
           let alreadyDirty = try? await git.changedPaths(from: "HEAD", to: base),
           let now = try? await git.captureTree(),
           let changedSince = try? await git.changedPaths(from: base, to: now) {
            let theirs = Set(alreadyDirty)
            paths.formUnion(changedSince.filter { !theirs.contains($0) })
        }
        return (paths.sorted(), turns.map(\.id), outside.count)
    }

    /// Brings the checkout's default branch up to the merge without touching the working
    /// tree: the branch moves to what origin has, the index takes the merged version of the
    /// team's files (the working tree already holds it), and any other file the remote
    /// changed meanwhile is checked out only where it is clean locally. Returns false, and
    /// changes nothing, where that cannot be done safely.
    private func syncDefaultBranch(_ git: Git, from head: String, target: String, ownPaths: [String]) async -> Bool {
        let remote = "origin/\(target)"
        guard (try? await git.fetch()) != nil, await git.isAncestor(head, of: remote) else { return false }
        guard let changed = try? await git.changedPaths(from: head, to: remote) else { return false }
        let own = Set(ownPaths)
        let others = changed.filter { !own.contains($0) }
        let dirty = Set(await git.dirtyPaths())
        guard others.allSatisfy({ !dirty.contains($0) }) else { return false }
        var kept: [String] = []
        var gone: [String] = []
        for path in others {
            if await git.pathExists(path, in: remote) { kept.append(path) } else { gone.append(path) }
        }
        // `reset --soft` moves the branch with no expected old value, so a commit made in
        // a terminal while the merge ran would be left with nothing pointing at it. The
        // checkout is left alone instead, and `git pull` is the user's to run.
        guard (try? await git.commitHash()) == head else { return false }
        do {
            try await git.resetSoft(to: remote)
            try await git.resetIndex(paths: ownPaths)
            try await git.checkoutPaths(from: remote, kept)
            try await git.removePaths(gone)
            return true
        } catch {
            return false
        }
    }

    /// The commit message: written by the text engine from the patch, like the commit
    /// sheet's, else the chat's title over the heads' tasks.
    private func commitMessage(for lead: ChatThread, files: [DiffFile], patch: String, directory: String) async -> String {
        if let engine = textEngine(preferring: lead.provider) {
            let summary = files.map { "\($0.change == .added ? "A" : ($0.change == .deleted ? "D" : "M")) \($0.path)" }.joined(separator: "\n")
            if let text = await TextGeneration.commitMessage(
                summary: summary,
                patch: patch,
                instructions: settings.commitInstructions,
                engine: engine,
                directory: URL(fileURLWithPath: directory)
            ), !text.isEmpty {
                return text
            }
        }
        var lines = [lead.title == ChatThread.untitled ? "Hydra: the team's work" : lead.title, ""]
        for head in hydraTeam(of: lead.id) {
            guard let info = head.hydra, !info.task.isEmpty else { continue }
            lines.append("- \(info.persona.name): \(TextCleanup.singleLine(info.task, limit: 100))")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The request's description: what the team did and how the lead summed it up.
    private func mergeRequestBody(for lead: ChatThread, files: [DiffFile], runtime: ThreadRuntime) -> String {
        var lines = ["Opened by Droppy Code once its Hydra team finished.", ""]
        let heads = hydraTeam(of: lead.id).compactMap(\.hydra).filter { !$0.task.isEmpty }
        if !heads.isEmpty {
            lines.append("## Heads")
            for info in heads {
                var line = "- **\(info.persona.name)**: \(TextCleanup.singleLine(info.task, limit: 120))"
                if let landing = info.landing, !landing.files.isEmpty {
                    line += " (\(landing.files.count == 1 ? "1 file" : "\(landing.files.count) files"))"
                }
                lines.append(line)
            }
            lines.append("")
        }
        if let reply = runtime.entries.last(where: { $0.kind == .assistant }).flatMap({ entry -> String? in
            guard case .assistant(let message) = entry.item.content else { return nil }
            return message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }), !reply.isEmpty {
            lines.append("## The lead's summary")
            lines.append(reply.count > 2_000 ? String(reply.prefix(2_000)) + "…" : reply)
            lines.append("")
        }
        lines.append("## Files")
        lines += files.map { "- `\($0.path)` (+\($0.additions) −\($0.deletions))" }
        return lines.joined(separator: "\n")
    }

    private static func hydraBranchName(for lead: ChatThread) -> String {
        let title = lead.title == ChatThread.untitled ? "team" : lead.title
        var slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.count > 40 { slug = String(slug.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        let suffix = String(UUID().uuidString.lowercased().prefix(6))
        return "hydra/\(slug.isEmpty ? "team" : slug)-\(suffix)"
    }

    /// The files among `paths` that hold a three-way merge's conflict markers: a line that
    /// opens with `<<<<<<< ` and one that opens with `>>>>>>> `. Read off the main actor;
    /// a file that is gone (a deletion the team made) or too large to be source is skipped.
    private nonisolated static func pathsWithConflictMarkers(_ paths: [String], in checkout: String) async -> [String] {
        await Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: checkout)
            let opening = Data("\n<<<<<<< ".utf8)
            let closing = Data("\n>>>>>>> ".utf8)
            return paths.filter { path in
                let url = root.appendingPathComponent(path)
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 4_000_000,
                      let data = try? Data(contentsOf: url) else { return false }
                let body = Data([0x0A]) + data
                return body.range(of: opening) != nil && body.range(of: closing) != nil
            }
        }.value
    }

    private static func filesLine(_ files: [DiffFile]) -> String {
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        return "\(files.count == 1 ? "1 file" : "\(files.count) files") (+\(additions) −\(deletions))"
    }

    /// A note from Hydra in the lead's timeline, and word of it when the chat is out of view.
    private func note(_ leadID: UUID, _ title: String, _ body: String) {
        existingRuntime(for: leadID)?.appendHydraNote(title + "\n" + body)
        let onScreen = selectedThreadID == leadID
        guard !(NSApp.isActive && onScreen) else { return }
        updateThread(leadID) { $0.hasUnread = true }
        updateDockBadge()
        if settings.notifyWhenFinished, let lead = thread(leadID) {
            notify(threadID: leadID, title: lead.title, body: title)
        }
    }
}
