import SwiftUI

struct ThreadTimeline: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let scrollState: TimelineScrollState
    let projectName: String?

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isPinnedToBottom = true
    /// True while the reader drags or flicks the timeline, as opposed to it following new text.
    @State private var isUserScrolling = false
    @State private var viewportHeight: CGFloat = 0
    /// Lazy-loading window: only the newest groups are materialized, so opening a long
    /// thread and scrolling through it stays instant no matter how much history it holds.
    @State private var visibleCount = TimelineWindow.initial

    var body: some View {
        let entries = runtime.entries
        let meta = TimelineMeta.build(entries)
        let blocks = DisplayBlock.build(entries, meta: meta, showReasoning: model.settings.showReasoning)
        if blocks.isEmpty && !runtime.isRunning {
            NewThreadPrompt(threadID: runtime.threadID, projectName: projectName)
                .onAppear {
                    scrollChrome.update(travel: 0)
                    scrollState.showsJumpButton = false
                }
        } else {
            timeline(blocks, meta: meta)
        }
    }

    private func timeline(_ blocks: [DisplayBlock], meta: TimelineMeta) -> some View {
        // Only the newest window of blocks is rendered. Older history loads on demand,
        // so the view count stays bounded even for very long threads.
        let hidden = max(0, blocks.count - visibleCount)
        let visible = hidden == 0 ? blocks : Array(blocks.suffix(visibleCount))
        // One tick per block, so the rail's size and selection come from block ids alone; the
        // column reads the text itself, which keeps streaming out of this body.
        return HStack(spacing: 0) {
            if blocks.count > 1 {
                TimelineMinimapColumn(
                    blocks: blocks,
                    selectedID: activeMinimapID(blocks: blocks),
                    onNavigate: { id, animated in jump(to: id, in: blocks, animated: animated) }
                )
                .frame(width: 30)
            }
            timelineScroll(visible: visible, hidden: hidden, meta: meta)
        }
    }

    /// The block the reader is on: the view at the bottom-anchored scroll
    /// position when it matches a block, else the latest block while pinned
    /// to the bottom, else nothing.
    private func activeMinimapID(blocks: [DisplayBlock]) -> String? {
        if let id = position.viewID as? String, blocks.contains(where: { $0.id == id }) { return id }
        if isPinnedToBottom { return blocks.last?.id }
        return nil
    }

    /// Jump the timeline to a minimap block. A target above the loaded
    /// window first loads history down to it, then scrolls once layout
    /// exists. Jumping away from the latest unpins the follow behavior, so
    /// streaming text never yanks the reader back down.
    private func jump(to id: String, in blocks: [DisplayBlock], animated: Bool) {
        var needsExpand = false
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            let firstVisible = blocks.count - visibleCount
            if index < firstVisible {
                visibleCount = blocks.count - index
                needsExpand = true
            }
            isPinnedToBottom = (id == blocks.last?.id)
        }
        let scroll = { position.scrollTo(id: id, anchor: .top) }
        if animated {
            if needsExpand {
                DispatchQueue.main.async { withAnimation(.smooth(duration: 0.35)) { scroll() } }
            } else {
                withAnimation(.smooth(duration: 0.35)) { scroll() }
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            if needsExpand {
                DispatchQueue.main.async { withTransaction(transaction) { scroll() } }
            } else {
                withTransaction(transaction) { scroll() }
            }
        }
    }

    private func timelineScroll(visible: [DisplayBlock], hidden: Int, meta: TimelineMeta) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                if hidden > 0 {
                    Button {
                        visibleCount += TimelineWindow.page
                    } label: {
                        Label("Show \(hidden) earlier messages", systemImage: "chevron.up")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.5), in: Capsule(style: .continuous))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, TimelineMetrics.rowSpacing)
                }
                LazyVStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    ForEach(visible) { block in
                        DisplayBlockView(block: block, runtime: runtime, meta: meta)
                            .id(block.id)
                            .transition(.softAppear)
                    }
                    if runtime.isRunning {
                        WorkingIndicatorSlot(runtime: runtime, showsThinking: model.settings.showReasoning)
                    }
                }
                // The end of the conversation. While it is on screen the reader is at the latest message.
                Color.clear
                    .frame(height: 1)
                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                        guard scrollState.showsJumpButton == isVisible else { return }
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            scrollState.showsJumpButton = !isVisible
                        }
                    }
            }
            // The same column as the composer, so messages line up with its edges.
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, Chrome.contentTopInset)
            .padding(.bottom, 18)
            // A short conversation still fills the pane, with its messages resting at the bottom.
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
        }
        .id(runtime.threadID)
        .scrollIndicators(.never)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onGeometryChange(for: CGFloat.self, of: Self.visibleHeight) { viewportHeight = $0 }
        .onScrollPhaseChange { _, phase in
            isUserScrolling = phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: ScrollMetrics.self, of: ScrollMetrics.init(geometry:)) { old, new in
            scrollChrome.update(travel: new.travel)
            if isUserScrolling {
                // Only the reader's own scrolling decides whether the timeline follows new text.
                // Guarded, so measuring the scroll position never re-renders the timeline itself.
                let pinned = new.distanceFromBottom < 48
                if pinned != isPinnedToBottom { isPinnedToBottom = pinned }
            } else if new.contentHeight > old.contentHeight, isPinnedToBottom {
                withAnimation(.easeOut(duration: 0.2)) { position.scrollTo(edge: .bottom) }
            }
        }
        .onChange(of: runtime.isRunning) { _, running in
            // Sending a message always brings the reader back to the conversation's end.
            guard running else { return }
            isPinnedToBottom = true
            withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: scrollState.jumpRequest) {
            isPinnedToBottom = true
            withAnimation(.smooth(duration: 0.35)) { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: runtime.threadID) {
            // A new thread starts with a fresh window on its newest messages.
            visibleCount = TimelineWindow.initial
        }
    }

    /// The running turn's thinking, for the working indicator to reveal.
    private nonisolated static func visibleHeight(_ proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
    }
}

/// Scroll measurements, built by a plain initializer rather than an inline closure.
/// Deliberately minimal: every stored field is compared every scroll frame, and any
/// write to view state here would re-render the timeline mid-scroll.
private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var distanceFromBottom: CGFloat
    var travel: CGFloat

    init(geometry: ScrollGeometry) {
        contentHeight = geometry.contentSize.height
        travel = geometry.contentOffset.y + geometry.contentInsets.top
        let insets = geometry.contentInsets.top + geometry.contentInsets.bottom
        if geometry.contentSize.height + insets <= geometry.containerSize.height + 1 {
            distanceFromBottom = 0
        } else {
            distanceFromBottom = geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height
        }
    }
}

enum TimelineGroup: Identifiable {
    case single(TimelineEntry)
    /// A run of tool entries. `startsCollapsed` is true when reply text follows
    /// the run, so past work renders as one tappable summary line above the answer.
    case work(id: String, entries: [TimelineEntry], startsCollapsed: Bool)

    var id: String {
        switch self {
        case .single(let entry): entry.id
        case .work(let id, _, _): id
        }
    }

    @MainActor
    static func build(_ entries: [TimelineEntry], showReasoning: Bool) -> [TimelineGroup] {
        // Positions of replies. A work run sitting before one has been moved on from, so it
        // starts collapsed. Kind only, never the text: reading streaming content here made the
        // whole timeline regroup on every token. A reply row is created by its first delta.
        var replyIndices: [Int] = []
        for (index, entry) in entries.enumerated() where entry.kind == .assistant {
            replyIndices.append(index)
        }
        var groups: [TimelineGroup] = []
        var work: [TimelineEntry] = []
        var workStart = 0

        func flushWork() {
            guard let first = work.first else { return }
            let workEnd = workStart + work.count - 1
            let collapsed = replyIndices.contains { $0 > workEnd }
            groups.append(.work(id: "work-\(first.id)", entries: work, startsCollapsed: collapsed))
            work.removeAll()
        }

        for (index, entry) in entries.enumerated() {
            switch entry.kind {
            case .tool:
                if let last = work.last, last.turnID != entry.turnID { flushWork() }
                if work.isEmpty { workStart = index }
                work.append(entry)
            case .reasoning:
                // Thinking lives behind the working indicator's chevron, never as a row of its own.
                continue
            default:
                flushWork()
                groups.append(.single(entry))
            }
        }
        flushWork()
        return groups
    }
}

/// A finished turn collapses to its final response plus its file summary, so the
/// chat stays clean. The chevron re-opens the turn's full steps. Running turns
/// and entries without a turn render as plain groups, exactly as before.
enum DisplayBlock: Identifiable {
    case turn(id: String, turnID: UUID, userEntries: [TimelineEntry], content: [TimelineEntry], summary: TurnSummary)
    case group(TimelineGroup)

    var id: String {
        switch self {
        case .turn(let id, _, _, _, _): id
        case .group(let group): group.id
        }
    }

    @MainActor
    static func build(_ entries: [TimelineEntry], meta: TimelineMeta, showReasoning: Bool) -> [DisplayBlock] {
        // Partition into contiguous runs sharing one turnID (nil groups together),
        // so a finished turn becomes one collapsible block.
        var runs: [(turnID: UUID?, entries: [TimelineEntry])] = []
        for entry in entries {
            if runs.last?.turnID == entry.turnID {
                runs[runs.count - 1].entries.append(entry)
            } else {
                runs.append((entry.turnID, [entry]))
            }
        }
        var blocks: [DisplayBlock] = []
        for run in runs {
            if let turnID = run.turnID, let summary = meta.summaryByTurn[turnID] {
                let users = run.entries.filter { $0.kind == .user }
                let content = run.entries.filter { $0.kind != .user && $0.kind != .turnEnd && $0.kind != .reasoning }
                blocks.append(.turn(id: "turn-\(turnID.uuidString)", turnID: turnID, userEntries: users, content: content, summary: summary))
            } else {
                for group in TimelineGroup.build(run.entries, showReasoning: showReasoning) {
                    blocks.append(.group(group))
                }
            }
        }
        return blocks
    }
}

/// Lazy-loading window for the timeline: only the newest groups are materialized, so
/// the number of live views stays bounded even for very long threads.
enum TimelineWindow {
    static let initial = 80
    static let page = 100
}

/// Per-turn facts computed once per timeline pass, so rows never scan the thread to
/// find their own summary. `kind`, `id` and `turnID` are fixed for a row's lifetime,
/// and finished turn summaries never change, so building this never costs renders
/// while streaming.
struct TimelineMeta {
    var lastAssistantIDByTurn: [UUID: String] = [:]
    var summaryByTurn: [UUID: TurnSummary] = [:]
    var turnsWithReply: Set<UUID> = []

    @MainActor
    static func build(_ entries: [TimelineEntry]) -> TimelineMeta {
        var meta = TimelineMeta()
        for entry in entries {
            switch entry.kind {
            case .assistant:
                if let turnID = entry.turnID {
                    meta.lastAssistantIDByTurn[turnID] = entry.id
                    meta.turnsWithReply.insert(turnID)
                }
            case .turnEnd:
                if case .turnEnd(let summary) = entry.item.content {
                    meta.summaryByTurn[summary.turnID] = summary
                }
            default:
                break
            }
        }
        return meta
    }
}

private struct DisplayBlockView: View {
    let block: DisplayBlock
    let runtime: ThreadRuntime
    let meta: TimelineMeta

    var body: some View {
        switch block {
        case .group(let group):
            TimelineGroupView(group: group, runtime: runtime, meta: meta)
        case .turn(_, let turnID, let userEntries, let content, let summary):
            TurnFinishedBlock(runtime: runtime, turnID: turnID, summary: summary, userEntries: userEntries, content: content)
        }
    }
}

struct TimelineGroupView: View {
    @Environment(AppModel.self) private var model
    let group: TimelineGroup
    let runtime: ThreadRuntime
    let meta: TimelineMeta

    var body: some View {
        switch group {
        case .single(let entry):
            switch entry.kind {
            case .user: UserMessageRow(entry: entry, runtime: runtime)
            case .assistant: AssistantMessageRow(entry: entry, summary: assistantSummary(for: entry))
            case .reasoning: EmptyView()
            case .tool: WorkGroup(entries: [entry], workingDirectory: workingDirectory)
            case .plan: PlanCard(entry: entry, runtime: runtime)
            case .todos: TodoListRow(entry: entry)
            case .notice: NoticeRow(entry: entry)
            case .turnEnd:
                if case .turnEnd(let summary) = entry.item.content {
                    TurnEndRow(summary: summary, hasReply: meta.turnsWithReply.contains(summary.turnID))
                }
            }
        case .work(_, let entries, let startsCollapsed):
            WorkGroup(entries: entries, workingDirectory: workingDirectory, startsCollapsed: startsCollapsed)
        }
    }

    /// The turn's summary, shown on the turn's last reply only. A dictionary lookup,
    /// so rows never scan the thread.
    private func assistantSummary(for entry: TimelineEntry) -> TurnSummary? {
        guard let turnID = entry.turnID, meta.lastAssistantIDByTurn[turnID] == entry.id else { return nil }
        return meta.summaryByTurn[turnID]
    }

    private var workingDirectory: String? {
        guard let thread = model.thread(runtime.threadID) else { return nil }
        if let worktree = thread.worktreePath { return worktree }
        return model.project(thread.projectID)?.path
    }
}

/// Zeron's gradient pulse with a word that changes every few seconds, and the elapsed time.
private struct WorkingIndicator: View {
    let startedAt: Date
    let seed: UInt64
    /// The running turn's thinking. When there is any, a chevron opens it beneath the indicator.
    let thinkingSteps: [String]
    @State private var now = Date.now
    @State private var showsThinking = false

    var body: some View {
        let elapsed = now.timeIntervalSince(startedAt)
        let word = WorkingWords.word(seed: seed, elapsedSeconds: Int64(max(0, elapsed)))
        let canExpand = !thinkingSteps.isEmpty
        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
            Button {
                guard canExpand else { return }
                withAnimation(.snappy(duration: 0.24)) { showsThinking.toggle() }
            } label: {
                HStack(spacing: TimelineMetrics.iconSpacing) {
                    WorkingSpinner(cellSize: 3.5)
                        .frame(width: TimelineMetrics.iconWidth)
                    Text(verbatim: "\(word)…")
                        .foregroundStyle(.secondary)
                        .id(word)
                        .transition(.opacity.combined(with: .offset(y: 3)))
                    Text(RelativeTime.duration(elapsed))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsThinking ? 90 : 0))
                            .transition(.opacity)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(canExpand ? (showsThinking ? "Hide thinking" : "Show thinking") : "")
            .accessibilityHint(canExpand ? Text("Shows the agent's thinking") : Text(""))

            if showsThinking, canExpand {
                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    ForEach(Array(thinkingSteps.enumerated()), id: \.offset) { _, step in
                        MarkdownView(text: step).equatable()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .environment(\.markdownPointSize, 12)
                .environment(\.markdownDimmed, true)
                .padding(.leading, TimelineMetrics.iconWidth + TimelineMetrics.iconSpacing)
                .transition(.softAppear)
            }
        }
        .animation(.smooth(duration: 0.35), value: word)
        .animation(.smooth(duration: 0.2), value: canExpand)
        .font(.callout)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }
}

/// Whether the reader has scrolled away from the latest message, shared with the composer that shows the jump button.
@MainActor
@Observable
final class TimelineScrollState {
    var showsJumpButton = false
    private(set) var jumpRequest = 0

    func jumpToLatest() {
        jumpRequest += 1
    }
}

/// Where the working indicator sits while a turn runs. The moment the reply it is waiting on
/// arrives, the indicator steps aside and the reply takes its line, so the answer begins exactly
/// where the indicator was instead of pushing it down. It comes back below when the agent moves on
/// to another step. Indicator and reply are both one row tall — replies keep their hover line
/// inside the gap below them, never in their height — so the handover moves nothing. Only the
/// newest entry's kind is read here, which never changes while text streams, plus the turn's thinking.
private struct WorkingIndicatorSlot: View {
    let runtime: ThreadRuntime
    let showsThinking: Bool

    var body: some View {
        let replyTookOver = runtime.entries.last?.kind == .assistant
        ZStack(alignment: .topLeading) {
            if !replyTookOver {
                WorkingIndicator(
                    startedAt: runtime.turnStartedAt ?? .now,
                    seed: WorkingWords.seed(runtime.threadID.uuidString),
                    thinkingSteps: showsThinking ? thinking : []
                )
                .transition(.asymmetric(
                    insertion: .softAppear,
                    removal: .opacity.animation(.easeOut(duration: 0.1))
                ))
            }
        }
    }

    /// The running turn's thinking. Kind and turn are fixed at creation, so they are checked before
    /// any content is read.
    private var thinking: [String] {
        guard let turnID = runtime.entries.last.flatMap(\.turnID) else { return [] }
        // Walks back from the end and stops at the previous turn, so streamed thinking never rescans the thread.
        var steps: [String] = []
        for entry in runtime.entries.reversed() {
            guard let entryTurn = entry.turnID else { continue }
            guard entryTurn == turnID else { break }
            guard entry.kind == .reasoning, case .reasoning(let block) = entry.item.content, !block.text.isEmpty else { continue }
            steps.append(block.text)
        }
        return steps.reversed()
    }
}
