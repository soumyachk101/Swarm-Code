import AppKit
import SwiftUI

@MainActor
final class HydraHeadHoverPopover: NSObject, NSPopoverDelegate {
    static let shared = HydraHeadHoverPopover()

    private let popover = NSPopover()
    private var shownID: UUID?
    private var pending: Task<Void, Never>?

    private override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    func show(persona: HydraPersona, target: HydraMentionTarget, relativeTo rect: NSRect, of view: NSView) {
        if popover.isShown, shownID == target.threadID { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            if self.popover.isShown { self.popover.close() }
            let content = HydraHeadHoverCard(persona: persona, target: target)
            var size = NSHostingView(rootView: content).intrinsicContentSize
            if size.width <= 0 || size.height <= 0 { size = NSSize(width: 260, height: 80) }
            self.popover.setFixedContent(content, size: size)
            self.shownID = target.threadID
            self.popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        if popover.isShown { popover.performClose(nil) }
        shownID = nil
    }

    func popoverDidClose(_ notification: Notification) {
        shownID = nil
    }
}

private struct HydraHeadHoverCard: View {
    let persona: HydraPersona
    let target: HydraMentionTarget

    var body: some View {
        HStack(spacing: 10) {
            HydraGlyph(persona: persona, size: 28, isRunning: target.status == .running, status: target.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: persona.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(persona.color)
                Text(verbatim: target.task)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(3)
                Text(verbatim: statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private var statusLine: String {
        switch target.status {
        case .running: "Working…"
        case .completed: "Done · click to open the chat"
        case .failed: "Failed · click to open the chat"
        case .stopped: "Stopped · click to open the chat"
        }
    }
}
