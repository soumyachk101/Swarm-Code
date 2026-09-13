import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var renamingThreadID: UUID?
    @State private var threadPendingDeletion: ChatThread?

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedThreadID) {
            ForEach(model.projects) { project in
                ProjectSection(
                    project: project,
                    search: search,
                    renamingThreadID: $renamingThreadID,
                    threadPendingDeletion: $threadPendingDeletion
                )
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search threads")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    model.newThread()
                } label: {
                    Label("New thread", systemImage: "square.and.pencil")
                }
                .help("New thread (⌘N)")
            }
        }
        .confirmationDialog(
            "Delete this thread?",
            isPresented: Binding(
                get: { threadPendingDeletion != nil },
                set: { if !$0 { threadPendingDeletion = nil } }
            ),
            presenting: threadPendingDeletion
        ) { thread in
            Button("Delete thread", role: .destructive) { model.delete(thread.id) }
            if thread.worktreePath != nil {
                Button("Delete thread and worktree", role: .destructive) { model.delete(thread.id, removeWorktree: true) }
            }
        } message: { thread in
            Text("“\(thread.title)” and its history will be removed. Files in your project stay as they are.")
        }
    }
}

private struct ProjectSection: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let search: String
    @Binding var renamingThreadID: UUID?
    @Binding var threadPendingDeletion: ChatThread?

    private var threads: [ChatThread] {
        let all = model.threads(in: project)
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let isExpanded = Binding(
            get: { project.isExpanded || !search.isEmpty },
            set: { value in model.updateProject(project.id) { $0.isExpanded = value } }
        )
        Section(isExpanded: isExpanded) {
            ForEach(threads) { thread in
                ThreadRow(thread: thread, isRenaming: renamingThreadID == thread.id) { title in
                    if let title { model.rename(thread.id, to: title) }
                    renamingThreadID = nil
                }
                .tag(thread.id)
                .contextMenu {
                    Button("Rename") { renamingThreadID = thread.id }
                    Button(thread.isPinned ? "Unpin" : "Pin") {
                        model.updateThread(thread.id) { $0.isPinned.toggle() }
                    }
                    if let path = thread.worktreePath {
                        Button("Reveal worktree in Finder") { Workspace.revealInFinder(path) }
                    }
                    Divider()
                    Button("Archive") { model.archive(thread.id) }
                    Button("Delete…", role: .destructive) {
                        if model.settings.confirmBeforeDeleting {
                            threadPendingDeletion = thread
                        } else {
                            model.delete(thread.id)
                        }
                    }
                }
            }
            if threads.isEmpty && search.isEmpty {
                Button {
                    model.newThread(in: project)
                } label: {
                    Label("New thread", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } header: {
            ProjectHeader(project: project)
        }
    }
}

private struct ProjectHeader: View {
    @Environment(AppModel.self) private var model
    let project: Project
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(project.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                Menu {
                    Button("New thread") { model.newThread(in: project) }
                    Button("New thread in worktree") { model.newThread(in: project, workspace: .worktree) }
                    Divider()
                    Button("Reveal in Finder") { Workspace.revealInFinder(project.path) }
                    Divider()
                    Button("Remove project", role: .destructive) { model.removeProject(project) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 18, height: 18)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    model.newThread(in: project)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("New thread in \(project.name)")
            }
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let isRenaming: Bool
    let onRename: (String?) -> Void

    @State private var draftTitle = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ThreadStatusIndicator(thread: thread)
                .frame(width: 14)
            if isRenaming {
                TextField("Title", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit { onRename(draftTitle) }
                    .onExitCommand { onRename(nil) }
                    .onAppear {
                        draftTitle = thread.title
                        isFieldFocused = true
                    }
            } else {
                Text(thread.title)
                    .lineLimit(1)
                    .fontWeight(thread.hasUnread ? .semibold : .regular)
            }
            Spacer(minLength: 4)
            if thread.worktreePath != nil {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(RelativeTime.short(thread.updatedAt))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

private struct ThreadStatusIndicator: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        let runtime = model.existingRuntime(for: thread.id)
        let needsInput = !(runtime?.approvals.isEmpty ?? true) || !(runtime?.questions.isEmpty ?? true)
        Group {
            if needsInput {
                Image(systemName: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if runtime?.isRunning == true {
                ProgressView()
                    .controlSize(.mini)
            } else if thread.hasUnread {
                Circle()
                    .fill(thread.lastStatus == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                    .frame(width: 7, height: 7)
            } else if thread.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ProviderIcon(provider: thread.provider, size: 11)
                    .foregroundStyle(.tertiary)
                    .opacity(0.8)
            }
        }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.chooseProjectFolder()
            } label: {
                Label("Add project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.glass)
            .help("Add project (⌘O)")
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .help("Settings (⌘,)")
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
