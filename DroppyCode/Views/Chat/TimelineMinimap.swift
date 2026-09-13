import AppKit
import SwiftUI

/// One tick in the conversation outline. Titles come from the block's own
/// content (user prompt, reply preview, tool verb, "Worked for …"), so the
/// rail reads as a miniature table of contents for the thread.
struct TimelineMinimapEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let snippet: String
    /// 0…1, drives the tick width. Long replies read wide, short notices narrow.
    let weight: Double
}

enum TimelineMinimap {
    @MainActor
    static func entries(for blocks: [DisplayBlock]) -> [TimelineMinimapEntry] {
        blocks.map(entry(for:))
    }

    @MainActor
    private static func entry(for block: DisplayBlock) -> TimelineMinimapEntry {
        switch block {
        case .turn(let id, _, let userEntries, let content, let summary):
            let prompt = userEntries.compactMap { userText(of: $0) }.first ?? ""
            let reply = content.compactMap { assistantText(of: $0) }.last { !$0.isEmpty } ?? ""
            let title = firstWords(prompt, limit: 8)
            let snippet = reply.isEmpty
                ? TurnEndRow.label(for: summary) + fileSuffix(summary)
                : preview(reply)
            return TimelineMinimapEntry(
                id: id,
                title: title.isEmpty ? "Reply" : title,
                snippet: snippet,
                weight: weight(of: prompt + reply)
            )
        case .group(.single(let entry)):
            return singleEntry(entry)
        case .group(.work(let id, let entries, _)):
            let first = entries.first.flatMap { toolLabel(of: $0) } ?? ""
            let last = entries.last.flatMap { toolLabel(of: $0) } ?? ""
            let snippet = first == last || last.isEmpty ? first : first + " … " + last
            return TimelineMinimapEntry(
                id: id,
                title: "\(entries.count) steps",
                snippet: snippet,
                weight: 0.45
            )
        }
    }

    @MainActor
    private static func singleEntry(_ entry: TimelineEntry) -> TimelineMinimapEntry {
        switch entry.item.content {
        case .user(let message):
            return TimelineMinimapEntry(
                id: entry.id,
                title: nonEmpty(firstWords(message.text, limit: 8), fallback: "Message"),
                snippet: preview(message.text),
                weight: weight(of: message.text)
            )
        case .assistant(let message):
            return TimelineMinimapEntry(
                id: entry.id,
                title: nonEmpty(firstWords(message.text, limit: 8), fallback: "Reply"),
                snippet: preview(message.text),
                weight: weight(of: message.text)
            )
        case .tool(let call):
            return TimelineMinimapEntry(
                id: entry.id,
                title: ToolPresentation.verb(for: call) + " " + call.title,
                snippet: preview(call.detail ?? ""),
                weight: 0.3
            )
        case .plan(let plan):
            return TimelineMinimapEntry(
                id: entry.id,
                title: "Plan",
                snippet: preview(plan.markdown),
                weight: 0.3
            )
        case .todos(let steps):
            let done = steps.count { $0.status == .done }
            return TimelineMinimapEntry(
                id: entry.id,
                title: "\(done) of \(steps.count) done",
                snippet: steps.first.map { preview($0.text) } ?? "",
                weight: 0.3
            )
        case .notice(let notice):
            return TimelineMinimapEntry(
                id: entry.id,
                title: nonEmpty(firstWords(notice.message, limit: 8), fallback: "Notice"),
                snippet: preview(notice.message),
                weight: 0.2
            )
        case .turnEnd(let summary):
            return TimelineMinimapEntry(
                id: entry.id,
                title: TurnEndRow.label(for: summary),
                snippet: "",
                weight: 0.15
            )
        case .reasoning:
            return TimelineMinimapEntry(id: entry.id, title: "Thinking", snippet: "", weight: 0.15)
        }
    }

    @MainActor
    private static func userText(of entry: TimelineEntry) -> String? {
        guard case .user(let message) = entry.item.content, !message.text.isEmpty else { return nil }
        return message.text
    }

    @MainActor
    private static func assistantText(of entry: TimelineEntry) -> String? {
        guard case .assistant(let message) = entry.item.content else { return nil }
        return message.text
    }

    @MainActor
    private static func toolLabel(of entry: TimelineEntry) -> String? {
        guard case .tool(let call) = entry.item.content else { return nil }
        return ToolPresentation.verb(for: call) + " " + call.title
    }

    private static func fileSuffix(_ summary: TurnSummary) -> String {
        guard summary.filesChanged > 0 else { return "" }
        return summary.filesChanged == 1 ? " · 1 file" : " · \(summary.filesChanged) files"
    }

    private static func firstWords(_ text: String, limit: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return "" }
        let head = words.prefix(limit).joined(separator: " ")
        return words.count > limit ? head + "…" : head
    }

    private static func preview(_ text: String, limit: Int = 160) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)) + "…"
    }

    private static func weight(of text: String) -> Double {
        min(1, max(0.15, Double(text.count) / 420))
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        value.isEmpty ? fallback : value
    }
}

/// Builds the outline in its own body. The titles read message text, so building them in the
/// timeline's body made the whole conversation re-render on every streamed token; here only
/// the rail does.
struct TimelineMinimapColumn: View {
    let blocks: [DisplayBlock]
    var selectedID: String?
    var onNavigate: (String, Bool) -> Void

    var body: some View {
        TimelineMinimapRail(
            entries: TimelineMinimap.entries(for: blocks),
            selectedID: selectedID,
            onNavigate: onNavigate
        )
    }
}

/// Slim rail on the left edge of the chat: one tick per conversation block,
/// a preview bubble on hover, tap or drag to jump. Mounted for the whole
/// life of a thread, so it costs nothing at rest: no timers, no continuous
/// animation, plain rects only, and the bubble mounts solely while hovering.
struct TimelineMinimapRail: View {
    let entries: [TimelineMinimapEntry]
    var selectedID: String?
    /// Live scrub reports `animated: false` (the timeline tracks 1:1);
    /// release reports `true` (one glide to the landing block).
    var onNavigate: (String, Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tick under the pointer, nil once the pointer leaves the rail.
    @State private var hoveredID: String?
    /// True while a press is down on the rail (tap or scrub).
    @State private var isPressing = false
    /// Whether this view owns a pushed pointing-hand cursor, so a
    /// disappear-while-hovering pops exactly once.
    @State private var ownsCursorPush = false

    private var isExpanded: Bool { hoveredID != nil || isPressing }
    private var baseOpacity: Double { isExpanded ? 0.4 : 0.25 }
    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.22)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = MinimapRailMetrics(height: proxy.size.height, count: entries.count)
            ZStack(alignment: .leading) {
                // Full-height hit area so a scrub never drops between ticks.
                Color.clear
                    .contentShape(.rect)

                ticks(metrics: metrics)
                    .allowsHitTesting(false)

                if let hovered = hoveredEntry {
                    previewBubble(for: hovered, metrics: metrics, railHeight: proxy.size.height)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .offset(x: reduceMotion ? 0 : -6)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onHover { hovering in
                if hovering {
                    if !ownsCursorPush {
                        NSCursor.pointingHand.push()
                        ownsCursorPush = true
                    }
                } else {
                    releaseCursor()
                    hoveredID = nil
                }
            }
            .onDisappear { releaseCursor() }
            .gesture(scrubGesture(metrics: metrics))
        }
        .animation(hoverAnimation, value: hoveredID)
        .animation(hoverAnimation, value: isPressing)
        .animation(hoverAnimation, value: selectedID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation outline")
    }

    private func releaseCursor() {
        guard ownsCursorPush else { return }
        NSCursor.pop()
        ownsCursorPush = false
    }

    @ViewBuilder
    private func ticks(metrics: MinimapRailMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            ForEach(entries) { entry in
                tick(for: entry)
            }
        }
        .padding(.top, metrics.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func tick(for entry: TimelineMinimapEntry) -> some View {
        let isSelected = entry.id == selectedID
        let isHovered = entry.id == hoveredID
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(.primary.opacity(isHovered ? 0.95 : (isSelected ? 0.8 : baseOpacity)))
            .frame(width: tickWidth(for: entry, isHovered: isHovered, isSelected: isSelected), height: 2)
            .padding(.leading, 8)
            .accessibilityElement()
            .accessibilityLabel(entry.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onNavigate(entry.id, true) }
    }

    private func tickWidth(for entry: TimelineMinimapEntry, isHovered: Bool, isSelected: Bool) -> CGFloat {
        // 10 pt narrowest, 26 pt widest. Hovered and selected ticks punch
        // out to full width so the eye finds them while scrubbing.
        let base = 10 + CGFloat(entry.weight) * 12
        if isHovered || isSelected { return 26 }
        return isExpanded ? min(26, base + 2) : base
    }

    private var hoveredEntry: TimelineMinimapEntry? {
        guard let hoveredID else { return nil }
        return entries.first { $0.id == hoveredID }
    }

    @ViewBuilder
    private func previewBubble(
        for entry: TimelineMinimapEntry,
        metrics: MinimapRailMetrics,
        railHeight: CGFloat
    ) -> some View {
        let tickCenterY = metrics.centerY(for: indexOf(entry))
        // Estimated half height keeps the bubble inside the rail without a
        // measurement loop (measuring would re-lay-out on every hover
        // change). Covers a one-line title plus three snippet lines.
        let clampedY = min(max(tickCenterY, 56), max(56, railHeight - 56))
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                if !entry.snippet.isEmpty {
                    Text(entry.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 300, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            Spacer(minLength: 0)
        }
        .padding(.leading, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .offset(y: clampedY - railHeight / 2)
    }

    private func indexOf(_ entry: TimelineMinimapEntry) -> Int {
        entries.firstIndex(of: entry) ?? 0
    }

    private func scrubGesture(metrics: MinimapRailMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isPressing = true
                guard let id = metrics.entryID(at: value.location.y, entries: entries) else { return }
                if hoveredID != id {
                    hoveredID = id
                    onNavigate(id, false)
                }
            }
            .onEnded { value in
                isPressing = false
                if let id = metrics.entryID(at: value.location.y, entries: entries) {
                    hoveredID = id
                    onNavigate(id, true)
                }
            }
    }
}

/// Pure rail geometry, shared by the gesture and the bubble so Y always maps
/// to the same entry. Ticks center vertically; pitch only shrinks when the
/// thread holds more blocks than the rail fits.
private struct MinimapRailMetrics {
    let spacing: CGFloat
    let topInset: CGFloat

    init(height: CGFloat, count: Int) {
        guard count > 0, height > 0 else {
            spacing = 8
            topInset = 0
            return
        }
        let needed = CGFloat(count) * 2 + CGFloat(count - 1) * 8
        if needed <= height {
            spacing = 8
            topInset = (height - needed) / 2
        } else {
            let squeezed = max(4, (height - CGFloat(count) * 2) / CGFloat(max(1, count - 1)))
            spacing = min(8, squeezed)
            topInset = 0
        }
    }

    private var pitch: CGFloat { 2 + spacing }

    func centerY(for index: Int) -> CGFloat {
        topInset + CGFloat(index) * pitch + 1
    }

    func entryID(at y: CGFloat, entries: [TimelineMinimapEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        let raw = (y - topInset - 1 + pitch / 2) / pitch
        let clamped = min(max(Int(raw.rounded(.down)), 0), entries.count - 1)
        return entries[clamped].id
    }
}
