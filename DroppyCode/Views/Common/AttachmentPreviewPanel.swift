import AppKit
import os
import SwiftUI

/// Temporary tap tracing for the strip saga. Remove once taps are proven.
/// `.notice` on purpose: debug/info never hit the persisted log store, so
/// `log show` after a live run would come back empty.
enum StripLog {
    static let log = Logger(subsystem: "iordv.droppycode", category: "strip")
}

/// One attachment preview panel per thumbnail strip. A custom NSPopover (not
/// SwiftUI's `.popover`) because SwiftUI resolves several sibling popovers to
/// a single presentation, so with several pics only the last photo opened.
/// Here one panel is shared and every tap swaps its content, so any photo
/// opens in a single tap.
///
/// The panel anchors to the tapped thumbnail's own view, so the arrow lands
/// on the photo every time. While open, tapping another photo swaps the
/// content and re-shows at the new anchor, so the panel follows the tap
/// instead of staying stranded at the previous photo.
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

    /// `view` is the tapped thumbnail's own view when it has one. The panel aims
    /// at this click's tap point first, so the arrow lands on the photo even if
    /// a stored view went stale; the thumbnail and strip anchors are fallbacks.
    func toggle(_ attachment: Attachment, over view: NSView? = nil) {
        StripLog.log.notice("toggle id=\(attachment.id) name=\(attachment.name, privacy: .public) shown=\(self.popover.isShown)")
        if currentID == attachment.id, popover.isShown {
            close()
        } else {
            show(attachment, over: view)
        }
    }

    func close() {
        stopMonitors()
        currentID = nil
        if popover.isShown { popover.performClose(nil) }
    }

    private func show(_ attachment: Attachment, over view: NSView?) {
        let content = AttachmentLargePreview(attachment: attachment)
        let size = Self.contentSize(for: attachment)
        currentID = attachment.id
        guard let (anchor, rect) = anchorTarget(thumbnailView: view) else {
            StripLog.log.notice("show BLOCKED id=\(attachment.id) anchorNil=\(self.anchor?.value == nil)")
            return
        }
        if popover.isShown {
            // Already open for another photo: swap the content and ask AppKit
            // to move the panel above the tapped photo. Re-showing a shown
            // popover repositions it; the swap stays as the backstop, so even
            // if a reposition were ever ignored the new photo still shows.
            StripLog.log.notice("show swap id=\(attachment.id)")
            popover.contentViewController = NSHostingController(rootView: content)
            popover.contentSize = size
            popover.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
            return
        }
        popover.contentViewController = NSHostingController(rootView: content)
        popover.contentSize = size
        startMonitors()
        popover.show(relativeTo: rect, of: anchor, preferredEdge: .maxY)
    }

    /// The view and rect to anchor the panel to, best proof first. A stored
    /// thumbnail view can go stale (recycled rows, unregistered ids) and land
    /// the arrow far from the tapped photo, so the first choice is this
    /// click's own tap point inside the strip anchor: exactly where the finger
    /// is. The thumbnail's own bounds and the strip's bounds stay as fallbacks
    /// (keyboard/VoiceOver activation carries no click), and nil blocks.
    private func anchorTarget(thumbnailView: NSView?) -> (NSView, NSRect)? {
        if let strip = anchor?.value, strip.window != nil,
           strip.bounds.width >= 8, strip.bounds.height >= 8,
           let event = NSApp.currentEvent, event.type == .leftMouseUp,
           event.window === strip.window {
            var point = strip.convert(event.locationInWindow, from: nil)
            point.x = min(max(point.x, strip.bounds.minX + 2), strip.bounds.maxX - 2)
            let rect = NSRect(x: point.x - 1, y: strip.bounds.maxY - 1, width: 2, height: 1)
            StripLog.log.notice("show anchor=tap stripFrame=\(strip.frame.debugDescription, privacy: .public)")
            return (strip, rect)
        }
        if let thumbnailView, thumbnailView.window != nil {
            StripLog.log.notice("show anchor=thumb thumbFrame=\(thumbnailView.frame.debugDescription, privacy: .public)")
            return (thumbnailView, thumbnailView.bounds)
        }
        if let strip = anchor?.value, strip.window != nil {
            StripLog.log.notice("show anchor=strip stripFrame=\(strip.frame.debugDescription, privacy: .public)")
            return (strip, strip.bounds)
        }
        return nil
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
            // Measured overhead: outer padding (24) + spacing (10) + footer (~18).
            return NSSize(width: 464, height: min(320, max(120, CGFloat(text.count / 4))) + 60)
        }
        // Measured content (~84: padding + 32pt icon row + spacing + footer), so the
        // footer sits just above the photo instead of floating over dead space.
        return NSSize(width: 344, height: 100)
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
    init(_ value: NSView? = nil) { self.value = value }
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
