import AppKit
import SwiftUI

/// Sets up the hosting window the way Swarm Code's settings window is built: a transparent title bar over
/// a clear window, a SwiftUI glass pane underneath, and AppKit's own traffic lights pinned to the chrome,
/// with the title bar kept reaching down to them so they take their clicks wherever they are pinned.
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

    /// The title bar whose height this view keeps (see `WindowChrome.fitTitlebar`), or nil until
    /// the view is in a window.
    private weak var titlebarContainer: NSView?
    /// A fit is queued for after AppKit's current layout pass.
    private var titlebarFitPending = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let titlebarContainer {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: titlebarContainer)
            self.titlebarContainer = nil
        }
        guard let window else { return }
        WindowChrome.configure(window)
        WindowChrome.placeTrafficLights(on: window, sidebarVisible: sidebarVisible, animated: false)
        // AppKit tiles the title bar back to its own height when the window resizes, and with
        // that the buttons level with the chrome are out of its reach again. It says so through
        // the container's frame, and the fit goes back on.
        guard let container = WindowChrome.titlebarContainer(of: window) else { return }
        container.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(titlebarFrameDidChange), name: NSView.frameDidChangeNotification, object: container
        )
        titlebarContainer = container
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Runs inside AppKit's own tiling of the title bar; the fit waits for it to finish, so the
    /// container is never resized halfway through a pass that is laying out its subviews.
    @objc private func titlebarFrameDidChange(_ notification: Notification) {
        guard !titlebarFitPending else { return }
        titlebarFitPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            titlebarFitPending = false
            if let window { WindowChrome.fitTitlebar(of: window) }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum WindowChrome {
    private static let leadingIdentifier = "swarmcode.trafficLight.leading"
    private static let topIdentifier = "swarmcode.trafficLight.top"

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

    /// Where the buttons sit with the sidebar hidden: level with the chat's chrome capsules,
    /// which then step aside for them, and inset like the chrome is from the sheet's edge.
    static var collapsedTrafficLightTop: CGFloat {
        Chrome.sheetInset + Chrome.chromeTopPadding + (Chrome.capsuleHeight - Chrome.trafficLightDiameter) / 2
    }

    /// How far down the title bar reaches: to the bottom of the chrome row, so the buttons are
    /// inside it in either placement. AppKit only hands a click or a hover to a button within the
    /// title bar's own bounds, and its own bar stops short of buttons level with the chrome; the
    /// clicks fell through to the pane underneath. Being transparent, the bar shows nothing of
    /// its size; what changes is that the row's gaps drag the window, as a title bar's do, while
    /// the controls on it never do. Every chrome control carries a `NoWindowDragArea` behind its
    /// content (and native controls refuse the drag on their own), so a press starting on the zoom
    /// slider or any button, menu or field works only that control and leaves the window in place.
    static var titlebarHeight: CGFloat {
        Chrome.sheetInset + Chrome.chromeTopPadding + Chrome.capsuleHeight
    }

    /// The view AppKit sizes the title bar with: the buttons' bar and its accessories together.
    static func titlebarContainer(of window: NSWindow) -> NSView? {
        window.standardWindowButton(.closeButton)?.superview?.superview
    }

    /// Reaches the title bar down to `titlebarHeight`, keeping its top edge where it is. The
    /// buttons' bar fills the container, so it grows with it and the pinned buttons come inside.
    static func fitTitlebar(of window: NSWindow) {
        guard let container = titlebarContainer(of: window), let themeFrame = container.superview else { return }
        var fitted = container.frame
        guard fitted.height < titlebarHeight else { return }
        if themeFrame.isFlipped {
            fitted.size.height = titlebarHeight
        } else {
            fitted.origin.y = fitted.maxY - titlebarHeight
            fitted.size.height = titlebarHeight
        }
        container.frame = fitted
        container.layoutSubtreeIfNeeded()
    }

    /// Pins the native buttons with constraints, since the title bar's own layout pass resets
    /// frames. Beside the sidebar they sit in its top corner; with it hidden they move over
    /// to the chat's chrome row and down to its centre line, with the slide the chrome makes.
    static func placeTrafficLights(on window: NSWindow, sidebarVisible: Bool, animated: Bool) {
        let leading = sidebarVisible ? Chrome.trafficLightLeading : Chrome.sheetInset + Chrome.chromeHorizontalPadding
        let top = sidebarVisible ? Chrome.trafficLightTop : collapsedTrafficLightTop
        guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
        fitTitlebar(of: window)
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
                let topConstraint = button.topAnchor.constraint(equalTo: titlebar.topAnchor, constant: top)
                topConstraint.identifier = topIdentifier
                NSLayoutConstraint.activate([
                    leadingConstraint,
                    topConstraint,
                    button.widthAnchor.constraint(equalToConstant: Chrome.trafficLightDiameter),
                    button.heightAnchor.constraint(equalToConstant: Chrome.trafficLightDiameter),
                ])
                changed = true
            } else {
                for constraint in titlebar.constraints where constraint.firstItem as? NSView === button {
                    let target: CGFloat? = switch constraint.identifier {
                    case leadingIdentifier: x
                    case topIdentifier: top
                    default: nil
                    }
                    guard let target, constraint.constant != target else { continue }
                    constraint.constant = target
                    changed = true
                }
            }
        }
        guard changed else { return }
        guard animated else {
            titlebar.layoutSubtreeIfNeeded()
            return
        }
        // The same run as Chrome.panelSlide, so the buttons and the chrome row that makes
        // room for them arrive together.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            titlebar.layoutSubtreeIfNeeded()
        }
    }
}

// MARK: - Sidebar layout

/// The sidebar's width and visibility. Dragging its edge resizes it, and dragging past the
/// collapse point hides it, the same interaction as Swarm Code's settings sidebar.
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
    /// Whether the sidebar, as laid out this frame, is wide enough to hold the window buttons
    /// in its top corner. Until it is (while it slides open, or is dragged out from the edge)
    /// they stay over the chat's chrome, and the chrome keeps their room; the moment it is,
    /// they move over and the chrome closes up, together.
    private(set) var holdsTrafficLights: Bool

    /// The width from which the buttons fit beside the sidebar's edge with their usual clearance.
    static var trafficLightsFitWidth: CGFloat {
        Chrome.trafficLightLeading + Chrome.trafficLightsWidth + Chrome.trafficLightClearance
    }

    @ObservationIgnored private var anchorWidth: CGFloat = 0
    @ObservationIgnored private var restingWidth: CGFloat

    init() {
        let defaults = WebsiteCaptures.defaults ?? .standard
        let stored = (defaults.object(forKey: Key.width) as? Double).map { CGFloat($0) } ?? Self.defaultWidth
        restingWidth = min(Self.maximumWidth, max(Self.minimumWidth, stored))
        width = restingWidth
        let visible = defaults.object(forKey: Key.visible) as? Bool ?? true
        isVisible = visible
        holdsTrafficLights = visible
    }

    var renderedWidth: CGFloat { isVisible ? width : 0 }

    /// The sidebar's width as laid out, reported every frame it changes, so the buttons follow
    /// the sidebar as it actually is on screen rather than the state it is heading for.
    func noteLaidOutWidth(_ laidOut: CGFloat) {
        let fits = laidOut >= Self.trafficLightsFitWidth
        if fits != holdsTrafficLights { holdsTrafficLights = fits }
    }

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

    /// The strip's top runs through the title bar, where AppKit moves the window for any view
    /// that lets it; a press on the grip resizes the sidebar and nothing else.
    override var mouseDownCanMoveWindow: Bool { false }

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
