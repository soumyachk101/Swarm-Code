import AppKit
import SwiftUI

struct MarkdownView: View, Equatable {
    let text: String
    /// True while the text is still arriving. A streaming message parses through a slot of
    /// its own instead of the shared cache: it changes on every flush, and each of those
    /// would otherwise take a cache entry away from a finished message that scrolling back
    /// through the thread will ask for again.
    var isStreaming = false

    /// Equal text renders equally, so finished replies are skipped entirely while a
    /// new reply streams or the timeline rebuilds around them.
    nonisolated static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.text == rhs.text && lhs.isStreaming == rhs.isStreaming
    }

    var body: some View {
        let blocks = Self.blocks(for: text, streaming: isStreaming)
        let last = blocks.count - 1
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                MarkdownBlockView(block: block)
                    .equatable()
                    // Only the block still being written is streaming; the ones above it are
                    // settled and cache like any finished text.
                    .environment(\.markdownStreaming, isStreaming && index == last)
                    .transition(.softAppear)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Parsed blocks by source. Rows are rebuilt as they scroll into view, but a finished
    /// message parses to the same blocks, so each distinct text parses once.
    @MainActor private static var blockCache = RecentCache<String, [MarkdownBlock]>(limit: 200)
    /// The one streaming message's latest parse, so re-renders between flushes never parse.
    @MainActor private static var streamingParse: (text: String, blocks: [MarkdownBlock])?

    @MainActor
    static func blocks(for text: String, streaming: Bool = false) -> [MarkdownBlock] {
        if streaming {
            if let parse = streamingParse, parse.text == text { return parse.blocks }
            let parsed = MarkdownParser.parse(text)
            streamingParse = (text, parsed)
            return parsed
        }
        if let cached = blockCache.value(for: text) { return cached }
        // A message that just finished streaming is already parsed; keep that parse.
        let parsed: [MarkdownBlock]
        if let parse = streamingParse, parse.text == text {
            parsed = parse.blocks
            streamingParse = nil
        } else {
            parsed = MarkdownParser.parse(text)
        }
        blockCache.insert(parsed, for: text)
        return parsed
    }

    /// Parses finished messages before their rows are built, off the main thread, so a row
    /// scrolling into view finds its blocks and its paragraphs' runs already made instead of
    /// parsing them on the frame. Texts already cached cost nothing.
    @MainActor
    static func warm(_ texts: [String]) async {
        let missing = texts.filter { !blockCache.contains($0) }
        guard !missing.isEmpty else { return }
        let parsed = await Task.detached(priority: .utility) {
            missing.map { text -> (String, [MarkdownBlock], [(String, AttributedString)]) in
                let blocks = MarkdownParser.parse(text)
                var inline: [(String, AttributedString)] = []
                for source in inlineSources(of: blocks) { inline.append((source, RichLink.build(source))) }
                return (text, blocks, inline)
            }
        }.value
        for (text, blocks, inline) in parsed {
            if !blockCache.contains(text) { blockCache.insert(blocks, for: text) }
            for (source, pretty) in inline { RichLink.warm(source, with: pretty) }
        }
    }

    /// Every inline-styled string a set of blocks renders: paragraphs, headings, list items.
    nonisolated private static func inlineSources(of blocks: [MarkdownBlock]) -> [String] {
        var out: [String] = []
        for block in blocks {
            switch block {
            case .paragraph(let text), .heading(_, let text):
                out.append(text)
            case .list(_, _, let items):
                for item in items {
                    if !item.text.isEmpty { out.append(item.text) }
                    out += inlineSources(of: item.children)
                }
            case .quote(let inner):
                out += inlineSources(of: inner)
            case .code, .table, .rule:
                break
            }
        }
        return out
    }
}

struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    @Environment(\.markdownDimmed) private var dimmed
    @Environment(\.markdownListDepth) private var listDepth

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
                        // Nested lists read one level deeper, so their dots turn into rings.
                        .environment(\.markdownListDepth, listDepth + 1)
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
                .fontWeight(.medium)
                .foregroundStyle(markerColor)
        } else {
            // A hidden bullet glyph keeps the text baseline; the dot drawn over it is the
            // marker, in the theme accent. Nested levels get a ring instead of a fill.
            Text("•")
                .hidden()
                .overlay {
                    if listDepth == 0 {
                        Circle()
                            .fill(markerColor)
                            .frame(width: 5, height: 5)
                    } else {
                        Circle()
                            .strokeBorder(markerColor, lineWidth: 1.2)
                            .frame(width: 5.5, height: 5.5)
                    }
                }
        }
    }

    private var markerColor: Color {
        Chrome.accent.opacity(dimmed ? 0.55 : 0.9)
    }
}

/// How many lists the block sits inside; the marker style follows it.
private struct MarkdownListDepthKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var markdownListDepth: Int {
        get { self[MarkdownListDepthKey.self] }
        set { self[MarkdownListDepthKey.self] = newValue }
    }
}

/// Pretty linktitels + favicons voor chat-markdown.
///
/// Kale URL's (`https://…`) kwamen volledig in beeld. Afspraak: toon de titel
/// (expliciete `[titel](url)` of host+pad zonder scheme) met de favicon ervoor.
enum RichLink {
    @MainActor private static var prettyCache = RecentCache<String, AttributedString>(limit: 400)
    /// The paragraph still being streamed, kept apart so its every flush leaves the cache alone.
    @MainActor private static var streamingPretty: (source: String, value: AttributedString)?

    @MainActor
    static func prettyAttributed(_ source: String, streaming: Bool = false) -> AttributedString {
        if streaming {
            if let pretty = streamingPretty, pretty.source == source { return pretty.value }
            let value = build(source)
            streamingPretty = (source, value)
            return value
        }
        if let hit = prettyCache.value(for: source) { return hit }
        let value: AttributedString
        if let pretty = streamingPretty, pretty.source == source {
            value = pretty.value
            streamingPretty = nil
        } else {
            value = build(source)
        }
        prettyCache.insert(value, for: source)
        return value
    }

    /// Stores a run built off the main thread (see `MarkdownView.warm`).
    @MainActor
    static func warm(_ source: String, with pretty: AttributedString) {
        if !prettyCache.contains(source) { prettyCache.insert(pretty, for: source) }
    }

    nonisolated static func build(_ source: String) -> AttributedString {
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
        return result
    }

    @MainActor
    static func linkHosts(for source: String, streaming: Bool = false) -> [String] {
        let pretty = prettyAttributed(source, streaming: streaming)
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
    static func containsLinks(in source: String, streaming: Bool = false) -> Bool {
        prettyAttributed(source, streaming: streaming).runs.contains { $0.link != nil }
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

/// Whether the paragraph's text is still arriving, so its parses bypass the shared caches.
private struct MarkdownStreamingKey: EnvironmentKey {
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
    var markdownStreaming: Bool {
        get { self[MarkdownStreamingKey.self] }
        set { self[MarkdownStreamingKey.self] = newValue }
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
        // Icons come from a service on the web, so the host is told to it. Tool output is
        // full of names that belong to this machine and this network; those never leave.
        guard isPublic(host: key) else {
            failed.insert(key)
            return nil
        }
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

    /// Suffixes that only ever name something inside a network, never a site on the web.
    private static let privateSuffixes = [
        ".local", ".localhost", ".localdomain", ".internal", ".intranet",
        ".lan", ".home", ".home.arpa", ".test", ".invalid", ".corp",
    ]

    /// Whether a host is one a public favicon service could possibly know: not the loopback,
    /// not a bare machine name, not one of the private suffixes, and not an address in the
    /// ranges that never leave a network. A host that fails any of these is never asked about.
    static func isPublic(host: String) -> Bool {
        guard !host.isEmpty, host != "localhost" else { return false }
        // An IPv6 literal (no brackets by the time it comes off a URL) has no favicon worth
        // the request, and half of them are link-local or unique-local addresses.
        guard !host.contains(":") else { return false }
        for suffix in privateSuffixes where host.hasSuffix(suffix) { return false }
        // A single label with no dot in it is a machine on this network, not a site.
        guard host.contains(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        var octets: [Int] = []
        for label in labels {
            guard let value = Int(label), (0...255).contains(value) else { break }
            octets.append(value)
        }
        guard octets.count == 4, octets.count == labels.count else { return true }
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _): return false
        case (169, 254), (192, 168): return false
        case (172, 16...31): return false
        // Carrier-grade NAT, which tunnels and VPNs hand out.
        case (100, 64...127): return false
        default: return true
        }
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
    /// Built runs by source. Paragraphs are rebuilt whenever their row scrolls into view,
    /// and joining the runs is the same work every time, so a settled paragraph keeps its
    /// text. Only link-free paragraphs come through here, so no favicon can go stale in it.
    private static var textCache = RecentCache<String, Text>(limit: 400)

    static func text(for source: String, streaming: Bool = false) -> Text {
        if !streaming, let cached = textCache.value(for: source) { return cached }
        let pretty = RichLink.prettyAttributed(source, streaming: streaming)
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
        if !streaming { textCache.insert(out, for: source) }
        return out
    }
}

struct InlineText: View {
    let source: String
    @Environment(\.markdownPointSize) private var pointSize
    @Environment(\.markdownDimmed) private var dimmed
    @Environment(\.markdownStreaming) private var streaming
    @State private var faviconRevision = 0
    /// The link paragraph's text view, for the hover that sets the cursor.
    @State private var linkView = WeakView()
    /// Whether the pointing hand is up over a link, so hover only sets the cursor on change.
    @State private var showsHand = false

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        // faviconRevision read so loaded favicons rebuild the text.
        let _ = faviconRevision
        if RichLink.containsLinks(in: source, streaming: streaming) {
            // An AppKit view has no text baseline of its own, so a list's marker sat on the
            // paragraph's top edge and the text started a line below it. The first line's
            // baseline is the base font's ascender from the top; the last is one line up
            // from the bottom. Measured once per size and kept: the alignment guides run
            // off the main actor, so they take the two numbers rather than the font.
            let metrics = Self.metrics(pointSize: pointSize)
            let ascender = metrics.ascender
            let lineHeight = metrics.lineHeight
            LinkParagraphView(source: source, pointSize: pointSize, dimmed: dimmed, streaming: streaming, revision: faviconRevision, onHost: { linkView.value = $0 })
                .frame(maxWidth: .infinity, alignment: .leading)
                .alignmentGuide(.firstTextBaseline) { _ in ascender }
                .alignmentGuide(.lastTextBaseline) { $0.height - lineHeight + ascender }
                // The pointing hand over links, from here rather than the text view's own
                // tracking (which AppKit would rebuild every scrolled frame). Hover is off
                // while the timeline scrolls, so this costs nothing then.
                .onContinuousHover(coordinateSpace: .local) { phase in
                    let overLink: Bool
                    switch phase {
                    case .active(let point): overLink = (linkView.value as? LinkTextView)?.hasLink(at: point) ?? false
                    case .ended: overLink = false
                    }
                    guard overLink != showsHand else { return }
                    showsHand = overLink
                    if overLink { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .onDisappear {
                    if showsHand { NSCursor.pop(); showsHand = false }
                }
                .task(id: source) { await fetchFavicons() }
        } else {
            RichInlineBuilder.text(for: source, streaming: streaming)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The base font's baseline numbers, measured once per point size. Asking AppKit for a
    /// font and its metrics on every render of every link paragraph is work with one answer.
    @MainActor private static var metricsBySize: [CGFloat: (ascender: CGFloat, lineHeight: CGFloat)] = [:]

    @MainActor
    private static func metrics(pointSize: CGFloat) -> (ascender: CGFloat, lineHeight: CGFloat) {
        if let known = metricsBySize[pointSize] { return known }
        let font = NSFont.systemFont(ofSize: pointSize)
        let measured = (ceil(font.ascender), ceil(font.ascender - font.descender + font.leading))
        metricsBySize[pointSize] = measured
        return measured
    }

    private func fetchFavicons() async {
        let streaming = streaming
        let hosts = await MainActor.run { RichLink.linkHosts(for: source, streaming: streaming) }
        var changed = false
        for host in hosts where FaviconCache.cached(host: host) == nil {
            if await FaviconCache.image(for: host) != nil { changed = true }
        }
        if changed { await MainActor.run { faviconRevision += 1 } }
    }

    @MainActor
    static func attributed(_ source: String, streaming: Bool = false) -> AttributedString {
        RichLink.prettyAttributed(source, streaming: streaming)
    }
}

/// A hover flag kept in an object instead of view state. A code block's body holds its whole
/// text, counts its lines and cuts its head off; running all of that again because the
/// pointer crossed the block is what made the copy control feel sticky over a big dump.
/// Only the control reads this, so only the control re-renders.
@MainActor
@Observable
private final class BlockHover {
    var isHovering = false
}

/// The copy control on a code block's header, in a view of its own so the hover that
/// reveals it never reaches the block's text.
private struct CodeBlockCopyButton: View {
    let text: String
    let hover: BlockHover

    var body: some View {
        CopyButton(text: text)
            .opacity(hover.isHovering ? 1 : 0)
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String

    @State private var hover = BlockHover()
    @State private var showsAll = false

    /// Long dumps render collapsed: materializing thousands of lines at once is what
    /// makes expanding feel laggy. The full text is one instant tap away.
    private static let collapsedLineLimit = 120

    var body: some View {
        // A count of newlines, not a split: hovering re-runs this body, and a big dump split
        // into an array of lines on every hover is what made the copy button feel sticky.
        let lineCount = 1 + code.utf8.count { $0 == 0x0A }
        let truncated = !showsAll && lineCount > Self.collapsedLineLimit
        let visible = truncated ? Self.head(of: code, lines: Self.collapsedLineLimit) : code
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CodeBlockCopyButton(text: code, hover: hover)
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
            if lineCount > Self.collapsedLineLimit {
                Button(showsAll ? "Show less" : "Show all \(lineCount) lines") {
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
        .onHover { hover.isHovering = $0 }
    }

    /// The first `lines` lines of `code`, without splitting the rest.
    private static func head(of code: String, lines: Int) -> String {
        var remaining = lines
        var end = code.utf8.startIndex
        for index in code.utf8.indices where code.utf8[index] == 0x0A {
            remaining -= 1
            if remaining == 0 {
                end = index
                break
            }
        }
        return remaining == 0 ? String(code[..<end]) : code
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
                // Cells go through the shared cache even while the table streams: only its
                // last row changes between flushes, and the rest hit.
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
