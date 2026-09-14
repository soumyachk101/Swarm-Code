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

    func makeNSView(context: Context) -> LinkTextView {
        let view = LinkTextView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: LinkTextView, context: Context) {
        // Read so a favicon-load bump rebuilds the string with icons.
        _ = revision
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
                out.append(NSAttributedString(string: string, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.linkColor,
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

/// Non-editable selectable text view that sizes itself to its content width.
/// No continuous work: layout runs once per text or width change.
final class LinkTextView: NSTextView {
    private var lastLaidOutWidth: CGFloat = 0
    private var lastMeasuredHeight: CGFloat = 0

    init() {
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        super.init(frame: .zero, textContainer: container)
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

    /// The last measurement, so the several `sizeThatFits` calls one layout pass makes
    /// with the same width run the text layout once.
    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0

    /// New content; skips the layout pass when nothing changed (favicons and
    /// streaming rebuilds both funnel through here).
    func render(_ text: NSAttributedString) {
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
        guard width > 0, abs(width - lastLaidOutWidth) > 0.5 else { return }
        lastLaidOutWidth = width
        let height = height(forWidth: width)
        guard abs(height - lastMeasuredHeight) > 0.5 else { return }
        lastMeasuredHeight = height
        invalidateIntrinsicContentSize()
    }
}
