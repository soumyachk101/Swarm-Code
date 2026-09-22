import AppKit
import Foundation

// With "Merge when the team is done" on, a Hydra lead's finished job lands by itself: the
// files the lead and its heads changed go out as a commit on a branch of their own, the
// branch is pushed, a merge request is opened and merged with the forge's CLI, and the
// checkout is brought up to date. The checkout never changes branch for any of it: the
// commit is built from a snapshot of the working tree, so nothing running in the checkout
// meanwhile is disturbed, and nothing uncommitted that is not the team's goes along.

/// A head whose work a merge takes, for the note the merge popover reads.
struct HydraMergeHead {
    var name: String
    var index: Int
    var task: String
    /// The head's files among the merge's, relative to the checkout.
    var files: [String]
}

/// What merging one project's share of a Hydra job came to.
private enum HydraProjectMerge {
    case merged
    case alreadyOnMain
    case failed
}

extension AppModel {
    /// One project's share of a job: the paths this merge may take, the turns and heads
    /// they settle, the paths that lie under no checkout, the heads' files, and - of the
    /// paths the job's own records hold - the ones another chat's unfinished work holds
    /// instead, each under the name of the chat that holds it.
    typealias HydraWork = (paths: [String], turnIDs: [UUID], headIDs: [UUID], outside: [String], heads: [HydraMergeHead], held: [String: String])

    /// Whether any chat's team work is on its way to the remote right now.
    var isAnyHydraMergeRunning: Bool { liveRuntimes.contains { $0.isHydraMerging } }

    /// How long after its last message a lead is still one the auto-merge visits. It is
    /// the window `resumeHydraMerges` sweeps, and so also how long a head's claim on its
    /// files lives once the lead has gone quiet: a lead outside it never merges again,
    /// and a claim of its heads could only hold those files from every later merge.
    private static var hydraMergeWindow: TimeInterval { 3 * 24 * 3600 }

    /// Merges the last run left unfinished: a lead chat with the auto-merge on, no turn
    /// running, no head still out, and work of its own that never went out - a finished
    /// turn's files, or a head whose landing no merge has taken, which stands even when
    /// every turn reads as spent. The merge itself finds the files and lets a job that
    /// changed nothing be.
    func resumeHydraMerges() async {
        guard settings.hydraAutoMerge else { return }
        let cutoff = Date.now.addingTimeInterval(-Self.hydraMergeWindow)
        let leads = threads.filter { !$0.isArchived && hydraIsOn($0) && $0.updatedAt > cutoff }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        // Load every competitor before choosing the first winner. A cold runtime
        // must not keep a completed job looking unfinished until the next sweep.
        for lead in leads {
            await runtime(for: lead.id).ensureLoaded()
        }
        for lead in leads {
            guard let runtime = existingRuntime(for: lead.id),
                  runtime.isReadyForHydraMerge, !runtime.isHydraMerging else { continue }
            // The job is finished, whatever its turns read: a lead whose report-review turn
            // was booked spent while its head's work never went out has no unmerged turn
            // left, and requiring one here stranded exactly that head. A head whose landing
            // no merge has taken yet is work of its own, and the test below counts it.
            let finished = runtime.hydraUnmergedTurns.filter { $0.status == .completed }
            // A chat with nothing of its own to show never merges: Hydra merely being
            // switched on is not work, and the checkout sweep would otherwise take whatever
            // else in that checkout had changed, another chat's files or the user's own.
            let hasOwnWork = finished.contains { !($0.touchedPaths ?? []).isEmpty }
                || hydraTeam(of: lead.id).contains { $0.hydra.map { $0.mergedAt == nil && ($0.landing?.landed ?? false) } ?? false }
            guard hasOwnWork else { continue }
            await autoMergeHydraWork(of: lead.id)
        }
    }

    /// Lands a lead's finished work, when the setting says so. Runs once per finished job;
    /// what happened lands in the lead's timeline as a note from Hydra.
    func autoMergeHydraWork(of leadID: UUID) async {
        // `isAnyHydraMergeRunning` holds the one merge flag: several jobs finishing in the
        // same moment would otherwise each pass their own `isHydraMerging` check, take a
        // flag of their own and snapshot shared files side by side. The guard and the flag
        // are set with no suspension between them, so whoever gets here first goes and the
        // rest are picked up by the resume sweep. A job skipped this way is not forgotten:
        // `resumeHydraMerges` finds it while it stays eligible.
        guard settings.hydraAutoMerge, let lead = thread(leadID), hydraIsOn(lead), let project = project(lead.projectID),
              let runtime = existingRuntime(for: leadID), !runtime.isHydraMerging, !isAnyHydraMergeRunning,
              runtime.isReadyForHydraMerge else { return }
        runtime.isHydraMerging = true
        runtime.hydraMergeStartedAt = .now
        runtime.hydraMergeNoteID = UUID().uuidString
        runtime.hydraMergeStage = HydraMergeStage.gathering.words
        runtime.hydraMergeStep = .gathering
        defer {
            runtime.isHydraMerging = false
            runtime.hydraMergeStage = nil
            runtime.hydraMergeStep = nil
            runtime.hydraMergeStartedAt = nil
            runtime.hydraMergeNoteID = nil
        }
        // A head's work still going into the checkout finishes first: the snapshot the
        // commit is built from must hold the patch whole or not at all. Landings that have
        // not started yet wait for the merge instead (see `waitForSettledCheckout`).
        await runtime.hydraLanding?.value
        guard runtime.isReadyForHydraMerge else { return }

        // What the team touched, and only that, so a sibling's uncommitted work in the
        // same checkout stays behind. The chat's own checkout goes first, then every
        // other sidebar project that holds touched files, one merge each; only paths
        // under no sidebar project at all stay out. What the records do not hold in one
        // of those other checkouts cannot be told apart from a sibling's work there and
        // stays behind without a word: none of it was this merge's to take.
        let ownCheckout = lead.worktreePath ?? project.path
        let own = await hydraWork(of: leadID, runtime: runtime, checkout: ownCheckout, git: Git(ownCheckout), projectID: project.id, leadCheckout: ownCheckout, leadProjectID: project.id, sweepsCheckout: true)
        var groups: [(project: Project, checkout: String, work: HydraWork)] = [(project, ownCheckout, own)]
        // An outside path belongs to the sidebar project with the longest path that
        // holds it, so nested checkouts resolve to the inner one.
        var owners: [String: Project] = [:]
        for path in own.outside {
            if let holder = projects.filter({ $0.id != project.id && TouchedPaths.relative(path, root: $0.path) != nil }).max(by: { $0.path.count < $1.path.count }) {
                owners[path] = holder
            }
        }
        for other in projects where other.id != project.id && owners.values.contains(where: { $0.id == other.id }) {
            let work = await hydraWork(of: leadID, runtime: runtime, checkout: other.path, git: Git(other.path), projectID: other.id, leadCheckout: ownCheckout, leadProjectID: project.id, sweepsCheckout: false)
            groups.append((other, other.path, work))
        }
        // A head's scratch (a throwaway script in /tmp, a stray write into its own copy)
        // is nobody's project and not worth a word; only a real folder outside the
        // sidebar is something the user can act on.
        let stray = own.outside.filter { path in !Self.isScratchPath(path) && !projects.contains { TouchedPaths.relative(path, root: $0.path) != nil } }
        func strayBody(_ paths: [String]) -> String {
            let shown = paths.prefix(6).map { "`\($0)`" }.joined(separator: ", ") + (paths.count > 6 ? " and \(paths.count - 6) more" : "")
            return "\(paths.count == 1 ? "1 file was" : "\(paths.count) files were") changed outside every project: \(shown). Add the folder that holds them to the sidebar and ask for the merge again."
        }
        // A hold in any project keeps the whole job pending; otherwise a shared turn
        // could be marked merged by its unblocked project's share.
        var held: [String: String] = [:]
        for group in groups {
            for (path, owner) in group.work.held {
                held[(group.checkout as NSString).appendingPathComponent(path)] = owner
            }
        }
        if !held.isEmpty {
            recordHydraHold(held, leadID: leadID, runtime: runtime)
            return
        }
        groups.removeAll { $0.work.paths.isEmpty }
        guard !groups.isEmpty else {
            guard !stray.isEmpty else {
                // Nothing to send and nothing outside a project: whatever the turns
                // recorded is already on the branch, ignored, build output, or gone. Mark
                // it spent, or the merge note counts those files forever.
                runtime.markHydraMerged(own.turnIDs)
                let spentAt = Date.now
                for headID in own.headIDs { updateHydraHead(headID) { $0.mergedAt = spentAt } }
                if runtime.hydraMerges.last?.outcome == .held {
                    recordHydraSettlement(leadID: leadID, runtime: runtime)
                }
                return
            }
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .stray, project: nil, label: nil, url: nil, files: stray.count, detail: strayBody(stray)))
            note(leadID, "Hydra did not merge: the team's files are outside every project.", strayBody(stray))
            return
        }
        let several = groups.count > 1
        var outcomes: [HydraProjectMerge] = []
        for group in groups {
            outcomes.append(await mergeHydraProject(of: leadID, lead: lead, project: group.project, checkout: group.checkout, work: group.work, runtime: runtime, several: several))
        }
        guard !outcomes.contains(.failed) else { return }
        // The work is on the default branch now, so these turns are spent: the next
        // job merges what comes after them and never this again.
        runtime.markHydraMerged(groups.flatMap { $0.work.turnIDs })
        let mergedAt = Date.now
        for headID in groups.flatMap({ $0.work.headIDs }) { updateHydraHead(headID) { $0.mergedAt = mergedAt } }
        // The projects' shares went out; only what no project holds stayed behind.
        if !stray.isEmpty {
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .stray, project: nil, label: nil, url: nil, files: stray.count, detail: strayBody(stray)))
            note(leadID, "Hydra left \(stray.count == 1 ? "a file" : "\(stray.count) files") outside every project.", strayBody(stray))
        } else if outcomes.allSatisfy({ $0 == .alreadyOnMain }) {
            recordHydraSettlement(leadID: leadID, runtime: runtime)
        }
    }

    /// A path no sidebar project could ever hold: a head's copy of a checkout under the
    /// worktrees folder, the temporary folders a head drops a throwaway script into,
    /// `~/Library`, and the dot-folders under home where agents keep their own state
    /// (`~/.claude`, `~/.codex`, `~/.droppy-code-dev`): a lead writing its memory files
    /// is not leaving work behind.
    private static func isScratchPath(_ path: String) -> Bool {
        let full = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        let home = (LoginEnvironment.homeDirectory as NSString).standardizingPath
        var roots = [Storage.worktreesDirectory.path, NSTemporaryDirectory(), "/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]
        roots.append((home as NSString).appendingPathComponent("Library"))
        let underHome = home.hasSuffix("/") ? home : home + "/"
        if full.hasPrefix(underHome), full.dropFirst(underHome.count).first == "." { return true }
        // `standardizingPath` drops a leading `/private` only while the file still exists,
        // so a head's temp file deleted since it was written keeps its `/private/tmp`
        // form while the roots lose theirs: both spellings are tried.
        let spellings = full.hasPrefix("/private/") ? [full, String(full.dropFirst("/private".count))] : [full]
        return roots.contains { root in
            let root = (root as NSString).standardizingPath
            let prefix = root.hasSuffix("/") ? root : root + "/"
            return spellings.contains { $0.hasPrefix(prefix) }
        }
    }

    /// Merges one project's share of a lead's finished work from its checkout: the guards
    /// for repository, remote and operation in progress; the conflict-marker check; the
    /// commit, branch, push, merge request and notes. The caller groups the projects and
    /// marks the turns and heads merged once every project went through.
    private func mergeHydraProject(of leadID: UUID, lead: ChatThread, project: Project, checkout: String, work: HydraWork, runtime: ThreadRuntime, several: Bool) async -> HydraProjectMerge {
        func stage(_ name: String) -> String { several ? "\(project.name): \(name)" : name }
        func title(_ name: String) -> String { several ? "\(project.name): \(name)" : name }
        // The words carry the project's name with several projects, the step is the dot on the pill's track.
        func advance(_ step: HydraMergeStage) { runtime.hydraMergeStage = stage(step.words); runtime.hydraMergeStep = step }

        let git = Git(checkout)
        guard await git.isRepository(), await git.hasCommits() else { return .failed }
        guard await git.remoteURL() != nil else {
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra did not merge: no remote.") + ": The team's work is in the checkout; there is no origin to push it to."))
            note(leadID, title("Hydra did not merge: no remote."), "The team's work is in the checkout; there is no origin to push it to.")
            return .failed
        }
        guard !(await git.hasOperationInProgress()) else {
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra did not merge: a rebase or merge is underway.") + ": The team's work is in the checkout; finish that first and merge by hand."))
            note(leadID, title("Hydra did not merge: a rebase or merge is underway."), "The team's work is in the checkout; finish that first and merge by hand.")
            return .failed
        }

        let sorted = work.paths
        // A head's landing can leave conflict markers behind (see `Git.apply`), and a lead
        // told not to look at git status may answer without settling them. Those markers
        // must never reach the remote: the job stays in the checkout until they are gone.
        let conflicted = await Self.pathsWithConflictMarkers(sorted, in: checkout)
        guard conflicted.isEmpty else {
            let files = conflicted.map { "`\($0)`" }.joined(separator: ", ")
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra did not merge: conflict markers in \(conflicted.count == 1 ? "a file" : "\(conflicted.count) files").") + ": \(files) still \(conflicted.count == 1 ? "holds" : "hold") conflict markers from a head's landing."))
            note(leadID, title("Hydra did not merge: conflict markers in \(conflicted.count == 1 ? "a file" : "\(conflicted.count) files")."), "\(files) still \(conflicted.count == 1 ? "holds" : "hold") conflict markers from a head's landing. Resolve them, then ask for the merge again.")
            return .failed
        }

        do {
            let head = try await git.commitHash()
            advance(.committing)
            let tree = try await git.captureTree(paths: sorted)
            // A lead can resume while gathering or capturing files. Check after
            // the snapshot so no newly active shared work is sent to the remote.
            guard runtime.isReadyForHydraMerge else { return .failed }
            let currentClaims = siblingOwnedPaths(in: checkout, projectID: project.id, excluding: leadID).blocking
            let held = sorted.reduce(into: [String: String]()) { result, path in
                if let owner = currentClaims[path] {
                    result[(checkout as NSString).appendingPathComponent(path)] = owner
                }
            }
            guard held.isEmpty else {
                recordHydraHold(held, leadID: leadID, runtime: runtime)
                return .failed
            }
            // Everything the team did is committed already: taken along by another chat's
            // merge from the same checkout, or committed by hand. The job is spent either
            // way, and there is nothing to tell: the work is where it was meant to go.
            guard try await tree != git.treeHash(of: "HEAD") else { return .alreadyOnMain }

            let patch = (try? await git.diff(from: head, to: tree)) ?? ""
            // A whole job's patch is big and parsing it counts every line: off the main
            // actor, so the chat stays live while the work goes out.
            let files = await Task.detached(priority: .utility) { DiffParser.parse(patch) }.value
            advance(.describing)
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
                runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra did not merge: the checkout moved while it worked.") + ": A commit landed on `\(current ?? target)` while the team's work was being prepared."))
                note(leadID, title("Hydra did not merge: the checkout moved while it worked."), "A commit landed on `\(current ?? target)` while the team's work was being prepared, and moving the branch now would orphan it. The work is still in the checkout; ask for the merge again.")
                return .failed
            }
            // A branch of its own must not exist yet; the checkout's own branch must still
            // be where it was read.
            try await git.updateRef("refs/heads/\(branch)", to: commit, expecting: ownBranch ? nil : head)
            if !ownBranch {
                // The branch moved under the checkout: the index catches up, the working
                // tree already has the content.
                try await git.resetIndex(paths: sorted)
            }
            advance(.pushing)
            try await git.pushBranch(branch)

            let body = mergeRequestBody(for: lead, files: files, through: Set(work.turnIDs), runtime: runtime)
            advance(.opening)
            let requestURL: URL?
            do {
                requestURL = try await hydraCreateMergeRequest(git: git, title: subject, body: body, source: branch, target: target)
            } catch {
                runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra pushed \(branch) but could not open a merge request.") + ": \(error.localizedDescription)"))
                note(leadID, title("Hydra pushed \(branch) but could not open a merge request."), "\(error.localizedDescription)\n\nOpen one for `\(branch)` into `\(target)` and merge it from there. The work is still in the checkout.")
                return .failed
            }
            guard let url = requestURL,
                  let link = MergeRequestLink(url: url) else {
                runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: title("Hydra pushed \(branch) but could not open a merge request.")))
                note(leadID, title("Hydra pushed \(branch) but could not open a merge request."), "Open one for `\(branch)` into `\(target)` and merge it from there.")
                return .failed
            }
            advance(.merging)
            do {
                try await git.mergePullRequest(link)
            } catch {
                runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: link.label, url: url, files: 0, detail: title("Hydra opened \(link.label) but could not merge it.") + ": \(error.localizedDescription)"))
                note(leadID, title("Hydra opened \(link.label) but could not merge it."), "\(url.absoluteString)\n\n\(error.localizedDescription)\n\nMerge it from the link once it is ready; the branch `\(branch)` has the team's work.")
                return .failed
            }

            var lines = ["\(url.absoluteString)", "", Self.filesLine(files) + " landed on `\(target)` from `\(branch)`."]
            if !work.heads.isEmpty {
                lines.append("")
                lines.append("Heads")
                for head in work.heads {
                    if head.files.isEmpty {
                        lines.append("- \(head.name) (\(head.index)): \(head.task) — no files")
                    } else {
                        lines.append("- \(head.name) (\(head.index)): \(head.task) — \(head.files.count == 1 ? "1 file" : "\(head.files.count) files"): \(head.files.joined(separator: ", "))")
                    }
                }
            }
            // What the merge left out (files written outside the checkout, build output,
            // ignored or missing paths, a sibling chat's files) is not said: none of it
            // was this merge's to take, and every line about it read as if something
            // had gone wrong.
            if ownBranch {
                advance(.syncing)
                let synced = await syncDefaultBranch(git, from: head, target: target, ownPaths: sorted)
                lines.append(synced ? "The checkout is up to date." : "The checkout was left as it was: `\(target)` moved on in other ways meanwhile, or the team's files changed again; `git pull` when it suits you.")
            } else if lead.worktreePath != nil {
                // The lead worked in a worktree: the project's own checkout follows when it can.
                advance(.syncing)
                let main = Git(project.path)
                if await main.status()?.branch == target, await main.dirtyPaths().isEmpty, !(await main.hasOperationInProgress()) {
                    if (try? await main.pullFastForward()) != nil { lines.append("The project checkout is up to date.") }
                }
            }
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .merged, project: project.name, label: link.label, url: url, files: files.count, detail: nil))
            note(leadID, title("Hydra merged \(link.label)"), lines.joined(separator: "\n"))
            existingRuntime(for: leadID)?.noteDiffChanged()
            return .merged
        } catch {
            runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .failed, project: project.name, label: nil, url: nil, files: 0, detail: "Hydra could not merge the team's work: \(error.localizedDescription)"))
            note(leadID, title("Hydra could not merge the team's work."), "\(error.localizedDescription)\n\nThe work is still in the checkout.")
            return .failed
        }
    }

    /// Opens the merge request for a Hydra branch. On GitLab this wraps `glab mr create`
    /// rather than calling `Git.createPullRequest` straight: glab answers a missing or
    /// expired token with `401 Unauthorized` next to a recovery file, which used to land in
    /// the timeline as-is. The token is checked with `glab auth status` first, a 401
    /// re-checks it (it may have been refreshed while the push ran) and otherwise tells
    /// the user how to sign in again, and any other failure that left a recovery file is
    /// retried once with `--recover` so its saved options are picked up. Squash and
    /// source-branch removal are explicit for GitLab team merges.
    private func hydraCreateMergeRequest(git: Git, title: String, body: String, source: String, target: String) async throws -> URL? {
        guard await git.forge() == .gitlab, LoginEnvironment.which("glab") != nil else {
            return try await git.createPullRequest(title: title, body: body, source: source, target: target)
        }
        let host = await git.remoteWebURL()?.host ?? "your GitLab host"
        // An explicit project keeps glab from resolving the wrong one; it names the same
        // origin remote glab would use on its own. Any credentials embedded in the remote
        // stay out of the arguments.
        var arguments = ["mr", "create", "--title", title, "--description", body, "--yes", "--squash-before-merge"]
        if var web = await git.remoteWebURL(), web.host != nil {
            if web.user != nil, var components = URLComponents(url: web, resolvingAgainstBaseURL: false) {
                components.user = nil
                components.password = nil
                if let stripped = components.url { web = stripped }
            }
            arguments += ["--repo", web.absoluteString]
        }
        arguments += ["--source-branch", source, "--target-branch", target]

        // No token on file means `mr create` can only fail with a 401: say how to sign in
        // instead of running into it.
        if let detail = await hydraGitLabAuthFailure(in: git.directory) {
            throw HydraMergeRequestError.gitLabAuth(host: host, branch: source, detail: detail)
        }

        var failure = try await Shell.run(tool: "glab", arguments, in: git.directory, timeout: 300)
        if failure.succeeded { return Self.hydraMergeRequestURL(from: failure) }
        if Self.isGitLabAuthFailure(failure) {
            // The token may have been refreshed while the push ran: check again before
            // giving up, and retry with the explicit options when it is good now.
            if await hydraGitLabAuthFailure(in: git.directory) == nil {
                let retry = try await Shell.run(tool: "glab", arguments, in: git.directory, timeout: 300)
                if retry.succeeded { return Self.hydraMergeRequestURL(from: retry) }
                failure = retry
            }
            if Self.isGitLabAuthFailure(failure) {
                throw HydraMergeRequestError.gitLabAuth(host: host, branch: source, detail: failure.failureMessage)
            }
        }
        // A failure that saved its options is retried once with `--recover`, which loads
        // them back from the recovery file.
        if Self.mentionsRecoverFile(failure) {
            let retry = try await Shell.run(tool: "glab", arguments + ["--recover"], in: git.directory, timeout: 300)
            if retry.succeeded { return Self.hydraMergeRequestURL(from: retry) }
            failure = retry
        }
        throw HydraMergeRequestError.creationFailed(failure.failureMessage)
    }

    /// The reason `glab auth status` gives for not being signed in, or nil when the token
    /// is good. Runs in the checkout so glab checks the host the merge goes to.
    private func hydraGitLabAuthFailure(in directory: URL) async -> String? {
        // A throw means glab itself could not run here; let the creation attempt surface
        // that. A non-zero exit is glab reporting it is not signed in.
        guard let status = try? await Shell.run(tool: "glab", ["auth", "status"], in: directory, timeout: 30) else { return nil }
        if status.succeeded { return nil }
        let message = status.failureMessage
        return message.isEmpty ? "glab is not signed in to this GitLab host." : message
    }

    /// Whether glab's output is an authentication refusal: the 401 the merge used to fail with.
    private static func isGitLabAuthFailure(_ result: ShellResult) -> Bool {
        let text = (result.output + "\n" + result.errorOutput).lowercased()
        return text.contains("401") || text.contains("unauthorized")
            || (text.contains("authentication") && (text.contains("failed") || text.contains("expired") || text.contains("invalid") || text.contains("required")))
    }

    /// Whether glab's output points at a recovery file its failed creation left behind.
    private static func mentionsRecoverFile(_ result: ShellResult) -> Bool {
        (result.output + "\n" + result.errorOutput).lowercased().contains("recover")
    }

    /// The merge request's page in glab's output, parsed the same way `Git` does.
    private static func hydraMergeRequestURL(from result: ShellResult) -> URL? {
        let text = result.output + "\n" + result.errorOutput
        let match = text.firstMatch(of: #/https://\S+/#)
        return match.flatMap { URL(string: String($0.output)) }
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
    private func hydraWork(of leadID: UUID, runtime: ThreadRuntime, checkout: String, git: Git, projectID: UUID, leadCheckout: String, leadProjectID: UUID, sweepsCheckout: Bool) async -> HydraWork {
        let turns = runtime.hydraUnmergedTurns
        var reported: [String] = turns.flatMap { $0.touchedPaths ?? [] }
        // A head counts until a merge has taken its work (see `HydraHeadInfo.mergedAt`),
        // and only that explicit mark proves a merge took it: a lead turn's `hydraMerged`
        // flag is bookkeeping, and a turn falsely booked spent would let a timestamp
        // shortcut discard a head whose files were still in the checkout. A head from
        // before the mark existed that already went out settles below instead, where the
        // gathering finds its paths unchanged from HEAD.
        var headPaths: [(id: UUID, name: String, index: Int, task: String, paths: [String])] = []
        for head in hydraTeam(of: leadID) {
            guard let info = head.hydra, info.mergedAt == nil,
                  info.landing?.patchPath == nil, info.landing?.error == nil else { continue }
            // The checkout the head's work landed in: the chat's own for a head in its
            // project, that project's for a head sent elsewhere. A path the head's tools
            // reported lies in its own copy of that checkout and stands for the same path
            // there; a landing path is relative to it already. Anchored at that checkout,
            // a path resolves against this pass's checkout or counts as outside it, so a
            // head's work in another project reaches that project's merge instead of
            // reading as this project's, and its copy never shows up as a stray folder.
            let headRoot = head.projectID == leadProjectID ? leadCheckout : (project(head.projectID)?.path ?? leadCheckout)
            func anchored(_ path: String) -> String {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                if let copy = head.worktreePath, let inCopy = TouchedPaths.relative(trimmed, root: copy) {
                    return (headRoot as NSString).appendingPathComponent(inCopy)
                }
                if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.contains("://") { return trimmed }
                return (headRoot as NSString).appendingPathComponent(trimmed)
            }
            var own: [String] = []
            var seen = Set<String>()
            func collect(_ path: String) {
                guard !path.isEmpty, let relative = TouchedPaths.relative(anchored(path), root: checkout), seen.insert(relative).inserted else { return }
                own.append(relative)
            }
            for file in info.landing?.files ?? [] { collect(file.path) }
            reported += (info.landing?.files ?? []).map { anchored($0.path) }
            // A head's timeline runs to megabytes. One still open is read as it is; one
            // that has gone cold is decoded off the main actor rather than brought back
            // as a runtime, which would parse the whole history on the main thread for
            // every head of the team, one after another, while the chat sits frozen.
            let items: [TimelineItem]
            if let live = existingRuntime(for: head.id) {
                items = live.entries.map(\.item)
            } else {
                let headID = head.id
                items = await Task.detached(priority: .utility) { Storage.decodeDocument(headID)?.items ?? [] }.value
            }
            for item in items {
                guard case .tool(let call) = item.content else { continue }
                reported += call.edits.map { anchored($0.path) }
                for edit in call.edits { collect(edit.path) }
            }
            headPaths.append((head.id, HydraRoster.persona(at: info.index).name, info.index, TextCleanup.singleLine(info.task, limit: 120), own))
        }

        // The lead's own tool edits, from its timeline: a lead works in any sidebar project
        // too, and a path it wrote outside its checkout is that project's share of the merge.
        // Its turns' `touchedPaths` hold only what lies inside the checkout.
        let unmerged = Set(turns.map(\.id))
        for entry in runtime.entries where entry.item.turnID.map(unmerged.contains) == true {
            guard case .tool(let call) = entry.item.content else { continue }
            for edit in call.edits {
                let trimmed = edit.path.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || trimmed.contains("://") {
                    reported.append(trimmed)
                } else {
                    reported.append((leadCheckout as NSString).appendingPathComponent(trimmed))
                }
            }
        }

        var paths = Set<String>()
        var outside = Set<String>()
        for path in reported where !path.isEmpty && !TouchedPaths.isBuildOutput(path) {
            if let relative = TouchedPaths.relative(path, root: checkout) {
                paths.insert(relative)
            } else {
                outside.insert(path)
            }
        }

        // Files another chat's team put in this same checkout that no merge has taken
        // yet: that chat's merge carries them, never this one's. Without this, the
        // sweep below took a sibling's landed files along, and the sibling's own merge
        // then found nothing left and said nothing.
        //
        // Two sets come back. Every reservation keeps the sweep off a sibling's file this
        // merge has no record of. The blocking claims are the reservations that also hold
        // this job: a file only a finished, idle sibling job ranks behind this one owns is
        // settled by the ordering instead, and this job's own record of it may go out (see
        // `siblingOwnedPaths`).
        let siblingFiles = siblingOwnedPaths(in: checkout, projectID: projectID, excluding: leadID)
        let siblingClaims = Set(siblingFiles.reserved.keys)
        let blockingClaims = siblingFiles.blocking
        if sweepsCheckout,
           let base = turns.first?.baseCheckpoint,
           let alreadyDirty = try? await git.changedPaths(from: "HEAD", to: base),
           let now = try? await git.captureTree(),
           let changedSince = try? await git.changedPaths(from: base, to: now) {
            let theirs = Set(alreadyDirty)
            let fresh = changedSince.filter { !theirs.contains($0) }
            paths.formUnion(fresh.filter { !siblingClaims.contains($0) })
        }

        // A file a live sibling head or chat holds never goes out under this chat, even
        // when this chat's own records list it: a turn's touched paths are read off the
        // checkout's diff, and so can hold a file another chat made while the turn ran.
        // The turns and heads that put those files there are not booked as done here
        // either: a turn kept open keeps its files pending, so they go out with a later
        // merge that can take them, instead of reading as merged while lying uncommitted.
        // A claim the ordering lets this job take is left in `paths`: the file goes out
        // here, and the sibling's own merge finds it already on the branch.
        let claimed = paths.intersection(blockingClaims.keys)
        paths.subtract(blockingClaims.keys)
        paths = paths.filter { !TouchedPaths.isBuildOutput($0) }
        paths.subtract(await git.ignoredPaths(among: paths.sorted()))
        let tracked = await git.trackedPaths(among: paths.sorted())
        let fileManager = FileManager.default
        let checkoutURL = URL(fileURLWithPath: checkout)
        let missing = Set(paths.filter { path in
            !fileManager.fileExists(atPath: checkoutURL.appendingPathComponent(path).path) && !tracked.contains(path)
        })
        paths.subtract(missing)
        let heads = headPaths.map { entry in
            HydraMergeHead(name: entry.name, index: entry.index, task: entry.task, files: entry.paths.filter { paths.contains($0) })
        }
        // What this merge took: every turn and head whose files were all sendable here.
        // One that still has a file another chat holds stays open, so its files are not
        // booked as merged before a commit carries them.
        let turnIDs = turns.filter { turn in
            (turn.touchedPaths ?? []).allSatisfy { path in
                guard let relative = TouchedPaths.relative(path, root: checkout) else { return true }
                return !claimed.contains(relative)
            }
        }.map(\.id)
        let headIDs = headPaths.filter { Set($0.paths).isDisjoint(with: claimed) }.map(\.id)
        // The held files with the chat holding each, so a job that can send nothing at
        // all can say who has it rather than being written off in silence.
        let held = claimed.reduce(into: [String: String]()) { result, path in result[path] = blockingClaims[path] }
        return (paths.sorted(), turnIDs, headIDs, outside.sorted(), heads, held)
    }

    /// Files another chat's team put or is still putting in this same checkout that no
    /// merge has taken yet, each mapped to the chat that holds it, split in two: every
    /// reservation, and the claims that hold this job outright. That chat's own merge
    /// carries them, never this one's, so the checkout sweep in `hydraWork` keeps every
    /// reservation out of a merge the same way.
    ///
    /// A claim holds - `blocking` - unless it is a file only a finished, idle, eligible
    /// competing job ranks behind this one owns (`hydraIsFinishedIdleEligible`,
    /// `hydraRanksAfter`): two finished jobs that recorded the same files used to hold
    /// each other for good, and nothing said so. One ordering by lead UUID settles which
    /// of them takes a contested file, so the earliest job keeps priority and every job
    /// reads the same order. Active work, a job that has not completed after an
    /// interruption, a failed head's partial work, and a pending landing keep their hold.
    ///
    /// A claim stands only while the chat that made it can still land its work
    /// (`canStillMerge`). A head left unmarked by an older merge - its lead merged again
    /// since, or the job is long over - used to go on claiming its files forever, and
    /// every chat that later touched one of them went out empty, without a word.
    private func siblingOwnedPaths(in checkout: String, projectID: UUID, excluding leadID: UUID) -> (reserved: [String: String], blocking: [String: String]) {
        let team = Set(hydraTeam(of: leadID).map(\.id))
        var reserved: [String: String] = [:]
        var blocking: [String: String] = [:]
        func reserve(_ path: String, owner: String, blocks: Bool) {
            guard let relative = TouchedPaths.relative(path, root: checkout) else { return }
            reserved[relative] = owner
            if blocks { blocking[relative] = owner }
        }
        for other in threads where other.id != leadID && other.projectID == projectID && !team.contains(other.id) {
            if other.isHydraHead {
                guard let info = other.hydra, info.mergedAt == nil else { continue }
                // A head still out has files coming whatever its lead is doing; a head
                // that has finished holds them only for a lead that can still land them.
                let parent = other.parentThreadID.flatMap { thread($0) }
                guard info.status == .running || parent.map(canStillMerge) == true else { continue }
                // A running head is active work and a stopped or failed one left partial
                // work behind: both hold whatever their lead is doing. Only a completed
                // head whose lead is a finished, idle, eligible competitor ranking behind
                // this job loses its hold to the ordering.
                let rankedOut = info.status == .completed
                    && parent.map { hydraRanksAfter($0, leadID) && hydraIsFinishedIdleEligible($0) } == true
                for file in info.landing?.files ?? [] {
                    reserve(file.path, owner: parent?.title ?? other.title, blocks: !rankedOut)
                }
            } else if let live = existingRuntime(for: other.id) {
                // A later completed turn finishes the resumed job, including its
                // earlier interrupted edits. Without one, readiness remains false
                // and those partial edits keep their hold.
                let rankedOut = hydraRanksAfter(other, leadID) && hydraIsFinishedIdleEligible(other)
                for turn in live.hydraUnmergedTurns where canStillMerge(other) || turn.status != .completed {
                    for path in turn.touchedPaths ?? [] {
                        reserve(path, owner: other.title, blocks: !rankedOut)
                    }
                }
            }
        }
        return (reserved, blocking)
    }

    /// Whether a lead is a finished job that can still land its own work and so takes part
    /// in the ordering between competing jobs: idle and not merging, every head in, no
    /// landing still being written, its last turn completed, and unmerged work that the
    /// resume sweep can still pick up. A stopped or failed head whose work was kept as a
    /// patch keeps the whole job out, so its partial files stay protected.
    private func hydraIsFinishedIdleEligible(_ lead: ChatThread) -> Bool {
        guard hydraIsOn(lead), let live = existingRuntime(for: lead.id) else { return false }
        guard live.isReadyForHydraMerge, !live.isHydraMerging,
              !hydraHasPendingLanding(lead.id) else { return false }
        return canStillMerge(lead)
    }

    /// Whether a head's work is still on its way into the checkout: files that have not
    /// gone in cleanly, which is how a stopped or failed head keeps its partial work as a
    /// patch. A head that changed nothing carries no files and no work to wait for.
    private func hydraHasPendingLanding(_ leadID: UUID) -> Bool {
        hydraTeam(of: leadID).contains { head in
            guard let info = head.hydra, info.mergedAt == nil, let landing = info.landing else { return false }
            return !landing.files.isEmpty && !landing.landed
        }
    }

    /// One stable total ordering across every project, by lead UUID: the earliest job
    /// keeps priority and every job reads the same order, so a contested file is never
    /// settled by a different winner than its neighbours.
    private func hydraRanksAfter(_ lead: ChatThread, _ other: UUID) -> Bool {
        lead.id.uuidString > other.uuidString
    }

    /// Active work keeps its claims regardless of age. Completed head landings stop
    /// reserving files when their idle lead is no longer eligible for recovery.
    private func canStillMerge(_ lead: ChatThread) -> Bool {
        let live = existingRuntime(for: lead.id)
        if let live, live.phase != .idle || live.isHydraMerging { return true }
        guard !lead.isArchived, hydraIsOn(lead),
              lead.updatedAt > Date.now.addingTimeInterval(-Self.hydraMergeWindow) else { return false }
        // Landed head work no merge has taken keeps the claim alive the same way an
        // unmerged turn does: this is the eligibility `resumeHydraMerges` uses.
        let landedHeadWork = hydraTeam(of: lead.id).contains { $0.hydra.map { $0.mergedAt == nil && ($0.landing?.landed ?? false) } ?? false }
        guard let live else { return lead.lastStatus == .completed }
        return live.turns.last?.status == .completed && (!live.hydraUnmergedTurns.isEmpty || landedHeadWork)
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
        // One git process answers for every path at once; a process per path took a
        // remote that had moved on by thousands of files minutes to sort.
        let present = await git.presentPaths(among: others, in: remote)
        let kept = others.filter { present.contains($0) }
        let gone = others.filter { !present.contains($0) }
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
    private func mergeRequestBody(for lead: ChatThread, files: [DiffFile], through: Set<UUID>, runtime: ThreadRuntime) -> String {
        var lines = ["Opened by Swarm Code once its Hydra team finished.", ""]
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
        if let reply = runtime.entries.last(where: { $0.kind == .assistant && $0.item.turnID.map(through.contains) == true }).flatMap({ entry -> String? in
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

    private func recordHydraSettlement(leadID: UUID, runtime: ThreadRuntime) {
        guard hydraUnmergedFileCount(of: leadID) == 0 else { return }
        runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .settled, project: nil, label: nil, url: nil, files: 0, detail: nil))
        note(leadID, "Hydra has no files left to merge.", "The checkout has no remaining changes from this job to send. No new merge request was needed.")
    }

    private func recordHydraHold(_ held: [String: String], leadID: UUID, runtime: ThreadRuntime) {
        let detail = Self.heldDetail(held)
        let last = runtime.hydraMerges.last
        guard last?.outcome != .held || last?.detail != detail else { return }
        runtime.recordHydraMerge(HydraMergeRecord(at: .now, outcome: .held, project: nil, label: nil, url: nil, files: held.count, detail: detail))
        note(leadID, "Hydra is waiting for another chat's files.", detail + " The work stays in the checkout. Hydra retries after the other chat finishes or its queued merge completes.")
    }

    /// What to say about files a merge had to leave with another chat's work:
    /// the files, and the chats holding them. Used for both the note the user reads and
    /// the record the lead's next message is briefed from, so the two never disagree.
    private static func heldDetail(_ held: [String: String]) -> String {
        let files = held.keys.sorted()
        let shown = files.prefix(6).map { "`\($0)`" }.joined(separator: ", ") + (files.count > 6 ? " and \(files.count - 6) more" : "")
        let names = Set(held.values).sorted().joined(separator: ", ")
        return "\(files.count == 1 ? "1 file the team changed is" : "\(files.count) files the team changed are") also claimed by \(names): \(shown)."
    }

    private static func filesLine(_ files: [DiffFile]) -> String {
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        return "\(files.count == 1 ? "1 file" : "\(files.count) files") (+\(additions) −\(deletions))"
    }

    /// A note from Hydra in the lead's timeline, and word of it when the chat is out of view.
    private func note(_ leadID: UUID, _ title: String, _ body: String) {
        // The note lands under the id the merging pill has been drawn with, so the timeline
        // keeps one row from the first stage to the outcome; the id is spent here, so a
        // second note in the same run would get one of its own.
        let runtime = existingRuntime(for: leadID)
        let id = runtime?.hydraMergeNoteID
        runtime?.hydraMergeNoteID = nil
        runtime?.appendHydraNote(title + "\n" + body, id: id)
        let onScreen = selectedThreadID == leadID
        guard !(NSApp.isActive && onScreen) else { return }
        updateThread(leadID) { $0.hasUnread = true }
        updateDockBadge()
        if settings.notifyWhenFinished, let lead = thread(leadID) {
            notify(threadID: leadID, title: lead.title, body: title)
        }
    }
}

/// Why a Hydra merge request could not be opened on GitLab.
private enum HydraMergeRequestError: LocalizedError {
    /// glab is not signed in, or GitLab answered 401: the token is missing or expired.
    case gitLabAuth(host: String, branch: String, detail: String)
    /// glab failed for any other reason, recovery retry included.
    case creationFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitLabAuth(let host, let branch, let detail):
            return "GitLab refused the login (401 Unauthorized) for \(host): the token glab signs in with is missing or expired.\n\n\(detail)\n\nSign back in with `glab auth login --hostname \(host)` (or export a valid GITLAB_TOKEN), then ask for the merge again. The branch `\(branch)` is already pushed, so the team's work is safe."
        case .creationFailed(let message):
            return message
        }
    }
}
