import AppKit
import SwiftUI

/// Sets up the hosting window the way Droppy's settings window is built: a transparent title bar over
/// a clear window, a SwiftUI glass pane underneath, and AppKit's own traffic lights pinned to the chrome.
struct WindowChromeConfigurator: NSViewRepresentable {
    var sidebarVisible = true

    func makeNSView(context: Context) -> WindowChromeProbeView {
        WindowChromeProbeView()
    }

    func updateNSView(_ nsView: WindowChromeProbeView, context: Context) {
        nsView.sidebarVisible = sidebarVisible
    }
}

final class WindowChromeProbeView: NSView {
    var sidebarVisible = true {
        didSet {
            guard sidebarVisible != oldValue, let window else { return }
            WindowChrome.placeTrafficLights(on: window, sidebarVisible: sidebarVisible, animated: true)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        WindowChrome.configure(window)
        WindowChrome.placeTrafficLights(on: window, sidebarVisible: sidebarVisible, animated: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum WindowChrome {
    private static let leadingIdentifier = "droppycode.trafficLight.leading"
    private static let topIdentifier = "droppycode.trafficLight.top"

    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // A focused window draws a separator under the title bar that cuts through the rounded corner.
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.invalidateShadow()
    }

    /// Pins the native buttons with constraints, since the title bar's own layout pass resets frames.
    static func placeTrafficLights(on window: NSWindow, sidebarVisible: Bool, animated: Bool) {
        let leading = sidebarVisible ? Chrome.trafficLightLeading : Chrome.sheetInset + Chrome.chromeHorizontalPadding
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        var changed = false
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.isHidden = false
            let x = leading + CGFloat(index) * Chrome.trafficLightPitch
            if button.translatesAutoresizingMaskIntoConstraints {
                button.translatesAutoresizingMaskIntoConstraints = false
                let leadingConstraint = button.leadingAnchor.constraint(equalTo: titlebar.leadingAnchor, constant: x)
                leadingConstraint.identifier = leadingIdentifier
                let topConstraint = button.topAnchor.constraint(equalTo: titlebar.topAnchor, constant: Chrome.trafficLightTop)
                topConstraint.identifier = topIdentifier
                NSLayoutConstraint.activate([
                    leadingConstraint,
                    topConstraint,
                    button.widthAnchor.constraint(equalToConstant: Chrome.trafficLightDiameter),
                    button.heightAnchor.constraint(equalToConstant: Chrome.trafficLightDiameter),
                ])
                changed = true
            } else {
                for constraint in titlebar.constraints
                where constraint.firstItem as? NSView === button && constraint.identifier == leadingIdentifier && constraint.constant != x {
                    constraint.constant = x
                    changed = true
                }
            }
        }
        guard changed else { return }
        guard animated else {
            titlebar.layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            titlebar.layoutSubtreeIfNeeded()
        }
    }
}

// MARK: - Sidebar layout

/// The sidebar's width and visibility. Dragging its edge resizes it, and dragging past the
/// collapse point hides it, the same interaction as Droppy's settings sidebar.
@MainActor
@Observable
final class SidebarLayout {
    static let minimumWidth: CGFloat = 210
    static let maximumWidth: CGFloat = 440
    static let collapseThreshold: CGFloat = 110
    static let defaultWidth: CGFloat = 268

    private enum Key {
        static let width = "sidebarWidth"
        static let visible = "sidebarVisible"
    }

    private(set) var width: CGFloat
    private(set) var isVisible: Bool

    @ObservationIgnored private var anchorWidth: CGFloat = 0
    @ObservationIgnored private var restingWidth: CGFloat

    init() {
        let defaults = WebsiteCaptures.defaults ?? .standard
        let stored = (defaults.object(forKey: Key.width) as? Double).map { CGFloat($0) } ?? Self.defaultWidth
        restingWidth = min(Self.maximumWidth, max(Self.minimumWidth, stored))
        width = restingWidth
        isVisible = defaults.object(forKey: Key.visible) as? Bool ?? true
    }

    var renderedWidth: CGFloat { isVisible ? width : 0 }

    func beginDrag() {
        if isVisible {
            anchorWidth = width
            return
        }
        anchorWidth = 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            width = 0
            isVisible = true
        }
    }

    func drag(by translation: CGFloat) {
        width = min(Self.maximumWidth, max(0, anchorWidth + translation))
    }

    func endDrag() {
        if width < Self.collapseThreshold {
            withAnimation(Chrome.panelSlide) { isVisible = false }
            width = restingWidth
        } else {
            let settled = max(Self.minimumWidth, width)
            restingWidth = settled
            withAnimation(Chrome.panelSlide) { width = settled }
        }
        persist()
    }

    func toggle() {
        if !isVisible { width = restingWidth }
        withAnimation(Chrome.panelSlide) { isVisible.toggle() }
        persist()
    }

    private func persist() {
        let defaults = WebsiteCaptures.defaults ?? .standard
        defaults.set(Double(restingWidth), forKey: Key.width)
        defaults.set(isVisible, forKey: Key.visible)
    }
}

// MARK: - Resize handle

/// The grab strip on the sidebar edge. AppKit gives it a real resize cursor and first-click tracking.
struct SidebarResizeHandle: NSViewRepresentable {
    static let hitWidth: CGFloat = 9

    let isActive: Bool
    let onBegin: () -> Void
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> SidebarResizeHandleView {
        let view = SidebarResizeHandleView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: SidebarResizeHandleView, context: Context) {
        update(nsView)
    }

    private func update(_ view: SidebarResizeHandleView) {
        view.onBegin = onBegin
        view.onChange = onChange
        view.onEnd = onEnd
        view.isActive = isActive
    }
}

final class SidebarResizeHandleView: NSView {
    var onBegin: (() -> Void)?
    var onChange: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    var isActive = true {
        didSet {
            guard isActive != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            updateGrip(animated: false)
        }
    }

    private enum Grip {
        static let width: CGFloat = 2.5
        static let restHeight: CGFloat = 10
        static let shownHeight: CGFloat = 22
        static let alpha: Float = 0.6
        static let hoverGlow: Float = 0.05
        static let dragGlow: Float = 0.10
        static let duration: CFTimeInterval = 0.18
        static let verticalInset = Chrome.trafficLightTop + Chrome.trafficLightDiameter
    }

    private var pressOriginX: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private var isHovering = false
    private var isDragging = false
    private let gripLayer = CALayer()
    private let glowLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        gripLayer.cornerRadius = Grip.width / 2
        gripLayer.opacity = 0
        glowLayer.cornerRadius = 4
        glowLayer.opacity = 0
        applyColors()
        layer?.addSublayer(glowLayer)
        layer?.addSublayer(gripLayer)
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.cgColor
            gripLayer.backgroundColor = color
            glowLayer.backgroundColor = color
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override func layout() {
        super.layout()
        updateGrip(animated: false)
    }

    private var showsGrip: Bool { isActive && (isHovering || isDragging) }

    private func updateGrip(animated: Bool) {
        let height = showsGrip ? Grip.shownHeight : Grip.restHeight
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(Grip.duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        gripLayer.frame = CGRect(x: (bounds.width - Grip.width) / 2, y: (bounds.height - height) / 2, width: Grip.width, height: height)
        gripLayer.opacity = showsGrip ? Grip.alpha : 0
        glowLayer.frame = CGRect(
            x: bounds.minX + 0.5,
            y: Grip.verticalInset,
            width: max(0, bounds.width - 1),
            height: max(0, bounds.height - Grip.verticalInset)
        )
        glowLayer.opacity = showsGrip ? (isDragging ? Grip.dragGlow : Grip.hoverGlow) : 0
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isActive else { return }
        addCursorRect(bounds, cursor: .columnResize)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        pressOriginX = event.locationInWindow.x
        isDragging = true
        updateGrip(animated: true)
        onBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        onChange?(event.locationInWindow.x - pressOriginX)
    }

    override func mouseUp(with event: NSEvent) {
        onChange?(event.locationInWindow.x - pressOriginX)
        isDragging = false
        updateGrip(animated: true)
        onEnd?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateGrip(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateGrip(animated: true)
    }
}
