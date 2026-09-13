import AppKit
import SwiftUI

/// The queued steering prompts as a tab rising from the top of the chat box. The composer draws
/// over its lower edge, so it reads as part of the box, exactly like the changes tab. Each row
/// is one stacked follow-up: it is sent as a direct user chat message once the running turn
/// finishes, in order from top to bottom.
struct FollowUpQueueTab: View {
    static let overlap: CGFloat = ThreadChangesTab.overlap

    let runtime: ThreadRuntime

    @State private var editingPrompt: FollowUpPrompt?
    @State private var preview = AttachmentPreviewCoordinator()

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
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .accessibilityLabel(Text(verbatim: runtime.followUps.count == 1 ? "1 queued follow-up" : "\(runtime.followUps.count) queued follow-ups"))

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(runtime.followUps.enumerated()), id: \.element.id) { index, prompt in
                    FollowUpRow(
                        position: index + 1,
                        prompt: prompt,
                        isFirst: index == 0,
                        isLast: index == runtime.followUps.count - 1,
                        runtime: runtime,
                        preview: preview,
                        onEdit: { editingPrompt = prompt }
                    )
                    if prompt.id != runtime.followUps.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 7 + Self.overlap)
        .frame(maxWidth: 560)
        .background { shape.fill(Chrome.overlay(0.07)) }
        .contentShape(shape)
        .onChange(of: runtime.followUps) {
            preview.retire(except: Set(runtime.followUps.flatMap(\.attachments).map(\.id)))
        }
        .onDisappear { preview.close() }
        .sheet(item: $editingPrompt) { prompt in
            FollowUpEditSheet(prompt: prompt, runtime: runtime)
        }
    }
}

private struct FollowUpRow: View {
    let position: Int
    let prompt: FollowUpPrompt
    let isFirst: Bool
    let isLast: Bool
    let runtime: ThreadRuntime
    let preview: AttachmentPreviewCoordinator
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(position)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 14, alignment: .trailing)
                .padding(.top, 1)
                .accessibilityHidden(true)
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
                if !prompt.attachments.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(prompt.attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment, size: 28, preview: preview)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                QueueIconButton(symbol: "chevron.up", help: "Move earlier", isEnabled: !isFirst) {
                    runtime.moveFollowUp(prompt.id, earlier: true)
                }
                QueueIconButton(symbol: "chevron.down", help: "Move later", isEnabled: !isLast) {
                    runtime.moveFollowUp(prompt.id, earlier: false)
                }
                QueueIconButton(symbol: "pencil", help: "Edit follow-up") {
                    onEdit()
                }
                QueueIconButton(symbol: "trash", help: "Delete follow-up") {
                    runtime.removeFollowUp(prompt.id)
                }
            }
            .fixedSize()
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

/// Edits one queued follow-up, text and attachments included.
private struct FollowUpEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: FollowUpPrompt
    let runtime: ThreadRuntime

    @State private var text: String
    @State private var attachments: [Attachment]
    @State private var preview = AttachmentPreviewCoordinator()

    init(prompt: FollowUpPrompt, runtime: ThreadRuntime) {
        self.prompt = prompt
        self.runtime = runtime
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
                    // Same dead-space reservation as the composer strip: the delete badge
                    // overhangs top-trailing, and without it only the last photo stays deletable.
                    HStack(spacing: 2) {
                        ForEach(attachments) { attachment in
                            AttachmentThumbnail(attachment: attachment, size: 48, preview: preview)
                                .padding(.trailing, 14)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        attachments.removeAll { $0.id == attachment.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 6, y: -6)
                                    .accessibilityLabel(Text("Remove \(attachment.name)"))
                                }
                        }
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
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
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button("Save") {
                    runtime.updateFollowUp(prompt.id, text: text, attachments: attachments)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
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
