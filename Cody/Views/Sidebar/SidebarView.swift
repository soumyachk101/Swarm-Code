import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    @State private var search = ""
    @State private var renaming: ChatThread?
    @State private var renameText = ""
    @State private var pendingDeletion: ChatThread?

    private var query: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the native window buttons that float over the sidebar's top corner.
            Color.clear
                .frame(height: Chrome.trafficLightDiameter)
                .padding(.top, Chrome.trafficLightTop)

            SidebarSearchField(text: $search, prompt: "Search threads") {
                if let first = searchResults.first?.threads.first {
                    model.selectedThreadID = first.id
                }
            }
            .padding(.horizontal, Chrome.listInset)
            .padding(.top, 14)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    if query.isEmpty {
                        projectList
                    } else {
                        searchList
                    }
                }
                .padding(.horizontal, Chrome.listInset)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: 1) {
                SidebarRow(title: "Add project", action: { model.chooseProjectFolder() }) {
                    SidebarIconBadge(tint: Chrome.blue) { SidebarSymbol("plus") }
                }
                SidebarRow(title: "Settings", action: { openSettings() }) {
                    SidebarIconBadge(tint: Chrome.gray) { SidebarSymbol("gear", scale: 1.15) }
                }
            }
            .padding(.horizontal, Chrome.listInset)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { WindowDragArea() }
        .alert("Rename thread", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let thread = renaming { model.rename(thread.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete this thread?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { thread in
            Button("Delete thread", role: .destructive) { model.delete(thread.id) }
            if thread.worktreePath != nil {
                Button("Delete thread and worktree", role: .destructive) { model.delete(thread.id, removeWorktree: true) }
            }
        } message: { thread in
            Text("“\(thread.title)” and its history will be removed. Files in your project stay as they are.")
        }
    }

    @ViewBuilder
    private var projectList: some View {
        ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
            if index > 0 {
                Color.clear.frame(height: Chrome.groupGap)
            }
            ProjectRow(project: project)
            if project.isExpanded {
                ForEach(model.threads(in: project)) { thread in
                    threadRow(thread)
                }
            }
        }
    }

    @ViewBuilder
    private var searchList: some View {
        let results = searchResults
        if results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No results")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText.opacity(0.92))
                Text("Try a thread title or a project name.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.top, 14)
        } else {
            ForEach(Array(results.enumerated()), id: \.element.project.id) { index, result in
                if index > 0 {
                    Color.clear.frame(height: Chrome.groupGap)
                }
                ProjectRow(project: result.project, togglesExpansion: false)
                ForEach(result.threads) { thread in
                    threadRow(thread)
                }
            }
        }
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        ThreadRow(
            thread: thread,
            onRename: {
                renameText = thread.title
                renaming = thread
            },
            onDelete: {
                if model.settings.confirmBeforeDeleting {
                    pendingDeletion = thread
                } else {
                    model.delete(thread.id)
                }
            }
        )
    }

    private var searchResults: [(project: Project, threads: [ChatThread])] {
        model.projects.compactMap { project in
            let all = model.threads(in: project)
            let threads = project.name.localizedCaseInsensitiveContains(query)
                ? all
                : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
            return threads.isEmpty ? nil : (project, threads)
        }
    }
}

private struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let project: Project
    var togglesExpansion = true

    var body: some View {
        let count = model.threads(in: project).count
        SidebarRow(
            title: project.name,
            accessoryWidth: 40,
            action: {
                guard togglesExpansion else { return }
                withAnimation(Chrome.panelSlide) {
                    model.updateProject(project.id) { $0.isExpanded.toggle() }
                }
            },
            icon: {
                SidebarIconBadge(tint: Chrome.tileHue(for: project.id)) { SidebarSymbol("folder.fill") }
            },
            accessory: { hovering in
                if hovering {
                    HStack(spacing: 0) {
                        Menu {
                            menuItems
                        } label: {
                            RowAccessoryIcon("ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        Button {
                            model.newThread(in: project)
                        } label: {
                            RowAccessoryIcon("plus")
                        }
                        .buttonStyle(.plain)
                        .help("New thread in \(project.name)")
                    }
                } else if !project.isExpanded, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.trailing, 4)
                }
            }
        )
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("New thread") { model.newThread(in: project) }
        Button("New thread in worktree") { model.newThread(in: project, workspace: .worktree) }
        Divider()
        Button("Reveal in Finder") { Workspace.revealInFinder(project.path) }
        Divider()
        Button("Remove project", role: .destructive) { model.removeProject(project) }
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SidebarRow(
            title: thread.title,
            isSelected: model.selectedThreadID == thread.id,
            isEmphasized: thread.hasUnread,
            accessoryWidth: 30,
            action: { model.selectedThreadID = thread.id },
            icon: { ThreadBadge(thread: thread) },
            accessory: { hovering in
                if hovering {
                    Menu {
                        menuItems
                    } label: {
                        RowAccessoryIcon("ellipsis")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                } else {
                    Text(verbatim: RelativeTime.short(thread.updatedAt))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                        .padding(.trailing, 4)
                }
            }
        )
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Rename") { onRename() }
        Button(thread.isPinned ? "Unpin" : "Pin") {
            model.updateThread(thread.id) { $0.isPinned.toggle() }
        }
        if let path = thread.worktreePath {
            Button("Reveal worktree in Finder") { Workspace.revealInFinder(path) }
        }
        Divider()
        Button("Archive") { model.archive(thread.id) }
        Button("Delete…", role: .destructive) { onDelete() }
    }
}

private struct ThreadBadge: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        let runtime = model.existingRuntime(for: thread.id)
        let needsInput = !(runtime?.approvals.isEmpty ?? true) || !(runtime?.questions.isEmpty ?? true)
        let isRunning = runtime?.isRunning == true
        SidebarIconBadge(tint: needsInput ? Chrome.orange : nil) {
            if needsInput {
                SidebarSymbol("hand.raised.fill")
            } else if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
            } else if thread.isPinned {
                SidebarSymbol("pin.fill", scale: 0.9)
            } else {
                ProviderIcon(provider: thread.provider, size: 11)
            }
        }
        .overlay(alignment: .topTrailing) {
            if thread.hasUnread, !needsInput, !isRunning {
                Circle()
                    .fill(thread.lastStatus == .failed ? Color.red : Chrome.accent)
                    .frame(width: 7, height: 7)
                    .offset(x: 2.5, y: -2.5)
            }
        }
    }
}
