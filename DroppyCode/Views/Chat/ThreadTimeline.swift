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
        let groups = TimelineGroup.build(entries, showReasoning: model.settings.showReasoning)
        if groups.isEmpty && !runtime.isRunning {
            NewThreadPrompt(threadID: runtime.threadID, projectName: projectName)
                .onAppear {
                    scrollChrome.update(travel: 0)
                    scrollState.showsJumpButton = false
                }
        } else {
            timeline(groups, meta: TimelineMeta.build(entries))
        }
    }

    private func timeline(_ groups: [TimelineGroup], meta: TimelineMeta) -> some View {
        // Only the newest window of groups is rendered. Older history loads on demand,
        // so the view count stays bounded even for very long threads.
        let hidden = max(0, groups.count - visibleCount)
        let visible = hidden == 0 ? groups : Array(groups.suffix(visibleCount))
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
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(visible) { group in
                        TimelineGroupView(group: group, runtime: runtime, meta: meta)
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
    case work(id: String, entries: [TimelineEntry])

    var id: String {
        switch self {
        case .single(let entry): entry.id
        case .work(let id, _): id
        }
    }

    @MainActor
    static func build(_ entries: [TimelineEntry], showReasoning: Bool) -> [TimelineGroup] {
        var groups: [TimelineGroup] = []
        var work: [TimelineEntry] = []

        func flushWork() {
            guard let first = work.first else { return }
            groups.append(.work(id: "work-\(first.id)", entries: work))
            work.removeAll()
        }

        for entry in entries {
            switch entry.kind {
            case .tool:
                if let last = work.last, last.turnID != entry.turnID { flushWork() }
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

private struct TimelineGroupView: View {
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
        case .work(_, let entries):
            WorkGroup(entries: entries, workingDirectory: workingDirectory)
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
        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard canExpand else { return }
                withAnimation(.snappy(duration: 0.24)) { showsThinking.toggle() }
            } label: {
                HStack(spacing: 10) {
                    WorkingSpinner(cellSize: 3.5)
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(thinkingSteps.enumerated()), id: \.offset) { _, step in
                        MarkdownView(text: step).equatable()
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 23)
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
/// to another step. Only the newest entry's kind is read here, which never changes while text
/// streams, plus the turn's thinking.
private struct WorkingIndicatorSlot: View {
    let runtime: ThreadRuntime
    let showsThinking: Bool

    var body: some View {
        let replyTookOver = runtime.entries.last?.kind == .assistant
        ZStack(alignment: .topLeading) {
            if !replyTookOver {
                VStack(alignment: .leading, spacing: 2) {
                    WorkingIndicator(
                        startedAt: runtime.turnStartedAt ?? .now,
                        seed: WorkingWords.seed(runtime.threadID.uuidString),
                        thinkingSteps: showsThinking ? thinking : []
                    )
                    // The room a reply keeps under its text for the copy line, so the reply's first
                    // line appears exactly where the indicator's text was.
                    Color.clear
                        .frame(height: 22)
                        .accessibilityHidden(true)
                }
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
        return runtime.entries.compactMap { entry in
            guard entry.kind == .reasoning, entry.turnID == turnID,
                  case .reasoning(let block) = entry.item.content, !block.text.isEmpty else { return nil }
            return block.text
        }
    }
}
