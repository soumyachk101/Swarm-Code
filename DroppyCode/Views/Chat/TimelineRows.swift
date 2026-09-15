import AppKit
import SwiftUI

/// The timeline's shared geometry. One vertical rhythm governs every pair of rows —
/// reply to reply, reply to work line, work line to row — so the distance between
/// text and the steps never varies. A message's hover controls sit inside that gap
/// rather than widening it.
enum TimelineMetrics {
    /// The gap between any two consecutive rows in the timeline.
    static let rowSpacing: CGFloat = 20
    /// The room a message keeps for its hover line (copy, revert). Reserved inside
    /// the row so showing the controls never moves text, then subtracted from the
    /// row's own height so they fill the gap below instead of adding to it.
    static let hoverLineHeight: CGFloat = 22
    /// The icon column every transcript row starts with. Rows carry no leading inset,
    /// so the column sits on the reply text's own x and all labels line up after it.
    static let iconWidth: CGFloat = 16
    static let iconSpacing: CGFloat = 8
}

struct UserMessageRow: View {
    let entry: TimelineEntry
    let runtime: ThreadRuntime
    /// Whether the message's turn can be reverted right now. Decided by the timeline, which
    /// reads the provider and the turn list once for every row.
    let canRevert: Bool

    @State private var isHovering = false
    @State private var isConfirmingRevert = false

    var body: some View {
        if case .user(let message) = entry.item.content, message.isFromHydra {
            HydraReportRow(message: message)
        } else if case .user(let message) = entry.item.content {
            VStack(alignment: .trailing, spacing: 6) {
                if !message.attachments.isEmpty {
                    AttachmentStrip(attachments: message.attachments)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .textSelection(.enabled)
                        .padding(.leading, 14)
                        // The tail hangs past the body; the text keeps its inset from the body.
                        .padding(.trailing, 14 + UserBubble.tail)
                        .padding(.vertical, 9)
                        .background(.tint.opacity(0.14), in: UserBubble())
                }
                HStack(spacing: 2) {
                    if canRevert {
                        Button {
                            isConfirmingRevert = true
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .frame(width: 22, height: 22)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Edit from here")
                    }
                    CopyButton(text: message.text)
                }
                .opacity(isHovering ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 96)
            // The binding alone, so the hover responder never keeps this row (and its
            // message) alive after it scrolls away.
            .onHover { [hovering = $isHovering] in hovering.wrappedValue = $0 }
            // The room for the hover line lives inside the row but is taken back out
            // of its height, so the controls show up in the gap to the next row and
            // that gap stays the same whether or not they are showing. (6 = the
            // VStack's spacing above them.)
            .padding(.bottom, -(TimelineMetrics.hoverLineHeight + 6))
            .confirmationDialog("Edit from this message?", isPresented: $isConfirmingRevert) {
                Button("Revert and keep file changes") { revert(restoreFiles: false) }
                Button("Revert files too", role: .destructive) { revert(restoreFiles: true) }
            } message: {
                Text("This message and everything after it leave the thread, and your prompt returns to the composer.")
            }
        }
    }

    private func revert(restoreFiles: Bool) {
        guard let turnID = entry.turnID else { return }
        Task { await runtime.revert(to: turnID, restoreFiles: restoreFiles) }
    }
}

/// Heads reporting back to their lead: their glyphs and names on a line, and their reports
/// in a popover off it. It sits on the user's side, since that is where the lead reads it from,
/// but reads as the team's, not the user's. A note from Hydra itself (heads held back, the
/// team's work merged) takes the same row with the Hydra mark in the glyphs' place; a note
/// that leads with the merge request's address links to it from the pill.
struct HydraReportRow: View {
    @Environment(\.chatZoom) private var zoom
    let message: UserMessage

    @State private var isShowingReport = false

    var body: some View {
        let personas = (message.hydraHeads ?? []).map(HydraRoster.persona(at:))
        let names = personas.map(\.name)
        let who = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        // A note from Hydra itself says what it is on its first line; the rest is the message.
        // That line ends like a sentence, and the pill reads it as a label.
        // A heads' report keeps its full text for the popover, but the pill reads a
        // short human summary with the heads first, never the file-heavy detail.
        let parts = message.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        let title = personas.isEmpty ? Self.withoutTrailingStop(String(parts.first ?? "Hydra")) : Self.reportSummary(who: who, text: message.text)
        let body = personas.isEmpty ? String(parts.count > 1 ? parts[1] : "").trimmingCharacters(in: .whitespacesAndNewlines) : message.text
        // A merge note puts the merge request's address on the body's first line: that becomes
        // a link on the pill, and the chevron stays only for what the note says after it.
        let link = personas.isEmpty ? Self.leadingURL(in: body) : nil
        let details = link == nil ? body : Self.withoutFirstLine(body)
        Button {
            guard !details.isEmpty else { return }
            isShowingReport.toggle()
        } label: {
            HStack(spacing: 8) {
                // The mark takes a glyph's slot, so both rows sit the same in the pill.
                // (Only one or the other: an empty stack would still keep its spacing.)
                if personas.isEmpty {
                    HydraMarkImage()
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 18, height: 18)
                } else {
                    HStack(spacing: -4) {
                        ForEach(Array(personas.enumerated()), id: \.offset) { _, persona in
                            HydraGlyph(persona: persona, size: 18)
                        }
                    }
                }
                Text(verbatim: title)
                    .font(.chat(.callout, weight: .medium, zoom: zoom))
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let link {
                    Link(destination: link) {
                        Text("Open")
                            .font(.chat(.caption, weight: .semibold, zoom: zoom))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                    .help("Open in the browser")
                }
                if !details.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The pill stays live for its link when there is nothing more to open.
        .disabled(details.isEmpty && link == nil)
        .help(details.isEmpty ? "" : "Show the message")
        .popover(isPresented: $isShowingReport, arrowEdge: .bottom) {
            HydraReportPopover(text: body)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 96)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    /// The title without the one full stop a note's first line ends on.
    private static func withoutTrailingStop(_ title: String) -> String {
        title.hasSuffix(".") ? String(title.dropLast()) : title
    }

    /// The pill for heads reporting back: the heads first, then what they did in
    /// a few words. Tasks come from the report's own `## Name: task` sections,
    /// so landing lines and file counts stay in the popover. Falls back to the
    /// first line that is not report scaffolding, and only then to "reported back".
    private static func reportSummary(who: String, text: String) -> String {
        let tasks = reportTasks(in: text)
        if !tasks.isEmpty {
            let joined = tasks.joined(separator: "; ")
            return TextCleanup.singleLine("\(who): \(joined)", limit: 140)
        }
        if let line = firstSummaryLine(in: text) {
            return TextCleanup.singleLine("\(who): \(line)", limit: 140)
        }
        if text.split(whereSeparator: \.isNewline).contains(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("changed nothing")
        }) {
            return TextCleanup.singleLine("\(who): changed nothing", limit: 140)
        }
        return TextCleanup.singleLine("\(who) reported back", limit: 140)
    }

    /// One short task per `## Name: task (outcome) (took)` section, in order.
    private static func reportTasks(in text: String) -> [String] {
        var tasks: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("## ") else { continue }
            var task = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let colon = task.firstIndex(of: ":") {
                task = String(task[task.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            task = withoutTrailingParentheticals(task)
            task = TextCleanup.singleLine(task, limit: 60).trimmingCharacters(in: .whitespacesAndNewlines)
            if !task.isEmpty { tasks.append(task) }
        }
        return tasks
    }

    /// The outcome and effort suffixes (`(failed)`, `(2 tools)`, `(1m 3s, 4 tools)`)
    /// off the end of a section's task.
    private static func withoutTrailingParentheticals(_ task: String) -> String {
        var result = task.trimmingCharacters(in: .whitespaces)
        while result.hasSuffix(")"), let open = result.lastIndex(of: "(") {
            let inner = String(result[result.index(after: open)..<result.index(before: result.endIndex)])
            guard !inner.isEmpty, !inner.contains(where: { $0.isNewline }),
                  inner.range(of: #"(failed|stopped|tool|\ds|\dm )"#, options: .regularExpression) != nil
            else { break }
            result = String(result[..<open]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// The first line worth saying out loud: not the "Hydra reports:" opening,
    /// a section header, a landing or file-count line, or report scaffolding.
    private static func firstSummaryLine(in text: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("## "), !line.hasPrefix("#"),
                  line != "No report." else { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("hydra reports:") || lower.hasPrefix("landed in your checkout:")
                || lower == "changed nothing." || lower.hasPrefix("did not land")
                || lower.hasPrefix("nothing landed") || lower.hasPrefix("the changes listed above")
                || lower.hasPrefix("the heads worked in your checkout") || lower.hasPrefix("do not check")
                || lower.hasPrefix("do not wait") { continue }
            // A bare file line (`path (+a −d)`) or bullet is detail, not summary.
            if line.range(of: #"\(\+\d+.*−\d+\)"#, options: .regularExpression) != nil { continue }
            if line.hasPrefix("- ") || line.hasPrefix("· ") { continue }
            return TextCleanup.singleLine(line, limit: 80)
        }
        return nil
    }

    /// The address on the body's first line, when that line is an address and nothing else.
    private static func leadingURL(in body: String) -> URL? {
        guard let line = body.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces),
              line.lowercased().hasPrefix("http://") || line.lowercased().hasPrefix("https://"),
              !line.contains(where: \.isWhitespace) else { return nil }
        return URL(string: line)
    }

    /// The body past its first line: what a note says after the address it leads with.
    private static func withoutFirstLine(_ body: String) -> String {
        guard let newline = body.firstIndex(where: \.isNewline) else { return "" }
        return String(body[newline...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The heads still out on the lead's behalf: who they are, working, until they report back.
/// The report pill's twin while the work is still on.
struct HydraHeadsWorkingRow: View {
    @Environment(\.chatZoom) private var zoom
    let heads: [Int]
    let runtime: ThreadRuntime

    var body: some View {
        let personas = heads.map(HydraRoster.persona(at:))
        let names = personas.map(\.name)
        let who: String = {
            if names.isEmpty { return "" }
            if names.count == 1 { return names[0] }
            return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }()
        let title = names.isEmpty ? "Heads are working" : "\(who) \(names.count == 1 ? "is" : "are") working"
        HStack(spacing: 8) {
            HStack(spacing: -4) {
                ForEach(Array(personas.enumerated()), id: \.offset) { _, persona in
                    HydraGlyph(persona: persona, size: 18, isRunning: true)
                }
            }
            Text(verbatim: title)
                .font(.chat(.callout, weight: .medium, zoom: zoom))
                .foregroundStyle(Chrome.primaryText.opacity(0.9))
                .modifier(HydraShimmer())
                .contentTransition(.opacity)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.smooth(duration: 0.3), value: heads)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 96)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
    }
}

/// A shimmer sweeping across the content on a loop: a narrow bright band sliding
/// left to right, masked to the content itself. Still when reduced motion is on.
private struct HydraShimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            content
        } else {
            // The band lives in a layer the size of the text and is masked to the text
            // there: masking the band alone would cut the text to the band's own width.
            let band = max(24, width / 3)
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .overlay {
                    Color.clear
                        .overlay(alignment: .leading) {
                            LinearGradient(
                                stops: [
                                    .init(color: Chrome.primaryText.opacity(0), location: 0),
                                    .init(color: Chrome.primaryText.opacity(0.9), location: 0.5),
                                    .init(color: Chrome.primaryText.opacity(0), location: 1),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: band)
                            .offset(x: -band + phase * (width + band))
                        }
                        .mask { content }
                        .allowsHitTesting(false)
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }
}

/// A head's report in the popover its pill opens: the markdown at reading width, scrolling
/// past the panel's height rather than pushing the timeline apart.
private struct HydraReportPopover: View {
    let text: String

    var body: some View {
        ScrollView {
            MarkdownView(text: text)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 440)
        .frame(idealHeight: 320, maxHeight: 460)
    }
}

/// The lead's delegation block, the fenced `hydra` JSON at the end of its reply, as the
/// card it stands for: the mark, how many heads are going out and the task each one gets.
/// Never the JSON itself. While the block is still streaming, or when it cannot be read,
/// the card says the briefs are being written and nothing more.
struct HydraDelegationBlock: View {
    @Environment(\.chatZoom) private var zoom
    let json: String

    var body: some View {
        let tasks = Self.tasks(in: json)
        // The mark and the title share a line; the tasks run under both, flush with the
        // mark, so the list reads from the card's own left edge.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: TimelineMetrics.iconSpacing) {
                HydraMarkImage()
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                if tasks.isEmpty {
                    Text("Writing the heads' briefs…")
                        .font(.chat(.callout, zoom: zoom))
                        .foregroundStyle(Chrome.secondaryText)
                } else {
                    Text(tasks.count == 1 ? "Sending out a head" : "Sending out \(tasks.count) heads")
                        .font(.chat(.callout, weight: .medium, zoom: zoom))
                }
            }
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                        Text(verbatim: "· " + task)
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// What each head is given, in the block's order: its task, or the start of its prompt
    /// when it has none (as `HydraPrompts.delegations(in:)` titles it). Nothing until the
    /// JSON is whole and holds at least one head.
    private static func tasks(in json: String) -> [String] {
        guard let parsed = JSONValue.parse(json) else { return [] }
        let entries: [JSONValue] = parsed.array ?? (parsed.object == nil ? [] : [parsed])
        return entries.compactMap { entry -> String? in
            let task = entry["task"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !task.isEmpty { return task }
            let prompt = entry["prompt"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return prompt.isEmpty ? nil : TextCleanup.singleLine(prompt, limit: 60)
        }
    }
}

/// The team's work on its way to the remote once the lead has finished, in the report
/// pill's own frame: the mark, the spinner, the stage the merge is at right now (the same
/// words the sidebar shows), with how long it has been at it. The timeline appends the
/// pill while the merge runs and drops it when the note about the outcome lands, so the
/// merging state reads inside the exact pill that then morphs into the merged report,
/// with no second row. It holds no condition of its own.
struct HydraMergingRow: View {
    @Environment(\.chatZoom) private var zoom
    let runtime: ThreadRuntime
    @State private var now = Date.now

    /// The one motion for the stage's words changing.
    private static let change = Animation.smooth(duration: 0.3)

    var body: some View {
        // The same stage words the sidebar shows beside its own spinner.
        let stage = (runtime.hydraMergeStage ?? "Merging") + "…"
        let elapsed = now.timeIntervalSince(runtime.hydraMergeStartedAt ?? now)
        HStack(spacing: 8) {
            HydraMarkImage()
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            WorkingSpinner(cellSize: 3)
                .frame(width: 14)
            Text(verbatim: stage)
                .font(.chat(.callout, weight: .medium, zoom: zoom))
                .foregroundStyle(Chrome.primaryText.opacity(0.9))
                .modifier(HydraShimmer())
                .contentTransition(.opacity)
            Text(RelativeTime.duration(elapsed))
                .font(.chat(.caption, zoom: zoom))
                .foregroundStyle(Chrome.secondaryText)
                .monospacedDigit()
        }
        .animation(Self.change, value: stage)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 96)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Merging the team's work: \(stage)"))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }
}

/// iMessage's outgoing bubble: rounded on three corners, the bottom-right one drawn out into
/// the little tail that curls back under the bubble. The shape only; the fill is the row's.
/// The tail's tip sits `tail` points past the body's trailing edge, at the very bottom.
struct UserBubble: Shape {
    static let cornerRadius: CGFloat = 18
    static let tail: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let r = Self.cornerRadius
        let left = rect.minX
        let top = rect.minY
        let bottom = rect.maxY
        // The body's trailing edge; the tail reaches past it.
        let edge = rect.maxX - Self.tail
        var path = Path()
        path.move(to: CGPoint(x: left + r, y: top))
        path.addLine(to: CGPoint(x: edge - r, y: top))
        path.addArc(center: CGPoint(x: edge - r, y: top + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: edge, y: bottom - 11))
        // Out to the tip at the bottom corner, then curling back in under the body and
        // easing into the bottom edge.
        path.addCurve(
            to: CGPoint(x: edge + Self.tail, y: bottom),
            control1: CGPoint(x: edge, y: bottom - 1),
            control2: CGPoint(x: edge + Self.tail, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: edge - 7, y: bottom - 4),
            control1: CGPoint(x: edge, y: bottom + 0.5),
            control2: CGPoint(x: edge - 4, y: bottom - 1)
        )
        path.addCurve(
            to: CGPoint(x: edge - 21, y: bottom),
            control1: CGPoint(x: edge - 12, y: bottom),
            control2: CGPoint(x: edge - 16, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + r, y: bottom))
        path.addArc(center: CGPoint(x: left + r, y: bottom - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: left, y: top + r))
        path.addArc(center: CGPoint(x: left + r, y: top + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct AttachmentStrip: View {
    let attachments: [Attachment]

    /// One preview panel for the strip, so every photo opens in a single tap no matter
    /// how many are attached, and made on the first tap rather than with the row.
    @State private var preview = AttachmentPreviewSlot()

    var body: some View {
        // Weak/box captures only: hover responders and anchor views must not keep this
        // strip (and its panel) alive after it scrolls away.
        let slot = preview
        // A plain stack hugs the thumbnails, so a trailing-aligned row keeps the
        // photos over the bubble — and the anchor view fills just the photos.
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                AttachmentThumbnail(attachment: attachment, preview: preview)
                    .help(attachment.name)
            }
        }
        .background {
            AttachmentAnchorCapture { [weak slot] in slot?.setAnchor($0) }
        }
        .onDisappear { [weak slot] in slot?.close() }
    }
}

struct AttachmentThumbnail: View {
    @Environment(\.chatZoom) private var zoom
    let attachment: Attachment
    var size: CGFloat = 56
    /// The panel the photo opens in: either a slot, which makes its panel on the first
    /// tap, or one the caller already holds. A strip that scrolls with the conversation
    /// wants the slot; the composer's own strips, which are made once, take either.
    private let slot: AttachmentPreviewSlot?
    private let panel: AttachmentPreviewCoordinator?

    @State private var image: CGImage?
    /// The thumbnail's own NSView, handed to the panel on tap so the arrow
    /// lands on the tapped photo rather than the strip's middle. Mounted once the
    /// pointer has been on the photo: a tap always follows a hover, and a strip
    /// scrolling past should not be building views for a tap that never comes.
    @State private var ownAnchor = WeakView()
    @State private var needsAnchor = false

    init(attachment: Attachment, size: CGFloat = 56, preview: AttachmentPreviewSlot) {
        self.init(attachment: attachment, size: size, slot: preview, panel: nil)
    }

    init(attachment: Attachment, size: CGFloat = 56, preview: AttachmentPreviewCoordinator) {
        self.init(attachment: attachment, size: size, slot: nil, panel: preview)
    }

    private init(attachment: Attachment, size: CGFloat, slot: AttachmentPreviewSlot?, panel: AttachmentPreviewCoordinator?) {
        self.attachment = attachment
        self.size = size
        self.slot = slot
        self.panel = panel
        // A photo shown before starts out drawn, so scrolling back to it never fades it in again.
        _image = State(initialValue: attachment.isImage ? ThumbnailMemory.image(for: attachment.path, pointSize: size) : nil)
    }

    /// Opens (or closes) the panel for this photo, making one only now if the caller
    /// handed over a slot.
    private func togglePanel() {
        if let slot {
            slot.panel.toggle(attachment, over: ownAnchor.value)
        } else {
            panel?.toggle(attachment, over: ownAnchor.value)
        }
    }

    var body: some View {
        // The anchor box alone: the hover responder and the anchor view must not keep
        // this row (and its attachment) alive after it scrolls away.
        let anchorBox = ownAnchor
        Button {
            togglePanel()
        } label: {
            if attachment.isImage {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.quaternary.opacity(0.6))
                    if let image {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
            } else if attachment.isVideo {
                AttachmentVideoThumbnail(attachment: attachment, size: size)
            } else {
                VStack(spacing: 3) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(attachment.name)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .font(.chat(.caption, zoom: zoom))
                .padding(.horizontal, 6)
                .frame(width: size, height: size)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        // The .fill image is drawn wider than the cell before it is clipped;
        // pinning the hit shape to the cell keeps the neighbour's remove badge
        // reachable no matter how hit-testing treats the overflow.
        .contentShape(.rect(cornerRadius: 12, style: .continuous))
        .onHover { [needed = $needsAnchor] hovering in
            if hovering, !needed.wrappedValue { needed.wrappedValue = true }
        }
        .background {
            if needsAnchor {
                AttachmentAnchorCapture { [weak anchorBox] in anchorBox?.value = $0 }
            }
        }
        .task(id: attachment.path) {
            guard attachment.isImage else { return }
            if let known = ThumbnailMemory.image(for: attachment.path, pointSize: size) {
                if image !== known { image = known }
                return
            }
            guard let thumbnail = await ThumbnailCache.shared.thumbnail(for: attachment.path, pointSize: size) else { return }
            ThumbnailMemory.store(thumbnail.image, for: attachment.path, pointSize: size)
            withAnimation(.easeOut(duration: 0.15)) { image = thumbnail.image }
        }
    }
}

struct AssistantMessageRow: View {
    @Environment(\.chatZoom) private var zoom
    let entry: TimelineEntry
    /// The turn's summary, set only on the turn's last reply. Precomputed by the
    /// timeline, so rows never scan the thread.
    let summary: TurnSummary?
    @State private var isHovering = false

    var body: some View {
        if case .assistant(let message) = entry.item.content {
            VStack(alignment: .leading, spacing: 2) {
                MarkdownView(text: message.text, isStreaming: message.isStreaming).equatable()
                // One side for both kinds of message: the copy control sits on the trailing
                // edge. On the leading edge it landed in the tool rows' icon column, where a
                // step below the answer drew right under it.
                HStack(spacing: 8) {
                    if let summary {
                        Text(TurnEndRow.label(for: summary))
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    CopyButton(text: message.text)
                }
                .opacity(isHovering && !message.isStreaming ? 1 : 0)
            }
            .onHover { [hovering = $isHovering] isOver in
                withAnimation(.easeOut(duration: 0.12)) { hovering.wrappedValue = isOver }
            }
            // Same trade as the user row: the hover line's room stays inside the row
            // (so hovering it works and text never moves), but not in its height, so
            // the controls fill the gap below instead of adding to it. (2 = the
            // VStack's spacing above them.)
            .padding(.bottom, -(TimelineMetrics.hoverLineHeight + 2))
        }
    }
}

/// Consecutive tool calls, rendered inline with no card: a summary header
/// ("Edited files, ran commands") whose chevron collapses the rows. A group the
/// agent has moved on from (reply text follows it) starts collapsed, so past work
/// reads as one tappable line above the answer; the live group stays expanded.
/// A lone tool renders as its row alone.
struct WorkGroup: View {
    @Environment(\.chatZoom) private var zoom
    let entries: [TimelineEntry]
    let runtime: ThreadRuntime
    var workingDirectory: String?
    var startsCollapsed = false
    @State private var isCollapsed: Bool

    init(entries: [TimelineEntry], runtime: ThreadRuntime, workingDirectory: String? = nil, startsCollapsed: Bool = false) {
        self.entries = entries
        self.runtime = runtime
        self.workingDirectory = workingDirectory
        self.startsCollapsed = startsCollapsed
        _isCollapsed = State(initialValue: startsCollapsed)
    }

    var body: some View {
        if entries.count == 1, let only = entries.first {
            ToolRow(entry: only, runtime: runtime, workingDirectory: workingDirectory)
        } else {
            VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: TimelineMetrics.iconSpacing) {
                        Image(systemName: WorkGroupSummary.symbol(for: entries))
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(.secondary)
                            .frame(width: TimelineMetrics.iconWidth)
                        Text(WorkGroupSummary.text(for: entries))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                    .font(.chat(.callout, zoom: zoom))
                    .padding(.trailing, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Show these steps" : "Hide these steps")
                .accessibilityLabel(Text(isCollapsed ? "Show these steps" : "Hide these steps"))
                if !isCollapsed {
                    WorkSteps(entries: entries, runtime: runtime, workingDirectory: workingDirectory)
                }
            }
            .onChange(of: startsCollapsed) { _, collapsed in
                // One-way: arriving reply text collapses the group, but a group
                // the reader opened never snaps shut on its own.
                if collapsed { isCollapsed = true }
            }
        }
    }
}

/// A tool group's rows: only the two latest steps show, the rest fold under
/// one "N earlier steps" line until tapped. Shared by the expanded work group
/// and the running turn's working line.
struct WorkSteps: View {
    @Environment(\.chatZoom) private var zoom
    let entries: [TimelineEntry]
    let runtime: ThreadRuntime
    var workingDirectory: String?
    @State private var showsAll = false

    var body: some View {
        let hidden = showsAll ? 0 : max(0, entries.count - 2)
        if hidden > 0 {
            Button {
                withAnimation(.snappy) { showsAll = true }
            } label: {
                HStack(spacing: TimelineMetrics.iconSpacing) {
                    Image(systemName: "ellipsis")
                        .font(.chat(.caption, zoom: zoom))
                        .foregroundStyle(.secondary)
                        .frame(width: TimelineMetrics.iconWidth)
                    Text(hidden == 1 ? "1 earlier step" : "\(hidden) earlier steps")
                        .foregroundStyle(.secondary)
                }
                .font(.chat(.callout, zoom: zoom))
                .padding(.trailing, 12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        ForEach(entries.suffix(entries.count - hidden)) { entry in
            ToolRow(entry: entry, runtime: runtime, workingDirectory: workingDirectory)
        }
    }
}

/// The heads a turn sent out, one tool row each, as a plain list: no header, no
/// chevron, never folded. Sits below the turn's steps and replies while the turn runs
/// and under the folded turn once it is over, so a head never disappears with the steps.
struct HydraHeadsList: View {
    let entries: [TimelineEntry]
    let runtime: ThreadRuntime
    var workingDirectory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
            ForEach(entries) { entry in
                ToolRow(entry: entry, runtime: runtime, workingDirectory: workingDirectory)
            }
        }
    }
}

/// The "Edited files, ran commands" line above a tool group, derived from the
/// calls' kinds rather than their localized titles. First part capitalized, the
/// rest lowered, in a fixed kind order. A kind with a call still running reads
/// in the present tense ("Editing files, ran commands").
///
/// Main-actor isolated like the entries it reads: `TimelineEntry.item` lives on
/// the main actor, so this can only run where view bodies run.
@MainActor
enum WorkGroupSummary {
    static func text(for entries: [TimelineEntry]) -> String {
        var kinds: [ToolCall.Kind] = []
        for entry in entries {
            guard case .tool(let call) = entry.item.content, !kinds.contains(call.kind) else { continue }
            kinds.append(call.kind)
        }
        let order: [ToolCall.Kind] = [.edit, .read, .command, .search, .web, .mcp, .agent, .other]
        var parts: [String] = []
        for kind in order where kinds.contains(kind) {
            let running = entries.contains {
                guard case .tool(let call) = $0.item.content else { return false }
                return call.kind == kind && call.status == .running
            }
            parts.append(label(for: kind, running: running))
        }
        if parts.isEmpty { return "Worked" }
        guard parts.count > 1 else { return parts[0] }
        let rest = parts.dropFirst().map { part -> String in
            guard let head = part.first else { return part }
            return String(head).lowercased() + String(part.dropFirst())
        }
        return ([parts[0]] + rest).joined(separator: ", ")
    }

    static func symbol(for entries: [TimelineEntry]) -> String {
        let kinds = Set(entries.compactMap { entry -> ToolCall.Kind? in
            guard case .tool(let call) = entry.item.content else { return nil }
            return call.kind
        })
        let order: [ToolCall.Kind] = [.edit, .read, .command, .search, .web, .mcp, .agent, .other]
        guard let first = order.first(where: { kinds.contains($0) }) else { return "wrench.and.screwdriver" }
        return ToolPresentation.symbol(for: first)
    }

    private static func label(for kind: ToolCall.Kind, running: Bool) -> String {
        switch kind {
        case .edit: running ? "Editing files" : "Edited files"
        case .read: running ? "Reading files" : "Read files"
        case .command: running ? "Running commands" : "Ran commands"
        case .search: running ? "Searching" : "Searched"
        case .web: running ? "Browsing" : "Browsed"
        case .mcp: running ? "Calling tools" : "Called tools"
        case .agent: running ? "Delegating tasks" : "Delegated tasks"
        case .other: running ? "Using tools" : "Used tools"
        }
    }
}

struct ToolRow: View {
    @Environment(\.chatZoom) private var zoom
    @Environment(AppModel.self) private var model
    let entry: TimelineEntry
    let runtime: ThreadRuntime
    var workingDirectory: String?
    @State private var isExpanded = false
    /// The row's label (icon through chevron), so the changes popover hangs from the
    /// text that was tapped, and the panel that shows an image the agent looked at.
    /// Both are made on first use: a thread holds hundreds of tool rows, and building a
    /// popover and an anchor view for each of them is work the scroll pays for a panel
    /// almost none of them ever opens.
    @State private var preview = AttachmentPreviewSlot()
    /// Whether the pointer has been on the row's label, which is when its anchor view is
    /// mounted. A click always follows a hover, and hovering is off while the timeline
    /// scrolls, so a row scrolling past never mounts one. Once mounted it stays: a popover
    /// is positioned against this view, and taking it away under an open one closes it.
    @State private var needsAnchor = false
    /// Whether the steps popover of the head this row sent out is open.
    @State private var isShowingHead = false

    var body: some View {
        if case .tool(let call) = entry.item.content {
            // A row that carries a diff never unfolds: the diff opens in the changes
            // popover, below the row's label. A read of an image opens the image itself
            // the same way, whatever text came with it, and so does any other row with an
            // image and nothing else to show. Only a row whose content is its own output
            // (a command's text, a tool's detail) still expands in place.
            let edits = call.edits.filter { !$0.path.isEmpty }
            let opensDiff = !edits.isEmpty
            let imagePath = opensDiff ? nil : PreviewImages.resolveToolImagePath(for: call, workingDirectory: workingDirectory)
            let showsOutput = !opensDiff && (!call.output.isEmpty || !(call.detail ?? "").isEmpty)
            let opensImage = imagePath != nil && (call.kind == .read || !showsOutput)
            let opensPopover = opensDiff || opensImage
            // A row that sent out a head opens the head's steps in a popover of its own,
            // never its raw tool output.
            let headID = call.kind == .agent ? runtime.hydraHead(forTool: entry.id) : nil
            let opensHead = headID != nil
            // A call with no change to show, no image and no output of its own has
            // nothing to open. Rendered as a line of text rather than a control, so the
            // pointer and VoiceOver both treat it as what it is.
            let isTappable = opensPopover || opensHead || showsOutput
            // Values and weak boxes only below: the button action must not keep this
            // row's entry (and its text) alive through menus and hovers.
            let turn = entry.turnID
            let diffEdits = edits
            let slot = preview
            let rt = runtime
            VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                if isTappable {
                    Button {
                        [weak slot, weak rt, presented = $isShowingHead, expanded = $isExpanded] in
                        if opensHead {
                            presented.wrappedValue.toggle()
                        } else if opensDiff {
                            guard let view = slot?.anchor.value else { return }
                            rt?.showDiff(on: view, edge: .minY, turn: turn, focusEdits: diffEdits)
                        } else if opensImage, let imagePath {
                            slot?.panel.toggle(PreviewImages.attachment(for: imagePath), over: slot?.anchor.value, edge: .minY)
                        } else {
                            withAnimation(.snappy(duration: 0.2)) { expanded.wrappedValue.toggle() }
                        }
                    } label: {
                        line(call: call, imagePath: imagePath, opensPopover: opensPopover, opensHead: opensHead, showsOutput: showsOutput)
                            .contentShape(.rect)
                            .modifier(HeadStepsPopoverModifier(headID: headID, isPresented: $isShowingHead))
                    }
                    .buttonStyle(.plain)
                    .help(helpText(opensDiff: opensDiff, opensImage: opensImage, opensHead: opensHead, showsOutput: showsOutput))
                } else {
                    line(call: call, imagePath: imagePath, opensPopover: opensPopover, opensHead: opensHead, showsOutput: showsOutput)
                }
                if isExpanded, showsOutput, !opensImage {
                    ToolDetailView(call: call, workingDirectory: workingDirectory)
                        .padding(.trailing, 12)
                }
            }
            .onDisappear { [weak slot] in slot?.close() }
        }
    }

    /// The row itself: icon, text, stats and chevron, laid out the same whether or not
    /// the line can be tapped.
    @ViewBuilder
    private func line(call: ToolCall, imagePath: String?, opensPopover: Bool, opensHead: Bool, showsOutput: Bool) -> some View {
        // The slot alone: the hover responder and the anchor view must not keep this
        // row's entry (and its text) alive after it scrolls away.
        let previewSlot = preview
        HStack(spacing: TimelineMetrics.iconSpacing) {
            HStack(spacing: TimelineMetrics.iconSpacing) {
                // A row that sent out a head wears the head's glyph and name.
                let head = call.kind == .agent ? runtime.hydraHead(forTool: entry.id).flatMap { model.thread($0)?.hydra } : nil
                if let head {
                    HydraGlyph(persona: head.persona, size: 14, isRunning: call.status == .running && head.status == .running, status: head.status)
                        .frame(width: TimelineMetrics.iconWidth)
                } else {
                    ToolStatusIcon(call: call, symbol: imagePath != nil && call.kind == .read ? "photo" : nil)
                }
                // One text run after the icon, so the row reads as
                // icon + space + text instead of three spaced items.
                Text(head.map { "\(call.status == .running ? "Sending out" : "Sent out") \($0.persona.name): \(call.title)" } ?? ToolPresentation.label(for: call))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let stats = ToolPresentation.stats(for: call) {
                    DiffStatLabel(additions: stats.additions, deletions: stats.deletions)
                }
                // Beside the subject, not out at the trailing edge: the chevron
                // belongs to the row's own text.
                if opensPopover || opensHead {
                    Image(systemName: "chevron.down")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                } else if showsOutput {
                    Image(systemName: "chevron.right")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .onHover { [needed = $needsAnchor] hovering in
                if hovering, !needed.wrappedValue { needed.wrappedValue = true }
            }
            .background {
                if opensPopover, needsAnchor {
                    AttachmentAnchorCapture { [weak previewSlot] in previewSlot?.setAnchor($0) }
                }
            }
            Spacer(minLength: 8)
            if call.status == .failed, let exitCode = call.exitCode {
                Text("exit \(exitCode)")
                    .font(.chat(.caption, zoom: zoom).monospacedDigit())
                    .foregroundStyle(Chrome.danger)
            } else if call.status == .declined {
                Text("Declined")
                    .font(.chat(.caption, zoom: zoom))
                    .foregroundStyle(Chrome.warning)
            }
        }
        .font(.chat(.callout, zoom: zoom))
        .padding(.trailing, 12)
    }

    private func helpText(opensDiff: Bool, opensImage: Bool, opensHead: Bool, showsOutput: Bool) -> String {
        if opensHead { return "Show the head's steps" }
        if opensDiff { return "Show this change" }
        if opensImage { return "Show the image" }
        guard showsOutput else { return "" }
        return isExpanded ? "Hide the output" : "Show the output"
    }
}

/// Hangs the head's steps popover from a row that sent out a head. A row that did not
/// mounts nothing: the popover, its state and its anchor exist only where they can open.
private struct HeadStepsPopoverModifier: ViewModifier {
    let headID: UUID?
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if let headID {
            content.popover(isPresented: $isPresented, arrowEdge: .bottom) {
                HydraHeadStepsPopover(headID: headID)
            }
        } else {
            content
        }
    }
}

/// What a head did, in plain text: its brief, then every step it took, then its report.
/// Reads the head's own runtime straight from the model, so the list grows while the
/// head still works.
struct HydraHeadStepsPopover: View {
    @Environment(\.chatZoom) private var zoom
    let headID: UUID
    @Environment(AppModel.self) private var model

    private static let width: CGFloat = 440
    private static let maxHeight: CGFloat = 520

    var body: some View {
        let hydra = model.thread(headID)?.hydra
        let steps = Self.steps(in: model.runtime(for: headID).entries)
        let report = hydra.flatMap { head -> String? in
            guard head.isFinished else { return nil }
            let text = (head.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let hydra {
                    header(hydra)
                    if !hydra.task.isEmpty {
                        Text(verbatim: hydra.task)
                            .font(.chat(.callout, zoom: zoom))
                            .foregroundStyle(Chrome.primaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    sectionTitle("Steps")
                    if steps.isEmpty {
                        Text("No steps yet.")
                            .font(.chat(.callout, zoom: zoom))
                            .foregroundStyle(Chrome.secondaryText)
                    } else {
                        ForEach(steps) { entry in
                            step(entry)
                        }
                    }
                }
                if let report {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Report")
                        Text(verbatim: report)
                            .font(.chat(.callout, zoom: zoom))
                            .foregroundStyle(Chrome.primaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(width: Self.width, alignment: .leading)
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight)
    }

    /// The head's glyph and name, with where it stands on the trailing side.
    private func header(_ hydra: HydraHeadInfo) -> some View {
        HStack(alignment: .center, spacing: TimelineMetrics.iconSpacing) {
            HydraGlyph(persona: hydra.persona, size: 22, isRunning: hydra.status == .running, status: hydra.status)
            Text(verbatim: hydra.persona.name)
                .font(.chat(.headline, zoom: zoom))
                .foregroundStyle(Chrome.primaryText)
            Spacer(minLength: 12)
            Text(verbatim: Self.statusLine(for: hydra))
                .font(.chat(.caption, zoom: zoom))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.chat(.caption, weight: .semibold, zoom: zoom))
            .foregroundStyle(Chrome.secondaryText)
    }

    /// One step, laid out like the timeline's own rows: the icon column, then the text.
    @ViewBuilder
    private func step(_ entry: TimelineEntry) -> some View {
        switch entry.item.content {
        case .tool(let call):
            HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.iconSpacing) {
                ToolStatusIcon(call: call)
                    .frame(width: TimelineMetrics.iconWidth)
                Text(verbatim: ToolPresentation.label(for: call))
                    .font(.chat(.callout, zoom: zoom))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let stats = ToolPresentation.stats(for: call) {
                    DiffStatLabel(additions: stats.additions, deletions: stats.deletions)
                }
            }
        case .assistant(let message):
            Text(verbatim: message.text)
                .font(.chat(.callout, zoom: zoom))
                .foregroundStyle(Chrome.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .user(let message):
            // A later brief: the lead steering the head on.
            Text(verbatim: message.text)
                .font(.chat(.callout, zoom: zoom))
                .foregroundStyle(Chrome.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .notice(let notice):
            HStack(alignment: .firstTextBaseline, spacing: TimelineMetrics.iconSpacing) {
                Image(systemName: Self.noticeSymbol(for: notice.level))
                    .font(.chat(.caption, zoom: zoom))
                    .foregroundStyle(Self.noticeColor(for: notice.level))
                    .frame(width: TimelineMetrics.iconWidth)
                Text(verbatim: notice.message)
                    .font(.chat(.callout, zoom: zoom))
                    .foregroundStyle(Self.noticeColor(for: notice.level))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            EmptyView()
        }
    }

    /// "Working…" or the outcome, then the tool count and, once the head is done, how
    /// long it took.
    private static func statusLine(for hydra: HydraHeadInfo) -> String {
        let outcome: String = switch hydra.status {
        case .running: "Working…"
        case .completed: "Done"
        case .failed: "Failed"
        case .stopped: "Stopped"
        }
        var parts = [outcome]
        if hydra.toolCalls > 0 {
            parts.append(hydra.toolCalls == 1 ? "1 tool" : "\(hydra.toolCalls) tools")
        }
        if let finishedAt = hydra.finishedAt {
            parts.append(RelativeTime.duration(finishedAt.timeIntervalSince(hydra.startedAt)))
        }
        return parts.joined(separator: " · ")
    }

    /// The entries worth a line: every tool call, reply and notice, and any brief after
    /// the first. The first user entry is the task itself, shown above; thinking, plans,
    /// todo lists and turn ends are the head's own bookkeeping.
    private static func steps(in entries: [TimelineEntry]) -> [TimelineEntry] {
        var sawBrief = false
        return entries.filter { entry in
            switch entry.item.content {
            case .user(let message):
                if !sawBrief {
                    sawBrief = true
                    return false
                }
                return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .assistant(let message):
                return !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .tool, .notice:
                return true
            case .reasoning, .turnEnd, .plan, .todos:
                return false
            }
        }
    }

    private static func noticeSymbol(for level: Notice.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.octagon"
        }
    }

    private static func noticeColor(for level: Notice.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warning: Chrome.warning
        case .error: Chrome.danger
        }
    }
}

private struct ToolStatusIcon: View {
    @Environment(\.chatZoom) private var zoom
    let call: ToolCall
    /// Stands in for the kind's symbol: a photo for a read that looked at one.
    var symbol: String?

    var body: some View {
        Group {
            switch call.status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Chrome.danger)
            case .declined:
                Image(systemName: "hand.raised.slash")
                    .foregroundStyle(Chrome.warning)
            case .completed:
                Image(systemName: symbol ?? ToolPresentation.symbol(for: call.kind))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.chat(.caption, zoom: zoom))
        .frame(width: TimelineMetrics.iconWidth)
    }
}

private struct ToolDetailView: View {
    @Environment(\.chatZoom) private var zoom
    let call: ToolCall
    var workingDirectory: String?

    @State private var showsFullOutput = false

    /// Tool output renders inline and collapsed: a nested scroll view inside the
    /// timeline's scroll view fights gestures and hitches, and materializing tens of
    /// thousands of characters at once is what made expanding feel laggy.
    private static let outputLineLimit = 30

    var body: some View {
        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
            if let imagePath = PreviewImages.resolveToolImagePath(for: call, workingDirectory: workingDirectory) {
                ToolImagePreview(path: imagePath)
            }
            if let detail = call.detail, !detail.isEmpty {
                Text(detail)
                    .font(.chat(.caption, design: .monospaced, zoom: zoom))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            ForEach(Array(call.edits.enumerated()), id: \.offset) { _, edit in
                if let diff = edit.diff, !diff.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(edit.path)
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        DiffLinesView(file: DiffDetailCache.file(diff: diff, path: edit.path), showsLineNumbers: false)
                    }
                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
            }
            if !call.output.isEmpty {
                let output = call.output.trimmingCharacters(in: .newlines)
                let lines = output.components(separatedBy: "\n")
                let collapsed = !showsFullOutput && lines.count > Self.outputLineLimit
                let visible = collapsed ? lines.prefix(Self.outputLineLimit).joined(separator: "\n") : output
                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    Text(visible)
                        .font(.chat(.caption, design: .monospaced, zoom: zoom))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
                    if lines.count > Self.outputLineLimit {
                        Button(showsFullOutput ? "Show less" : "Show full output (\(lines.count) lines)") {
                            showsFullOutput.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.chat(.caption, zoom: zoom))
                    }
                }
            }
        }
    }
}

/// Parsed per-file diffs for expanded tool rows. Parsing runs once per distinct diff,
/// so opening and closing a row is instant no matter how large the patch is.
private enum DiffDetailCache {
    @MainActor private static var cache = RecentCache<String, DiffFile>(limit: 60)

    @MainActor
    static func file(diff: String, path: String) -> DiffFile {
        let key = path + "\n" + diff
        if let hit = cache.value(for: key) { return hit }
        let parsed = DiffParser.parseHunks(diff, path: path)
        cache.insert(parsed, for: key)
        return parsed
    }
}

enum ToolPresentation {
    /// The row's text run: verb plus subject. Agents that title a call with the
    /// tool's own name ("Edit file") would read "Edited Edit file" — drop the
    /// redundant leading word so it reads "Edited file".
    static func label(for call: ToolCall) -> String {
        let root: String = switch call.kind {
        case .command: "run"
        case .read: "read"
        case .edit: "edit"
        case .search: "search"
        case .web: "fetch"
        case .mcp: "call"
        case .agent: "delegate"
        case .other: "use"
        }
        var subject = call.title
        let words = call.title.split(separator: " ", maxSplits: 1)
        if words.first?.lowercased() == root {
            subject = words.count > 1 ? String(words[1]) : ""
        }
        return [verb(for: call), subject].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func verb(for call: ToolCall) -> String {
        let running = call.status == .running
        return switch call.kind {
        case .command: running ? "Running" : "Ran"
        case .read: running ? "Reading" : "Read"
        case .edit: running ? "Editing" : "Edited"
        case .search: running ? "Searching" : "Searched"
        case .web: running ? "Browsing" : "Browsed"
        case .mcp: running ? "Calling" : "Called"
        case .agent: running ? "Delegating" : "Delegated"
        case .other: running ? "Using" : "Used"
        }
    }

    static func symbol(for kind: ToolCall.Kind) -> String {
        switch kind {
        case .command: "terminal"
        case .read: "doc.text"
        case .edit: "pencil"
        case .search: "magnifyingglass"
        case .web: "globe"
        case .mcp: "puzzlepiece.extension"
        case .agent: "person.2"
        case .other: "wrench.and.screwdriver"
        }
    }

    static func stats(for call: ToolCall) -> (additions: Int, deletions: Int)? {
        guard !call.edits.isEmpty else { return nil }
        let additions = call.edits.reduce(0) { $0 + $1.additions }
        let deletions = call.edits.reduce(0) { $0 + $1.deletions }
        return additions + deletions > 0 ? (additions, deletions) : nil
    }
}

struct PlanCard: View {
    @Environment(\.chatZoom) private var zoom
    let entry: TimelineEntry
    let runtime: ThreadRuntime

    var body: some View {
        if case .plan(let plan) = entry.item.content {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundStyle(.tint)
                    Text("Plan")
                        .font(.chat(.headline, zoom: zoom))
                    Spacer()
                    switch plan.state {
                    case .accepted:
                        Label("Approved", systemImage: "checkmark")
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(.secondary)
                    case .dismissed:
                        Text("Dismissed")
                            .font(.chat(.caption, zoom: zoom))
                            .foregroundStyle(.secondary)
                    default:
                        EmptyView()
                    }
                    CopyButton(text: plan.markdown)
                }
                if plan.markdown.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    MarkdownView(text: plan.markdown, isStreaming: plan.state == .drafting).equatable()
                }
                if plan.state == .proposed {
                    // The controls stay where they are while the thread is busy, greyed
                    // rather than gone: a plan whose buttons vanish mid-turn reads as a
                    // plan that has already been dealt with.
                    let isBusy = runtime.pendingPlanApproval != nil || runtime.isRunning
                    HStack(spacing: 8) {
                        Button("Implement plan") { runtime.implementPlan(entry.id) }
                            .buttonStyle(.glassProminent)
                        Button("Dismiss") { runtime.dismissPlan(entry.id) }
                            .buttonStyle(.glass)
                    }
                    .disabled(isBusy)
                    .help(isBusy ? "Wait for the current turn to finish" : "")
                    .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.06), in: .rect(cornerRadius: 18, style: .continuous))
        }
    }
}

struct TodoListRow: View {
    @Environment(\.chatZoom) private var zoom
    let entry: TimelineEntry

    var body: some View {
        if case .todos(let steps) = entry.item.content, !steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    Text("\(steps.count { $0.status == .done }) of \(steps.count) done")
                }
                .font(.chat(.caption, zoom: zoom))
                .foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.symbol(for: step.status))
                            .foregroundStyle(step.status == .pending ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                        Text(step.text)
                            .foregroundStyle(step.status == .done ? .secondary : .primary)
                            .strikethrough(step.status == .done, color: .secondary)
                    }
                    .font(.chat(.callout, zoom: zoom))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 14, style: .continuous))
            // One checklist per turn: updates rewrite these steps in place, so
            // checking an item off animates the same list instead of adding a row.
            .animation(.snappy(duration: 0.2), value: steps)
        }
    }

    private static func symbol(for status: TodoStep.Status) -> String {
        switch status {
        case .pending: "circle"
        case .active: "circle.dotted.circle"
        case .done: "checkmark.circle.fill"
        }
    }
}

struct NoticeRow: View {
    @Environment(\.chatZoom) private var zoom
    let entry: TimelineEntry

    var body: some View {
        if case .notice(let notice) = entry.item.content {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(for: notice.level))
                    .foregroundStyle(Self.color(for: notice.level))
                Text(notice.message)
                    .textSelection(.enabled)
                    .foregroundStyle(notice.level == .info ? .secondary : .primary)
            }
            .font(.chat(.callout, zoom: zoom))
            .padding(.horizontal, notice.level == .info ? 0 : 12)
            .padding(.vertical, notice.level == .info ? 0 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Self.background(for: notice.level), in: .rect(cornerRadius: 12, style: .continuous))
        }
    }

    private static func symbol(for level: Notice.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "exclamationmark.octagon"
        }
    }

    /// The theme's own status colours, like every other warning and failure in the app,
    /// rather than the system orange and red.
    private static func color(for level: Notice.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warning: Chrome.warning
        case .error: Chrome.danger
        }
    }

    private static func background(for level: Notice.Level) -> Color {
        switch level {
        case .info: .clear
        case .warning: Chrome.warning.opacity(0.1)
        case .error: Chrome.danger.opacity(0.1)
        }
    }
}

struct TurnEndRow: View {
    @Environment(\.chatZoom) private var zoom
    let summary: TurnSummary
    /// Whether the turn produced a reply. Set by the timeline; when true the duration
    /// lives on the reply's hover line instead.
    let hasReply: Bool

    var body: some View {
        if !hasReply {
            Text(Self.label(for: summary))
                .font(.chat(.caption, zoom: zoom))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func label(for summary: TurnSummary) -> String {
        let duration = RelativeTime.duration(summary.duration)
        return switch summary.status {
        case .completed, .running: "Worked for \(duration)"
        case .interrupted: "Stopped after \(duration)"
        case .failed: "Failed after \(duration)"
        }
    }
}

/// A finished turn, collapsed to nothing more than its header, its final response
/// and its file summary. The chevron re-opens the turn's full steps.
struct TurnFinishedBlock: View {
    @Environment(\.chatZoom) private var zoom
    let runtime: ThreadRuntime
    let turnID: UUID
    let summary: TurnSummary
    let userEntries: [TimelineEntry]
    /// Everything in the turn except the user message, the turn-end marker and
    /// reasoning. Pre-partitioned by the timeline, so rows never scan the thread.
    let content: [TimelineEntry]
    let workingDirectory: String?
    /// Whether the turn can be reverted right now. Decided by the timeline, which reads
    /// the provider and the turn list once for every row.
    let canUndo: Bool

    @State private var isExpanded = false
    @State private var isConfirmingUndo = false

    struct FileStat: Hashable {
        var path: String
        var additions: Int
        var deletions: Int
    }

    /// Everything the body derives from the turn's content, gathered in one pass per
    /// render instead of a filter per use.
    private struct Derived {
        /// Every reply with something to read, narration included, in order.
        var assistantEntries: [TimelineEntry] = []
        /// The turn's conclusive answer: the replies that follow its last tool call.
        /// Prose between tool calls narrates work the collapsed turn doesn't show, and
        /// stays with the steps behind the chevron. A turn that ended on a tool (stopped
        /// or failed mid-work) keeps the last words it said rather than showing nothing.
        var answerEntries: [TimelineEntry] = []
        var collapsedPlans: [TimelineEntry] = []
        /// Errors and warnings stay visible even when collapsed, so a failed turn
        /// never hides what went wrong. Plain info notices stay in the expanded view.
        var collapsedNotices: [TimelineEntry] = []
        /// Per-file totals aggregated from this turn's tool edits. The header totals
        /// come from the turn summary itself, which is measured from the actual diff.
        var fileStats: [FileStat] = []
        var hasResponse = false
        /// The heads the turn sent out, always shown below the final response, folded or not.
        var headEntries: [TimelineEntry] = []
        /// The turn's full steps, built only while they are showing. The heads are not
        /// among them: they have their list of their own below the response.
        var detailGroups: [TimelineGroup] = []

        @MainActor
        init(content: [TimelineEntry], expanded: Bool) {
            var totals: [String: FileStat] = [:]
            for entry in content {
                switch entry.kind {
                case .assistant:
                    // A message still streaming when its turn failed can be blank. Asked
                    // character by character, which stops at the first word: trimming made
                    // a second copy of every reply in the turn on every render of the block.
                    guard case .assistant(let message) = entry.item.content,
                          message.text.contains(where: { !$0.isWhitespace }) else { continue }
                    assistantEntries.append(entry)
                    answerEntries.append(entry)
                    hasResponse = true
                case .plan:
                    collapsedPlans.append(entry)
                case .notice:
                    if case .notice(let notice) = entry.item.content, notice.level != .info {
                        collapsedNotices.append(entry)
                    }
                case .tool:
                    // Reaching for a tool ends the answer so far: whatever the model says
                    // next is about the work, until it stops calling tools and concludes.
                    // Plans, notices and checklists don't interrupt it.
                    answerEntries.removeAll(keepingCapacity: true)
                    guard case .tool(let call) = entry.item.content else { continue }
                    if call.kind == .agent { headEntries.append(entry) }
                    for edit in call.edits where !edit.path.isEmpty {
                        var stat = totals[edit.path] ?? FileStat(path: edit.path, additions: 0, deletions: 0)
                        stat.additions += edit.additions
                        stat.deletions += edit.deletions
                        totals[edit.path] = stat
                    }
                default:
                    break
                }
            }
            if answerEntries.isEmpty, let last = assistantEntries.last { answerEntries = [last] }
            if !collapsedPlans.isEmpty || !collapsedNotices.isEmpty { hasResponse = true }
            fileStats = totals.values.sorted { $0.path < $1.path }
            if expanded {
                detailGroups = TimelineGroup.build(content, showReasoning: false).filter {
                    if case .heads = $0 { return false }
                    return true
                }
            }
        }
    }

    var body: some View {
        let derived = Derived(content: content, expanded: isExpanded)
        let showsHeads = !derived.headEntries.isEmpty
        let showsBody = showsHeads || summary.filesChanged > 0 || (isExpanded ? !derived.detailGroups.isEmpty : derived.hasResponse)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(userEntries) { entry in
                UserMessageRow(entry: entry, runtime: runtime, canRevert: canUndo)
                    .padding(.bottom, TimelineMetrics.rowSpacing)
            }
            Button {
                withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(TurnEndRow.label(for: summary))
                        .font(.chat(.callout, zoom: zoom))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide this turn's steps" : "Show this turn's steps")
            .accessibilityLabel(Text(isExpanded ? "Hide this turn's steps" : "Show this turn's steps"))

            if showsBody {
                Divider()
                    .opacity(0.6)
                    // Half a row gap on each side, so the header and the body sit one
                    // row gap apart with the rule in between.
                    .padding(.vertical, TimelineMetrics.rowSpacing / 2)

                if isExpanded {
                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    ForEach(derived.detailGroups) { group in
                        switch group {
                        case .single(let entry):
                            switch entry.kind {
                            case .assistant:
                                AssistantMessageRow(entry: entry, summary: nil)
                            case .tool:
                                WorkGroup(entries: [entry], runtime: runtime, workingDirectory: workingDirectory)
                            case .plan:
                                PlanCard(entry: entry, runtime: runtime)
                            case .todos:
                                TodoListRow(entry: entry)
                            case .notice:
                                NoticeRow(entry: entry)
                            case .user, .reasoning, .turnEnd:
                                EmptyView()
                            }
                        case .work(_, let entries, let startsCollapsed):
                            WorkGroup(entries: entries, runtime: runtime, workingDirectory: workingDirectory, startsCollapsed: startsCollapsed)
                        case .heads:
                            // Never among the steps: the heads list below shows them.
                            EmptyView()
                        }
                    }
                }
                .padding(.bottom, derived.hasResponse || showsHeads ? TimelineMetrics.rowSpacing : 0)
            } else if derived.hasResponse {
                VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    ForEach(derived.answerEntries) { entry in
                        if case .assistant(let message) = entry.item.content, !message.text.isEmpty {
                            MarkdownView(text: message.text).equatable()
                        }
                    }
                    ForEach(derived.collapsedPlans) { entry in
                        PlanCard(entry: entry, runtime: runtime)
                    }
                    ForEach(derived.collapsedNotices) { entry in
                        NoticeRow(entry: entry)
                    }
                }
                .padding(.bottom, TimelineMetrics.rowSpacing)
            }

            // The heads the turn sent out stay in view under the response, folded or not.
            if showsHeads {
                HydraHeadsList(entries: derived.headEntries, runtime: runtime, workingDirectory: workingDirectory)
                    .padding(.bottom, summary.filesChanged > 0 ? TimelineMetrics.rowSpacing : 0)
            }

            if summary.filesChanged > 0 {
                // Weak runtime: the card (and its review closure) must not keep the thread
                // alive after its turn scrolls away.
                let reviewRuntime = runtime
                TurnFileCard(
                    summary: summary,
                    files: derived.fileStats,
                    canUndo: canUndo,
                    onUndo: { isConfirmingUndo = true },
                    // On the button itself, so the changes open where the reader
                    // clicked, whatever is above the chat box.
                    onReview: { [weak reviewRuntime] button in reviewRuntime?.showDiff(on: button, turn: turnID) }
                )
            }
            }
        }
        .confirmationDialog("Undo this turn?", isPresented: $isConfirmingUndo) {
            Button("Revert files and conversation", role: .destructive) {
                Task { await runtime.revert(to: turnID, restoreFiles: true) }
            }
        } message: {
            Text("Files go back to how they were before this turn, and the turn leaves the conversation.")
        }
    }
}

private struct TurnFileCard: View {
    @Environment(\.chatZoom) private var zoom
    let summary: TurnSummary
    let files: [TurnFinishedBlock.FileStat]
    let canUndo: Bool
    let onUndo: () -> Void
    /// Receives the Review button's own view, for the popover to open on.
    let onReview: (NSView) -> Void
    /// The Review button's own view, captured once the pointer has been on it: a folded
    /// turn is a block of the lazy stack, and the anchor is only ever for a click, which
    /// has to hover the button first.
    @State private var reviewAnchor = WeakView()
    @State private var needsReviewAnchor = false

    var body: some View {
        // The anchor box alone: the hover responder and the anchor view must not keep
        // this card alive after it scrolls away.
        let reviewBox = reviewAnchor
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "plus.app")
                            .font(.system(size: 15 * zoom))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.filesChanged == 1 ? "Edited 1 file" : "Edited \(summary.filesChanged) files")
                        .font(.chat(.callout, weight: .medium, zoom: zoom))
                    DiffStatLabel(additions: summary.additions, deletions: summary.deletions)
                }
                Spacer(minLength: 8)
                if canUndo {
                    Button(action: onUndo) {
                        HStack(spacing: 4) {
                            Text("Undo")
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .font(.chat(.callout, zoom: zoom))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Revert this turn's files and conversation")
                }
                Button("Review") { [weak reviewBox] in
                    guard let view = reviewBox?.value else { return }
                    onReview(view)
                }
                .buttonStyle(.glass)
                .onHover { [needed = $needsReviewAnchor] hovering in
                    if hovering, !needed.wrappedValue { needed.wrappedValue = true }
                }
                .background {
                    if needsReviewAnchor {
                        AttachmentAnchorCapture { [weak reviewBox] in reviewBox?.value = $0 }
                    }
                }
                .help("Show this turn's changes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !files.isEmpty {
                Divider()
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files.prefix(12), id: \.path) { file in
                        HStack(spacing: 8) {
                            Text(verbatim: file.path)
                                .font(.chat(.callout, zoom: zoom))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            DiffStatLabel(additions: file.additions, deletions: file.deletions)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    if files.count > 12 {
                        Text(files.count == 13 ? "and 1 more file" : "and \(files.count - 12) more files")
                            .font(.chat(.callout, zoom: zoom))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(.quaternary.opacity(0.32), in: .rect(cornerRadius: 14, style: .continuous))
    }
}
