import SwiftUI

/// A single-head popover's header: the head's glyph, its name with a status caption, and its task.
struct HydraPopoverHeader: View {
    let persona: HydraPersona
    var status: HydraHeadInfo.Status? = nil
    var caption: String? = nil
    var captionColor: Color = Chrome.secondaryText
    var title: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HydraGlyph(persona: persona, size: 24, status: status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(persona.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(persona.color)
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(captionColor)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// A finished head's report in the popover its pill opens: the header stays put, the report scrolls under it.
struct HydraHeadReportPopover: View {
    let head: HydraHeadInfo
    private let blocks: [MarkdownBlock]

    private static let width: CGFloat = 460

    @MainActor
    init(head: HydraHeadInfo) {
        self.head = head
        let summary = head.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        blocks = summary.isEmpty ? [] : MarkdownView.blocks(for: summary)
    }

    var body: some View {
        VStack(spacing: 0) {
            HydraPopoverHeader(
                persona: head.persona,
                status: head.status,
                caption: Self.caption(for: head),
                captionColor: Self.captionColor(for: head.status),
                title: head.task
            )
            Divider()
            PopoverScroll(maxHeight: 460, width: Self.width) {
                Group {
                    if blocks.isEmpty {
                        Text("No report yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(Chrome.secondaryText)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                MarkdownBlockView(block: block)
                                    .equatable()
                            }
                        }
                        .font(.system(size: 12))
                        .environment(\.markdownPointSize, 12)
                        .environment(\.markdownDimmed, false)
                        .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.width)
        .environment(\.chatZoom, 1)
    }

    static func caption(for head: HydraHeadInfo) -> String {
        let base: String = switch head.status {
        case .completed: "Finished"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .running: "Working"
        }
        guard head.status != .running, let finishedAt = head.finishedAt else { return base }
        return "\(base) · \(duration(from: head.startedAt, to: finishedAt))"
    }

    static func captionColor(for status: HydraHeadInfo.Status) -> Color {
        switch status {
        case .failed: Chrome.danger
        case .stopped: Chrome.warning
        default: Chrome.secondaryText
        }
    }

    static func duration(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60) min" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
    }
}

/// The lead's brief to a head in the popover its pill opens: the same header over the brief's markdown.
struct HydraBriefPopover: View {
    let persona: HydraPersona
    let task: String?
    let text: String
    private let blocks: [MarkdownBlock]

    private static let width: CGFloat = 520

    @MainActor
    init(persona: HydraPersona, task: String?, text: String) {
        self.persona = persona
        self.task = task
        self.text = text
        blocks = MarkdownView.blocks(for: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            HydraPopoverHeader(persona: persona, caption: "Brief", title: task)
            Divider()
            PopoverScroll(maxHeight: 460, width: Self.width) {
                Group {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            MarkdownBlockView(block: block)
                                .equatable()
                        }
                    }
                    .font(.system(size: 12))
                    .environment(\.markdownPointSize, 12)
                    .environment(\.markdownDimmed, false)
                    .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.width)
        .environment(\.chatZoom, 1)
    }
}
