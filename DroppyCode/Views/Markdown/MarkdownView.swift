import AppKit
import SwiftUI

struct MarkdownView: View, Equatable {
    let text: String

    /// Equal text renders equally, so finished replies are skipped entirely while a
    /// new reply streams or the timeline rebuilds around them.
    nonisolated static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.text == rhs.text
    }

    var body: some View {
        let blocks = Self.blocks(for: text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
                    .equatable()
                    .transition(.softAppear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parsed blocks by source. Every timeline rebuild re-renders visible rows, but a
    /// finished message parses to the same blocks, so each distinct text parses once.
    @MainActor private static var blockCache: [String: [MarkdownBlock]] = [:]
    private static let blockCacheLimit = 200

    @MainActor
    static func blocks(for text: String) -> [MarkdownBlock] {
        if let cached = blockCache[text] { return cached }
        let parsed = MarkdownParser.parse(text)
        if blockCache.count >= blockCacheLimit { blockCache.removeAll(keepingCapacity: true) }
        blockCache[text] = parsed
        return parsed
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
            .environment(\.markdownDimmed, true)
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

/// Pretty linktitels + favicons voor chat-markdown.
///
/// Kale URL's (`https://…`) kwamen volledig in beeld. Afspraak: toon de titel
/// (expliciete `[titel](url)` of host+pad zonder scheme) met de favicon ervoor.
enum RichLink {
    @MainActor private static var prettyCache: [String: AttributedString] = [:]
    private static let prettyCacheLimit = 600

    @MainActor
    static func prettyAttributed(_ source: String) -> AttributedString {
        if let hit = prettyCache[source] { return hit }
        let base = baseAttributed(source)
        var result = AttributedString()
        for run in base.runs {
            let slice = AttributedString(base[run.range])
            guard let url = run.link else {
                result.append(slice)
                continue
            }
            let display = String(slice.characters)
            var linkSlice: AttributedString
            if isBareDisplay(display, url: url) {
                linkSlice = AttributedString(prettyTitle(for: url))
                linkSlice.link = url
            } else {
                linkSlice = slice
            }
            // Every link renders bold, whether the author titled it or the
            // URL was bare. Other intent bits (italic, code) are preserved.
            var intent = run.inlinePresentationIntent ?? []
            intent.insert(.stronglyEmphasized)
            linkSlice.inlinePresentationIntent = intent
            result.append(linkSlice)
        }
        if prettyCache.count >= prettyCacheLimit { prettyCache.removeAll(keepingCapacity: true) }
        prettyCache[source] = result
        return result
    }

    @MainActor
    static func linkHosts(for source: String) -> [String] {
        let pretty = prettyAttributed(source)
        var hosts: [String] = []
        var seen = Set<String>()
        for run in pretty.runs {
            if let host = run.link?.host?.lowercased(), !host.isEmpty, seen.insert(host).inserted {
                hosts.append(host)
            }
        }
        return hosts
    }

    /// Short display title for a bare URL. Forge links collapse to their
    /// native reference (`!3190`, `#123`); everything else keeps the host
    /// plus the last path segment, so a deep path never spills into chat.
    static func prettyTitle(for url: URL) -> String {
        if let reference = forgeReference(for: url) { return reference }
        guard var host = url.host?.lowercased(), !host.isEmpty else {
            return compactFallback(url.absoluteString)
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let segments = (url.path.removingPercentEncoding ?? url.path)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = segments.last else { return host }
        let tail = last.count > 24 ? String(last.prefix(21)) + "…" : last
        let title = segments.count == 1 ? host + "/" + tail : host + "/…/" + tail
        if title.count > 40 {
            return String(title.prefix(19)) + "…" + String(title.suffix(18))
        }
        return title
    }

    /// `!3190` for merge requests, `#123` for issues and pull requests.
    /// Matches GitLab (`/-/merge_requests/`, `/-/issues/`) and GitHub-style
    /// (`/pull/`, `/issues/`) paths on any host.
    static func forgeReference(for url: URL) -> String? {
        let segments = url.path.split(separator: "/").map(String.init)
        // GitLab nests the kind behind /-/: /group/project/-/merge_requests/3190
        if let dash = segments.firstIndex(of: "-"),
           dash + 2 < segments.count,
           let id = Int(segments[dash + 2]) {
            switch segments[dash + 1] {
            case "merge_requests": return "!\(id)"
            case "issues": return "#\(id)"
            default: break
            }
        }
        // GitHub style: /owner/repo/pull/123 or /owner/repo/issues/123
        if segments.count >= 2, let id = Int(segments.last ?? "") {
            let kind = segments[segments.count - 2]
            if kind == "pull" || kind == "issues" { return "#\(id)" }
        }
        return nil
    }

    /// Hostless URLs (mailto:, custom schemes) have no host to lean on, so
    /// they only get the length cap.
    static func compactFallback(_ absolute: String) -> String {
        guard absolute.count > 40 else { return absolute }
        return String(absolute.prefix(19)) + "…" + String(absolute.suffix(18))
    }

    @MainActor
    static func containsLinks(in source: String) -> Bool {
        prettyAttributed(source).runs.contains { $0.link != nil }
    }

    static func isBareDisplay(_ display: String, url: URL) -> Bool {
        var d = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.hasPrefix("<"), d.hasSuffix(">"), d.count >= 2 {
            d = String(d.dropFirst().dropLast())
        }
        while let last = d.last, ".,;:!?)]}>".contains(last) { d.removeLast() }
        if d == url.absoluteString { return true }
        if (d.hasPrefix("http://") || d.hasPrefix("https://")) && !d.contains(" ") && !d.contains("\n") {
            return true
        }
        return false
    }

    private static func baseAttributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

/// Base point size for link paragraphs. SwiftUI's `.font` environment is
/// opaque, so the two non-default contexts (thinking text, headings) set
/// this explicitly; everything else reads the 13 pt chat default.
private struct MarkdownPointSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 13
}

/// Whether the paragraph renders in secondary styling (quotes, thinking).
/// Threaded explicitly for the same reason as the point size above.
private struct MarkdownDimmedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var markdownPointSize: CGFloat {
        get { self[MarkdownPointSizeKey.self] }
        set { self[MarkdownPointSizeKey.self] = newValue }
    }
    var markdownDimmed: Bool {
        get { self[MarkdownDimmedKey.self] }
        set { self[MarkdownDimmedKey.self] = newValue }
    }
}

@MainActor
enum FaviconCache {
    private static var memory: [String: NSImage] = [:]

    static func cached(host: String) -> NSImage? {
        memory[host.lowercased()]
    }

    /// Hosts with no icon are remembered too, and concurrent asks share one request: a streaming
    /// reply restarts its row's task on every token, and scrolling re-runs it on every appear.
    private static var failed: Set<String> = []
    private static var inFlight: [String: Task<NSImage?, Never>] = [:]

    static func image(for host: String) async -> NSImage? {
        let key = host.lowercased()
        if let hit = memory[key] { return hit }
        guard !failed.contains(key) else { return nil }
        if let task = inFlight[key] { return await task.value }
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(key)&sz=64") else { return nil }
        let task = Task { () -> NSImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let raw = NSImage(data: data) else { return nil }
            return resizedIcon(raw)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            if memory.count >= 300 { memory.removeAll(keepingCapacity: true) }
            memory[key] = image
        } else {
            failed.insert(key)
        }
        return image
    }

    private static func resizedIcon(_ image: NSImage) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

@MainActor
enum RichInlineBuilder {
    static func text(for source: String) -> Text {
        let pretty = RichLink.prettyAttributed(source)
        var out = Text("")
        for run in pretty.runs {
            let slice = Text(AttributedString(pretty[run.range]))
            if let host = run.link?.host?.lowercased(), !host.isEmpty {
                let icon: Text
                if let cached = FaviconCache.cached(host: host) {
                    icon = Text(Image(nsImage: cached))
                } else {
                    icon = Text(Image(systemName: "globe"))
                }
                out = Text("\(out)\(icon) \(slice)")
            } else {
                out = Text("\(out)\(slice)")
            }
        }
        return out
    }
}

struct InlineText: View {
    let source: String
    @Environment(\.markdownPointSize) private var pointSize
    @Environment(\.markdownDimmed) private var dimmed
    @State private var faviconRevision = 0

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        // faviconRevision read so loaded favicons rebuild the text.
        let _ = faviconRevision
        if RichLink.containsLinks(in: source) {
            LinkParagraphView(source: source, pointSize: pointSize, dimmed: dimmed, revision: faviconRevision)
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: source) { await fetchFavicons() }
        } else {
            RichInlineBuilder.text(for: source)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fetchFavicons() async {
        let hosts = await MainActor.run { RichLink.linkHosts(for: source) }
        var changed = false
        for host in hosts where FaviconCache.cached(host: host) == nil {
            if await FaviconCache.image(for: host) != nil { changed = true }
        }
        if changed { await MainActor.run { faviconRevision += 1 } }
    }

    @MainActor
    static func attributed(_ source: String) -> AttributedString {
        RichLink.prettyAttributed(source)
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String

    @State private var isHovering = false
    @State private var didCopy = false
    @State private var showsAll = false

    /// Long dumps render collapsed: materializing thousands of lines at once is what
    /// makes expanding feel laggy. The full text is one instant tap away.
    private static let collapsedLineLimit = 120

    var body: some View {
        let lines = code.components(separatedBy: "\n")
        let truncated = !showsAll && lines.count > Self.collapsedLineLimit
        let visible = truncated ? lines.prefix(Self.collapsedLineLimit).joined(separator: "\n") : code
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
                Text(visible)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
            }
            if lines.count > Self.collapsedLineLimit {
                Button(showsAll ? "Show less" : "Show all \(lines.count) lines") {
                    showsAll.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
}

struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    @State private var showsAll = false

    private static let collapsedRowLimit = 30

    var body: some View {
        let visible = showsAll ? rows : Array(rows.prefix(Self.collapsedRowLimit))
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        ForEach(header.indices, id: \.self) { column in
                            Text(InlineText.attributed(header[column]))
                                .fontWeight(.semibold)
                        }
                    }
                    ForEach(visible.indices, id: \.self) { row in
                        GridRow {
                            ForEach(header.indices, id: \.self) { column in
                                Text(InlineText.attributed(column < visible[row].count ? visible[row][column] : ""))
                                    .foregroundStyle(.primary.opacity(0.9))
                            }
                        }
                    }
                }
                .textSelection(.enabled)
                .padding(12)
            }
            if !showsAll, rows.count > Self.collapsedRowLimit {
                Button("Show all \(rows.count) rows") {
                    showsAll.toggle()
                }
                .buttonStyle(.link)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
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
