import AppKit
import os
import SwiftUI

/// Temporary tap tracing for the strip saga. Remove once taps are proven.
enum StripLog {
    static let log = Logger(subsystem: "iordv.droppycode", category: "strip")
}

/// One attachment preview panel per thumbnail strip. A custom NSPopover (not
/// SwiftUI's `.popover`) because SwiftUI resolves several sibling popovers to
/// a single presentation, so with several pics only the last photo opened.
/// Here one panel is shared and every tap swaps its content, so any photo
/// opens in a single tap.
///
/// The panel anchors to the strip itself rather than to each thumbnail: one
/// stable anchor means no per-photo bookkeeping that can go stale (recycled
/// views, unregistered ids) and silently swallow taps. While open, tapping
/// another photo swaps the content in place instead of re-showing, which is
/// the unreliable step for an already-shown popover.
///
/// The panel is semitransient: taps elsewhere in the window still reach their
/// target, and a tap outside the strip dismisses it, as does Escape, tapping
/// the same thumbnail again, or the strip going away.
@MainActor
final class AttachmentPreviewCoordinator: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var anchor: WeakView?
    private var currentID: Attachment.ID?
    private var monitors: [Any] = []

    override init() {
        super.init()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    /// The strip's own view, captured from the strip's background. One stable
    /// view per strip: never a recycled row, never a stale id.
    func setAnchor(_ view: NSView) {
        anchor = WeakView(view)
    }

    /// Forget the panel when its attachment left
    /// (e.g. removed from the draft while previewing).
    func retire(except ids: Set<Attachment.ID>) {
        if let currentID, !ids.contains(currentID) { close() }
    }

    func toggle(_ attachment: Attachment) {
        StripLog.log.debug("toggle id=\(attachment.id) name=\(attachment.name, privacy: .public) shown=\(self.popover.isShown)")
        if currentID == attachment.id, popover.isShown {
            close()
        } else {
            show(attachment)
        }
    }

    func close() {
        stopMonitors()
        currentID = nil
        if popover.isShown { popover.performClose(nil) }
    }

    private func show(_ attachment: Attachment) {
        let content = AttachmentLargePreview(attachment: attachment)
        let size = Self.contentSize(for: attachment)
        currentID = attachment.id
        if popover.isShown {
            // Already open: swap the content in place. Re-showing a shown
            // popover is unreliable, and the strip anchor never moves anyway.
            StripLog.log.debug("show swap id=\(attachment.id)")
            popover.contentViewController = NSHostingController(rootView: content)
            popover.contentSize = size
            return
        }
        guard let anchor = anchor?.value, anchor.window != nil else {
            StripLog.log.debug("show BLOCKED id=\(attachment.id) anchorNil=\(self.anchor?.value == nil)")
            return
        }
        StripLog.log.debug("show open id=\(attachment.id) anchorFrame=\(anchor.frame.debugDescription, privacy: .public)")
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = size
        startMonitors()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    // MARK: - Dismissal

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.stopMonitors()
            self?.currentID = nil
        }
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
    }

    /// Clicks inside the panel or anywhere on the strip pass through (a
    /// thumbnail button toggles or switches the panel); any other click
    /// dismisses first.
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if event.window === popover.contentViewController?.view.window { return event }
        if let window = event.window,
           let view = anchor?.value, view.window === window, !view.isHiddenOrHasHiddenAncestor,
           view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { return event }
        close()
        return event
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53 else { return event } // Escape
        close()
        return nil
    }

    private func stopMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    /// Generous fixed size per attachment kind. The large preview loads its
    /// image asynchronously, so the panel cannot size itself to content after
    /// it appears; sizing up front also keeps it from jumping when it loads.
    private static func contentSize(for attachment: Attachment) -> NSSize {
        let chrome: CGFloat = 60 // outer padding + name/footer row + spacing
        if attachment.isImage {
            var display = NSSize(width: 480, height: 300)
            if let image = NSImage(contentsOfFile: attachment.path),
               image.size.width > 0, image.size.height > 0 {
                let scale = min(480 / image.size.width, 360 / image.size.height)
                display = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            }
            return NSSize(width: 504, height: ceil(display.height) + chrome)
        }
        if let text = textSample(for: attachment) {
            return NSSize(width: 464, height: min(320, max(120, CGFloat(text.count / 4))) + chrome + 12)
        }
        return NSSize(width: 344, height: 130)
    }

    private static func textSample(for attachment: Attachment) -> String? {
        let url = attachment.url
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 500_000 else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }
}

/// A weak box for an NSView anchor, so coordinators never keep views alive.
final class WeakView {
    weak var value: NSView?
    init(_ value: NSView) { self.value = value }
}

/// Captures the strip's own NSView so the preview panel can anchor to it.
/// Mounted as the strip's background, so it fills exactly the strip.
struct AttachmentAnchorCapture: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        AnchorView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AnchorView)?.onResolve = onResolve
        onResolve(nsView)
    }

    private final class AnchorView: NSView {
        var onResolve: ((NSView) -> Void)?

        init(onResolve: @escaping (NSView) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onResolve?(self) }
        }
    }
}
