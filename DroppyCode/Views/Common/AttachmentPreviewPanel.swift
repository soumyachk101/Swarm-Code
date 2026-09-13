import AppKit
import SwiftUI

/// One attachment preview panel per thumbnail strip, anchored to the tapped
/// thumbnail. A custom NSPopover (not SwiftUI's `.popover`) for two reasons:
///
/// - SwiftUI resolves several sibling popovers to a single presentation, and a
///   transient popover swallows the tap that would switch to another photo, so
///   with several pics not every preview opens. Here one panel is shared and
///   every tap re-anchors it, so any photo opens in a single tap.
/// - The panel is shown relative to the tapped thumbnail's own view, so the
///   arrow always sits on the photo that was tapped.
///
/// The panel is semitransient: taps elsewhere in the window still reach their
/// target, and a tap outside every thumbnail dismisses it, as does Escape,
/// tapping the same thumbnail again, or the strip going away.
@MainActor
final class AttachmentPreviewCoordinator: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var anchors: [Attachment.ID: WeakView] = [:]
    private var currentID: Attachment.ID?
    private var monitors: [Any] = []

    override init() {
        super.init()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    func register(_ view: NSView, for id: Attachment.ID) {
        anchors[id] = WeakView(view)
    }

    func unregister(_ id: Attachment.ID) {
        anchors[id] = nil
        if currentID == id { close() }
    }

    /// Forget anchors for attachments that are gone, closing the panel when
    /// its own attachment left (e.g. removed from the draft while previewing).
    func retire(except ids: Set<Attachment.ID>) {
        anchors = anchors.filter { ids.contains($0.key) && $0.value.value != nil }
        if let currentID, !ids.contains(currentID) { close() }
    }

    func toggle(_ attachment: Attachment) {
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
        anchors = anchors.filter { $0.value.value != nil }
        guard let anchor = anchors[attachment.id]?.value, anchor.window != nil else { return }
        popover.contentViewController = NSHostingController(rootView: AttachmentLargePreview(attachment: attachment))
        popover.contentSize = Self.contentSize(for: attachment)
        currentID = attachment.id
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

    /// Clicks inside the panel or on any thumbnail pass through (the button
    /// toggles or switches the panel); any other click dismisses first.
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if event.window === popover.contentViewController?.view.window { return event }
        if let window = event.window {
            for weakView in anchors.values {
                guard let view = weakView.value, view.window === window, !view.isHiddenOrHasHiddenAncestor else { continue }
                if view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { return event }
            }
        }
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

private final class WeakView {
    weak var value: NSView?
    init(_ value: NSView) { self.value = value }
}

/// Captures the thumbnail's own NSView so the preview panel can anchor to it.
/// Mounted as the button's background, so it fills exactly the thumbnail.
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
