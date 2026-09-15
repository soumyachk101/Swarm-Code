import AppKit
import SwiftUI

/// How far a head has got, as one bar filling in from the left: a stave for each thing it
/// did, in order, the taller the more it changed. A read, a search or a lookup is short and
/// faint, a command taller, an edit taller still, and a reply stands full height in the
/// head's own colour. Under it, what that amounts to and how long the head has been at it.
/// The steps themselves are the sidebar's to show; here the shape of the work is enough.
///
/// The staves are one `Canvas`, redrawn on the display's clock while the head works: a new
/// stave rises over 0.45 s from the moment its entry arrived, and a soft highlight sweeps
/// the filled staves every 1.8 s. Once the head is done and its last stave is up, the clock
/// stops and the bar is drawn once. Past what the width holds, consecutive steps share a
/// stave, the tallest of them setting its height, so the bar always fits and keeps filling.
struct HydraProgressBar: View {
    let runtime: ThreadRuntime
    let startedAt: Date
    let finishedAt: Date?
    let status: HydraHeadInfo.Status
    /// The head's persona colour.
    let tint: Color

    @State private var width: CGFloat = 0
    /// The head is done and its last stave has risen: nothing left to animate.
    @State private var isSettled = false

    private static let height: CGFloat = 28
    private static let staveWidth: CGFloat = 3
    private static let gap: CGFloat = 2
    private static let pitch = staveWidth + gap
    /// How long a new stave takes to rise to its height.
    private static let rise: TimeInterval = 0.45
    /// One pass of the highlight across the filled staves.
    private static let sweep: TimeInterval = 1.8

    var body: some View {
        let events = Self.events(in: runtime.entries)
        let capacity = max(1, Int(((width + Self.gap) / Self.pitch).rounded(.down)))
        let staves = Self.staves(for: events, capacity: capacity)
        let counts = Counts(of: events)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let isRunning = status == .running
        let elapsed = RelativeTime.duration((isRunning ? Date.now : finishedAt ?? .now).timeIntervalSince(startedAt))
        VStack(alignment: .leading, spacing: 6) {
            // The display's clock drives the rise and the sweep; with reduced motion, or
            // once the head is done and settled, the canvas is drawn only when the steps change.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || isSettled)) { context in
                Canvas { graphics, size in
                    Self.draw(
                        staves,
                        in: &graphics,
                        size: size,
                        capacity: capacity,
                        at: context.date,
                        rising: !reduceMotion,
                        sweeping: isRunning && !reduceMotion,
                        status: status,
                        tint: tint
                    )
                }
            }
            .frame(height: Self.height)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: counts.line)
                Spacer(minLength: 8)
                if isRunning {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(verbatim: RelativeTime.duration(context.date.timeIntervalSince(startedAt)))
                            .monospacedDigit()
                    }
                } else {
                    Text(verbatim: elapsed)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Chrome.secondaryText)
        }
        // A finished head's last stave still needs its rise before the clock can stop.
        .task(id: isRunning ? -1 : events.count) {
            isSettled = false
            guard !isRunning else { return }
            guard (try? await Task.sleep(for: .seconds(Self.rise + 0.1))) != nil else { return }
            isSettled = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(counts.sentence), \(elapsed)\(isRunning ? " so far" : "")"))
    }

    // MARK: - Steps

    /// One thing the head did, as the bar shows it.
    private struct Stave {
        enum Kind {
            /// A read, a search, the web, an MCP tool, a helper: looking, not changing.
            case lookup
            case command
            case edit
            case reply
        }

        let kind: Kind
        let arrivedAt: Date

        /// The stave's share of the bar's height.
        var height: CGFloat {
            switch kind {
            case .lookup: 0.45
            case .command: 0.65
            case .edit: 0.85
            case .reply: 1
            }
        }
    }

    /// What the bar counts, for the line under it and the accessibility label.
    private struct Counts {
        var edits = 0
        var commands = 0
        var reads = 0

        init(of events: [Stave]) {
            for event in events {
                switch event.kind {
                case .edit: edits += 1
                case .command: commands += 1
                case .lookup: reads += 1
                case .reply: break
                }
            }
        }

        private var parts: [String] {
            var parts: [String] = []
            if edits > 0 { parts.append("\(edits) \(edits == 1 ? "edit" : "edits")") }
            if commands > 0 { parts.append("\(commands) \(commands == 1 ? "command" : "commands")") }
            if reads > 0 { parts.append("\(reads) \(reads == 1 ? "read" : "reads")") }
            return parts
        }

        /// "3 edits · 2 commands · 5 reads", the zero parts left out.
        var line: String { parts.joined(separator: " · ") }

        var sentence: String {
            parts.isEmpty ? "Nothing done yet" : parts.joined(separator: ", ")
        }
    }

    /// One stave per tool call and per reply, in the order they happened.
    private static func events(in entries: [TimelineEntry]) -> [Stave] {
        entries.compactMap { entry in
            switch entry.kind {
            case .tool:
                guard case .tool(let call) = entry.item.content else { return nil }
                let kind: Stave.Kind = switch call.kind {
                case .edit: .edit
                case .command: .command
                default: call.edits.isEmpty ? .lookup : .edit
                }
                return Stave(kind: kind, arrivedAt: entry.item.date)
            case .assistant:
                return Stave(kind: .reply, arrivedAt: entry.item.date)
            default:
                return nil
            }
        }
    }

    /// The staves the bar draws: the events themselves while they fit, else consecutive
    /// runs of them, each run's stave as tall as its tallest member. A run is as old as
    /// its first member, so its stave rises once, when the run opens, and only grows after.
    private static func staves(for events: [Stave], capacity: Int) -> [Stave] {
        guard events.count > capacity else { return events }
        let run = Int((Double(events.count) / Double(capacity)).rounded(.up))
        return stride(from: 0, to: events.count, by: run).map { start in
            let bucket = events[start..<min(start + run, events.count)]
            let tallest = bucket.max { $0.height < $1.height } ?? events[start]
            return Stave(kind: tallest.kind, arrivedAt: events[start].arrivedAt)
        }
    }

    // MARK: - Drawing

    private static func color(for kind: Stave.Kind, tint: Color) -> Color {
        switch kind {
        case .edit, .reply: tint
        case .command: tint.opacity(0.7)
        case .lookup: tint.opacity(0.4)
        }
    }

    /// One pass over the staves: each filled from the baseline up, the newest still rising,
    /// faint slots where the bar has yet to fill, and the highlight over what is filled.
    private static func draw(
        _ staves: [Stave],
        in context: inout GraphicsContext,
        size: CGSize,
        capacity: Int,
        at date: Date,
        rising: Bool,
        sweeping: Bool,
        status: HydraHeadInfo.Status,
        tint: Color
    ) {
        let bottom = size.height
        var filled = Path()
        for (index, stave) in staves.enumerated() {
            var factor: CGFloat = 1
            if rising {
                let age = date.timeIntervalSince(stave.arrivedAt)
                if age < rise {
                    // Eased out, like the smooth curve the rest of the panel moves on.
                    let t = max(0, age / rise)
                    factor = 1 - pow(1 - t, 3)
                }
            }
            let height = bottom * stave.height * factor
            guard height > 0 else { continue }
            let rect = CGRect(x: CGFloat(index) * pitch, y: bottom - height, width: staveWidth, height: height)
            let path = Path(roundedRect: rect, cornerRadius: staveWidth / 2)
            // The last stave is where a head that failed or was stopped ended.
            let isLast = index == staves.count - 1
            let color: Color = if isLast, status == .failed {
                Chrome.danger
            } else if isLast, status == .stopped {
                Chrome.secondaryText
            } else {
                color(for: stave.kind, tint: tint)
            }
            context.fill(path, with: .color(color))
            filled.addPath(path)
        }

        if staves.count < capacity {
            let height = bottom * 0.45
            var slots = Path()
            for slot in staves.count..<capacity {
                slots.addRoundedRect(
                    in: CGRect(x: CGFloat(slot) * pitch, y: bottom - height, width: staveWidth, height: height),
                    cornerSize: CGSize(width: staveWidth / 2, height: staveWidth / 2)
                )
            }
            context.fill(slots, with: .color(Chrome.overlay(0.06)))
        }

        guard sweeping, !staves.isEmpty else { return }
        // A soft band crossing the filled staves, left to right, once every sweep; clipped
        // to the staves, so the slots and the gaps stay as they are.
        let filledWidth = CGFloat(staves.count) * pitch - gap
        let band = max(24, filledWidth / 3)
        let phase = CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: sweep) / sweep)
        let x = -band + phase * (filledWidth + band)
        var highlight = context
        highlight.clip(to: filled)
        highlight.fill(
            Path(CGRect(x: x, y: 0, width: band, height: bottom)),
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)]),
                startPoint: CGPoint(x: x, y: 0),
                endPoint: CGPoint(x: x + band, y: 0)
            )
        )
    }
}

/// A head's panel with "Show what heads are doing" off: what it was sent to do and the
/// progress bar, centred where the transcript would be.
struct HydraHeadProgress: View {
    let head: ChatThread
    let runtime: ThreadRuntime

    var body: some View {
        let info = head.hydra
        let task = info?.task.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: task.isEmpty ? head.title : task)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HydraProgressBar(
                runtime: runtime,
                startedAt: info?.startedAt ?? head.createdAt,
                finishedAt: info?.finishedAt,
                status: info?.status ?? .running,
                tint: (info?.persona ?? HydraRoster.persona(at: 0)).color
            )
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
