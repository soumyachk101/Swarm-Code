import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The queued steering prompts as a tab rising from the top of the chat box. The composer draws
/// over its lower edge, so it reads as part of the box, exactly like the changes tab. Each row
/// is one stacked follow-up: it is sent as a direct user chat message once the running turn
/// finishes, in order from top to bottom.
struct FollowUpQueueTab: View {
    static let overlap: CGFloat = ThreadChangesTab.overlap

    let runtime: ThreadRuntime

    /// Whether the queued rows are folded away under the title.
    @State private var isCollapsed = false

    /// The prompt being dragged, and each row's height for above/below detection.
    @State private var draggingID: UUID?
    @State private var rowHeights: [UUID: CGFloat] = [:]

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Chrome.secondaryText)
                Text(verbatim: runtime.followUps.count == 1 ? "1 follow-up" : "\(runtime.followUps.count) follow-ups")
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                Text(verbatim: "queued")
                    .foregroundStyle(Chrome.secondaryText)
                Spacer(minLength: 8)
                Button {
                    withAnimation(Chrome.panelSlide) { isCollapsed.toggle() }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
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

            if !isCollapsed {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(runtime.followUps.enumerated()), id: \.element.id) { index, prompt in
                    FollowUpRow(
                        position: index + 1,
                        prompt: prompt,
                        runtime: runtime,
                        dragging: $draggingID,
                        rowHeight: rowHeights[prompt.id] ?? 44,
                        reportHeight: { rowHeights[prompt.id] = $0 },
                        onHoverMove: { dragged, neighbor, placeAfter in
                            withAnimation(Chrome.panelSlide) {
                                runtime.moveFollowUp(dragged, to: neighbor, placeAfter: placeAfter)
                            }
                        },
                        onDropEnd: { draggingID = nil }
                    )
                    if prompt.id != runtime.followUps.last?.id {
                        Divider().opacity(0.35)
                    }
                }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7 + Self.overlap)
        .frame(maxWidth: 560)
        .glassEffect(.regular, in: shape)
        .contentShape(shape)
    }
}

private struct FollowUpRow: View {
    let position: Int
    let prompt: FollowUpPrompt
    let runtime: ThreadRuntime
    @Binding var dragging: UUID?
    let rowHeight: CGFloat
    let reportHeight: (CGFloat) -> Void
    let onHoverMove: (UUID, UUID, Bool) -> Void
    let onDropEnd: () -> Void

    /// One preview panel for this row's thumbnails, so every photo opens.
    @State private var preview = AttachmentPreviewCoordinator()
    /// The editor popover for this row, anchored to its pencil button.
    @State private var editor = FollowUpEditCoordinator()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(position)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Chrome.secondaryText.opacity(0.7))
                .frame(width: 18, height: 22)
                .contentShape(.rect)
                .onDrag {
                    dragging = prompt.id
                    return NSItemProvider(object: prompt.id.uuidString as NSString)
                }
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
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { reportHeight($0) }
        .onDrop(
            of: [.plainText],
            delegate: FollowUpDropDelegate(
                promptID: prompt.id,
                rowHeight: rowHeight,
                dragging: $dragging,
                onHoverMove: onHoverMove,
                onEnd: onDropEnd
            )
        )
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

/// Reorders queued follow-ups by dragging their grip. The upper half of a row
/// drops above it, the lower half below; hovering moves the prompt live, so
/// the list reshuffles smoothly under the dragged row instead of jumping on drop.
private struct FollowUpDropDelegate: DropDelegate {
    let promptID: UUID
    let rowHeight: CGFloat
    @Binding var dragging: UUID?
    let onHoverMove: (UUID, UUID, Bool) -> Void
    let onEnd: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return dragging != promptID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let dragging, dragging != promptID else { return nil }
        onHoverMove(dragging, promptID, info.location.y > rowHeight / 2)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        onEnd()
        return true
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
/// editing never takes over the window. Application-defined: it stays open
/// through file picks and outside clicks (no lost edits) and closes on Save,
/// Cancel or Escape, or when its row goes away.
@MainActor
final class FollowUpEditCoordinator: NSObject {
    private let popover = NSPopover()
    private var anchor: WeakView?
    private var keyMonitor: Any?

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
        popover.contentViewController = NSHostingController(rootView: FollowUpEditor(
            prompt: prompt,
            runtime: runtime,
            onDone: { [weak self] in self?.close() }
        ))
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        startKeyMonitor()
    }

    func close() {
        stopKeyMonitor()
        if popover.isShown { popover.performClose(nil) }
    }

    private func startKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            self?.close()
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        self.keyMonitor = nil
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
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    // The delete badge sits fully inside the thumbnail's top-trailing
                    // corner: nothing overhangs into the next cell, so no later
                    // sibling can cover it and every photo stays deletable.
                    HStack(spacing: 8) {
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
                                    .padding(.top, 2)
                                    .padding(.trailing, 2)
                                    .accessibilityLabel(Text("Remove \(attachment.name)"))
                                }
                        }
                    }
                    .padding(.top, 6)
                }
                .background {
                    AttachmentAnchorCapture { preview.setAnchor($0) }
                }
            }
            Button {
                chooseFiles()
            } label: {
                Label("Add files", systemImage: "paperclip")
            }
            .buttonStyle(.glass)
            .disabled(attachments.count >= 8)
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
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "heic" || fileExtension == "heif" {
                guard let image = NSImage(contentsOf: url), let data = image.jpegData,
                      let attachment = try? Storage.importAttachment(
                        data: data,
                        name: url.deletingPathExtension().lastPathComponent + ".jpg",
                        fileExtension: "jpg"
                      ) else { continue }
                attachments.append(attachment)
            } else if let attachment = try? Storage.importAttachment(from: url) {
                attachments.append(attachment)
            }
        }
    }
}
