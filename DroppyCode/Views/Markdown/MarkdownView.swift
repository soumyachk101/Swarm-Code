import AppKit
import SwiftUI

struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
                    .equatable()
                    .transition(.softAppear)
            }
        }
        // Only a new block animates; text growing inside a block is not interpolated.
        .animation(.softAppear, value: blocks.count)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock

    /// Blocks compare by content, so a finished block is skipped while the reply keeps streaming.
    nonisolated static func == (lhs: MarkdownBlockView, rhs: MarkdownBlockView) -> Bool {
        lhs.block == rhs.block
    }

    var body: some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            InlineText(text)
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(ordered: ordered, number: start + index, checked: item.checked)
                        VStack(alignment: .leading, spacing: 6) {
                            if !item.text.isEmpty { InlineText(item.text) }
                            ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                                MarkdownBlockView(block: child)
                            }
                        }
                    }
                }
            }
        case .quote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Capsule().fill(.quaternary).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, child in
                        MarkdownBlockView(block: child)
                    }
                }
            }
            .foregroundStyle(.secondary)
        case .table(let header, let rows):
            TableBlock(header: header, rows: rows)
        case .rule:
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 2: .title3.weight(.semibold)
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    @ViewBuilder
    private func marker(ordered: Bool, number: Int, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .imageScale(.small)
        } else if ordered {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .foregroundStyle(.tertiary)
        }
    }
}

struct InlineText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        Text(Self.attributed(source))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parsed inline Markdown by source. A streaming reply re-renders many times while most of its
    /// paragraphs never change, so each distinct string is parsed once.
    @MainActor private static var cache: [String: AttributedString] = [:]
    private static let cacheLimit = 600

    @MainActor
    static func attributed(_ source: String) -> AttributedString {
        if let cached = cache[source] { return cached }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let parsed = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[source] = parsed
        return parsed
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: code)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
            }
        }
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
}

struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    ForEach(header.indices, id: \.self) { column in
                        Text(InlineText.attributed(header[column]))
                            .fontWeight(.semibold)
                    }
                }
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            Text(InlineText.attributed(column < rows[row].count ? rows[row][column] : ""))
                                .foregroundStyle(.primary.opacity(0.9))
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(12)
        }
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
    }
}

struct CopyButton: View {
    let text: String
    var label = "Copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(label)
    }
}
