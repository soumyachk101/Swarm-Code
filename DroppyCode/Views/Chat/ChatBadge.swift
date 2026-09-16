import AppKit
import SwiftUI

/// A pill like the Hydra badges in the conversation: a glyph, a title, an
/// optional caption and a chevron, opening its detail in a popover.
/// `needsAttention` means the reader has to do something here: the accent dot
/// wave runs along the badge's top quarter, in the theme's accent, until it is
/// dealt with.
struct ChatBadge<Glyph: View, Detail: View>: View {
    let title: String
    var caption: String? = nil
    var showsChevron = true
    var needsAttention = false
    var isEnabled = true
    @Binding var isPresented: Bool
    @ViewBuilder let glyph: () -> Glyph
    @ViewBuilder let detail: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatZoom) private var zoom
    @State private var coordinator = BadgePopoverCoordinator()

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                glyph()
                    .frame(width: 18, height: 18)
                Text(verbatim: title)
                    .font(.chat(.callout, weight: .medium, zoom: zoom))
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption {
                    Text(verbatim: caption)
                        .font(.chat(.caption, zoom: zoom))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                }
            }
            // The whole pill takes the click, padding included, as the Hydra pills do.
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .overlay(alignment: .top) {
            if needsAttention {
                GeometryReader { proxy in
                    DotFieldLayerView.Representable(color: Chrome.accentNSColor, animated: !reduceMotion)
                        .scaleEffect(y: -1)
                        .frame(height: proxy.size.height * 0.25)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .windowRectAnchor { coordinator.setAnchor(windowRect: $0) }
        .onChange(of: isPresented) { _, shown in
            if shown {
                if !coordinator.isShown { coordinator.show(detail().presentedChrome()) }
            } else {
                coordinator.close()
            }
        }
        .onAppear { coordinator.onClose = { isPresented = false } }
        .onDisappear { coordinator.close() }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 96)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(needsAttention ? "Needs your attention" : ""))
    }
}

/// The badge's detail as an anchored popover instead of a SwiftUI popover, so
/// the arrow starts on the badge: measured once and frozen (see
/// setFixedContent), it never resizes off the badge while shown.
@MainActor
final class BadgePopoverCoordinator: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var anchorRect: CGRect?
    private var monitors: [Any] = []
    private weak var shownIn: NSWindow?
    private var shownRect: NSRect = .zero
    var onClose: (() -> Void)?

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    func setAnchor(windowRect: CGRect) {
        anchorRect = windowRect
    }

    var isShown: Bool { popover.isShown }

    func show<Content: View>(_ content: Content) {
        guard let anchor = anchorRect.flatMap(WindowRectAnchor.target(for:)) else { return }
        var size = NSHostingView(rootView: content).fittingSize
        if size.width <= 0 || size.height <= 0 { size = NSSize(width: 460, height: 320) }
        popover.setFixedContent(content, size: size)
        shownIn = anchor.view.window
        shownRect = anchor.view.convert(anchor.rect, to: nil)
        popover.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: anchor.view.isFlipped ? .minY : .maxY)
        startMonitors()
    }

    func close() {
        guard popover.isShown else { return }
        stopMonitors()
        popover.performClose(nil)
        onClose?()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.stopMonitors()
            self?.onClose?()
        }
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            self?.close()
            return nil
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window, let shownIn, window === shownIn else { return event }
        if shownRect.contains(event.locationInWindow) { return event }
        close()
        return event
    }

    private func stopMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }
}
