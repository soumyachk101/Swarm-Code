import SwiftUI

/// The running turn's line as a tab on the chat box: Zeron's gradient pulse, what the agent is
/// doing right now (the live tool run's summary, or a word that changes every few seconds before
/// any tool starts) and the elapsed time. It rises from the top of the box exactly like the
/// changes and queue tabs, and while one of those holds the top it hangs from the bottom
/// instead, the box moving up to make room. The chevron opens the thinking (when shown) and
/// the run's steps beneath the line; past a screenful they scroll.
struct WorkingTab: View {
    /// The edge of the chat box the tab is attached to.
    enum Edge {
        case top
        case bottom
    }

    static let overlap = ThreadChangesTab.overlap
    /// The most the opened steps take before they scroll, so a long think never pushes the
    /// conversation off the top of the window.
    private static let maxStepsHeight: CGFloat = 260

    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let edge: Edge
    let workingDirectory: String?
    /// Owned by the chat box, so the steps stay open when the tab moves from one edge to the other.
    @Binding var isExpanded: Bool

    @State private var now = Date.now
    /// The steps' natural height, so the tab grows to exactly it and no further than the cap.
    @State private var stepsHeight: CGFloat = 0

    var body: some View {
        let liveWork = Self.liveWork(in: runtime.entries)
        let thinking = model.settings.showReasoning ? thinkingSteps : []
        let elapsed = now.timeIntervalSince(runtime.turnStartedAt ?? .now)
        let word = WorkingWords.word(seed: WorkingWords.seed(runtime.threadID.uuidString), elapsedSeconds: Int64(max(0, elapsed)))
        let label = liveWork.isEmpty ? "\(word)…" : WorkGroupSummary.text(for: liveWork)
        let canExpand = !thinking.isEmpty || !liveWork.isEmpty
        let showsSteps = isExpanded && canExpand
        // Rounded on the side away from the box; the box draws over the other.
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .top ? 12 : 0,
            bottomLeadingRadius: edge == .top ? 0 : 12,
            bottomTrailingRadius: edge == .top ? 0 : 12,
            topTrailingRadius: edge == .top ? 12 : 0,
            style: .continuous
        )
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard canExpand else { return }
                withAnimation(Chrome.panelSlide) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    WorkingSpinner(cellSize: 3)
                        .frame(width: 16)
                    Text(verbatim: label)
                        .foregroundStyle(Chrome.primaryText.opacity(0.9))
                        .lineLimit(1)
                        .id(label)
                        .transition(.opacity.combined(with: .offset(y: 3)))
                    Text(RelativeTime.duration(elapsed))
                        .foregroundStyle(Chrome.secondaryText)
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(Chrome.inlineIconFont)
                            .foregroundStyle(Chrome.secondaryText)
                            .frame(width: 16, height: 22)
                            .rotationEffect(.degrees(showsSteps ? 90 : 0))
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(canExpand ? (showsSteps ? "Hide these steps" : "Show these steps") : "")
            .accessibilityHint(canExpand ? Text("Shows what the agent is doing") : Text(""))

            if showsSteps {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().opacity(0.5)
                    // The rows report their height and the clip takes exactly it, up to the
                    // cap; only then does the scroll view have anything to scroll.
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                            if !thinking.isEmpty {
                                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                                    ForEach(Array(thinking.enumerated()), id: \.offset) { _, step in
                                        MarkdownView(text: step.text, isStreaming: step.isStreaming).equatable()
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .environment(\.markdownPointSize, 12)
                                .environment(\.markdownDimmed, true)
                                .padding(.leading, TimelineMetrics.iconWidth + TimelineMetrics.iconSpacing)
                            }
                            if !liveWork.isEmpty {
                                WorkSteps(entries: liveWork, runtime: runtime, workingDirectory: workingDirectory)
                            }
                        }
                        .font(.callout)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { stepsHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(stepsHeight, Self.maxStepsHeight))
                    // Rows arriving while the steps are open grow the tab instead of snapping it.
                    .animation(Chrome.panelSlide, value: stepsHeight)
                }
                .padding(.top, 6)
                .transition(.softAppear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, edge == .top ? 7 : 7 + Self.overlap)
        .padding(.bottom, edge == .top ? 7 + Self.overlap : 7)
        // A closed tab hugs its line like the changes tab; the steps open it to the queue's width.
        .frame(maxWidth: showsSteps ? 560 : nil)
        .glassEffect(.regular, in: shape)
        .contentShape(shape)
        .animation(.smooth(duration: 0.35), value: label)
        .animation(.smooth(duration: 0.2), value: canExpand)
        .animation(Chrome.panelSlide, value: showsSteps)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }

    /// The tool run in progress: the tools at the end of the running turn, back to its last
    /// reply. Thinking between them is skipped, the way the timeline groups them, so the tab
    /// shows exactly the run the timeline holds back while it runs.
    @MainActor
    static func liveWork(in entries: [TimelineEntry]) -> [TimelineEntry] {
        var run: [TimelineEntry] = []
        scan: for entry in entries.reversed() {
            switch entry.kind {
            case .tool:
                if let last = run.last, last.turnID != entry.turnID { break scan }
                run.append(entry)
            case .reasoning:
                continue
            default:
                break scan
            }
        }
        return run.reversed()
    }

    /// The running turn's thinking. Kind and turn are fixed at creation, so they are checked before
    /// any content is read.
    private var thinkingSteps: [ThinkingStep] {
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

/// One piece of the running turn's thinking, and whether it is still arriving.
struct ThinkingStep: Equatable {
    var text: String
    var isStreaming: Bool
}
