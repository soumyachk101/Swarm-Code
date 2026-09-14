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
    /// Each row's height including its padding: one row's slot in the stack.
    @State private var rowHeights: [UUID: CGFloat] = [:]
    /// The rows' natural height, so the fold can animate to and from exactly it.
    @State private var listHeight: CGFloat = 0

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.right")
                    .font(Chrome.inlineIconFont)
                    .foregroundStyle(Chrome.secondaryText)
                Text(verbatim: runtime.followUps.count == 1 ? "1 follow-up" : "\(runtime.followUps.count) follow-ups")
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                Text(verbatim: "queued")
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 8)
                Button {
                    withAnimation(Chrome.panelSlide) { isCollapsed.toggle() }
                } label: {
                    // Points the way the tab will go: down to close while open,
                    // up to reopen while collapsed.
                    Image(systemName: "chevron.down")
                        .font(Chrome.inlineIconFont)
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                        .rotationEffect(.degrees(isCollapsed ? 180 : 0))
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand queued follow-ups" : "Collapse queued follow-ups")
                .accessibilityLabel(Text(isCollapsed ? "Expand queued follow-ups" : "Collapse queued follow-ups"))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .accessibilityLabel(Text(verbatim: runtime.followUps.count == 1 ? "1 queued follow-up" : "\(runtime.followUps.count) queued follow-ups"))

            // The rows stay in place and fold: a clip animates between zero
            // and their measured height while they fade, so nothing is ever
            // removed mid-animation to linger over the composer as a ghost.
            VStack(alignment: .leading, spacing: 8) {
                Divider().opacity(0.5)

                // Rows carry their own vertical padding and rule, so a row's
                // measured height is exactly its slot and the reorder maths
                // never has to know about stack spacing.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(runtime.followUps.enumerated()), id: \.element.id) { index, prompt in
                        let isDragged = drag.id == prompt.id
                        FollowUpRow(
                            position: index + 1,
                            prompt: prompt,
                            runtime: runtime,
                            isDragged: isDragged,
                            showsRule: prompt.id != runtime.followUps.last?.id && !isDragged,
                            onDragChanged: { translation in dragChanged(prompt.id, translation: translation) },
                            onDragEnded: { dragEnded() }
                        )
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { rowHeights[prompt.id] = $0 }
                        .offset(y: isDragged ? drag.visualOffset : 0)
                        .zIndex(isDragged ? 1 : 0)
                    }
                }
            }
            .padding(.top, 8)
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
    }

    // MARK: - Reorder

    /// Neighbours sliding out of the grabbed row's way.
    private static let slide = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// The pointer has moved `translation` since the grab. The grabbed row
    /// follows it exactly and `RowDrag` swaps it past every neighbour whose
    /// centre it has crossed.
    private func dragChanged(_ id: UUID, translation: CGFloat) {
        if drag.id != id {
            drag = RowDrag(id: id)
            NSCursor.closedHand.push()
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { drag.translation = translation }

        let moved = drag.settle(order: runtime.followUps.map(\.id), heights: rowHeights, fallbackHeight: 44) { neighbour, placeAfter in
            // The neighbour slides and the grabbed row's slot moves in the
            // same animation as its compensation, so it stays put under
            // the pointer while the list flows around it.
            withAnimation(Self.slide) {
                runtime.moveFollowUp(id, to: neighbour, placeAfter: placeAfter)
            }
        }
        if moved {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func dragEnded() {
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
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    /// One preview panel for this row's thumbnails, so every photo opens.
    @State private var preview = AttachmentPreviewCoordinator()
    /// The editor popover for this row, anchored to its pencil button.
    @State private var editor = FollowUpEditCoordinator()

    /// Whether the pointer is over the reorder grip, for the grab cursor.
    @State private var isHoveringGrip = false

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
            Text(verbatim: "\(position)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 14, alignment: .trailing)
                .accessibilityHidden(true)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Chrome.secondaryText.opacity(isHoveringGrip ? 1 : 0.7))
                .frame(width: 28, height: 28)
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
                        .onChanged { value in onDragChanged(value.translation.height) }
                        .onEnded { _ in onDragEnded() }
                )
                .help("Drag to reorder")
                .accessibilityLabel(Text("Drag to reorder"))
            if !prompt.attachments.isEmpty {
                HStack(spacing: 4) {
                    ForEach(prompt.attachments) { attachment in
                        AttachmentThumbnail(attachment: attachment, size: 28, preview: preview)
                    }
                }
                .background {
                    AttachmentAnchorCapture { preview.setAnchor($0) }
                }
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
                    Text(verbatim: prompt.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.primaryText.opacity(0.9))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The line box centres on cap height, which is right for the digit and the
            // symbols, but prose is read by its x-height and sat a hair low beside them.
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] + Self.proseLift }
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                QueueIconButton(symbol: "pencil", help: "Edit follow-up") {
                    editor.show(prompt: prompt, runtime: runtime)
                }
                .background {
                    AttachmentAnchorCapture { editor.setAnchor($0) }
                }
                QueueIconButton(symbol: "trash", help: "Delete follow-up") {
                    runtime.removeFollowUp(prompt.id)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            if showsRule { Divider().opacity(0.35) }
        }
        // Lifted: a touch larger with a shadow, over an opaque glass so the
        // rows sliding underneath never show through.
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Chrome.overlay(0.12))
                    .padding(.horizontal, -8)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            }
        }
        .scaleEffect(isDragged ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isDragged)
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
    private var anchor: WeakView?
    private var monitors: [Any] = []

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
    }

    /// The pencil button's own view. Captured from the button's background, so
    /// it is always the live view.
    func setAnchor(_ view: NSView) {
        anchor = WeakView(view)
    }

    func show(prompt: FollowUpPrompt, runtime: ThreadRuntime) {
        guard let anchor = anchor?.value, anchor.window != nil else { return }
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
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
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
        guard let window = event.window, let anchor = anchor?.value, window === anchor.window else { return event }
        if anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
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
    @State private var preview = AttachmentPreviewCoordinator()
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
                                    StripLog.log.notice("sheet X tap id=\(attachment.id) name=\(attachment.name, privacy: .public) countBefore=\(attachments.count)")
                                    attachments.removeAll { $0.id == attachment.id }
                                    StripLog.log.notice("sheet X removed countAfter=\(attachments.count)")
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
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
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .buttonStyle(.glass)
                Button("Save") {
                    runtime.updateFollowUp(prompt.id, text: text, attachments: attachments)
                    onDone()
                }
                .buttonStyle(.glassProminent)
                .disabled(isEmpty)
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
