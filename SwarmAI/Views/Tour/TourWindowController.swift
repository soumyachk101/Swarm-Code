import AppKit
import SwiftUI

@MainActor
final class TourWindowController {
    static let shared = TourWindowController()

    private final class HostWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private var window: NSWindow?
    private var windowDelegate: WindowDelegate?

    init() {}

    @discardableResult
    func present(
        pages: [TourPage],
        width: CGFloat = 660,
        continueButtonTitle: String = "Continue",
        finishButtonTitle: String = "Done",
        onFinish: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) -> NSWindow {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }

        let dismiss: () -> Void = { [weak self] in
            self?.close()
        }

        let imageHeight = (width / TourView.imageAspectRatio).rounded()
        let maxPanelHeight = Self.maxBottomPanelHeight(
            pages: pages,
            width: width,
            continueButtonTitle: continueButtonTitle,
            finishButtonTitle: finishButtonTitle
        )
        let totalHeight = max(imageHeight + maxPanelHeight, 1)

        let rootView = TourView(
            pages: pages,
            width: width,
            continueButtonTitle: continueButtonTitle,
            finishButtonTitle: finishButtonTitle,
            onFinish: {
                if let onFinish {
                    onFinish()
                } else {
                    onClose?()
                }
                dismiss()
            },
            onClose: {
                onClose?()
                dismiss()
            }
        )

        let contentSize = CGSize(width: width, height: totalHeight)
        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: contentSize)

        let window = HostWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.contentView = hosting

        if let main = NSApp.windows.first(where: { $0.title == "SwarmAI" && $0.isVisible }) {
            let mainFrame = main.frame
            let origin = NSPoint(
                x: mainFrame.midX - contentSize.width / 2,
                y: mainFrame.midY - contentSize.height / 2
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        window.delegate = delegate
        self.windowDelegate = delegate

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
        return window
    }

    private static func maxBottomPanelHeight(
        pages: [TourPage],
        width: CGFloat,
        continueButtonTitle: String,
        finishButtonTitle: String
    ) -> CGFloat {
        guard !pages.isEmpty else { return 0 }

        return pages.enumerated().map { index, page in
            let isLast = (index == pages.count - 1)
            let sizingView = TourBottomPanelSizingView(
                page: page,
                buttonTitle: isLast ? finishButtonTitle : continueButtonTitle
            )
            .frame(width: width)

            let hosting = NSHostingView(rootView: sizingView)
            hosting.layoutSubtreeIfNeeded()
            return hosting.fittingSize.height
        }.max() ?? 0
    }

    func close() {
        window?.close()
        window = nil
        windowDelegate = nil
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

private struct TourBottomPanelSizingView: View {
    let page: TourPage
    let buttonTitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(verbatim: page.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)

            Text(verbatim: buttonTitle)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 220, height: 42)
                .padding(.top, 18)
        }
        .padding(.horizontal, 32)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }
}
