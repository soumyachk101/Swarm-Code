import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Bindable var runtime: ThreadRuntime
    @State private var git = GitStatusModel()

    var body: some View {
        let thread = model.thread(runtime.threadID)
        let project = thread.flatMap { model.project($0.projectID) }
        let directory = thread?.worktreePath ?? project?.path ?? LoginEnvironment.homeDirectory
        VStack(spacing: 0) {
            ThreadTimeline(runtime: runtime)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerArea(runtime: runtime)
                }
            if runtime.isTerminalVisible {
                TerminalPanel(runtime: runtime, directory: directory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: runtime.isTerminalVisible)
        .navigationTitle(thread?.title ?? "")
        .navigationSubtitle(project?.name ?? "")
        .toolbar {
            if git.isRepository {
                ToolbarItem(placement: .navigation) {
                    BranchMenu(runtime: runtime, directory: directory, git: git)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                OpenInMenu(directory: directory)
                if let project {
                    ScriptsMenu(project: project, runtime: runtime, directory: directory)
                }
                if git.isRepository {
                    GitActionsMenu(runtime: runtime, directory: directory, git: git)
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $runtime.isTerminalVisible) {
                    Label("Terminal", systemImage: "terminal")
                }
                .help("Terminal (⌘J)")
                Toggle(isOn: $runtime.isDiffVisible) {
                    Label("Changes", systemImage: "plusminus")
                }
                .help("Changes (⌘D)")
            }
        }
        .inspector(isPresented: $runtime.isDiffVisible) {
            DiffInspector(runtime: runtime)
                .inspectorColumnWidth(min: 380, ideal: 540, max: 960)
        }
        .task(id: "\(directory)-\(runtime.diffRevision)") {
            await git.refresh(directory)
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

    func refresh(_ directory: String) async {
        let git = Git(directory)
        isRepository = await git.isRepository()
        guard isRepository else {
            status = nil
            branches = []
            remoteURL = nil
            return
        }
        status = await git.status()
        branches = await git.branches()
        remoteURL = await git.remoteWebURL()
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
        if git.isRepository {
            Menu {
                Section("Switch branch") {
                    ForEach(git.branches.prefix(25)) { branch in
                        Button {
                            switchBranch(branch.name)
                        } label: {
                            if branch.isCurrent {
                                Label(branch.name, systemImage: "checkmark")
                            } else {
                                Text(branch.name)
                            }
                        }
                        .disabled(branch.isCurrent || runtime.isRunning)
                    }
                }
                Button("New branch…") {
                    branchName = ""
                    isNamingBranch = true
                }
                if runtime.thread?.worktreePath == nil, runtime.turns.isEmpty {
                    Divider()
                    Button("Use a new worktree for this thread") {
                        Task { await model.createWorktree(for: runtime.threadID) }
                    }
                }
            } label: {
                Label(git.status?.branch ?? "Detached", systemImage: "arrow.triangle.branch")
                    .labelStyle(.titleAndIcon)
            }
            .help("Branch")
            .alert("New branch", isPresented: $isNamingBranch) {
                TextField("Branch name", text: $branchName)
                Button("Create") { createBranch() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func switchBranch(_ name: String) {
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Switching branch", { try await repository.switchBranch(name) }) {
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
            if let error = await git.perform("Creating branch", { try await repository.createBranch(name) }) {
                model.alert = AppAlert(title: "Could not create branch", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }
}

private struct OpenInMenu: View {
    let directory: String

    var body: some View {
        Menu {
            Button("Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: directory)) }
            ForEach(Workspace.installedEditors) { editor in
                Button {
                    Workspace.open(directory, with: editor)
                } label: {
                    if let icon = Workspace.icon(for: editor) {
                        Label { Text(editor.name) } icon: { Image(nsImage: icon) }
                    } else {
                        Text(editor.name)
                    }
                }
            }
            Divider()
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(directory, forType: .string)
            }
        } label: {
            Label("Open in", systemImage: "arrow.up.forward.app")
        }
        .help("Open in another app")
    }
}

private struct ScriptsMenu: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let runtime: ThreadRuntime
    let directory: String

    @State private var isEditing = false

    var body: some View {
        Menu {
            ForEach(project.scripts) { script in
                Button {
                    model.terminals.run(script, threadID: runtime.threadID, directory: directory)
                    runtime.isTerminalVisible = true
                } label: {
                    Label(script.name, systemImage: script.symbol)
                }
            }
            if !project.scripts.isEmpty { Divider() }
            Button(project.scripts.isEmpty ? "Add a script…" : "Edit scripts…") { isEditing = true }
        } label: {
            Label("Run", systemImage: "play")
        }
        .help("Project scripts")
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
        if git.isRepository {
            Menu {
                Button("Commit…") { isCommitting = true }
                    .disabled((git.status?.changedFiles ?? 0) == 0)
                Button("Push") { push() }
                Button("Create pull request") { openPullRequest() }
                if let url = git.remoteURL {
                    Divider()
                    Button("Open repository") { NSWorkspace.shared.open(url) }
                }
            } label: {
                if let activity = git.activity {
                    Label(activity, systemImage: "arrow.triangle.2.circlepath")
                } else {
                    let changed = git.status?.changedFiles ?? 0
                    Label(changed == 0 ? "Git" : "\(changed) changed", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .labelStyle(.titleAndIcon)
                }
            }
            .help("Commit, push and open pull requests")
            .sheet(isPresented: $isCommitting) {
                CommitSheet(runtime: runtime, directory: directory, git: git)
            }
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
                    body: body.isEmpty ? "Opened from T3 Code." : body
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
                .font(.title3.weight(.semibold))
            if !summary.isEmpty {
                ScrollView {
                    Text(summary)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10, style: .continuous))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if message.isEmpty {
                    Text(isGenerating ? "Writing a message…" : "Commit message")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 130)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10, style: .continuous))
            HStack(spacing: 12) {
                Button {
                    Task { await generate() }
                } label: {
                    Label("Write for me", systemImage: "sparkles")
                }
                .disabled(isGenerating)
                Toggle("Push after committing", isOn: $pushesAfterCommit)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
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
                .font(.title3.weight(.semibold))
            Text("Scripts run in a terminal at the project root. T3 Code also picks up scripts from t3.json.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach($scripts) { $script in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $script.name)
                            Button(role: .destructive) {
                                scripts.removeAll { $0.id == script.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        TextField("Command", text: $script.command)
                            .font(.system(.body, design: .monospaced))
                        Toggle("Run when a worktree is created", isOn: $script.runOnWorktreeCreate)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button {
                    scripts.append(ProjectScript(name: "New script", command: ""))
                } label: {
                    Label("Add script", systemImage: "plus")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    let cleaned = scripts.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
                    model.updateProject(projectID) { $0.scripts = cleaned }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 580, height: 440)
        .onAppear { scripts = model.project(projectID)?.scripts ?? [] }
    }
}
