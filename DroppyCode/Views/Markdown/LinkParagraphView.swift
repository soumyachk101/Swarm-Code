import AppKit
import SwiftUI

/// Selectable paragraph with real links. SwiftUI `Text` with selection shows
/// the I-beam cursor over links too; this NSTextView shows the native
/// pointing hand over links and the I-beam over prose, with click-to-open,
/// exactly like every other Mac app. Plain paragraphs without links keep
/// using `InlineText`'s `Text` path, so only link paragraphs pay for this.
struct LinkParagraphView: NSViewRepresentable {
    let source: String
    var pointSize: CGFloat = 13
    var dimmed: Bool = false
    /// Whether the text is still arriving, so its parses bypass the shared caches.
    var streaming: Bool = false
    /// Bumped when favicons finish loading, so the icons appear.
    var revision: Int = 0

    /// Receives the text view, so the hover that sets the cursor can ask it what is under the pointer.
    var onHost: ((LinkTextView) -> Void)?

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
        view.delegate = context.coordinator
        view.mergeTarget = context.environment.mergeRequestTarget
        onHost?(view)
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        // Read so a favicon-load bump rebuilds the string with icons.
        _ = revision
        view.mergeTarget = context.environment.mergeRequestTarget
        view.render(Self.attributed(source: source, pointSize: pointSize, dimmed: dimmed, streaming: streaming))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
                return true
            }
            if let string = link as? String, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        }
    }

    /// Same pretty string the `Text` path renders (short titles, bold
    /// links), rebuilt on AppKit types with an explicit base font, adaptive
    /// colors and favicon attachments.
    @MainActor
    static func attributed(source: String, pointSize: CGFloat, dimmed: Bool, streaming: Bool = false) -> NSAttributedString {
        let pretty = RichLink.prettyAttributed(source, streaming: streaming)
        let base = NSFont.systemFont(ofSize: pointSize)
        let bold = NSFont.boldSystemFont(ofSize: pointSize)
        let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
        let mono = NSFont.monospacedSystemFont(ofSize: max(9, pointSize - 1), weight: .regular)
        let textColor = dimmed ? NSColor.secondaryLabelColor : NSColor.labelColor
        let out = NSMutableAttributedString()
        for run in pretty.runs {
            let string = String(pretty[run.range].characters)
            guard !string.isEmpty else { continue }
            var font = base
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                font = mono
            } else {
                if intent.contains(.emphasized) { font = italic }
                if intent.contains(.stronglyEmphasized) { font = bold }
            }
            if let url = run.link {
                if let host = url.host?.lowercased(),
                   let icon = FaviconCache.cached(host: host) {
                    let attachment = NSTextAttachment()
                    attachment.image = icon
                    attachment.bounds = NSRect(x: 0, y: base.descender + 1, width: 14, height: 14)
                    out.append(NSAttributedString(attachment: attachment))
                    out.append(NSAttributedString(string: " ", attributes: [
                        .font: base,
                        .foregroundColor: textColor,
                    ]))
                }
                // Colour and underline come from the view's `linkTextAttributes`.
                out.append(NSAttributedString(string: string, attributes: [
                    .font: font,
                    .link: url,
                ]))
            } else {
                out.append(NSAttributedString(string: string, attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                ]))
            }
        }
        return out
    }
}

/// What a merge or pull request link in a chat hands its request to, set by a chat that can
/// spawn a merge helper; a link then offers "Merge" at the top of its menu. Compared by the
/// chat it stands for, so a chat setting it on every render never re-renders a link paragraph.
struct MergeRequestTarget: Equatable {
    let chatID: UUID
    let merge: @MainActor (MergeRequestLink) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chatID == rhs.chatID
    }
}

private struct MergeRequestTargetKey: EnvironmentKey {
    static let defaultValue: MergeRequestTarget? = nil
}

extension EnvironmentValues {
    var mergeRequestTarget: MergeRequestTarget? {
        get { self[MergeRequestTargetKey.self] }
        set { self[MergeRequestTargetKey.self] = newValue }
    }
}

/// Non-editable selectable text view that sizes itself to its content width.
/// No continuous work: layout runs once per text or width change.
final class LinkTextView: NSTextView {
    private var lastLaidOutWidth: CGFloat = 0
    private var lastMeasuredHeight: CGFloat = 0

    /// Receives a merge or pull request link when its menu's Merge item is chosen. Nil keeps
    /// the system's menu on every link.
    var mergeTarget: MergeRequestTarget?

    /// The view owns its text storage. `init(frame:textContainer:)` only takes a
    /// container and holds it weakly; a bare container with no layout manager or
    /// storage behind it is released on the spot, leaving the view with no
    /// `textContainer` and no `textStorage`, so `render` had nothing to write into
    /// and every link paragraph came out blank.
    private let storage = NSTextStorage()

    init() {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
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
        importsGraphics = true
        allowsUndo = false
        usesFindBar = false
        focusRingType = .none
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
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

    // MARK: - No per-view tracking

    // A text view normally keeps a tracking area and cursor rects of its own, and AppKit
    // rebuilds every one of them on each frame the content scrolls, which a long thread
    // full of link paragraphs turned into a per-frame tax. These views keep none: the
    // paragraph's SwiftUI hover sets the pointing hand over a link instead (see
    // `InlineText`), and clicks still reach `clickedOnLink` through `mouseDown`.
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
    }

    override func resetCursorRects() {}

    /// Whether `point`, in this view's coordinates, is over a link.
    func hasLink(at point: CGPoint) -> Bool {
        link(at: point) != nil
    }

    /// The link under `point`, in this view's coordinates.
    func link(at point: CGPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer).contains(point) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < textStorage.length, let link = textStorage.attribute(.link, at: index, effectiveRange: nil) else { return nil }
        if let url = link as? URL { return url }
        if let string = link as? String { return URL(string: string) }
        return nil
    }

    // MARK: - Link menu

    /// A merge or pull request link gets "Merge" at the top of its menu, with the plain link
    /// items and the system's own below it. Every other link keeps the system's menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard mergeTarget != nil, let url = link(at: point), let request = MergeRequestLink(url: url) else {
            return super.menu(for: event)
        }
        let menu = NSMenu()
        let merge = NSMenuItem(title: "Merge \(request.label)", action: #selector(mergeRequest(_:)), keyEquivalent: "")
        merge.target = self
        merge.representedObject = request
        menu.addItem(merge)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Link", action: #selector(openLink(_:)), keyEquivalent: "")
        open.target = self
        open.representedObject = url
        menu.addItem(open)
        let copy = NSMenuItem(title: "Copy Link", action: #selector(copyLink(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = url
        menu.addItem(copy)
        if let standard = super.menu(for: event), !standard.items.isEmpty {
            menu.addItem(.separator())
            for item in standard.items {
                standard.removeItem(item)
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc private func mergeRequest(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MergeRequestLink else { return }
        mergeTarget?.merge(request)
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// The last measurement, so the several `sizeThatFits` calls one layout pass makes
    /// with the same width run the text layout once.
    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0

    /// New content; skips the layout pass when nothing changed (favicons and
    /// streaming rebuilds both funnel through here).
    func render(_ text: NSAttributedString) {
        // Links wear the theme's accent with no underline, like the rest of
        // the chrome; the system accent for System/Light/Dark. Set per render
        // so a theme change recolours links already on screen.
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
    }
}
