import AppKit
import SwiftUI

/// The queued steering prompts as a tab rising from the top of the chat box. The composer draws
/// over its lower edge, so it reads as part of the box, exactly like the changes tab. Each row
/// is one stacked follow-up: it is sent as a direct user chat message once the running turn
/// finishes, in order from top to bottom.
struct FollowUpQueueTab: View {
    static let overlap: CGFloat = ThreadChangesTab.overlap

    let runtime: ThreadRuntime

    /// Whether the queued rows are folded away under the title.
    @State private var isCollapsed = false

    /// The live reorder: the grabbed prompt, the pointer's travel since the
    /// grab, and how far its slot has already moved to meet it (see `RowDrag`).
    @State private var drag = RowDrag<UUID>()
    /// Watches for the mouse going up while a row is held: a gesture cancelled from under
    /// the pointer reports no end, and the row would stay lifted.
    @State private var mouseUpMonitor: Any?
    /// Each row's height including its padding: one row's slot in the stack.
    @State private var rowHeights: [UUID: CGFloat] = [:]
    /// The row the held row would pair with while nudged right, lit up as the target.
    @State private var pairTarget: UUID?
    /// The rows' natural height, so the fold can animate to and from exactly it.
    @State private var listHeight: CGFloat = 0

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            // The whole title line folds the queue and opens it again; the chevron at
            // its end only says which way it will go: down to close while open, up to
            // reopen while collapsed.
            Button {
                withAnimation(Chrome.panelSlide) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(Chrome.inlineIconFont)
                        .foregroundStyle(Chrome.secondaryText)
                    Text(verbatim: runtime.followUps.count == 1 ? "1 follow-up" : "\(runtime.followUps.count) follow-ups")
                        .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    Text(verbatim: "queued")
                        .foregroundStyle(Chrome.secondaryText)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(Chrome.inlineIconFont)
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Kept out of the key view loop on purpose. SwiftUI's default key-view-loop builder
            // walks focusable views in reading order, and with this line sitting flush above
            // the row's trash button at the same x it never advanced past it: the main
            // thread spun in that rebuild forever (the Sept 15 2026 freezes). None of the tab's
            // controls are meant to be tabbed to, so none of them join the loop.
            .focusable(false)
            .help(isCollapsed ? "Expand queued follow-ups" : "Collapse queued follow-ups")
            .accessibilityLabel(Text(verbatim: runtime.followUps.count == 1 ? "1 queued follow-up" : "\(runtime.followUps.count) queued follow-ups"))
            .accessibilityValue(Text(isCollapsed ? "Collapsed" : "Expanded"))

            // The rows stay in place and fold: a clip animates between zero
            // and their measured height while they fade, so nothing is ever
            // removed mid-animation to linger over the composer as a ghost.
            VStack(alignment: .leading, spacing: 4) {
                Divider().opacity(0.5)

                // Rows carry their own vertical padding and rule, so a row's
                // measured height is exactly its slot and the reorder maths
                // never has to know about stack spacing.
                VStack(alignment: .leading, spacing: 0) {
                    let numbers = Self.numbers(for: runtime.followUps)
                    ForEach(Array(runtime.followUps.enumerated()), id: \.element.id) { index, prompt in
                        let isDragged = drag.id == prompt.id
                        let previous = index > 0 ? runtime.followUps[index - 1] : nil
                        let next = index + 1 < runtime.followUps.count ? runtime.followUps[index + 1] : nil
                        let isBundledWithPrevious = prompt.bundleID != nil && prompt.bundleID == previous?.bundleID
                        let bundledWithNext = prompt.bundleID != nil && prompt.bundleID == next?.bundleID
                        FollowUpRow(
                            position: numbers[prompt.id] ?? index + 1,
                            prompt: prompt,
                            runtime: runtime,
                            isDragged: isDragged,
                            showsRule: prompt.id != runtime.followUps.last?.id && !isDragged && !bundledWithNext,
                            isBundledWithPrevious: isBundledWithPrevious,
                            isPairTarget: pairTarget == prompt.id,
                            isPairing: isDragged && pairTarget != nil,
                            onDragChanged: { translation in dragChanged(prompt.id, translation: translation) },
                            onDragEnded: { dragEnded() }
                        )
                        .modifier(RowHeightReporter(id: prompt.id, heights: $rowHeights))
                        // Only while dragging: settling is the only reader. In pairing
                        // mode the held row indents to show it will pair on release.
                        .offset(x: pairTarget != nil && isDragged ? 14 : 0, y: isDragged ? drag.visualOffset : 0)
                        .animation(Self.slide, value: pairTarget != nil)
                        .zIndex(isDragged ? 1 : 0)
                    }
                }
                .background {
                    // One frame around each bundle: the rows inside it go as one prompt. It
                    // springs in on the drop and follows the rows as they are measured.
                    let spans = Self.bundleSpans(for: runtime.followUps, heights: rowHeights)
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            ForEach(spans, id: \.id) { span in
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
                                    }
                                    .frame(width: geometry.size.width + 16, height: span.height)
                                    .offset(x: -8, y: span.top)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                        .animation(Chrome.panelSlide, value: spans)
                    }
                }
            }
            .padding(.top, 6)
            // Kept always: the fold animates to exactly this.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if height > 0 { listHeight = height }
            }
            .frame(height: isCollapsed ? 0 : listHeight, alignment: .top)
            .opacity(isCollapsed ? 0 : 1)
            .clipped()
            .allowsHitTesting(!isCollapsed)
            .accessibilityHidden(isCollapsed)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7 + Self.overlap)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: shape)
        .contentShape(shape)
        .onChange(of: runtime.followUps.map(\.id)) { _, ids in
            // A row that left mid-drag (deleted, or sent) ends the drag cleanly.
            if let id = drag.id, !ids.contains(id) { dragEnded() }
        }
        .onChange(of: drag.id) { _, id in
            if id != nil {
                guard mouseUpMonitor == nil else { return }
                mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
                    // After the gesture's own end, which settles the row; this only
                    // catches the drags it never reports.
                    DispatchQueue.main.async { dragEnded() }
                    return event
                }
            } else if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                mouseUpMonitor = nil
            }
        }
        .onDisappear {
            if let monitor = mouseUpMonitor {
                NSEvent.removeMonitor(monitor)
                mouseUpMonitor = nil
            }
        }
    }

    /// Reports its row's height for the reorder maths. Always on: switching the modifier
    /// in as a drag began changed every row's structure under the grip mid-gesture, and a
    /// gesture torn down that way never ends, leaving the row lifted for good.
    private struct RowHeightReporter: ViewModifier {
        let id: UUID
        @Binding var heights: [UUID: CGFloat]

        func body(content: Content) -> some View {
            content.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                if heights[id] != height { heights[id] = height }
            }
        }
    }

    // MARK: - Reorder

    /// Neighbours sliding out of the grabbed row's way.
    private static let slide = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// The middle share of a neighbour's slot over which the held row pairs with it rather
    /// than swapping past it: a quarter either side of its centre.
    private static let pairBand: CGFloat = 0.25

    /// One shared number per bundle: the number climbs when a prompt starts a new
    /// bundle or has none at all.
    private static func numbers(for prompts: [FollowUpPrompt]) -> [UUID: Int] {
        var numbers: [UUID: Int] = [:]
        var number = 0
        var previous: UUID?
        var hadPrevious = false
        for prompt in prompts {
            if prompt.bundleID == nil || !hadPrevious || prompt.bundleID != previous {
                number += 1
            }
            numbers[prompt.id] = number
            previous = prompt.bundleID
            hadPrevious = true
        }
        return numbers
    }

    /// One framed span per bundle of two or more rows, in the rows' own coordinates.
    private struct BundleSpan: Equatable {
        let id: UUID
        let top: CGFloat
        let height: CGFloat
    }

    private static func bundleSpans(for prompts: [FollowUpPrompt], heights: [UUID: CGFloat]) -> [BundleSpan] {
        var spans: [BundleSpan] = []
        var top: CGFloat = 0
        var index = 0
        while index < prompts.count {
            let prompt = prompts[index]
            let height = heights[prompt.id] ?? 32
            if let bundle = prompt.bundleID {
                var end = index + 1
                var span = height
                while end < prompts.count, prompts[end].bundleID == bundle {
                    span += heights[prompts[end].id] ?? 32
                    end += 1
                }
                if end - index > 1 { spans.append(BundleSpan(id: bundle, top: top, height: span)) }
                top += span
                index = end
            } else {
                top += height
                index += 1
            }
        }
        return spans
    }

    /// The pointer has moved `translation` since the grab. The grabbed row follows it exactly; over the middle of a neighbour it pairs with that row, past the neighbour's far quarter the two swap. Sideways travel plays no part.
    private func dragChanged(_ id: UUID, translation: CGSize) {
        if drag.id != id {
            drag = RowDrag(id: id)
            pairTarget = nil
            NSCursor.closedHand.push()
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag.translation = translation.height }

        // Past the far quarter of a neighbour the rows swap; over its middle the two pair.
        let moved = drag.settle(order: runtime.followUps.map(\.id), heights: rowHeights, fallbackHeight: 32, pastCentre: Self.pairBand) { neighbour, placeAfter in
            // The neighbour slides and the grabbed row's slot moves in the same animation
            // as its compensation, so it stays put under the pointer while the list flows.
            withAnimation(Self.slide) {
                runtime.moveFollowUp(id, to: neighbour, placeAfter: placeAfter)
            }
        }
        if moved {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }

        // Pairing: the held row's centre sits within the middle half of the neighbour it is
        // heading for, wherever the pointer is sideways.
        let ids = runtime.followUps.map(\.id)
        var target: UUID?
        if let index = ids.firstIndex(of: id) {
            let own = rowHeights[id] ?? 32
            let offset = drag.visualOffset
            var neighbour: UUID?
            if offset > 0, index + 1 < ids.count { neighbour = ids[index + 1] }
            if offset < 0, index > 0 { neighbour = ids[index - 1] }
            if let neighbour {
                let slot = rowHeights[neighbour] ?? 32
                let toCentre = (own + slot) / 2
                if abs(abs(offset) - toCentre) <= slot * Self.pairBand { target = neighbour }
            }
        }
        if target != pairTarget {
            if target != nil, pairTarget == nil {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            withAnimation(Self.slide) { pairTarget = target }
        }
    }

    private func dragEnded() {
        if let held = drag.id, let target = pairTarget {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                runtime.bundleFollowUp(held, onto: target)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            pairTarget = nil
        }
        guard drag.id != nil else { return }
        NSCursor.pop()
        // The offset animates from wherever the pointer let go to the row's
        // slot, so the row settles instead of snapping.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { drag = RowDrag() }
    }
}

private struct FollowUpRow: View {
    let position: Int
    let prompt: FollowUpPrompt
    let runtime: ThreadRuntime
    /// Lifted and following the pointer.
    let isDragged: Bool
    /// The rule under the row, off for the last row and while lifted.
    let showsRule: Bool
    /// The previous row shares this row's bundle: dim the number and join with a bar.
    let isBundledWithPrevious: Bool
    /// The held row hovers over this row while pairing: light it up.
    let isPairTarget: Bool
    /// This row is the one held, and it hovers over a row it will pair with.
    let isPairing: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    /// One preview panel for this row's thumbnails, so every photo opens.
    @State private var preview = AttachmentPreviewSlot()
    /// The editor popover for this row, anchored to its pencil button.
    @State private var editor = FollowUpEditCoordinator()

    /// Whether the pointer is over the reorder grip, for the grab cursor.
    @State private var isHoveringGrip = false
    /// Held while the grip's drag runs; SwiftUI resets it when the gesture ends or is
    /// cancelled, and a cancelled gesture calls no `onEnded` of its own.
    @GestureState private var isGrabbing = false

    /// How far the prose is lifted to centre its x-height on the row's line: half the
    /// gap between cap height and x-height of its 12 pt font, on the half point.
    nonisolated private static let proseLift: CGFloat = {
        let font = NSFont.systemFont(ofSize: 12)
        return ((font.capHeight - font.xHeight) / 2 * 2).rounded() / 2
    }()

    var body: some View {
        // One shared center line: the number, grip, thumbnails, text and
        // buttons all center on it, so single-line rows read as one line.
        HStack(alignment: .center, spacing: 8) {
            // A joined row, a pairing target and the held row while pairing all show the
            // link instead of a number: the bundle goes as one prompt under one number.
            Group {
                if isBundledWithPrevious || isPairTarget || isPairing {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(verbatim: "\(position)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
            .frame(width: 14, alignment: .trailing)
            .accessibilityHidden(true)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Chrome.secondaryText.opacity(isHoveringGrip ? 1 : 0.7))
                .frame(width: 28, height: 22)
                .contentShape(.rect)
                .onHover { hovering in
                    isHoveringGrip = hovering
                    // The grab cursor is the drag's while a drag is on.
                    guard !isDragged else { return }
                    if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .onDisappear {
                    if isHoveringGrip { NSCursor.pop() }
                    isHoveringGrip = false
                }
                .onChange(of: isDragged) { _, dragging in
                    // Released away from the grip: the hover's open hand is
                    // still pushed with no leave to pop it.
                    if !dragging, !isHoveringGrip { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .updating($isGrabbing) { _, grabbing, _ in grabbing = true }
                        .onChanged { value in onDragChanged(value.translation) }
                        .onEnded { _ in onDragEnded() }
                )
                .onChange(of: isGrabbing) { _, grabbing in
                    if !grabbing, isDragged { onDragEnded() }
                }
                .help("Drag above or below to reorder · drop onto the middle of another to send them together")
                .accessibilityLabel(Text("Drag to reorder"))
            if !prompt.attachments.isEmpty {
                // No anchor view under the thumbnails or the strip: nothing in this tab
                // may join SwiftUI's key-view-loop walk (see `WindowRectAnchor`). The
                // panel hangs from the strip's rect on the window instead.
                HStack(spacing: 4) {
                    ForEach(prompt.attachments) { attachment in
                        AttachmentThumbnail(attachment: attachment, size: 22, preview: preview, anchorless: true)
                    }
                }
                .windowRectAnchor { preview.setAnchor(windowRect: $0) }
                .onDisappear { preview.close() }
            }
            VStack(alignment: .leading, spacing: 4) {
                if prompt.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(verbatim: attachmentOnlyLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    // Not selectable on purpose: selection mounts an AppKit text view,
                    // and this tab keeps every AppKit view out of the key-view-loop walk
                    // (see `WindowRectAnchor`). The pencil opens the full text to copy.
                    Text(verbatim: prompt.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.primaryText.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The line box centres on cap height, which is right for the digit and the
            // symbols, but prose is read by its x-height and sat a hair low beside them.
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] + Self.proseLift }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                // Native heads run inside the lead's turn, so that turn is not stopped for
                // a queued prompt; it goes the moment they have reported.
                let sendHelp = runtime.hasWorkingNativeHeads && runtime.isRunning
                    ? "Send as soon as the heads report"
                    : runtime.isRunning ? "Send now (stops the running turn)" : "Send now"
                QueueIconButton(symbol: "paperplane", help: sendHelp) {
                    runtime.sendFollowUpNow(prompt.id)
                }
                QueueIconButton(symbol: "pencil", help: "Edit follow-up") {
                    editor.show(prompt: prompt, runtime: runtime)
                }
                .windowRectAnchor { editor.setAnchor(windowRect: $0) }
                QueueIconButton(symbol: "trash", help: "Delete follow-up") {
                    runtime.removeFollowUp(prompt.id)
                }
            }
            .fixedSize()
        }
        // Tight rows: a one-line follow-up is 32 tall, the grip and buttons 22.
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            if showsRule { Divider().opacity(0.35) }
        }
        // Lifted: a touch larger with a shadow, over an opaque glass so the
        // rows sliding underneath never show through.
        .background {
            if isPairTarget {
                // Lit and framed: the held row will join this one on release.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.5)
                    }
                    .padding(.horizontal, -8)
            }
            if isDragged {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Chrome.overlay(0.12))
                    .padding(.horizontal, -8)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }
        }
        .scaleEffect(isPairTarget ? 1.015 : isDragged ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragged)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPairTarget)
        .onChange(of: prompt.attachments) {
            preview.retire(except: Set(prompt.attachments.map(\.id)))
        }
        .onDisappear {
            preview.close()
            editor.close()
        }
    }

    private var attachmentOnlyLabel: String {
        let images = prompt.attachments.filter(\.isImage).count
        let files = prompt.attachments.count - images
        var parts: [String] = []
        if images == 1 { parts.append("1 image") } else if images > 1 { parts.append("\(images) images") }
        if files == 1 { parts.append("1 file") } else if files > 1 { parts.append("\(files) files") }
        guard !parts.isEmpty else { return "Empty follow-up" }
        return parts.joined(separator: ", ")
    }
}

private struct QueueIconButton: View {
    let symbol: String
    let help: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chrome.secondaryText.opacity(isEnabled ? 1 : 0.35))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// The follow-up editor as an anchored popover instead of a modal sheet, so
/// editing never takes over the window. Application-defined so AppKit never
/// closes it on its own: it survives its nested panels (the file picker, the
/// recent-downloads popover, an attachment preview), and closes on Save,
/// Cancel, Escape, the pencil again, a click elsewhere in the chat window, or
/// when its row goes away.
@MainActor
final class FollowUpEditCoordinator: NSObject {
    private let popover = NSPopover()
    /// The pencil's frame in its window (see `WindowRectAnchor`): the editor hangs from
    /// that rect on the window's content view, since the queue tab mounts no view of
    /// its own for it to hang from.
    private var anchorRect: CGRect?
    private var monitors: [Any] = []
    /// The chat window and the pencil's rect in it as the editor opened, for the click
    /// monitor: resolving the anchor per event (see `WindowRectAnchor.target`) would
    /// name the editor's own window once a click lands there, and close it.
    private weak var shownIn: NSWindow?
    private var shownRect: NSRect = .zero

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
    }

    /// The pencil button's frame in the window, as its geometry reports it.
    func setAnchor(windowRect: CGRect) {
        anchorRect = windowRect
    }

    /// The pencil's place: the window's content view and the rect in it.
    private var anchorTarget: (view: NSView, rect: NSRect)? {
        anchorRect.flatMap(WindowRectAnchor.target(for:))
    }

    func show(prompt: FollowUpPrompt, runtime: ThreadRuntime) {
        guard let anchor = anchorTarget else { return }
        // The pencil toggles: a second tap while open closes the editor.
        if popover.isShown {
            close()
            return
        }
        let editor = FollowUpEditor(
            prompt: prompt,
            runtime: runtime,
            onDone: { [weak self] in self?.close() }
        )
        // Measured once at its ideal size, then frozen (see setFixedContent):
        // a panel that resizes while shown moves off the pencil, and the
        // editor's text and strip must not move it while the user types.
        var size = NSHostingView(rootView: editor).intrinsicContentSize
        if size.width <= 0 || size.height <= 0 { size = NSSize(width: 520, height: 320) }
        popover.setFixedContent(editor, size: size)
        shownIn = anchor.view.window
        shownRect = anchor.view.convert(anchor.rect, to: nil)
        popover.show(relativeTo: anchor.rect, of: anchor.view, preferredEdge: anchor.view.isFlipped ? .maxY : .minY)
        startMonitors()
    }

    func close() {
        stopMonitors()
        if popover.isShown { popover.performClose(nil) }
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

    /// A click in the chat window dismisses the editor, and still reaches its
    /// target. The editor, the file picker and the editor's nested popovers
    /// are windows of their own, so clicks there pass, as does the pencil
    /// (which toggles on its own).
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

/// Edits one queued follow-up, text and attachments included.
private struct FollowUpEditor: View {
    let prompt: FollowUpPrompt
    let runtime: ThreadRuntime
    let onDone: () -> Void

    @State private var text: String
    @State private var attachments: [Attachment]
    @State private var preview = AttachmentPreviewSlot()
    @State private var showingFiles = false
    @FocusState private var editorFocused: Bool

    init(prompt: FollowUpPrompt, runtime: ThreadRuntime, onDone: @escaping () -> Void) {
        self.prompt = prompt
        self.runtime = runtime
        self.onDone = onDone
        _text = State(initialValue: prompt.text)
        _attachments = State(initialValue: prompt.attachments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit follow-up")
                .font(.system(size: 17, weight: .semibold))
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($editorFocused)
                if text.isEmpty {
                    Text("Steer the agent…")
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 110)
            .background(Chrome.overlay(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            // The files and the buttons share one line, the buttons sitting on the
            // files' bottom edge. Many files scroll sideways in their own strip; the
            // buttons never move.
            HStack(alignment: .bottom, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    // The delete badge straddles the thumbnail's far top-right
                    // corner. The cell's own top/trailing padding reserves that
                    // overhang, so the badge sits inside its own cell — never in
                    // the gap where a later sibling could cover it.
                    HStack(spacing: 0) {
                        ForEach(attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment, size: 48, preview: preview)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        attachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .padding(4)
                                    }
                                    .buttonStyle(.plain)
                                    .focusable(false)
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel(Text("Remove \(attachment.name)"))
                                }
                                .padding(.top, 8)
                                .padding(.trailing, 8)
                        }
                        // The add tile: a file chip with a plus that opens the same
                        // recent-downloads popover as the composer's paperclip.
                        Button {
                            showingFiles.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Chrome.secondaryText)
                                .frame(width: 48, height: 48)
                                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
                                .contentShape(.rect(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Add files")
                        .accessibilityLabel(Text("Add files"))
                        .disabled(attachments.count >= 8)
                        .opacity(attachments.count >= 8 ? 0.4 : 1)
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .popover(isPresented: $showingFiles, arrowEdge: .bottom) {
                            DownloadsPopover(
                                pick: { importURL($0) },
                                chooseOther: { showingFiles = false; chooseFiles() }
                            )
                        }
                    }
                    .background {
                        AttachmentAnchorCapture { preview.setAnchor($0) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Button("Cancel", role: .cancel) { onDone() }
                        .buttonStyle(.glass)
                    Button("Save") {
                        runtime.updateFollowUp(prompt.id, text: text, attachments: attachments)
                        onDone()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isEmpty)
                }
                .fixedSize()
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { editorFocused = true }
        .onChange(of: attachments) {
            preview.retire(except: Set(attachments.map(\.id)))
        }
        .onDisappear { preview.close() }
    }

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard attachments.count < 8 else { break }
            importURL(url)
        }
    }

    /// Imports one file URL as an attachment, shared by the open panel and the
    /// recent-downloads popover. HEIC/HEIF converts to JPEG like the composer.
    private func importURL(_ url: URL) {
        guard attachments.count < 8 else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "heic" || fileExtension == "heif" {
            guard let image = NSImage(contentsOf: url), let data = image.jpegData,
                  let attachment = try? Storage.importAttachment(
                    data: data,
                    name: url.deletingPathExtension().lastPathComponent + ".jpg",
                    fileExtension: "jpg"
                  ) else { return }
            attachments.append(attachment)
        } else if let attachment = try? Storage.importAttachment(from: url) {
            attachments.append(attachment)
        }
    }
}
