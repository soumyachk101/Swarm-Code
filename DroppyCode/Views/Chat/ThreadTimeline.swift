import SwiftUI

struct ThreadTimeline: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let scrollState: TimelineScrollState
    let projectName: String?

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isPinnedToBottom = true
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
                        WorkingIndicator(startedAt: runtime.turnStartedAt ?? .now, seed: WorkingWords.seed(runtime.threadID.uuidString))
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
        .onScrollGeometryChange(for: ScrollMetrics.self, of: ScrollMetrics.init(geometry:)) { old, new in
            bottomInset = new.bottomInset
            scrollChrome.update(travel: new.travel)
            if new.contentHeight != old.contentHeight {
                if isPinnedToBottom { position.scrollTo(edge: .bottom) }
            } else {
                isPinnedToBottom = new.distanceFromBottom < 56
            }
        }
        .onChange(of: scrollState.jumpRequest) {
            isPinnedToBottom = true
            withAnimation(.smooth(duration: 0.35)) { position.scrollTo(edge: .bottom) }
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
            case .reasoning where !showReasoning:
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
            case .reasoning: ReasoningRow(entry: entry)
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
    @State private var now = Date.now

    var body: some View {
        let elapsed = now.timeIntervalSince(startedAt)
        let word = WorkingWords.word(seed: seed, elapsedSeconds: Int64(max(0, elapsed)))
        HStack(spacing: 10) {
            WorkingSpinner(cellSize: 3.5)
            Text(verbatim: "\(word)…")
                .foregroundStyle(.secondary)
                .id(word)
                .transition(.opacity.combined(with: .offset(y: 3)))
            Text(RelativeTime.duration(elapsed))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .animation(.smooth(duration: 0.35), value: word)
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
