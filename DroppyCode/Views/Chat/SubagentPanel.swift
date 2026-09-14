import AppKit
import SwiftUI

/// The side of the chat column a docked panel sits on.
enum PanelDockSide: Equatable {
    case leading, trailing
}

/// The corner a floating panel docks in.
enum PanelDockCorner: Equatable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var side: PanelDockSide {
        switch self {
        case .topLeading, .bottomLeading: .leading
        case .topTrailing, .bottomTrailing: .trailing
        }
    }

    var isTop: Bool { self == .topLeading || self == .topTrailing }

    /// The corner on the other side of the chat column, at the same edge.
    var acrossTheColumn: PanelDockCorner {
        switch self {
        case .topLeading: .topTrailing
        case .topTrailing: .topLeading
        case .bottomLeading: .bottomTrailing
        case .bottomTrailing: .bottomLeading
        }
    }
}

/// The room the docked panels take from the chat column on each side; the timeline and
/// the chat box centre in what is left, so they stay lined up with each other.
struct PanelReserve: Equatable {
    var leading: CGFloat = 0
    var trailing: CGFloat = 0
}

/// The four docked spots for the pane as it is.
struct PanelDocks {
    var topLeading: CGPoint
    var topTrailing: CGPoint
    var bottomLeading: CGPoint
    var bottomTrailing: CGPoint

    init(layout: SubagentPanelLayout, reserve: PanelReserve) {
        topLeading = layout.dockedOrigin(.topLeading, reserve: reserve)
        topTrailing = layout.dockedOrigin(.topTrailing, reserve: reserve)
        bottomLeading = layout.dockedOrigin(.bottomLeading, reserve: reserve)
        bottomTrailing = layout.dockedOrigin(.bottomTrailing, reserve: reserve)
    }

    subscript(corner: PanelDockCorner) -> CGPoint {
        switch corner {
        case .topLeading: topLeading
        case .topTrailing: topTrailing
        case .bottomLeading: bottomLeading
        case .bottomTrailing: bottomTrailing
        }
    }

    /// The docked spot in a corner with `below` panels already docked in it: each one
    /// stacks a panel's height further from the edge, above the last at the bottom and
    /// below it at the top.
    func stacked(_ corner: PanelDockCorner, below: Int, layout: SubagentPanelLayout) -> CGPoint {
        let spot = self[corner]
        let step = CGFloat(below) * (layout.panelHeight + SubagentPanelLayout.gap)
        let y = corner.isTop ? min(spot.y + step, layout.pane.height - layout.panelHeight - 8) : max(8, spot.y - step)
        return CGPoint(x: spot.x, y: y)
    }
}

/// Where a floating panel goes and how big it is, from the chat pane's size. Docked, it
/// sits in a corner beside the chat column, the group centred in the pane; when the pane
/// is too narrow for both side by side it sits in the corner above the box instead, so
/// neither is ever covered. Dragged elsewhere, it stays within the pane.
struct SubagentPanelLayout: Equatable {
    /// The panel's width, given the room: the composer's own column width at most.
    static let width: CGFloat = 400
    static let minWidth: CGFloat = 300
    /// Between the panel and the chat box.
    static let gap: CGFloat = 12
    /// The chat box's own margins (see ComposerArea), so the docked panel lines up with it.
    static let sideMargin: CGFloat = 20
    static let bottomMargin: CGFloat = 14
    /// The narrowest chat box worth typing in; below it the panel moves above the box.
    static let minComposerWidth: CGFloat = 360
    static let composerMaxWidth: CGFloat = 820
    /// How close to the docked spot a dropped panel snaps back into it.
    static let snapDistance: CGFloat = 56

    var pane: CGSize
    /// The chat box with its tabs and cards, so a panel above it clears them.
    var composerAreaHeight: CGFloat

    var panelWidth: CGFloat {
        min(Self.width, max(Self.minWidth, pane.width - 2 * Self.sideMargin))
    }

    /// Whether the panel and the chat box fit side by side.
    var sitsBesideComposer: Bool {
        pane.width - 2 * Self.sideMargin - panelWidth - Self.gap >= Self.minComposerWidth
    }

    /// The room the docked panel takes from the chat box's row; the box centres in the rest.
    var composerReserve: CGFloat {
        sitsBesideComposer ? panelWidth + Self.gap : 0
    }

    var panelHeight: CGFloat {
        let ideal = min(520, max(300, pane.height * 0.5))
        let below = sitsBesideComposer ? Self.bottomMargin : composerAreaHeight + Self.gap
        let room = pane.height - Chrome.contentTopInset - below
        return max(220, min(ideal, room))
    }

    var panelSize: CGSize { CGSize(width: panelWidth, height: panelHeight) }

    /// The docked spot in a corner: beside the chat column, the group centred, at the top
    /// under the chrome row or at the bottom level with the chat box; or, when the pane is
    /// too narrow for both side by side, in the corner above the box. Panels docked on
    /// both sides take room from both ends of the column, so it narrows to sit between them.
    func dockedOrigin(_ corner: PanelDockCorner, reserve: PanelReserve) -> CGPoint {
        let y = corner.isTop
            ? Chrome.contentTopInset
            : pane.height - (sitsBesideComposer ? Self.bottomMargin : composerAreaHeight + Self.gap) - panelHeight
        if sitsBesideComposer {
            let row = pane.width - reserve.leading - reserve.trailing
            let composerWidth = min(Self.composerMaxWidth, row - 2 * Self.sideMargin)
            let composerLeft = reserve.leading + (row - composerWidth) / 2
            switch corner.side {
            case .leading: return CGPoint(x: composerLeft - Self.gap - panelWidth, y: y)
            case .trailing: return CGPoint(x: composerLeft + composerWidth + Self.gap, y: y)
            }
        }
        return CGPoint(x: corner.side == .leading ? Self.sideMargin : pane.width - Self.sideMargin - panelWidth, y: y)
    }

    /// Where a dropped panel docks, if anywhere: let go in the top or bottom band and out
    /// towards either side, it slides into that corner. Nil leaves it where it was dropped.
    func dockCorner(forDrop origin: CGPoint, docks: PanelDocks) -> PanelDockCorner? {
        let centre = origin.x + panelWidth / 2
        let isTop = origin.y <= docks.topLeading.y + Self.snapDistance
        let isBottom = origin.y >= docks.bottomLeading.y - Self.snapDistance
        guard isTop || isBottom else { return nil }
        let bottom = isBottom && !isTop
        if centre >= docks.bottomTrailing.x - Self.snapDistance { return bottom ? .bottomTrailing : .topTrailing }
        if centre <= docks.bottomLeading.x + panelWidth + Self.snapDistance { return bottom ? .bottomLeading : .topLeading }
        return nil
    }

    /// Keeps a dragged panel inside the pane.
    func clamped(_ origin: CGPoint) -> CGPoint {
        let inset: CGFloat = 8
        return CGPoint(
            x: min(max(origin.x, inset), max(inset, pane.width - panelWidth - inset)),
            y: min(max(origin.y, inset), max(inset, pane.height - panelHeight - inset))
        )
    }
}

/// A helper thread's chat as a small floating glass panel: its conversation, its own chat
/// box at the bottom, and a glass pill in the top-right corner that closes it and stops the
/// chat. The strip along the top is the handle: drag it to move the panel anywhere in the pane.
struct SubagentPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let thread: ChatThread
    let size: CGSize
    let workingDirectory: String?
    let projectName: String?
    /// The pointer's travel since the handle was grabbed.
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let close: () -> Void

    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollState = TimelineScrollState()

    private static let cornerRadius: CGFloat = 22
    private static let handleHeight: CGFloat = Chrome.chromeTopPadding + Chrome.capsuleHeight + 6

    var body: some View {
        let runtime = model.runtime(for: thread.id)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        ThreadTimeline(
            runtime: runtime,
            scrollChrome: scrollChrome,
            scrollState: scrollState,
            projectName: projectName,
            workingDirectory: workingDirectory,
            supportsRewind: false,
            columnHeight: size.height
        )
        .equatable()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerArea(runtime: runtime, workingDirectory: workingDirectory, compactModelChip: true, takesFocusOnAppear: false)
                .overlay(alignment: .top) {
                    JumpToLatestButton(scrollState: scrollState)
                }
        }
        .overlay(alignment: .top) {
            PaneTopVeil(model: scrollChrome)
        }
        .overlay(alignment: .top) {
            HStack(alignment: .top, spacing: 8) {
                // The handle. Invisible, like a window's title bar with no title; the
                // cursor says what it does.
                PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.handleHeight)
                    .help("Drag to move")
                    .accessibilityLabel(Text("Drag to move"))
                ChromeCircleButton(symbol: "xmark", help: "Close and stop this chat") {
                    close()
                }
                .padding(.top, Chrome.chromeTopPadding)
                .padding(.trailing, Chrome.chromeHorizontalPadding)
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            // The window's own recipe, on the panel: one glass surface, a scrim for the
            // text over whatever the panel floats above, the theme's tint, and a hairline.
            let isDark = colorScheme == .dark
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Chrome.overlay(0.14), lineWidth: 1)
        }
        // The scrim sits under the glass and carries the panel's shadow: a plain filled
        // shape, so its shadow is drawn once and kept. A shadow on the whole panel was
        // blurred again with every token the transcript streamed under it.
        .background {
            let isDark = colorScheme == .dark
            shape
                .fill((isDark ? Color.black : Color.white).opacity(isDark ? 0.3 : 0.34))
                .shadow(color: .black.opacity(isDark ? 1 : 0.65), radius: 28, y: 10)
        }
    }
}

/// The strip a floating panel is dragged by. AppKit tracks the press itself, the way the
/// sidebar's resize grip does: the first click takes hold even when the window is not key,
/// nothing under the strip can claim the drag once it has begun, and the hand cursor is a
/// real cursor rect. A SwiftUI drag gesture here lost most presses to the transcript's
/// scroll view beneath it. Reports the pointer's travel since the press in the pane's
/// coordinates, y running down like the panel's offset.
struct PanelDragHandle: NSViewRepresentable {
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void

    func makeNSView(context: Context) -> PanelDragHandleView {
        let view = PanelDragHandleView(frame: .zero)
        update(view)
        return view
    }

    func updateNSView(_ nsView: PanelDragHandleView, context: Context) {
        update(nsView)
    }

    private func update(_ view: PanelDragHandleView) {
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
    }
}

final class PanelDragHandleView: NSView {
    var onDrag: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?

    /// How far the pointer travels before a press becomes a drag.
    private static let slop: CGFloat = 2

    private var pressOrigin: NSPoint = .zero
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A press on the handle moves the panel, never the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let travel = travel(to: event)
        if !isDragging {
            guard abs(travel.width) >= Self.slop || abs(travel.height) >= Self.slop else { return }
            isDragging = true
            NSCursor.closedHand.push()
        }
        onDrag?(travel)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()
        onDrag?(travel(to: event))
        onDragEnd?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Taken out mid-drag, the panel lets go of the cursor with it.
        if window == nil, isDragging {
            isDragging = false
            NSCursor.pop()
        }
    }

    /// The pointer's travel since the press. AppKit's y runs up; the panel's offset runs down.
    private func travel(to event: NSEvent) -> CGSize {
        let point = event.locationInWindow
        return CGSize(width: point.x - pressOrigin.x, height: pressOrigin.y - point.y)
    }
}
