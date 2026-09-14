import SwiftUI

struct ThreadTimeline: View, Equatable {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let scrollState: TimelineScrollState
    let projectName: String?
    /// The folder the thread works in, for tool rows that resolve paths. Read once by the
    /// chat and handed down as a value, so rows never look the thread up themselves.
    let workingDirectory: String?
    /// Whether the thread's provider can rewind a conversation, for the revert controls.
    let supportsRewind: Bool
    /// Full chat-column height, so the rail stays centred when the composer
    /// or queue tab grows.
    let columnHeight: CGFloat

    /// The chat re-renders whenever its thread changes (a title, the effort, a mode); the
    /// timeline only follows when what it was handed changed.
    nonisolated static func == (lhs: ThreadTimeline, rhs: ThreadTimeline) -> Bool {
        lhs.runtime === rhs.runtime
            && lhs.scrollChrome === rhs.scrollChrome
            && lhs.scrollState === rhs.scrollState
            && lhs.projectName == rhs.projectName
            && lhs.workingDirectory == rhs.workingDirectory
            && lhs.supportsRewind == rhs.supportsRewind
            && lhs.columnHeight == rhs.columnHeight
    }

    /// Everything the scroll view and the rows report while the reader scrolls: which blocks
    /// are on screen, whether the timeline follows new text, and the scroll position itself.
    /// It lives in an object rather than in view state on purpose. Rows write to it as they
    /// cross the viewport's edges and the scroll view writes to it as content grows, and only
    /// the rail reads it, so none of that ever re-runs this body.
    @State private var tracking = TimelineScrollTracking()
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
            timeline(blocks)
        }
    }

    private func timeline(_ blocks: [DisplayBlock]) -> some View {
        // Only the newest window of blocks is rendered. Older history loads on demand,
        // so the view count stays bounded even for very long threads.
        let hidden = max(0, blocks.count - visibleCount)
        let visible = hidden == 0 ? blocks : Array(blocks.suffix(visibleCount))
        // The turns a row may offer to revert. Read here, once, so a turn record changing
        // (checkpoints, diffs, anchors) re-runs this body alone; rows get a plain flag that
        // only changes when their own answer does.
        let rewindable: Set<UUID> = supportsRewind && !runtime.isRunning ? Set(runtime.turns.map(\.id)) : []
        // The rail floats over the timeline's leading gutter instead of taking layout
        // space, so the conversation stays centered exactly like the composer.
        // Ticks centre in the full column height, so the queue tab opening never moves them.
        return ZStack(alignment: .leading) {
            timelineScroll(visible: visible, hidden: hidden, rewindable: rewindable)
            if blocks.count(where: \.hasUserMessage) > 1 {
                TimelineMinimapColumn(
                    blocks: blocks,
                    tracking: tracking,
                    centerHeight: columnHeight,
                    onNavigate: { id, animated in jump(to: id, in: blocks, animated: animated) }
                )
                .equatable()
                .frame(width: 30)
                .frame(maxHeight: .infinity)
                // The hover card reaches over the conversation instead of being painted under it.
            }
        }
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
            tracking.isPinnedToBottom = (id == blocks.last?.id)
        }
        let tracking = tracking
        let scroll = { tracking.position.scrollTo(id: id, anchor: .top) }
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

    private func timelineScroll(visible: [DisplayBlock], hidden: Int, rewindable: Set<UUID>) -> some View {
        @Bindable var tracking = tracking
        return ScrollView {
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
                        let context = RowContext(
                            workingDirectory: workingDirectory,
                            canRewind: block.turnID.map(rewindable.contains) ?? false
                        )
                        DisplayBlockView(block: block, runtime: runtime, context: context)
                            .equatable()
                            .id(block.id)
                            .onScrollVisibilityChange(threshold: 0.05) { isVisible in
                                tracking.setOnScreen(block.id, isVisible)
                            }
                            // One point at the row's top edge: on screen means the block's
                            // top is inside the viewport; off screen while the block still
                            // shows means it owns the viewport's top edge.
                            .overlay(alignment: .top) {
                                Color.clear
                                    .frame(height: 1)
                                    .onScrollVisibilityChange { isVisible in
                                        tracking.setTopEdgeOnScreen(block.id, isVisible)
                                    }
                            }
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
        .scrollPosition($tracking.position)
        .defaultScrollAnchor(.bottom)
        .onGeometryChange(for: CGFloat.self, of: Self.visibleHeight) { viewportHeight = $0 }
        .onScrollPhaseChange { _, phase in
            tracking.isUserScrolling = phase == .interacting || phase == .decelerating
        }
        .onScrollGeometryChange(for: ScrollMetrics.self, of: ScrollMetrics.init(geometry:)) { old, new in
            scrollChrome.update(travel: new.travel)
            if tracking.isUserScrolling {
                // Only the reader's own scrolling decides whether the timeline follows new text.
                // Guarded, so measuring the scroll position never touches anything a body reads.
                let pinned = new.distanceFromBottom < 48
                if pinned != tracking.isPinnedToBottom { tracking.isPinnedToBottom = pinned }
            } else if new.contentHeight > old.contentHeight, tracking.isPinnedToBottom {
                withAnimation(.easeOut(duration: 0.2)) { tracking.position.scrollTo(edge: .bottom) }
            }
        }
        .onChange(of: runtime.isRunning) { _, running in
            // Sending a message always brings the reader back to the conversation's end.
            guard running else { return }
            tracking.isPinnedToBottom = true
            withAnimation(.easeOut(duration: 0.25)) { tracking.position.scrollTo(edge: .bottom) }
        }
        .onChange(of: scrollState.jumpRequest) {
            tracking.isPinnedToBottom = true
            withAnimation(.smooth(duration: 0.35)) { tracking.position.scrollTo(edge: .bottom) }
        }
        .onChange(of: runtime.threadID) {
            // A new thread starts with a fresh window on its newest messages, and no
            // block from the old one is on screen any more.
            visibleCount = TimelineWindow.initial
            tracking.clearOnScreen()
        }
    }

    private nonisolated static func visibleHeight(_ proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
    }
}

/// Scroll-driven facts about the timeline, kept out of view state so reporting them never
/// re-renders the conversation. Every write is guarded against no-ops: an observable write
/// notifies its readers whether or not the value moved.
@MainActor
@Observable
final class TimelineScrollTracking {
    /// Where the scroll view is. Written by the scroll view as it scrolls and by the
    /// follow-along and jump code; nothing reads it in a body.
    var position = ScrollPosition(edge: .bottom)
    /// Whether new text keeps the timeline at the conversation's end.
    var isPinnedToBottom = true
    /// True while the reader drags or flicks the timeline, as opposed to it following new text.
    @ObservationIgnored var isUserScrolling = false
    /// Ids of the blocks currently on screen, so the rail can light the block the reader is
    /// on. Rows write here only when they cross the viewport's edges, never per scroll frame.
    private(set) var onScreenBlockIDs: Set<String> = []
    /// Ids of the blocks whose top edge is on screen. A block that is on screen while its
    /// top edge is not straddles the viewport's top — that is the section the reader is in.
    private(set) var topEdgeOnScreenBlockIDs: Set<String> = []

    func setOnScreen(_ id: String, _ isOnScreen: Bool) {
        if isOnScreen {
            if !onScreenBlockIDs.contains(id) { onScreenBlockIDs.insert(id) }
        } else if onScreenBlockIDs.contains(id) {
            onScreenBlockIDs.remove(id)
        }
    }

    func setTopEdgeOnScreen(_ id: String, _ isOnScreen: Bool) {
        if isOnScreen {
            if !topEdgeOnScreenBlockIDs.contains(id) { topEdgeOnScreenBlockIDs.insert(id) }
        } else if topEdgeOnScreenBlockIDs.contains(id) {
            topEdgeOnScreenBlockIDs.remove(id)
        }
    }

    func clearOnScreen() {
        if !onScreenBlockIDs.isEmpty { onScreenBlockIDs.removeAll() }
        if !topEdgeOnScreenBlockIDs.isEmpty { topEdgeOnScreenBlockIDs.removeAll() }
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

enum TimelineGroup: Identifiable, Equatable {
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
///
/// Equatable, so a rebuilt timeline can tell an unchanged block from a changed one and
/// skip its row. Entries compare by identity: what a row shows of an entry it observes
/// itself, so the same entry object always means the same row.
enum DisplayBlock: Identifiable, Equatable {
    case turn(id: String, turnID: UUID, userEntries: [TimelineEntry], content: [TimelineEntry], summary: TurnSummary)
    /// A plain group, with the facts its row needs from the turn it belongs to: the turn's
    /// summary on the turn's last reply, and whether the turn produced a reply on its end marker.
    case group(TimelineGroup, summary: TurnSummary?, hasReply: Bool)

    var id: String {
        switch self {
        case .turn(let id, _, _, _, _): id
        case .group(let group, _, _): group.id
        }
    }

    /// The turn the block belongs to, for the revert controls.
    var turnID: UUID? {
        switch self {
        case .turn(_, let turnID, _, _, _): turnID
        case .group(.single(let entry), _, _): entry.turnID
        case .group(.work, _, _): nil
        }
    }

    /// Whether the block holds a message the user sent (a turn prompt or a
    /// standalone user message). Only these get rail ticks.
    var hasUserMessage: Bool {
        switch self {
        case .turn(_, _, let userEntries, _, _): !userEntries.isEmpty
        case .group(.single(let entry), _, _): entry.kind == .user
        case .group(.work, _, _): false
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
                    blocks.append(.group(group, summary: meta.summary(for: group), hasReply: meta.hasReply(for: group)))
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

    /// The turn's summary, shown on the turn's last reply only. A dictionary lookup,
    /// so rows never scan the thread.
    @MainActor
    func summary(for group: TimelineGroup) -> TurnSummary? {
        guard case .single(let entry) = group, entry.kind == .assistant,
              let turnID = entry.turnID, lastAssistantIDByTurn[turnID] == entry.id else { return nil }
        return summaryByTurn[turnID]
    }

    /// Whether a turn-end marker's turn produced a reply; when it did, the duration lives
    /// on the reply's hover line instead.
    @MainActor
    func hasReply(for group: TimelineGroup) -> Bool {
        guard case .single(let entry) = group, entry.kind == .turnEnd, let turnID = entry.turnID else { return false }
        return turnsWithReply.contains(turnID)
    }
}

/// What a row needs from outside its block, as plain values. Rows never read the app
/// model or the runtime's turn list themselves, so a change anywhere else in the app
/// never re-renders them; only a change to these values does.
struct RowContext: Equatable {
    var workingDirectory: String?
    /// Whether the block's turn can be reverted right now.
    var canRewind: Bool
}

private struct DisplayBlockView: View, Equatable {
    let block: DisplayBlock
    let runtime: ThreadRuntime
    let context: RowContext

    nonisolated static func == (lhs: DisplayBlockView, rhs: DisplayBlockView) -> Bool {
        lhs.block == rhs.block && lhs.runtime === rhs.runtime && lhs.context == rhs.context
    }

    var body: some View {
        switch block {
        case .group(let group, let summary, let hasReply):
            TimelineGroupView(group: group, runtime: runtime, summary: summary, hasReply: hasReply, context: context)
        case .turn(_, let turnID, let userEntries, let content, let summary):
            TurnFinishedBlock(
                runtime: runtime,
                turnID: turnID,
                summary: summary,
                userEntries: userEntries,
                content: content,
                workingDirectory: context.workingDirectory,
                canUndo: context.canRewind
            )
        }
    }
}

struct TimelineGroupView: View {
    let group: TimelineGroup
    let runtime: ThreadRuntime
    /// The turn's summary, when this group is the turn's last reply.
    let summary: TurnSummary?
    /// Whether the turn produced a reply, for a turn-end marker.
    let hasReply: Bool
    let context: RowContext

    var body: some View {
        switch group {
        case .single(let entry):
            switch entry.kind {
            case .user: UserMessageRow(entry: entry, runtime: runtime, canRevert: context.canRewind)
            case .assistant: AssistantMessageRow(entry: entry, summary: summary)
            case .reasoning: EmptyView()
            case .tool: WorkGroup(entries: [entry], workingDirectory: context.workingDirectory)
            case .plan: PlanCard(entry: entry, runtime: runtime)
            case .todos: TodoListRow(entry: entry)
            case .notice: NoticeRow(entry: entry)
            case .turnEnd:
                if case .turnEnd(let summary) = entry.item.content {
                    TurnEndRow(summary: summary, hasReply: hasReply)
                }
            }
        case .work(_, let entries, let startsCollapsed):
            WorkGroup(entries: entries, workingDirectory: context.workingDirectory, startsCollapsed: startsCollapsed)
        }
    }
}

/// Zeron's gradient pulse with a word that changes every few seconds, and the elapsed time.
private struct WorkingIndicator: View {
    let startedAt: Date
    let seed: UInt64
    /// The running turn's thinking. When there is any, a chevron opens it beneath the indicator.
    let thinkingSteps: [ThinkingStep]
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
                        .foregroundStyle(.secondary)
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
                        MarkdownView(text: step.text, isStreaming: step.isStreaming).equatable()
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

/// One piece of the running turn's thinking, and whether it is still arriving.
struct ThinkingStep: Equatable {
    var text: String
    var isStreaming: Bool
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
    private var thinking: [ThinkingStep] {
        guard let turnID = runtime.entries.last.flatMap(\.turnID) else { return [] }
        // Walks back from the end and stops at the previous turn, so streamed thinking never rescans the thread.
        var steps: [ThinkingStep] = []
        for entry in runtime.entries.reversed() {
            guard let entryTurn = entry.turnID else { continue }
            guard entryTurn == turnID else { break }
            guard entry.kind == .reasoning, case .reasoning(let block) = entry.item.content, !block.text.isEmpty else { continue }
            steps.append(ThinkingStep(text: block.text, isStreaming: block.isStreaming))
        }
        return steps.reversed()
    }
}
