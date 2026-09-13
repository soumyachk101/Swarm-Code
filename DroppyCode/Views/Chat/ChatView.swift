import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var runtime: ThreadRuntime

    @State private var git = GitStatusModel()
    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollState = TimelineScrollState()
    @State private var paneWidth: CGFloat = 1_000

    var body: some View {
        let thread = model.thread(runtime.threadID)
        let project = thread.flatMap { model.project($0.projectID) }
        let directory = thread?.worktreePath ?? project?.path ?? LoginEnvironment.homeDirectory
        let title = thread?.title ?? ""
        HStack(spacing: Chrome.sheetInset) {
            VStack(spacing: 0) {
                ThreadTimeline(
                    runtime: runtime,
                    scrollChrome: scrollChrome,
                    scrollState: scrollState,
                    projectName: project?.name
                )
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerArea(runtime: runtime)
                        .overlay(alignment: .top) {
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

                if runtime.isTerminalVisible {
                    TerminalPanel(runtime: runtime, directory: directory)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .detailSheet()

            if runtime.isDiffVisible, !diffFloats {
                DiffInspector(runtime: runtime)
                    .frame(width: diffWidth)
                    .frame(maxHeight: .infinity)
                    .detailSheet()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            if runtime.isDiffVisible, diffFloats {
                DiffInspector(runtime: runtime)
                    .frame(width: floatingDiffWidth)
                    .frame(maxHeight: .infinity)
                    .detailSheet()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Chrome.sheetCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 4)
                    // Below the chat's controls, so the changes button that closes it stays reachable.
                    .padding(.top, Chrome.chromeTopPadding + Chrome.capsuleHeight + 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self, of: Self.measureWidth) { paneWidth = $0 }
        .animation(Chrome.panelSlide, value: runtime.isTerminalVisible)
        .animation(Chrome.panelSlide, value: runtime.isDiffVisible)
        .task(id: directory) {
            await git.refresh(directory, force: false)
        }
        .onChange(of: runtime.diffRevision) {
            Task { await git.refresh(directory) }
        }
    }

    private static let chatMinimumWidth: CGFloat = 440
    private static let diffMinimumWidth: CGFloat = 320

    /// Whether the diff panel floats over the chat, because both no longer fit side by side.
    private var diffFloats: Bool {
        paneWidth - Chrome.sheetInset - Self.diffMinimumWidth < Self.chatMinimumWidth
    }

    private var diffWidth: CGFloat {
        let available = paneWidth - Chrome.sheetInset
        return max(Self.diffMinimumWidth, min(560, available * 0.42, available - Self.chatMinimumWidth))
    }

    private var floatingDiffWidth: CGFloat {
        min(paneWidth, max(Self.diffMinimumWidth, paneWidth * 0.62))
    }

    private nonisolated static func measureWidth(_ proxy: GeometryProxy) -> CGFloat {
        proxy.size.width
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
        let sidebarVisible = model.sidebar.isVisible
        HStack(alignment: .center, spacing: 10) {
            ChromeCircleButton(symbol: "square.and.pencil", help: "New thread (⌘N)") {
                model.newThread(in: project)
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
                        runtime.isDiffVisible.toggle()
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
            PopoverItem("Finder", image: NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")) {
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
