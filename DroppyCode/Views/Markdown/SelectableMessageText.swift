import AppKit
import SwiftUI

/// Whole-message text for the chat's 'Select text' mode. Markdown rows render one
/// SwiftUI `Text` per block, so a drag stays inside a paragraph; this hosts the whole
/// reply in one `NSTextView`, where a drag spans paragraphs and Cmd-A / Cmd-C work.
struct SelectableMessageText: NSViewRepresentable {
    /// A drag that began on the markdown blocks and is still under way: where it started
    /// and where the pointer was when the blocks swapped for this view, in this view's
    /// own coordinates. The selection picks up from the start and follows the mouse.
    struct DragOrigin: Equatable {
        let start: CGPoint
        let current: CGPoint
    }

    let text: String
    var pointSize: CGFloat = 13
    var dragOrigin: DragOrigin? = nil
    /// The view stopped being first responder (a click elsewhere): select mode is over.
    var onResign: (() -> Void)? = nil
    /// The text's height at the width the view was actually given, whenever it changes.
    /// The row frames the view to it (see `AssistantMessageRow`): a text view sized by
    /// SwiftUI's proposal alone could be measured at one width and placed at another, and
    /// the text then ran past the row over the messages below it.
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> SelectableMessageTextView {
        let view = SelectableMessageTextView()
        view.onHeightChange = onHeightChange
        return view
    }

    func updateNSView(_ view: SelectableMessageTextView, context: Context) {
        view.render(Self.attributed(text, pointSize: pointSize))
        view.onResign = onResign
        view.onHeightChange = onHeightChange
        if let dragOrigin {
            view.continueDrag(dragOrigin)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectableMessageTextView, context: Context) -> CGSize? {
        // Measured at the proposed width, or at the width it has when the proposal names
        // none (a probe): never at the container's stale width.
        let width = proposal.width ?? (nsView.bounds.width > 0 ? nsView.bounds.width : nil)
        guard let width else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    /// The whole reply as one attributed string: headings, lists, quotes, code and
    /// tables from the app's own blocks, inline runs through the chat's styler.
    @MainActor
    static func attributed(_ markdown: String, pointSize: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let blocks = MarkdownParser.parse(markdown)
        for (index, block) in blocks.enumerated() {
            // One blank line between blocks; the 8pt spacing lives on each block's style.
            if index > 0 {
                out.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: pointSize),
                    .foregroundColor: NSColor.labelColor,
                ]))
            }
            append(block, level: 0, dimmed: false, indent: 0, nested: false, pointSize: pointSize, to: out)
        }
        while out.string.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
        }
        return out
    }

    @MainActor
    private static func append(_ block: MarkdownBlock, level: Int, dimmed: Bool, indent: CGFloat, nested: Bool, pointSize: CGFloat, to out: NSMutableAttributedString) {
        let color = dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor
        let base = NSFont.systemFont(ofSize: pointSize)
        switch block {
        case .heading(let headingLevel, let text):
            let size: CGFloat
            switch headingLevel {
            case 1: size = pointSize * 1.35
            case 2: size = pointSize * 1.2
            case 3: size = pointSize * 1.1
            default: size = pointSize
            }
            appendLine(
                inline(text, size: size, color: color, defaultFont: NSFont.boldSystemFont(ofSize: size)),
                style: blockStyle(indent: indent, nested: nested),
                font: base, color: color, to: out
            )
        case .paragraph(let text):
            appendLine(
                inline(text, size: pointSize, color: color),
                style: blockStyle(indent: indent, nested: nested),
                font: base, color: color, to: out
            )
        case .code(let language, let code):
            if language?.lowercased() == "hydra" {
                // A brief for the team, not code: never the JSON.
                appendLine(
                    NSAttributedString(string: "Delegation block", attributes: [
                        .font: base,
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]),
                    style: blockStyle(indent: indent, nested: nested),
                    font: base, color: color, to: out
                )
                return
            }
            var body = code
            while body.hasSuffix("\n") { body.removeLast() }
            guard !body.isEmpty else { return }
            let mono = NSFont.monospacedSystemFont(ofSize: pointSize - 1, weight: .regular)
            appendLine(
                NSAttributedString(string: body, attributes: [
                    .font: mono,
                    .foregroundColor: color,
                    .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07),
                ]),
                style: blockStyle(indent: indent, nested: nested),
                font: mono, color: color, to: out
            )
        case .list(let ordered, let start, let items):
            for (index, item) in items.enumerated() {
                let marker: String
                if let checked = item.checked {
                    marker = checked ? "☑ " : "☐ "
                } else if ordered {
                    marker = "\(start + index).  "
                } else {
                    marker = "•  "
                }
                if !item.text.isEmpty {
                    let content = NSMutableAttributedString(string: marker, attributes: [
                        .font: base,
                        .foregroundColor: color,
                    ])
                    content.append(inline(item.text, size: pointSize, color: color))
                    appendLine(content, style: listStyle(indent: indent, level: level), font: base, color: color, to: out)
                }
                for child in item.children {
                    append(child, level: level + 1, dimmed: dimmed, indent: indent, nested: true, pointSize: pointSize, to: out)
                }
            }
        case .quote(let inner):
            for child in inner {
                append(child, level: level, dimmed: true, indent: indent + 16, nested: true, pointSize: pointSize, to: out)
            }
        case .table(let header, let rows):
            let bold = NSFont.boldSystemFont(ofSize: pointSize)
            let separator = NSAttributedString(string: "  ", attributes: [.font: base, .foregroundColor: color])
            let style = blockStyle(indent: indent, nested: nested)
            let headLine = NSMutableAttributedString()
            for (index, cell) in header.enumerated() {
                if index > 0 { headLine.append(separator) }
                headLine.append(inline(cell, size: pointSize, color: color, defaultFont: bold))
            }
            appendLine(headLine, style: style, font: base, color: color, to: out)
            for row in rows {
                let line = NSMutableAttributedString()
                for (index, cell) in row.enumerated() {
                    if index > 0 { line.append(separator) }
                    line.append(inline(cell, size: pointSize, color: color))
                }
                appendLine(line, style: style, font: base, color: color, to: out)
            }
        case .rule:
            appendLine(
                NSAttributedString(string: "────────────────", attributes: [
                    .font: base,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]),
                style: blockStyle(indent: indent, nested: nested),
                font: base, color: color, to: out
            )
        }
    }

    /// One inline-styled string through the chat's styler, rebuilt on AppKit types with
    /// an explicit base font and adaptive colours. Links keep only the URL: colour and
    /// underline come from the view's `linkTextAttributes`.
    @MainActor
    private static func inline(_ source: String, size: CGFloat, color: NSColor, defaultFont: NSFont? = nil) -> NSAttributedString {
        let base = NSFont.systemFont(ofSize: size)
        let bold = NSFont.boldSystemFont(ofSize: size)
        let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        let boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
        let pretty = InlineText.attributed(source)
        let out = NSMutableAttributedString()
        for run in pretty.runs {
            let string = String(pretty[run.range].characters)
            guard !string.isEmpty else { continue }
            var font = defaultFont ?? base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                font = mono
            } else {
                let emphasized = intent.contains(.emphasized)
                let strong = intent.contains(.stronglyEmphasized)
                if emphasized && strong { font = boldItalic }
                else if emphasized { font = italic }
                else if strong { font = bold }
            }
            if let url = run.link {
                out.append(NSAttributedString(string: string, attributes: [
                    .font: font,
                    .link: url,
                ]))
            } else {
                out.append(NSAttributedString(string: string, attributes: [
                    .font: font,
                    .foregroundColor: color,
                ]))
            }
        }
        return out
    }

    private static func blockStyle(indent: CGFloat, nested: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.paragraphSpacing = nested ? 0 : 8
        return style
    }

    private static func listStyle(indent: CGFloat, level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let at = indent + 16 * CGFloat(level)
        style.firstLineHeadIndent = at
        style.headIndent = at
        return style
    }

    @MainActor
    private static func appendLine(_ content: NSAttributedString, style: NSParagraphStyle, font: NSFont, color: NSColor, to out: NSMutableAttributedString) {
        let line = NSMutableAttributedString(attributedString: content)
        if line.length > 0 {
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        }
        line.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]))
        out.append(line)
    }
}

/// Non-editable selectable text view that sizes itself to its content width.
/// Same measurement as `LinkTextView`: layout runs once per width, the used height
/// is reported through `sizeThatFits` and the intrinsic size. Default link handling
/// opens links; a mouse down focuses by default, so Cmd-A selects all.
final class SelectableMessageTextView: NSTextView {
    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0
    private var lastLaidOutWidth: CGFloat = 0
    private var lastMeasuredHeight: CGFloat = 0

    /// The view owns its text storage (see `LinkTextView`): a bare container keeps
    /// nothing alive behind it and the view comes out blank.
    private let storage = NSTextStorage()
    /// The drag taken over from the markdown blocks, until the mouse goes up.
    private var dragMonitor: Any?
    private var dragAnchor: Int?
    private var takenDrag: SelectableMessageText.DragOrigin?
    var onResign: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    init() {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        // Vertical sizing is driven by `height(forWidth:)`; never clamp the text to
        // the zero frame this view starts with.
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        allowsUndo = false
        usesFindBar = false
        focusRingType = .none
        textContainerInset = .zero
        // The frame is SwiftUI's to set, from the height reported below; a view that
        // grew itself to its text drew past the row it was given, over the rows after it.
        isVerticallyResizable = false
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        let resigns = super.resignFirstResponder()
        if resigns { onResign?() }
        return resigns
    }

    /// Takes up a drag that began on the markdown blocks: the selection anchors where
    /// the drag started, runs to where the pointer is now, and follows every drag event
    /// until the mouse goes up. The events come through a monitor, since the mouse went
    /// down on a view that is gone. A drag already taken up is left alone.
    func continueDrag(_ origin: SelectableMessageText.DragOrigin) {
        guard takenDrag != origin else { return }
        takenDrag = origin
        endDragMonitor()
        let anchor = characterIndexForInsertion(at: origin.start)
        dragAnchor = anchor
        select(to: origin.current)
        // The mouse is already up: the selection stands as it is.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp {
                self.endDragMonitor()
            } else if let window = self.window, event.window == window {
                self.select(to: self.convert(event.locationInWindow, from: nil))
                self.autoscroll(with: event)
            }
            return event
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            endDragMonitor()
            return
        }
        // Select mode is for selecting: the view takes the keys (Cmd-A, Cmd-C) as it
        // appears, whether a drag or the menu brought it. After the update that put it
        // on screen, not during it, since the chat box gives focus up in the same move.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    isolated deinit {
        endDragMonitor()
    }

    private func select(to point: NSPoint) {
        guard let anchor = dragAnchor else { return }
        let index = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: min(anchor, index), length: abs(index - anchor)))
    }

    private func endDragMonitor() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
    }

    /// New content; skips the layout pass when nothing changed.
    func render(_ text: NSAttributedString) {
        // Links wear the theme's accent with no underline, like the rest of
        // the chrome. Set per render so a theme change recolours links on screen.
        linkTextAttributes = [
            .foregroundColor: Chrome.accentNSColor,
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand,
        ]
        if textStorage?.isEqual(to: text) != true {
            textStorage?.setAttributedString(text)
            lastMeasuredHeight = 0
            measuredWidth = 0
        }
        invalidateIntrinsicContentSize()
    }

    /// The last measurement, so the several `sizeThatFits` calls one layout pass makes
    /// with the same width run the text layout once.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard width > 0, let layout = layoutManager, let container = textContainer else { return 0 }
        if width == measuredWidth { return measuredHeight }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(layout.usedRect(for: container).height)
        measuredWidth = width
        measuredHeight = height
        return height
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : lastLaidOutWidth
        guard width > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        return NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: width))
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        // SwiftUI probes at infinity before settling on a width; make sure the text wraps
        // to the frame it was actually given, not the last probe.
        if width > 0, let container = textContainer, container.containerSize.width != width {
            container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
        guard width > 0, abs(width - lastLaidOutWidth) > 0.5 else { return }
        lastLaidOutWidth = width
        let height = height(forWidth: width)
        guard abs(height - lastMeasuredHeight) > 0.5 else { return }
        lastMeasuredHeight = height
        invalidateIntrinsicContentSize()
        // After this pass, not inside it: the row sets its frame from this.
        let report = onHeightChange
        DispatchQueue.main.async { report?(height) }
    }
}

/// The message as plain text for the clipboard: same walk as above, no styling.
/// Headings as their text, code blocks verbatim, links as `title (url)`, the
/// delegation block left out.
enum MessageText {
    static func plain(_ markdown: String) -> String {
        var lines: [String] = []
        var first = true
        for block in MarkdownParser.parse(markdown) {
            if !first { lines.append("") }
            first = false
            append(block, to: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func append(_ block: MarkdownBlock, to lines: inout [String]) {
        switch block {
        case .heading(_, let text):
            lines.append(inline(text))
        case .paragraph(let text):
            lines.append(inline(text))
        case .code(let language, let code):
            guard language?.lowercased() != "hydra", !code.isEmpty else { return }
            lines.append(code)
        case .list(let ordered, let start, let items):
            for (index, item) in items.enumerated() {
                let marker: String
                if let checked = item.checked {
                    marker = checked ? "☑ " : "☐ "
                } else if ordered {
                    marker = "\(start + index).  "
                } else {
                    marker = "•  "
                }
                if !item.text.isEmpty { lines.append(marker + inline(item.text)) }
                for child in item.children { append(child, to: &lines) }
            }
        case .quote(let inner):
            for child in inner { append(child, to: &lines) }
        case .table(let header, let rows):
            lines.append(header.joined(separator: "  "))
            for row in rows { lines.append(row.joined(separator: "  ")) }
        case .rule:
            break
        }
    }

    /// Links as `title (url)` when the title differs, the bare URL otherwise.
    private static func inline(_ source: String) -> String {
        var text = replace(#"!\[([^\[\]]*)\]\(\S+?\)"#, in: source) { $0[0] }
        text = replace(#"\[([^\[\]]+)\]\((\S+?)(?:\s+"[^"]*")?\)"#, in: text) { groups in
            groups[0] == groups[1] ? groups[1] : "\(groups[0]) (\(groups[1]))"
        }
        text = replace(#"<((?:https?|mailto):[^<>\s]+)>"#, in: text) { $0[0] }
        return text
    }

    private static func replace(_ pattern: String, in text: String, with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }
        var out = text
        for match in matches.reversed() {
            let ns = out as NSString
            var groups: [String] = []
            for group in 1..<match.numberOfRanges {
                let range = match.range(at: group)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            guard let range = Range(match.range, in: out) else { continue }
            out.replaceSubrange(range, with: transform(groups))
        }
        return out
    }
}
