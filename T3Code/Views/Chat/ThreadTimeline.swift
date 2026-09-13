import SwiftUI

struct ThreadTimeline: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let title: String
    let subtitle: String

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var isPinnedToBottom = true
    @State private var bottomInset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        let groups = TimelineGroup.build(runtime.entries, showReasoning: model.settings.showReasoning)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneHero(title: title, subtitle: subtitle)
                Spacer(minLength: 28)
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        TimelineGroupView(group: group, runtime: runtime)
                    }
                    if runtime.isRunning {
                        WorkingIndicator(startedAt: runtime.turnStartedAt ?? .now)
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, Chrome.contentTopInset)
            .padding(.bottom, 18)
            // A short conversation still fills the pane: the title rests at the top and messages at the bottom.
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
        }
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
        .overlay(alignment: .bottom) {
            if !isPinnedToBottom {
                ChromeCircleButton(symbol: "arrow.down", help: "Jump to latest") {
                    isPinnedToBottom = true
                    withAnimation(.snappy) { position.scrollTo(edge: .bottom) }
                }
                .padding(.bottom, bottomInset + 12)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: isPinnedToBottom)
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
            case .assistant: AssistantMessageRow(entry: entry)
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

private struct WorkingIndicator: View {
    let startedAt: Date
    @State private var now = Date.now

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Working")
                .foregroundStyle(.secondary)
            Text(RelativeTime.duration(now.timeIntervalSince(startedAt)))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.callout)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }
}
