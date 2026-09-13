import AppKit
import SwiftUI

enum ComposerKey {
    case up
    case down
    case tab
    case escape
    case submit
}

/// Lets SwiftUI reach into the text view for focus and in-place replacements.
@MainActor
final class ComposerController {
    fileprivate weak var textView: ComposerNSTextView?

    var cursorLocation: Int {
        textView?.selectedRange().location ?? 0
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func replaceCharacters(in range: NSRange, with replacement: String) {
        guard let textView, let storage = textView.textStorage, NSMaxRange(range) <= storage.length else { return }
        guard textView.shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (replacement as NSString).length, length: 0))
    }
}

final class ComposerNSTextView: NSTextView {
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    var onFiles: (([URL]) -> Void)?
    var onImage: ((Data) -> Void)?
    var onWidthChange: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onFiles?(urls)
            return
        }
        if pasteboard.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pasteboard),
           let data = image.pngData {
            onImage?(data)
            return
        }
        pasteAsPlainText(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            onFiles?(urls)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    var jpegData: Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String
    let controller: ComposerController
    var onKey: (ComposerKey) -> Bool
    var onFiles: ([URL]) -> Void
    var onImage: (Data) -> Void
    var onCursorChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = ComposerNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.placeholder = placeholder
        textView.string = text
        textView.onFiles = onFiles
        textView.onImage = onImage

        scrollView.documentView = textView
        controller.textView = textView
        let coordinator = context.coordinator
        coordinator.textView = textView
        textView.onWidthChange = { [weak coordinator] in
            Task { @MainActor in coordinator?.updateHeight() }
        }
        Task { @MainActor in
            textView.window?.makeFirstResponder(textView)
            coordinator.updateHeight()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        textView.onFiles = onFiles
        textView.onImage = onImage
        if textView.placeholder != placeholder { textView.placeholder = placeholder }
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            Task { @MainActor in context.coordinator.updateHeight() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: ComposerNSTextView?

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight()
            parent.onCursorChange(textView.selectedRange().location)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onCursorChange(textView.selectedRange().location)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                return parent.onKey(.submit)
            case #selector(NSResponder.moveUp(_:)):
                return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onKey(.down)
            case #selector(NSResponder.insertTab(_:)):
                return parent.onKey(.tab)
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onKey(.escape)
            default:
                return false
            }
        }

        func updateHeight() {
            guard let textView, textView.bounds.width > 24 else { return }
            var contentHeight: CGFloat = 18
            if let layoutManager = textView.textLayoutManager {
                layoutManager.ensureLayout(for: layoutManager.documentRange)
                contentHeight = layoutManager.usageBoundsForTextContainer.height
            }
            let total = ceil(max(18, contentHeight) + textView.textContainerInset.height * 2)
            if abs(parent.height - total) > 0.5 { parent.height = total }
        }
    }
}
