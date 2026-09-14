import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var runtime: ThreadRuntime

    @State private var git = GitStatusModel()
    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollState = TimelineScrollState()
    /// Full column height. The timeline rail centres in this, so composer and
    /// queue growth never shifts it.
    @State private var columnHeight: CGFloat = 0
    /// The conversation pane (the timeline with the chat box, above any terminal), which
    /// the helper panel floats in.
    @State private var paneSize: CGSize = .zero
    /// The chat box with its tabs and cards, so a helper panel above it clears them.
    @State private var composerAreaHeight: CGFloat = 0
    /// The helper panel's corner while its handle is held: where it was grabbed, and where
    /// it is now, moved without animation. Nil at rest.
    @State private var panelGrab: CGPoint?
    @State private var panelDrag: CGPoint?
    /// The same for the Hydra panel.
    @State private var hydraGrab: CGPoint?
    @State private var hydraDrag: CGPoint?

    var body: some View {
        let thread = model.thread(runtime.threadID)
        let project = thread.flatMap { model.project($0.projectID) }
        // The thread and project are read here, once, and passed down as values: the timeline
        // rows and the composer never observe them, so a change to either re-renders this
        // body alone and the children only where what they were handed changed.
        let workingDirectory = thread.flatMap { $0.worktreePath ?? project?.path }
        let directory = workingDirectory ?? LoginEnvironment.homeDirectory
        let title = thread?.title ?? ""
        // The helper this thread spawned, if it still has its panel open. Docked, it takes
        // room from the chat box's row so the two sit centred together; dragged away, the
        // box has the row to itself again.
        let subagent = model.subagent(of: runtime.threadID)
        let layout = SubagentPanelLayout(pane: paneSize, composerAreaHeight: composerAreaHeight)
        let isDocked = subagent != nil && runtime.subagentPanelOrigin == nil
        // The team, in its own panel: docked in the same corner, above the helper panel
        // when both are there.
        let heads = runtime.isHydraPanelHidden ? [] : model.hydraHeads(of: runtime.threadID)
        let showsHydra = !heads.isEmpty && paneSize != .zero
        let isHydraDocked = showsHydra && runtime.hydraPanelOrigin == nil
        let composerReserve = isDocked || isHydraDocked ? layout.composerReserve : 0
        VStack(spacing: 0) {
            ThreadTimeline(
                runtime: runtime,
                scrollChrome: scrollChrome,
                scrollState: scrollState,
                projectName: project?.name,
                workingDirectory: workingDirectory,
                supportsRewind: thread?.provider.supportsRewind ?? false,
                columnHeight: columnHeight
            )
            .equatable()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerArea(runtime: runtime, workingDirectory: workingDirectory)
                    .overlay(alignment: .top) {
                        JumpToLatestButton(scrollState: scrollState)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerAreaHeight = $0 }
                    .padding(.trailing, composerReserve)
                    .animation(Chrome.panelSlide, value: composerReserve)
            }
            .overlay(alignment: .top) {
                PaneTopVeil(model: scrollChrome)
            }
            .overlay(alignment: .top) {
                ChatChromeRow(
                    runtime: runtime,
                    scrollChrome: scrollChrome,
                    title: title,
                    project: project,
                    directory: directory,
                    git: git
                )
            }
            .overlay(alignment: .topLeading) {
                // Not before the pane has a size: the panel's spot comes from it.
                if let subagent, paneSize != .zero {
                    let origin = panelDrag ?? runtime.subagentPanelOrigin.map(layout.clamped) ?? layout.dockedOrigin
                    SubagentPanel(
                        thread: subagent,
                        size: layout.panelSize,
                        // The helper works in the project folder, whatever this thread's worktree.
                        workingDirectory: subagent.worktreePath ?? project?.path,
                        projectName: project?.name,
                        onDrag: { translation in
                            let grab = panelGrab ?? origin
                            if panelGrab == nil { panelGrab = grab }
                            panelDrag = layout.clamped(CGPoint(x: grab.x + translation.width, y: grab.y + translation.height))
                        },
                        onDragEnd: {
                            // Dropped near its corner, the panel snaps back into it; anywhere
                            // else it stays put.
                            let dropped = panelDrag ?? origin
                            runtime.subagentPanelOrigin = layout.snapsToDock(dropped) ? nil : dropped
                            panelGrab = nil
                            panelDrag = nil
                        },
                        close: {
                            // The helper moves to the sidebar under this thread; its row
                            // opens with the same slide as the panel leaving.
                            withAnimation(Chrome.panelSlide) {
                                model.closeSubagent(subagent.id)
                                runtime.subagentPanelOrigin = nil
                            }
                        }
                    )
                    // Inside the offset, so the panel grows in and fades out in place.
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .offset(x: origin.x, y: origin.y)
                    // The handle moves it live; only a drop and a resize settle it with a slide.
                    .animation(panelDrag == nil ? Chrome.panelSlide : nil, value: origin)
                }
            }
            .animation(Chrome.panelSlide, value: subagent?.id)
            .overlay(alignment: .topLeading) {
                if showsHydra {
                    // Docked above the helper panel when that one is docked too.
                    let dock = isDocked
                        ? CGPoint(x: layout.dockedOrigin.x, y: max(8, layout.dockedOrigin.y - layout.panelHeight - SubagentPanelLayout.gap))
                        : layout.dockedOrigin
                    let origin = hydraDrag ?? runtime.hydraPanelOrigin.map(layout.clamped) ?? dock
                    HydraPanel(
                        runtime: runtime,
                        heads: heads,
                        size: layout.panelSize,
                        workingDirectory: workingDirectory,
                        projectName: project?.name,
                        onDrag: { translation in
                            let grab = hydraGrab ?? origin
                            if hydraGrab == nil { hydraGrab = grab }
                            hydraDrag = layout.clamped(CGPoint(x: grab.x + translation.width, y: grab.y + translation.height))
                        },
                        onDragEnd: {
                            let dropped = hydraDrag ?? origin
                            let snaps = abs(dropped.x - dock.x) < SubagentPanelLayout.snapDistance && abs(dropped.y - dock.y) < SubagentPanelLayout.snapDistance
                            runtime.hydraPanelOrigin = snaps ? nil : dropped
                            hydraGrab = nil
                            hydraDrag = nil
                        },
                        dismiss: {
                            withAnimation(Chrome.panelSlide) {
                                model.dismissHydraHeads(of: runtime.threadID)
                                runtime.hydraPanelOrigin = nil
                            }
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
                    .offset(x: origin.x, y: origin.y)
                    .animation(hydraDrag == nil ? Chrome.panelSlide : nil, value: origin)
                }
            }
            .animation(Chrome.panelSlide, value: showsHydra)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { paneSize = $0 }

            if runtime.isTerminalVisible {
                TerminalPanel(runtime: runtime, directory: directory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .detailSheet()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { columnHeight = $0 }
        .animation(Chrome.panelSlide, value: runtime.isTerminalVisible)
        // A merge or pull request link in this chat can hand its request to a helper, which
        // opens in the panel and lands it on the same provider and model as this thread.
        .environment(\.mergeRequestTarget, MergeRequestTarget(chatID: runtime.threadID) { link in
            model.spawnSubagent(from: runtime.threadID, title: link.title, prompt: link.prompt)
        })
        .task(id: directory) {
            await git.refresh(directory, force: false)
        }
        .onChange(of: runtime.diffRevision) {
            Task { await git.refresh(directory) }
        }
    }
}

/// The "jump to latest" button floating above the chat box while the reader is scrolled up.
struct JumpToLatestButton: View {
    let scrollState: TimelineScrollState

    var body: some View {
        if scrollState.showsJumpButton {
            ChromeCircleButton(symbol: "arrow.down", help: "Jump to latest") {
                scrollState.jumpToLatest()
            }
            .padding(.bottom, 10)
            .frame(height: 0, alignment: .bottom)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(y: 10)),
                    removal: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: 6))
                )
            )
        }
    }
}

/// The sticky glass controls across the top of the conversation.
private struct ChatChromeRow: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let title: String
    let project: Project?
    let directory: String
    let git: GitStatusModel

    var body: some View {
        // Follows the buttons, not the sidebar's state: they leave for the sidebar only once it
        // is wide enough to hold them, and the row closes up as they go.
        let sidebarVisible = model.sidebar.holdsTrafficLights
        // One glass pass for the whole row. The row floats over the conversation, so its
        // capsules sample fresh content on every scrolled frame; drawn separately, each was
        // a pass of its own. The spacing is well under the gaps, so nothing morphs together.
        GlassEffectContainer(spacing: 2) {
            HStack(alignment: .center, spacing: 10) {
                // With the sidebar away, its list is one press away: the button arrives with the
                // window buttons and leaves with them.
                if !sidebarVisible {
                    ThreadsButton()
                        .transition(.softAppear)
                }
                ChromeCircleButton(symbol: "square.and.pencil", help: "New thread (⌘N)") {
                    model.newThread(in: project)
                }
                if let thread = model.thread(runtime.threadID) {
                    // The team switch, once Hydra is on in Settings. A head leads no team of its own.
                    if model.settings.hydraEnabled, !thread.isHelper {
                        HydraButton(thread: thread)
                            .transition(.softAppear)
                    }
                    PermissionMenu(thread: thread)
                }
                if git.isRepository {
                    BranchMenu(runtime: runtime, directory: directory, git: git)
                }
                ChromeCompactTitle(title: title, model: scrollChrome)
                HStack(spacing: 8) {
                    ChromeCapsule {
                        OpenInMenu(directory: directory)
                        if let project {
                            ChromeDivider()
                            ScriptsMenu(project: project, runtime: runtime, directory: directory)
                        }
                        if git.isRepository {
                            ChromeDivider()
                            GitActionsMenu(runtime: runtime, directory: directory, git: git)
                        }
                    }
                    ChromeCapsule {
                        ChromeIconButton(symbol: "terminal", isActive: runtime.isTerminalVisible, help: "Terminal (⌘J)") {
                            runtime.isTerminalVisible.toggle()
                        }
                        ChromeDivider()
                        ChromeIconButton(symbol: "plusminus", isActive: runtime.isDiffVisible, help: "Changes (⌘D)") {
                            runtime.toggleDiff()
                        }
                    }
                }
            }
        }
        // With the sidebar hidden the native window buttons sit over this row, so it steps clear of them.
        .padding(.leading, sidebarVisible ? 0 : Chrome.trafficLightsWidth + Chrome.trafficLightClearance)
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.top, Chrome.chromeTopPadding)
        .animation(Chrome.panelSlide, value: sidebarVisible)
    }
}

/// The sidebar's list in a popover, for a hidden sidebar: the same search, the same rows,
/// the same footer, at the sidebar's own width. Picking a thread closes it.
private struct ThreadsButton: View {
    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    var body: some View {
        ChromeCircleButton(symbol: "list.bullet", help: "Threads") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SidebarView(inPopover: true, dismiss: { isPresented = false })
                .frame(width: model.sidebar.width, height: 560)
        }
    }
}

@MainActor
@Observable
final class GitStatusModel {
    private(set) var isRepository = false
    private(set) var status: GitStatus?
    private(set) var branches: [GitBranch] = []
    private(set) var remoteURL: URL?
    private(set) var activity: String?

    private struct Snapshot {
        var isRepository = false
        var status: GitStatus?
        var branches: [GitBranch] = []
        var remoteURL: URL?
        var fetchedAt = Date.now
    }

    /// The last read per directory, shared by every chat. Switching threads shows the branch at
    /// once and only runs git again when the read is stale, a turn changed files, or forced.
    private static var snapshots: [String: Snapshot] = [:]
    private static let freshness: TimeInterval = 30

    func refresh(_ directory: String, force: Bool = true) async {
        if let cached = Self.snapshots[directory] {
            apply(cached)
            if !force, Date.now.timeIntervalSince(cached.fetchedAt) < Self.freshness { return }
        }
        let git = Git(directory)
        var snapshot = Snapshot(isRepository: await git.isRepository())
        if snapshot.isRepository {
            async let status = git.status()
            async let branches = git.branches()
            async let remoteURL = git.remoteWebURL()
            snapshot.status = await status
            snapshot.branches = await branches
            snapshot.remoteURL = await remoteURL
        }
        snapshot.fetchedAt = .now
        Self.snapshots[directory] = snapshot
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        isRepository = snapshot.isRepository
        status = snapshot.status
        branches = snapshot.branches
        remoteURL = snapshot.remoteURL
    }

    func perform(_ activity: String, _ work: () async throws -> Void) async -> Error? {
        self.activity = activity
        defer { self.activity = nil }
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }
}

/// The thread's permission level: how much the agent may do without asking.
private struct PermissionMenu: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        ChromeCircleMenu(symbol: thread.runtimeMode.symbol, help: "\(thread.runtimeMode.title) · \(thread.runtimeMode.summary)") {
            PopoverSectionHeader("Permissions")
            ForEach(RuntimeMode.allCases) { mode in
                PopoverItem(mode.title, symbol: mode.symbol, isChecked: thread.runtimeMode == mode) {
                    model.updateThread(thread.id) { $0.runtimeMode = mode }
                }
            }
        }
    }
}

private struct BranchMenu: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var isNamingBranch = false
    @State private var branchName = ""

    var body: some View {
        ChromeTextMenu(
            symbol: "arrow.triangle.branch",
            title: git.activity ?? git.status?.branch ?? "Detached",
            help: "Branch"
        ) {
            PopoverSectionHeader("Switch branch")
            ForEach(git.branches.prefix(25)) { branch in
                PopoverItem(
                    branch.name,
                    isChecked: branch.isCurrent,
                    isEnabled: !branch.isCurrent && !runtime.isRunning
                ) {
                    switchBranch(branch.name)
                }
            }
            PopoverDivider()
            PopoverItem("New branch…", symbol: "plus") {
                branchName = ""
                isNamingBranch = true
            }
            if runtime.thread?.worktreePath == nil, runtime.turns.isEmpty {
                PopoverItem("Use a new worktree for this thread", symbol: "square.stack.3d.up") {
                    Task { await model.createWorktree(for: runtime.threadID) }
                }
            }
        }
        .alert("New branch", isPresented: $isNamingBranch) {
            TextField("Branch name", text: $branchName)
            Button("Create") { createBranch() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func switchBranch(_ name: String) {
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Switching", { try await repository.switchBranch(name) }) {
                model.alert = AppAlert(title: "Could not switch branch", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }

    private func createBranch() {
        let name = branchName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty else { return }
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Creating", { try await repository.createBranch(name) }) {
                model.alert = AppAlert(title: "Could not create branch", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }
}

private struct OpenInMenu: View {
    let directory: String

    var body: some View {
        ChromeMenuButton(symbol: "arrow.up.forward.app", help: "Open in another app") {
            PopoverSectionHeader("Open in")
            PopoverItem("Finder", image: Workspace.finderIcon) {
                NSWorkspace.shared.open(URL(fileURLWithPath: directory))
            }
            ForEach(Workspace.installedEditors) { editor in
                PopoverItem(editor.name, symbol: "chevron.left.forwardslash.chevron.right", image: Workspace.icon(for: editor)) {
                    Workspace.open(directory, with: editor)
                }
            }
            PopoverDivider()
            PopoverItem("Copy path", symbol: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(directory, forType: .string)
            }
        }
    }
}

private struct ScriptsMenu: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let runtime: ThreadRuntime
    let directory: String

    @State private var isEditing = false

    var body: some View {
        ChromeMenuButton(symbol: "play", help: "Run a project script") {
            if !project.scripts.isEmpty {
                PopoverSectionHeader("Scripts")
                ForEach(project.scripts) { script in
                    PopoverItem(script.name, symbol: script.symbol) {
                        model.terminals.run(script, threadID: runtime.threadID, directory: directory)
                        runtime.isTerminalVisible = true
                    }
                }
                PopoverDivider()
            }
            PopoverItem(project.scripts.isEmpty ? "Add a script…" : "Edit scripts…", symbol: project.scripts.isEmpty ? "plus" : "pencil") {
                isEditing = true
            }
        }
        .sheet(isPresented: $isEditing) {
            ScriptsEditor(projectID: project.id)
        }
    }
}

private struct GitActionsMenu: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var isCommitting = false

    var body: some View {
        let changed = git.status?.changedFiles ?? 0
        ChromeMenuButton(symbol: "arrow.triangle.pull", help: changed == 0 ? "Commit, push and open pull requests" : "\(changed) changed files") {
            PopoverNote(changed == 1 ? "1 changed file" : "\(changed) changed files")
            PopoverDivider()
            PopoverItem("Commit…", symbol: "checkmark.circle", isEnabled: changed > 0) { isCommitting = true }
            PopoverItem("Push", symbol: "arrow.up.circle") { push() }
            PopoverItem("Create pull request", symbol: "arrow.triangle.pull") { openPullRequest() }
            if let url = git.remoteURL {
                PopoverDivider()
                PopoverItem("Open repository", symbol: "safari") { NSWorkspace.shared.open(url) }
            }
        }
        .sheet(isPresented: $isCommitting) {
            CommitSheet(runtime: runtime, directory: directory, git: git)
        }
    }

    private func push() {
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Pushing", { try await repository.push() }) {
                model.alert = AppAlert(title: "Push failed", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }

    private func openPullRequest() {
        Task {
            let repository = Git(directory)
            var url: URL?
            let error = await git.perform("Opening pull request") {
                try await repository.push()
                let subject = (try? await repository.output(["log", "-1", "--pretty=%s"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let body = (try? await repository.output(["log", "-1", "--pretty=%b"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                url = try await repository.createPullRequest(
                    title: subject.isEmpty ? "Update" : subject,
                    body: body.isEmpty ? "Opened from Droppy Code." : body
                )
            }
            if let error {
                model.alert = AppAlert(title: "Could not open a pull request", message: error.localizedDescription)
            } else if let url {
                NSWorkspace.shared.open(url)
            }
            await git.refresh(directory)
        }
    }
}

private struct CommitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var message = ""
    @State private var summary = ""
    @State private var isGenerating = false
    @State private var isCommitting = false
    @State private var pushesAfterCommit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Commit changes")
                .font(.system(size: 17, weight: .semibold))
            if !summary.isEmpty {
                ScrollView {
                    Text(summary)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(10)
                .background(Chrome.overlay(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if message.isEmpty {
                    Text(isGenerating ? "Writing a message…" : "Commit message")
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 130)
            .background(Chrome.overlay(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            HStack(spacing: 12) {
                Button {
                    Task { await generate() }
                } label: {
                    Label("Write for me", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .disabled(isGenerating)
                Toggle("Push after committing", isOn: $pushesAfterCommit)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button("Commit") { Task { await commit() } }
                    .buttonStyle(.glassProminent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            let changes = await Git(directory).workingChanges()
            summary = changes.summary
            if message.isEmpty { await generate(changes: changes) }
        }
    }

    private func generate(changes: (summary: String, patch: String)? = nil) async {
        guard let engine = model.textEngine(preferring: runtime.thread?.provider) else { return }
        isGenerating = true
        defer { isGenerating = false }
        let resolved: (summary: String, patch: String)
        if let changes {
            resolved = changes
        } else {
            resolved = await Git(directory).workingChanges()
        }
        if let text = await TextGeneration.commitMessage(
            summary: resolved.summary,
            patch: resolved.patch,
            instructions: model.settings.commitInstructions,
            engine: engine,
            directory: URL(fileURLWithPath: directory)
        ) {
            message = text
        }
    }

    private func commit() async {
        isCommitting = true
        defer { isCommitting = false }
        let repository = Git(directory)
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let pushes = pushesAfterCommit
        let error = await git.perform("Committing") {
            try await repository.commitAll(message: text)
            if pushes { try await repository.push() }
        }
        await git.refresh(directory)
        if let error {
            model.alert = AppAlert(title: "Commit failed", message: error.localizedDescription)
        } else {
            dismiss()
        }
    }
}

private struct ScriptsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var scripts: [ProjectScript] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project scripts")
                .font(.system(size: 17, weight: .semibold))
            Text("Scripts run in a terminal at the project root. Droppy Code also picks up scripts from droppy-code.json.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($scripts) { $script in
                        ChromeCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Name", text: $script.name)
                                        .textFieldStyle(.roundedBorder)
                                    Button(role: .destructive) {
                                        scripts.removeAll { $0.id == script.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                TextField("Command", text: $script.command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Toggle("Run when a worktree is created", isOn: $script.runOnWorktreeCreate)
                                    .toggleStyle(.checkbox)
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button {
                    scripts.append(ProjectScript(name: "New script", command: ""))
                } label: {
                    Label("Add script", systemImage: "plus")
                }
                .buttonStyle(.glass)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button("Save") {
                    let cleaned = scripts.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
                    model.updateProject(projectID) { $0.scripts = cleaned }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 580, height: 460)
        .onAppear { scripts = model.project(projectID)?.scripts ?? [] }
    }
}
