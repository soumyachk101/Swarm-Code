import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    @State private var search = ""
    @State private var renaming: ChatThread?
    @State private var renameText = ""
    @State private var pendingDeletion: ChatThread?
    @State private var draggingThreadID: UUID?
    @State private var dropTarget: ThreadDropTarget?

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
                LazyVStack(alignment: .leading, spacing: 1) {
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
                    SidebarIconBadge { SidebarSymbol("plus") }
                }
                SidebarRow(title: "Settings", action: { WindowManager.shared.showSettings() }) {
                    SidebarIconBadge { SidebarSymbol("gear", scale: 1.15) }
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
                    reorderableThreadRow(thread)
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

    private func reorderableThreadRow(_ thread: ChatThread) -> some View {
        let target = dropTarget?.id == thread.id ? dropTarget : nil
        return threadRow(thread)
            .onDrag {
                draggingThreadID = thread.id
                return NSItemProvider(object: thread.id.uuidString as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: ThreadDropDelegate(
                    threadID: thread.id,
                    dragging: $draggingThreadID,
                    target: $dropTarget,
                    accepts: { model.thread($0)?.projectID == thread.projectID },
                    onMove: { id, placeAfter in
                        withAnimation(Chrome.panelSlide) {
                            model.moveThread(id, to: thread.id, placeAfter: placeAfter)
                        }
                    }
                )
            )
            .overlay(alignment: target?.placeAfter == true ? .bottom : .top) {
                if let target {
                    Capsule()
                        .fill(Chrome.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 6)
                        .offset(y: target.placeAfter ? 1 : -1)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(Chrome.hover, value: target)
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

    @State private var isMenuPresented = false

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
                SidebarIconBadge { SidebarSymbol("folder.fill") }
            },
            accessory: { hovering in
                if hovering || isMenuPresented {
                    HStack(spacing: 0) {
                        RowActionsButton(actions: actions, isPresented: $isMenuPresented)
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
        .contextMenu { RowActionMenuButtons(actions: actions) }
    }

    private var actions: [RowAction] {
        [
            RowAction(title: "New thread", symbol: "square.and.pencil") { model.newThread(in: project) },
            RowAction(title: "New thread in worktree", symbol: "square.stack.3d.up") {
                model.newThread(in: project, workspace: .worktree)
            },
            RowAction(title: "Reveal in Finder", symbol: "folder", startsGroup: true) { Workspace.revealInFinder(project.path) },
            RowAction(title: "Remove project", symbol: "trash", isDestructive: true, startsGroup: true) {
                model.removeProject(project)
            },
        ]
    }
}

private struct ThreadRow: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isMenuPresented = false

    var body: some View {
        SidebarRow(
            title: thread.title,
            isSelected: model.selectedThreadID == thread.id,
            isEmphasized: thread.hasUnread,
            accessoryWidth: 52,
            action: { model.selectedThreadID = thread.id },
            icon: { ThreadBadge(thread: thread) },
            accessory: { hovering in
                if hovering || isMenuPresented {
                    HStack(spacing: 0) {
                        Button {
                            withAnimation(Chrome.panelSlide) { model.archive(thread.id) }
                        } label: {
                            RowAccessoryIcon("archivebox")
                        }
                        .buttonStyle(.plain)
                        .help("Archive thread")
                        RowActionsButton(actions: actions, isPresented: $isMenuPresented)
                    }
                } else {
                    Text(verbatim: RelativeTime.short(thread.updatedAt))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                        .padding(.trailing, 4)
                }
            }
        )
        .contextMenu { RowActionMenuButtons(actions: actions) }
    }

    private var actions: [RowAction] {
        var items = [
            RowAction(title: "Rename", symbol: "pencil") { onRename() },
            RowAction(title: thread.isPinned ? "Unpin" : "Pin", symbol: thread.isPinned ? "pin.slash" : "pin") {
                model.updateThread(thread.id) { $0.isPinned.toggle() }
            },
        ]
        if let path = thread.worktreePath {
            items.append(RowAction(title: "Reveal worktree in Finder", symbol: "folder") { Workspace.revealInFinder(path) })
        }
        items.append(RowAction(title: "Archive", symbol: "archivebox", startsGroup: true) { model.archive(thread.id) })
        items.append(RowAction(title: "Delete…", symbol: "trash", isDestructive: true) { onDelete() })
        return items
    }
}

private struct ThreadBadge: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        let runtime = model.existingRuntime(for: thread.id)
        let needsInput = !(runtime?.approvals.isEmpty ?? true) || !(runtime?.questions.isEmpty ?? true)
        let isRunning = runtime?.isRunning == true
        SidebarIconBadge {
            if needsInput {
                SidebarSymbol("hand.raised.fill")
                    .foregroundStyle(Chrome.orange)
            } else if isRunning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
            } else if thread.isPinned {
                SidebarSymbol("pin.fill", scale: 0.9)
            } else {
                ProviderIcon(provider: thread.provider, size: 14)
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

private struct ThreadDropTarget: Equatable {
    let id: UUID
    let placeAfter: Bool
}

/// Reorders threads within a project: the upper half of a row drops above it, the lower half below.
private struct ThreadDropDelegate: DropDelegate {
    let threadID: UUID
    @Binding var dragging: UUID?
    @Binding var target: ThreadDropTarget?
    let accepts: (UUID) -> Bool
    let onMove: (UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return dragging != threadID && accepts(dragging)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        let next = ThreadDropTarget(id: threadID, placeAfter: info.location.y > Chrome.rowHeight / 2)
        if target != next { target = next }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.id == threadID { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            target = nil
            dragging = nil
        }
        guard let dragging, dragging != threadID, accepts(dragging) else { return false }
        onMove(dragging, info.location.y > Chrome.rowHeight / 2)
        return true
    }
}
