import AppKit
import SwiftUI

struct UserMessageRow: View {
    let entry: TimelineEntry
    let runtime: ThreadRuntime

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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.tint.opacity(0.14), in: .rect(cornerRadius: 18, style: .continuous))
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
            .confirmationDialog("Edit from this message?", isPresented: $isConfirmingRevert) {
                Button("Revert and keep file changes") { revert(restoreFiles: false) }
                Button("Revert files too", role: .destructive) { revert(restoreFiles: true) }
            } message: {
                Text("This message and everything after it leave the thread, and your prompt returns to the composer.")
            }
        }
    }

    private var canRevert: Bool {
        guard !runtime.isRunning, let turnID = entry.turnID, let thread = runtime.thread else { return false }
        return thread.provider.supportsRewind && runtime.turns.contains { $0.id == turnID }
    }

    private func revert(restoreFiles: Bool) {
        guard let turnID = entry.turnID else { return }
        Task { await runtime.revert(to: turnID, restoreFiles: restoreFiles) }
    }
}

struct AttachmentStrip: View {
    let attachments: [Attachment]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                Button {
                    NSWorkspace.shared.open(attachment.url)
                } label: {
                    AttachmentThumbnail(attachment: attachment)
                }
                .buttonStyle(.plain)
                .help(attachment.name)
            }
        }
    }
}

struct AttachmentThumbnail: View {
    let attachment: Attachment
    var size: CGFloat = 56

    var body: some View {
        if attachment.isImage, let image = NSImage(contentsOfFile: attachment.path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 12, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "doc")
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
}

struct AssistantMessageRow: View {
    let entry: TimelineEntry
    let runtime: ThreadRuntime
    @State private var isHovering = false

    var body: some View {
        if case .assistant(let message) = entry.item.content {
            let summary = turnSummary
            VStack(alignment: .leading, spacing: 2) {
                MarkdownView(text: message.text)
                HStack(spacing: 8) {
                    CopyButton(text: message.text)
                    if let summary {
                        Text(TurnEndRow.label(for: summary))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .opacity(isHovering && !message.isStreaming ? 1 : 0)
                .offset(x: -4)
            }
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
    }

    /// The turn's summary, on the hover line of the turn's last reply only.
    private var turnSummary: TurnSummary? {
        guard let turnID = entry.turnID else { return nil }
        let lastReply = runtime.entries.last { candidate in
            guard candidate.turnID == turnID, case .assistant = candidate.kind else { return false }
            return true
        }
        guard lastReply?.id == entry.id else { return nil }
        for candidate in runtime.entries.reversed() {
            if case .turnEnd(let summary) = candidate.item.content, summary.turnID == turnID { return summary }
        }
        return nil
    }
}

struct ReasoningRow: View {
    let entry: TimelineEntry
    @State private var isExpanded = false

    var body: some View {
        if case .reasoning(let block) = entry.item.content {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .symbolEffect(.pulse, options: .repeating, isActive: block.isStreaming)
                        Text(Self.title(for: block))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if isExpanded {
                    MarkdownView(text: block.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
    }

    private static func title(for block: ReasoningBlock) -> String {
        if let match = block.text.firstMatch(of: #/\*\*(.+?)\*\*/#) {
            return String(match.output.1)
        }
        return block.isStreaming ? "Thinking" : "Thought"
    }
}

struct WorkGroup: View {
    let entries: [TimelineEntry]
    @State private var showsAll = false

    var body: some View {
        let hidden = showsAll ? 0 : max(0, entries.count - 6)
        VStack(alignment: .leading, spacing: 0) {
            if hidden > 0 {
                Button {
                    withAnimation(.snappy) { showsAll = true }
                } label: {
                    Label("\(hidden) earlier steps", systemImage: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            ForEach(entries.suffix(entries.count - hidden)) { entry in
                ToolRow(entry: entry)
            }
        }
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.32), in: .rect(cornerRadius: 14, style: .continuous))
    }
}

struct ToolRow: View {
    let entry: TimelineEntry
    @State private var isExpanded = false

    var body: some View {
        if case .tool(let call) = entry.item.content {
            let hasDetail = !call.output.isEmpty || !call.edits.isEmpty || !(call.detail ?? "").isEmpty
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    guard hasDetail else { return }
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        ToolStatusIcon(call: call)
                        Text(ToolPresentation.verb(for: call))
                            .foregroundStyle(.secondary)
                        Text(call.title)
                            .font(call.kind == .command ? .system(.callout, design: .monospaced) : .callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let stats = ToolPresentation.stats(for: call) {
                            DiffStatLabel(additions: stats.additions, deletions: stats.deletions)
                        }
                        Spacer(minLength: 8)
                        if call.status == .failed, let exitCode = call.exitCode {
                            Text("exit \(exitCode)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.red)
                        } else if call.status == .declined {
                            Text("Declined")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if hasDetail {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if isExpanded {
                    ToolDetailView(call: call)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        }
    }
}

private struct ToolStatusIcon: View {
    let call: ToolCall

    var body: some View {
        Group {
            switch call.status {
            case .running:
                ProgressView()
                    .controlSize(.mini)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .declined:
                Image(systemName: "hand.raised.slash")
                    .foregroundStyle(.orange)
            case .completed:
                Image(systemName: ToolPresentation.symbol(for: call.kind))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(width: 16)
    }
}

private struct ToolDetailView: View {
    let call: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        DiffLinesView(file: DiffParser.parseHunks(diff, path: edit.path), showsLineNumbers: false)
                    }
                    .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                }
            }
            if !call.output.isEmpty {
                ScrollView {
                    Text(call.output.trimmingCharacters(in: .newlines))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

enum ToolPresentation {
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
                    MarkdownView(text: plan.markdown)
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
                Text("\(steps.count { $0.status == .done }) of \(steps.count) done")
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
    let entry: TimelineEntry
    let runtime: ThreadRuntime

    var body: some View {
        if case .turnEnd(let summary) = entry.item.content, summary.filesChanged > 0 || !hasReply(summary) {
            HStack(spacing: 10) {
                // A turn that replied shows its duration on the reply's hover line instead.
                if !hasReply(summary) {
                    Text(Self.label(for: summary))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if summary.filesChanged > 0 {
                    Button {
                        runtime.diffSelection = summary.turnID
                        runtime.isDiffVisible = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plusminus")
                            Text(summary.filesChanged == 1 ? "1 file" : "\(summary.filesChanged) files")
                            DiffStatLabel(additions: summary.additions, deletions: summary.deletions)
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hasReply(_ summary: TurnSummary) -> Bool {
        runtime.entries.contains { candidate in
            guard candidate.turnID == summary.turnID, case .assistant = candidate.kind else { return false }
            return true
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
