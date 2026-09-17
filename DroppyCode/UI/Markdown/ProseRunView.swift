import AppKit
import SwiftUI

struct ProseRunView: View {
    let blocks: [MarkdownBlock]
    @Environment(\.markdownPointSize) private var pointSize
    @Environment(\.chatZoom) private var zoom
    @Environment(\.markdownDimmed) private var dimmed
    @Environment(\.hydraMentionPersonas) private var hydraMentionPersonas
    @State private var faviconRevision = 0

    var body: some View {
        let scaled = (pointSize * zoom * 2).rounded() / 2
        let sources = ProseRunRepresentable.joinedSources(blocks)
        let linkKey = RichLink.linkHosts(for: sources, streaming: false).joined(separator: ",")
        ProseRunRepresentable(blocks: blocks, pointSize: scaled, dimmed: dimmed, revision: faviconRevision, mentions: hydraMentionPersonas)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: linkKey) { [sources, linkKey, revision = $faviconRevision] in
                if !linkKey.isEmpty {
                    await InlineText.fetchFavicons(source: sources, streaming: false, revision: revision)
                }
            }
    }
}

struct ProseRunRepresentable: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    var pointSize: CGFloat = 13
    var dimmed: Bool = false
    var revision: Int = 0
    var mentions: [HydraPersona] = []

    func makeCoordinator() -> LinkParagraphView.Coordinator {
        LinkParagraphView.Coordinator()
    }

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
        view.delegate = context.coordinator
        view.passesProseThrough = false
        view.mergeTarget = context.environment.mergeRequestTarget
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        _ = revision
        let coordinator = context.coordinator
        let source = Self.joinedSources(blocks)
        let mentionNames = mentions.map(\.name)
        if coordinator.lastSource != source || coordinator.lastPointSize != pointSize
            || coordinator.lastDimmed != dimmed || coordinator.lastRevision != revision
            || coordinator.lastMentions != mentionNames {
            coordinator.lastSource = source
            coordinator.lastPointSize = pointSize
            coordinator.lastDimmed = dimmed
            coordinator.lastRevision = revision
            coordinator.lastMentions = mentionNames
            view.render(Self.attributed(blocks: blocks, pointSize: pointSize, dimmed: dimmed, mentions: mentions))
        }
        view.mergeTarget = context.environment.mergeRequestTarget
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    static func dismantleNSView(_ view: LinkTextView, coordinator: LinkParagraphView.Coordinator) {
        view.delegate = nil
        view.mergeTarget = nil
    }

    static func joinedSources(_ blocks: [MarkdownBlock]) -> String {
        var parts: [String] = []
        collect(blocks, into: &parts)
        return parts.joined(separator: "\n")
    }

    private static func collect(_ blocks: [MarkdownBlock], into parts: inout [String]) {
        for block in blocks {
            switch block {
            case .paragraph(let text), .heading(_, let text):
                parts.append(text)
            case .list(_, _, let items):
                for item in items {
                    parts.append(item.text)
                    collect(item.children, into: &parts)
                }
            case .quote(let inner):
                collect(inner, into: &parts)
            case .code, .table, .rule:
                break
            }
        }
    }

    @MainActor
    static func attributed(blocks: [MarkdownBlock], pointSize: CGFloat, dimmed: Bool, mentions: [HydraPersona]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for block in blocks {
            append(block, depth: 0, indent: 0, dimmed: dimmed, spacing: 12, pointSize: pointSize, mentions: mentions, to: out)
        }
        return out
    }

    @MainActor
    private static func append(_ block: MarkdownBlock, depth: Int, indent: CGFloat, dimmed: Bool, spacing: CGFloat, pointSize: CGFloat, mentions: [HydraPersona], to out: NSMutableAttributedString) {
        let base = NSFont.systemFont(ofSize: pointSize)
        let color = dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor
        switch block {
        case .paragraph(let text):
            separate(to: out, font: base, color: color)
            let line = NSMutableAttributedString(attributedString: LinkParagraphView.attributed(source: text, pointSize: pointSize, dimmed: dimmed, mentions: mentions))
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.paragraphSpacing = spacing
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            out.append(line)
        case .heading(let level, let text):
            separate(to: out, font: base, color: color)
            let size: CGFloat
            switch level {
            case 1: size = (pointSize * 1.35).rounded()
            case 2: size = (pointSize * 1.2).rounded()
            case 3: size = (pointSize * 1.08).rounded()
            default: size = pointSize
            }
            let line = NSMutableAttributedString(attributedString: LinkParagraphView.attributed(source: text, pointSize: size, dimmed: dimmed, mentions: mentions))
            let semibold = NSFont.systemFont(ofSize: size, weight: .semibold)
            line.enumerateAttribute(.font, in: NSRange(location: 0, length: line.length), options: []) { value, range, _ in
                guard let font = value as? NSFont else { return }
                let traits = font.fontDescriptor.symbolicTraits
                if !traits.contains(.bold) && !traits.contains(.monoSpace) {
                    line.addAttribute(.font, value: semibold, range: range)
                }
            }
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.paragraphSpacingBefore = level <= 2 ? 6 : 2
            style.paragraphSpacing = 12
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            out.append(line)
        case .list(let ordered, let start, let items):
            for (index, item) in items.enumerated() {
                separate(to: out, font: base, color: color)
                let marker: String
                if let checked = item.checked {
                    marker = checked ? "☑" : "☐"
                } else if ordered {
                    marker = "\(start + index)."
                } else {
                    marker = depth == 0 ? "•" : "◦"
                }
                let line = NSMutableAttributedString(string: marker + "\t", attributes: [
                    .font: base,
                    .foregroundColor: color,
                ])
                if !item.text.isEmpty {
                    line.append(LinkParagraphView.attributed(source: item.text, pointSize: pointSize, dimmed: dimmed, mentions: mentions))
                }
                let style = NSMutableParagraphStyle()
                style.firstLineHeadIndent = indent
                style.headIndent = indent + 18
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]
                style.defaultTabInterval = 18
                style.paragraphSpacing = (depth == 0 && index == items.count - 1) ? 12 : 6
                line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
                out.append(line)
                for child in item.children {
                    append(child, depth: depth + 1, indent: indent + 18, dimmed: dimmed, spacing: 6, pointSize: pointSize, mentions: mentions, to: out)
                }
            }
        case .quote(let inner):
            for child in inner {
                append(child, depth: depth, indent: indent + 14, dimmed: true, spacing: spacing, pointSize: pointSize, mentions: mentions, to: out)
            }
        case .code, .table, .rule:
            break
        }
    }

    @MainActor
    private static func separate(to out: NSMutableAttributedString, font: NSFont, color: NSColor) {
        guard out.length > 0 else { return }
        out.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: color,
        ]))
    }
}
