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

            HStack(spacing: 6) {
                SidebarSearchField(text: $search, prompt: "Search threads") {
                    if let first = searchResults.first?.threads.first {
                        model.selectedThreadID = first.id
                    }
                }
                ActivityViewToggle(isOn: Binding(
                    get: { model.settings.sidebarActivityView },
                    set: { model.settings.sidebarActivityView = $0 }
                ))
            }
            .padding(.horizontal, Chrome.listInset)
            .padding(.top, 14)

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if query.isEmpty {
                        // One list for both layouts: a thread keeps its row when the layout changes, so the
                        // row grows or shrinks and slides to its new place instead of being replaced.
                        ForEach(model.settings.sidebarActivityView ? activityItems : projectItems) { item in
                            itemView(item)
                                .transition(.sidebarRow)
                        }
                    } else {
                        searchList
                    }
                }
                // Adding or deleting a thread opens and closes its space with the same motion as every other row.
                .animation(Chrome.panelSlide, value: model.threads.count)
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
    private func itemView(_ item: SidebarItem) -> some View {
        switch item.kind {
        case .gap:
            Color.clear.frame(height: Chrome.groupGap)
        case .project(let project):
            ProjectRow(project: project)
        case .header(let title, let isFirst):
            ActivityHeader(title: title, isFirst: isFirst)
        case .note(let text):
            Text(verbatim: text)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText.opacity(0.7))
                .padding(.horizontal, Chrome.rowHorizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thread(let thread, let projectName, let peers):
            reorderableRow(thread, projectName: projectName, peers: peers)
        }
    }

    // MARK: Project layout

    private var projectItems: [SidebarItem] {
        var items: [SidebarItem] = []
        for (index, project) in model.projects.enumerated() {
            if index > 0 {
                items.append(SidebarItem(id: "gap-\(project.id)", kind: .gap))
            }
            items.append(SidebarItem(id: "project-\(project.id)", kind: .project(project)))
            guard project.isExpanded else { continue }
            for thread in model.threads(in: project) {
                items.append(SidebarItem(id: thread.id.uuidString, kind: .thread(thread, projectName: nil, peers: nil)))
            }
        }
        return items
    }

    // MARK: Activity layout

    private var activityItems: [SidebarItem] {
        let active = model.threads.filter { !$0.isArchived }
        let attention = Self.placed(active.filter(needsAttention))
        var items: [SidebarItem] = []
        if attention.isEmpty {
            items.append(SidebarItem(id: "attention-none", kind: .note("Nothing needs attention")))
        } else {
            items.append(SidebarItem(id: "attention", kind: .header("Needs attention", isFirst: true)))
            items.append(contentsOf: activityThreadItems(attention))
        }
        for group in Self.activityGroups(active.filter { !needsAttention($0) }) {
            items.append(SidebarItem(id: "day-\(group.title)", kind: .header(group.title, isFirst: false)))
            items.append(contentsOf: activityThreadItems(group.threads))
        }
        return items
    }

    /// Threads of one activity group. A thread can be dragged to another place within its own group.
    private func activityThreadItems(_ threads: [ChatThread]) -> [SidebarItem] {
        let peers = threads.map(\.id)
        return threads.map { thread in
            SidebarItem(
                id: thread.id.uuidString,
                kind: .thread(thread, projectName: model.project(thread.projectID)?.name ?? "", peers: peers)
            )
        }
    }

    private func needsAttention(_ thread: ChatThread) -> Bool {
        guard let runtime = model.existingRuntime(for: thread.id) else { return false }
        return !runtime.approvals.isEmpty || !runtime.questions.isEmpty
    }

    private struct ActivityGroup {
        let title: String
        var threads: [ChatThread]
    }

    /// Threads grouped under Today, Yesterday, a weekday within the week, then a date.
    private static func activityGroups(_ threads: [ChatThread]) -> [ActivityGroup] {
        let calendar = Calendar.current
        var groups: [ActivityGroup] = []
        for thread in threads.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            let title = dayTitle(for: thread.updatedAt, calendar: calendar)
            if groups.last?.title == title {
                groups[groups.count - 1].threads.append(thread)
            } else {
                groups.append(ActivityGroup(title: title, threads: [thread]))
            }
        }
        return groups.map { ActivityGroup(title: $0.title, threads: placed($0.threads)) }
    }

    /// Newest first, except threads dragged into place, which keep that place for the rest of their day.
    private static func placed(_ threads: [ChatThread]) -> [ChatThread] {
        let calendar = Calendar.current
        func order(_ thread: ChatThread) -> Double? {
            guard let order = thread.activityOrder, let day = thread.activityOrderDay,
                  calendar.isDate(day, inSameDayAs: thread.updatedAt) else { return nil }
            return order
        }
        return threads.sorted { lhs, rhs in
            switch (order(lhs), order(rhs)) {
            case let (left?, right?) where left != right: return left < right
            // Threads that became active after a reorder have no place yet and stay on top.
            case (nil, .some): return true
            case (.some, nil): return false
            default: return lhs.updatedAt > rhs.updatedAt
            }
        }
    }

    private static func dayTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide).day())
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    // MARK: Search

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
                    threadRow(thread, projectName: nil)
                }
            }
        }
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

    // MARK: Rows

    /// Drag a row above or below another: within its project in the project layout, within its group
    /// in the activity layout.
    private func reorderableRow(_ thread: ChatThread, projectName: String?, peers: [UUID]?) -> some View {
        let target = dropTarget?.id == thread.id ? dropTarget : nil
        return threadRow(thread, projectName: projectName)
            .onDrag {
                draggingThreadID = thread.id
                return NSItemProvider(object: thread.id.uuidString as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: ThreadDropDelegate(
                    threadID: thread.id,
                    rowHeight: projectName == nil ? Chrome.rowHeight : ThreadRowMetrics.detailedHeight,
                    dragging: $draggingThreadID,
                    target: $dropTarget,
                    accepts: { id in
                        if let peers { return peers.contains(id) }
                        return model.thread(id)?.projectID == thread.projectID
                    },
                    onMove: { id, placeAfter in
                        withAnimation(Chrome.panelSlide) {
                            if let peers {
                                model.moveInActivity(id, to: thread.id, placeAfter: placeAfter, among: peers)
                            } else {
                                model.moveThread(id, to: thread.id, placeAfter: placeAfter)
                            }
                        }
                    }
                )
            )
            .overlay(alignment: target?.placeAfter == true ? .bottom : .top) {
                DropIndicator(target: target)
            }
    }

    private func threadRow(_ thread: ChatThread, projectName: String?) -> some View {
        SidebarThreadRow(
            thread: thread,
            projectName: projectName,
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
}

/// One entry of the sidebar list. Thread entries use the thread's id in both layouts.
private struct SidebarItem: Identifiable {
    enum Kind {
        case gap
        case project(Project)
        case header(String, isFirst: Bool)
        case note(String)
        /// A thread, with its project's name in the activity layout and the threads it can be reordered among.
        case thread(ChatThread, projectName: String?, peers: [UUID]?)
    }

    let id: String
    let kind: Kind
}

private extension AnyTransition {
    /// A row leaves at once and arrives once its neighbours have mostly made room, so rows moving past
    /// each other never draw over one another.
    static var sidebarRow: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.18).delay(0.12)),
            removal: .opacity.animation(.easeOut(duration: 0.06))
        )
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

private enum ThreadRowMetrics {
    static let detailedVerticalPadding: CGFloat = 7
    /// A two-line activity row: title, project line and their padding.
    static let detailedHeight: CGFloat = 48
}

/// A thread in either sidebar layout. In the project layout it is one line with the thread's badge; in
/// the activity layout the project it belongs to shows underneath. It is the same row in both, so
/// switching layouts animates its height and contents rather than swapping one row for another.
private struct SidebarThreadRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let thread: ChatThread
    /// The project shown under the title in the activity layout; nil in the project layout.
    let projectName: String?
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isMenuPresented = false
    @State private var windowFrame = FrameHolder()

    var body: some View {
        let isSelected = model.selectedThreadID == thread.id
        let isDetailed = projectName != nil
        let showsActions = isHovering || isMenuPresented
        let shape = RoundedRectangle(cornerRadius: Chrome.rowCornerRadius, style: .continuous)
        let actions = ThreadActions.make(model: model, thread: thread, onRename: onRename, onDelete: onDelete)
        Button {
            model.selectedThreadID = thread.id
        } label: {
            HStack(spacing: 8) {
                if !isDetailed {
                    ThreadBadge(thread: thread)
                        .frame(width: Chrome.iconSize)
                        .transition(.opacity)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: thread.title)
                        .font(.system(size: 13, weight: isSelected || thread.hasUnread ? .medium : .regular))
                        .foregroundStyle(Chrome.primaryText.opacity(isSelected ? 1 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let projectName {
                        HStack(spacing: 4) {
                            Image(systemName: thread.worktreePath == nil ? "folder" : "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(verbatim: projectName)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Chrome.secondaryText)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.leading, Chrome.rowHorizontalPadding)
            .padding(.trailing, Chrome.rowHorizontalPadding + (isDetailed && !showsActions ? 18 : 52))
            .padding(.vertical, isDetailed ? ThreadRowMetrics.detailedVerticalPadding : 0)
            .frame(minHeight: Chrome.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Only the fill animates with selection; the row's place is never animated from here.
                shape
                    .fill(isSelected ? Chrome.overlay(0.12) : (isHovering ? Chrome.overlay(0.06) : Color.clear))
                    .animation(Chrome.hover, value: isSelected)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Group {
                if showsActions {
                    HStack(spacing: 0) {
                        Button {
                            archiveWithGenie()
                        } label: {
                            RowAccessoryIcon("archivebox")
                        }
                        .buttonStyle(.plain)
                        .help("Archive thread")
                        RowActionsButton(actions: actions, isPresented: $isMenuPresented)
                    }
                } else if isDetailed {
                    ActivityStatus(thread: thread)
                } else {
                    Text(verbatim: RelativeTime.short(thread.updatedAt))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                        .padding(.trailing, 4)
                }
            }
            .padding(.trailing, 6)
        }
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .onGeometryChange(for: CGRect.self, of: Self.windowFrame) { windowFrame.frame = $0 }
        .contextMenu { RowActionMenuButtons(actions: actions) }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private nonisolated static func windowFrame(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .named(GenieAnimator.coordinateSpace))
    }

    private func archiveWithGenie() {
        let title = thread.title
        let projectName = projectName
        let provider = thread.provider
        let symbol = thread.worktreePath == nil ? "folder" : "arrow.triangle.branch"
        let isSelected = model.selectedThreadID == thread.id
        let isDetailed = projectName != nil
        let isPinned = thread.isPinned
        let hasUnread = thread.hasUnread
        let runtime = model.existingRuntime(for: thread.id)
        let needsInput = !(runtime?.approvals.isEmpty ?? true) || !(runtime?.questions.isEmpty ?? true)
        let isRunning = runtime?.isRunning == true
        let weight: Font.Weight = isSelected || hasUnread ? .medium : .regular
        // The ghost mirrors the row's label — same text, badge, padding and
        // translucent fill — so the row hands over to it without a visible change.
        let fill = isSelected ? Chrome.overlay(0.12) : Chrome.overlay(0.06)
        let shape = RoundedRectangle(cornerRadius: Chrome.rowCornerRadius, style: .continuous)
        GenieAnimator.shared.launch(frame: windowFrame.frame, colorScheme: colorScheme) {
            HStack(spacing: 8) {
                if !isDetailed {
                    SidebarIconBadge {
                        if needsInput {
                            SidebarSymbol("hand.raised.fill")
                                .foregroundStyle(Chrome.orange)
                        } else if isRunning {
                            MiniSpinner(cellSize: 2.4)
                        } else if isPinned {
                            SidebarSymbol("pin.fill", scale: 0.9)
                        } else {
                            ProviderIcon(provider: provider, size: 14)
                        }
                    }
                    .frame(width: Chrome.iconSize)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: weight))
                        .foregroundStyle(Chrome.primaryText.opacity(isSelected ? 1 : 0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let projectName {
                        HStack(spacing: 4) {
                            Image(systemName: symbol)
                                .font(.system(size: 10))
                            Text(verbatim: projectName)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Chrome.secondaryText)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.leading, Chrome.rowHorizontalPadding)
            .padding(.trailing, Chrome.rowHorizontalPadding + 52)
            .padding(.vertical, isDetailed ? ThreadRowMetrics.detailedVerticalPadding : 0)
            .frame(minHeight: Chrome.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(fill) }
        }
        withAnimation(Chrome.panelSlide) { model.archive(thread.id) }
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
                MiniSpinner(cellSize: 2.4)
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

/// The accent line where a dragged thread will land. Its fade animates here, never the row under it.
private struct DropIndicator: View {
    let target: ThreadDropTarget?

    var body: some View {
        ZStack {
            if let target {
                Capsule()
                    .fill(Chrome.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
                    .offset(y: target.placeAfter ? 1 : -1)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(Chrome.hover, value: target)
    }
}

/// Reorders threads: the upper half of a row drops above it, the lower half below.
private struct ThreadDropDelegate: DropDelegate {
    let threadID: UUID
    let rowHeight: CGFloat
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
        let next = ThreadDropTarget(id: threadID, placeAfter: info.location.y > rowHeight / 2)
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
        onMove(dragging, info.location.y > rowHeight / 2)
        return true
    }
}

/// What a thread row offers from its ellipsis popover and its context menu, in both sidebar layouts.
@MainActor
private enum ThreadActions {
    static func make(model: AppModel, thread: ChatThread, onRename: @escaping () -> Void, onDelete: @escaping () -> Void) -> [RowAction] {
        var items = [
            RowAction(title: "Rename", symbol: "pencil") { onRename() },
            RowAction(title: thread.isPinned ? "Unpin" : "Pin", symbol: thread.isPinned ? "pin.slash" : "pin") {
                withAnimation(Chrome.panelSlide) {
                    model.updateThread(thread.id) { $0.isPinned.toggle() }
                }
            },
        ]
        if let path = thread.worktreePath {
            items.append(RowAction(title: "Reveal worktree in Finder", symbol: "folder") { Workspace.revealInFinder(path) })
        }
        items.append(RowAction(title: "Archive", symbol: "archivebox", startsGroup: true) {
            withAnimation(Chrome.panelSlide) { model.archive(thread.id) }
        })
        items.append(RowAction(title: "Delete…", symbol: "trash", isDestructive: true) { onDelete() })
        return items
    }
}

/// The bell beside the search field that switches the sidebar between projects and activity.
private struct ActivityViewToggle: View {
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        let chord = ShortcutStore.shared.chord(for: .toggleActivityView).map { " (\($0.description))" } ?? ""
        Button {
            withAnimation(Chrome.panelSlide) { isOn.toggle() }
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Chrome.accent : Chrome.secondaryText)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(isOn ? Chrome.accent.opacity(0.16) : (isHovering ? Chrome.overlay(0.08) : Color.clear))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help((isOn ? "Turn off activity view" : "Turn on activity view") + chord)
        .accessibilityLabel(Text("Activity view"))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

private struct ActivityHeader: View {
    let title: String
    let isFirst: Bool

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Chrome.secondaryText)
            .padding(.horizontal, Chrome.rowHorizontalPadding)
            .padding(.top, isFirst ? 2 : 14)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityStatus: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        let runtime = model.existingRuntime(for: thread.id)
        if !(runtime?.approvals.isEmpty ?? true) || !(runtime?.questions.isEmpty ?? true) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.orange)
        } else if runtime?.isRunning == true {
            MiniSpinner(cellSize: 2.4)
        } else if thread.hasUnread {
            Circle()
                .fill(thread.lastStatus == .failed ? Color.red : Chrome.accent)
                .frame(width: 7, height: 7)
                .padding(.trailing, 4)
        }
    }
}

/// A row's latest frame, kept out of SwiftUI's observation: scrolling updates it on every frame,
/// and only an archive tap ever reads it.
private final class FrameHolder {
    var frame: CGRect = .zero
}
