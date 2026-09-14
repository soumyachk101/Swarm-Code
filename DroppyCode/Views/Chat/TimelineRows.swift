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
        if case .user(let message) = entry.item.content {
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
            .onHover { isHovering = $0 }
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

    /// One preview panel for the strip, so every photo opens in a single tap
    /// no matter how many are attached.
    @State private var preview = AttachmentPreviewCoordinator()

    var body: some View {
        // A plain stack hugs the thumbnails, so a trailing-aligned row keeps the
        // photos over the bubble — and the anchor view fills just the photos.
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                AttachmentThumbnail(attachment: attachment, preview: preview)
                    .help(attachment.name)
            }
        }
        .background {
            AttachmentAnchorCapture { preview.setAnchor($0) }
        }
        .onDisappear { preview.close() }
    }
}

struct AttachmentThumbnail: View {
    let attachment: Attachment
    var size: CGFloat = 56
    let preview: AttachmentPreviewCoordinator

    @State private var image: CGImage?
    /// The thumbnail's own NSView, handed to the panel on tap so the arrow
    /// lands on the tapped photo rather than the strip's middle.
    @State private var ownAnchor = WeakView()

    init(attachment: Attachment, size: CGFloat = 56, preview: AttachmentPreviewCoordinator) {
        self.attachment = attachment
        self.size = size
        self.preview = preview
        // A photo shown before starts out drawn, so scrolling back to it never fades it in again.
        _image = State(initialValue: attachment.isImage ? ThumbnailMemory.image(for: attachment.path, pointSize: size) : nil)
    }

    var body: some View {
        Button {
            StripLog.log.notice("thumb tap id=\(attachment.id) name=\(attachment.name, privacy: .public)")
            preview.toggle(attachment, over: ownAnchor.value)
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
            } else {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                    Text(attachment.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .frame(height: size * 0.6)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        // The .fill image is drawn wider than the cell before it is clipped;
        // pinning the hit shape to the cell keeps the neighbour's remove badge
        // reachable no matter how hit-testing treats the overflow.
        .contentShape(.rect(cornerRadius: 12, style: .continuous))
        .background {
            AttachmentAnchorCapture { ownAnchor.value = $0 }
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
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    CopyButton(text: message.text)
                }
                .opacity(isHovering && !message.isStreaming ? 1 : 0)
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
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
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: TimelineMetrics.iconWidth)
                        Text(WorkGroupSummary.text(for: entries))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    }
                    .font(.callout)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: TimelineMetrics.iconWidth)
                    Text(hidden == 1 ? "1 earlier step" : "\(hidden) earlier steps")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
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
    let entry: TimelineEntry
    let runtime: ThreadRuntime
    var workingDirectory: String?
    @State private var isExpanded = false
    /// The row's label (icon through chevron), so the changes popover hangs from the
    /// text that was tapped. The row itself spans the column, and a popover anchored
    /// on it centred itself on the empty half with its arrow pointing at nothing.
    @State private var popoverAnchor = WeakView()
    /// The image the agent looked at, in the same large preview a sent photo opens in.
    @State private var imagePreview = AttachmentPreviewCoordinator()

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
            VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                Button {
                    if opensDiff {
                        guard let view = popoverAnchor.value else { return }
                        runtime.showDiff(on: view, edge: .minY, turn: entry.turnID, focusEdits: edits)
                    } else if opensImage, let imagePath {
                        imagePreview.toggle(PreviewImages.attachment(for: imagePath), over: popoverAnchor.value, edge: .minY)
                    } else if showsOutput {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                    }
                } label: {
                    HStack(spacing: TimelineMetrics.iconSpacing) {
                        HStack(spacing: TimelineMetrics.iconSpacing) {
                            ToolStatusIcon(call: call, symbol: imagePath != nil && call.kind == .read ? "photo" : nil)
                            // One text run after the icon, so the row reads as
                            // icon + space + text instead of three spaced items.
                            Text(ToolPresentation.label(for: call))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let stats = ToolPresentation.stats(for: call) {
                                DiffStatLabel(additions: stats.additions, deletions: stats.deletions)
                            }
                            // Beside the subject, not out at the trailing edge: the chevron
                            // belongs to the row's own text.
                            if opensPopover {
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            } else if showsOutput {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                        }
                        .background {
                            if opensPopover {
                                AttachmentAnchorCapture {
                                    popoverAnchor.value = $0
                                    imagePreview.setAnchor($0)
                                }
                            }
                        }
                        Spacer(minLength: 8)
                        if call.status == .failed, let exitCode = call.exitCode {
                            Text("exit \(exitCode)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Chrome.danger)
                        } else if call.status == .declined {
                            Text("Declined")
                                .font(.caption)
                                .foregroundStyle(Chrome.warning)
                        }
                    }
                    .font(.callout)
                    .padding(.trailing, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(helpText(opensDiff: opensDiff, opensImage: opensImage, showsOutput: showsOutput))
                if isExpanded, showsOutput, !opensImage {
                    ToolDetailView(call: call, workingDirectory: workingDirectory)
                        .padding(.trailing, 12)
                }
            }
            .onDisappear { imagePreview.close() }
        }
    }

    private func helpText(opensDiff: Bool, opensImage: Bool, showsOutput: Bool) -> String {
        if opensDiff { return "Show this change" }
        if opensImage { return "Show the image" }
        guard showsOutput else { return "" }
        return isExpanded ? "Hide the output" : "Show the output"
    }
}

private struct ToolStatusIcon: View {
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
        .font(.caption)
        .frame(width: TimelineMetrics.iconWidth)
    }
}

private struct ToolDetailView: View {
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
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            ForEach(Array(call.edits.enumerated()), id: \.offset) { _, edit in
                if let diff = edit.diff, !diff.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(edit.path)
                            .font(.caption)
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
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
                    if lines.count > Self.outputLineLimit {
                        Button(showsFullOutput ? "Show less" : "Show full output (\(lines.count) lines)") {
                            showsFullOutput.toggle()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
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
    let entry: TimelineEntry
    let runtime: ThreadRuntime

    var body: some View {
        if case .plan(let plan) = entry.item.content {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .foregroundStyle(.tint)
                    Text("Plan")
                        .font(.headline)
                    Spacer()
                    switch plan.state {
                    case .accepted:
                        Label("Approved", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .dismissed:
                        Text("Dismissed")
                            .font(.caption)
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
                if plan.state == .proposed, runtime.pendingPlanApproval == nil, !runtime.isRunning {
                    HStack(spacing: 8) {
                        Button("Implement plan") { runtime.implementPlan(entry.id) }
                            .buttonStyle(.glassProminent)
                        Button("Dismiss") { runtime.dismissPlan(entry.id) }
                            .buttonStyle(.glass)
                    }
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
    let entry: TimelineEntry

    var body: some View {
        if case .todos(let steps) = entry.item.content, !steps.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    Text("\(steps.count { $0.status == .done }) of \(steps.count) done")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.symbol(for: step.status))
                            .foregroundStyle(step.status == .pending ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                        Text(step.text)
                            .foregroundStyle(step.status == .done ? .secondary : .primary)
                            .strikethrough(step.status == .done, color: .secondary)
                    }
                    .font(.callout)
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
            .font(.callout)
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

    private static func color(for level: Notice.Level) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }

    private static func background(for level: Notice.Level) -> Color {
        switch level {
        case .info: .clear
        case .warning: .orange.opacity(0.1)
        case .error: .red.opacity(0.1)
        }
    }
}

struct TurnEndRow: View {
    let summary: TurnSummary
    /// Whether the turn produced a reply. Set by the timeline; when true the duration
    /// lives on the reply's hover line instead.
    let hasReply: Bool

    var body: some View {
        if !hasReply {
            Text(Self.label(for: summary))
                .font(.caption)
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
        /// The turn's full steps, built only while they are showing.
        var detailGroups: [TimelineGroup] = []

        @MainActor
        init(content: [TimelineEntry], expanded: Bool) {
            var totals: [String: FileStat] = [:]
            for entry in content {
                switch entry.kind {
                case .assistant:
                    // A message still streaming when its turn failed can be blank.
                    guard case .assistant(let message) = entry.item.content,
                          !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
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
            if expanded { detailGroups = TimelineGroup.build(content, showReasoning: false) }
        }
    }

    var body: some View {
        let derived = Derived(content: content, expanded: isExpanded)
        let showsBody = isExpanded
            ? !derived.detailGroups.isEmpty || summary.filesChanged > 0
            : derived.hasResponse || summary.filesChanged > 0
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
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
                        }
                    }
                }
                .padding(.bottom, derived.hasResponse ? TimelineMetrics.rowSpacing : 0)
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

            if summary.filesChanged > 0 {
                TurnFileCard(
                    summary: summary,
                    files: derived.fileStats,
                    canUndo: canUndo,
                    onUndo: { isConfirmingUndo = true },
                    // On the button itself, so the changes open where the reader
                    // clicked, whatever is above the chat box.
                    onReview: { button in runtime.showDiff(on: button, turn: turnID) }
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
    let summary: TurnSummary
    let files: [TurnFinishedBlock.FileStat]
    let canUndo: Bool
    let onUndo: () -> Void
    /// Receives the Review button's own view, for the popover to open on.
    let onReview: (NSView) -> Void
    @State private var reviewAnchor = WeakView()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "plus.app")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.filesChanged == 1 ? "Edited 1 file" : "Edited \(summary.filesChanged) files")
                        .font(.callout.weight(.medium))
                    DiffStatLabel(additions: summary.additions, deletions: summary.deletions)
                }
                Spacer(minLength: 8)
                if canUndo {
                    Button(action: onUndo) {
                        HStack(spacing: 4) {
                            Text("Undo")
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Revert this turn's files and conversation")
                }
                Button("Review") {
                    guard let view = reviewAnchor.value else { return }
                    onReview(view)
                }
                .buttonStyle(.glass)
                .background {
                    AttachmentAnchorCapture { reviewAnchor.value = $0 }
                }
                .help("Show this turn's changes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !files.isEmpty {
                Divider()
                    .opacity(0.5)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(files, id: \.path) { file in
                        HStack(spacing: 8) {
                            Text(verbatim: file.path)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            DiffStatLabel(additions: file.additions, deletions: file.deletions)
                        }
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
