import AppKit
import SwiftUI

/// Where the helper panel goes and how big it is, from the chat pane's size. Docked, it
/// sits in the bottom-right corner beside the chat box, the two centred in the pane as one
/// group; when the pane is too narrow for both side by side it sits above the box instead,
/// so neither is ever covered. Dragged elsewhere, it stays within the pane.
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

    /// The docked spot: beside the chat box, the pair centred, or above it when they do not fit.
    var dockedOrigin: CGPoint {
        if sitsBesideComposer {
            let composerWidth = min(Self.composerMaxWidth, pane.width - 2 * Self.sideMargin - composerReserve)
            let groupWidth = composerWidth + Self.gap + panelWidth
            let groupLeft = (pane.width - groupWidth) / 2
            return CGPoint(x: groupLeft + composerWidth + Self.gap, y: pane.height - Self.bottomMargin - panelHeight)
        }
        return CGPoint(
            x: pane.width - Self.sideMargin - panelWidth,
            y: pane.height - composerAreaHeight - Self.gap - panelHeight
        )
    }

    /// Keeps a dragged panel inside the pane.
    func clamped(_ origin: CGPoint) -> CGPoint {
        let inset: CGFloat = 8
        return CGPoint(
            x: min(max(origin.x, inset), max(inset, pane.width - panelWidth - inset)),
            y: min(max(origin.y, inset), max(inset, pane.height - panelHeight - inset))
        )
    }

    func snapsToDock(_ origin: CGPoint) -> Bool {
        abs(origin.x - dockedOrigin.x) < Self.snapDistance && abs(origin.y - dockedOrigin.y) < Self.snapDistance
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
    @State private var isHoveringHandle = false
    @State private var isDragging = false

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
            ComposerArea(runtime: runtime, workingDirectory: workingDirectory, compactModelChip: true)
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
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.handleHeight)
                    .contentShape(.rect)
                    .onHover { hovering in
                        isHoveringHandle = hovering
                        guard !isDragging else { return }
                        if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2, coordinateSpace: .global)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    NSCursor.closedHand.push()
                                }
                                onDrag(value.translation)
                            }
                            .onEnded { _ in
                                isDragging = false
                                NSCursor.pop()
                                if !isHoveringHandle { NSCursor.pop() }
                                onDragEnd()
                            }
                    )
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
        .onDisappear {
            if isDragging { NSCursor.pop() }
            if isHoveringHandle { NSCursor.pop() }
        }
    }
}
