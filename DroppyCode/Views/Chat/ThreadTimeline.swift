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
    @State private var bottomInset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        let groups = TimelineGroup.build(runtime.entries, showReasoning: model.settings.showReasoning)
        if groups.isEmpty && !runtime.isRunning {
            NewThreadPrompt(threadID: runtime.threadID, projectName: projectName)
                .onAppear {
                    scrollChrome.update(travel: 0)
                    scrollState.showsJumpButton = false
                }
        } else {
            timeline(groups)
        }
    }

    private func timeline(_ groups: [TimelineGroup]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        TimelineGroupView(group: group, runtime: runtime)
                            .transition(.softAppear)
                    }
                    if runtime.isRunning {
                        WorkingIndicator(
                            startedAt: runtime.turnStartedAt ?? .now,
                            seed: WorkingWords.seed(runtime.threadID.uuidString),
                            thinkingSteps: model.settings.showReasoning ? currentThinking : []
                        )
                            .transition(.softAppear)
                    }
                }
                .animation(.softAppear, value: groups.count)
                .animation(.softAppear, value: runtime.isRunning)
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
            bottomInset = new.bottomInset
            scrollChrome.update(travel: new.travel)
            if isUserScrolling {
                // Only the reader's own scrolling decides whether the timeline follows new text.
                isPinnedToBottom = new.distanceFromBottom < 48
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
    }

    /// The running turn's thinking, for the working indicator to reveal.
    private var currentThinking: [String] {
        guard let turnID = runtime.entries.last.flatMap(\.turnID) else { return [] }
        // Kind and turn are fixed at creation; checking them first keeps the timeline from
        // observing, and re-rendering on, every streaming entry of the turn.
        return runtime.entries.compactMap { entry in
            guard entry.kind == .reasoning, entry.turnID == turnID,
                  case .reasoning(let block) = entry.item.content, !block.text.isEmpty else { return nil }
            return block.text
        }
    }

    private nonisolated static func visibleHeight(_ proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
    }
}

/// Scroll measurements, built by a plain initializer rather than an inline closure.
private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var distanceFromBottom: CGFloat
    var bottomInset: CGFloat
    var travel: CGFloat

    init(geometry: ScrollGeometry) {
        contentHeight = geometry.contentSize.height
        bottomInset = geometry.contentInsets.bottom
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

private struct TimelineGroupView: View {
    let group: TimelineGroup
    let runtime: ThreadRuntime

    var body: some View {
        switch group {
        case .single(let entry):
            switch entry.kind {
            case .user: UserMessageRow(entry: entry, runtime: runtime)
            case .assistant: AssistantMessageRow(entry: entry, runtime: runtime)
            case .reasoning: EmptyView()
            case .tool: WorkGroup(entries: [entry])
            case .plan: PlanCard(entry: entry, runtime: runtime)
            case .todos: TodoListRow(entry: entry)
            case .notice: NoticeRow(entry: entry)
            case .turnEnd: TurnEndRow(entry: entry, runtime: runtime)
            }
        case .work(_, let entries):
            WorkGroup(entries: entries)
        }
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
                        MarkdownView(text: step)
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
