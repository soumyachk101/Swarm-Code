import AppKit
import ImageIO
import SwiftUI

/// Shared helpers for showing large image previews of attachments and files the agent read.
enum PreviewImages {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif",
        "bmp", "tif", "tiff", "avif", "ico", "svg",
    ]

    static func isImagePath(_ path: String) -> Bool {
        extensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Finds an image file a read tool looked at. Checks the title first, then the detail,
    /// resolving relative paths against the thread's working directory.
    static func resolveToolImagePath(for call: ToolCall, workingDirectory: String?) -> String? {
        guard call.kind == .read else { return nil }
        var candidates: [String] = [call.title]
        if let detail = call.detail, !detail.isEmpty { candidates.append(detail) }
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, isImagePath(trimmed) else { continue }
            let absolute: String
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") {
                absolute = URL(string: trimmed)?.path ?? trimmed
            } else if let workingDirectory {
                absolute = (workingDirectory as NSString).appendingPathComponent(trimmed)
            } else {
                continue
            }
            if FileManager.default.fileExists(atPath: absolute) { return absolute }
        }
        return nil
    }

    static func fileSize(_ path: String) -> String? {
        guard let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size.int64Value)
    }
}

/// A large preview shown in a popover when an attachment thumbnail is clicked.
///
/// The photo slot is sized up front (`imageSize`, see `imageDisplaySize`), so
/// the spinner and the loaded photo take exactly the same room: the panel is
/// sized once before it opens and never reflows under the arrow.
struct AttachmentLargePreview: View {
    let attachment: Attachment
    /// The photo's display size, precomputed by the panel. Nil for non-images.
    var imageSize: CGSize?

    @State private var image: CGImage?
    @State private var textPreview: String?

    /// The largest a photo is shown at inside the panel.
    static let imageBounds = CGSize(width: 480, height: 360)

    /// The photo aspect-fitted into `imageBounds`, from the file's pixel size
    /// (orientation applied). Only the aspect matters, so this reads the
    /// header through ImageIO rather than decoding the image.
    static func imageDisplaySize(for attachment: Attachment) -> CGSize {
        var pixels = CGSize(width: 4, height: 3)
        if let source = CGImageSourceCreateWithURL(attachment.url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           width > 0, height > 0 {
            let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
            pixels = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }
        let scale = min(imageBounds.width / pixels.width, imageBounds.height / pixels.height)
        return CGSize(width: floor(pixels.width * scale), height: floor(pixels.height * scale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachment.isImage {
                let slot = imageSize ?? Self.imageBounds
                ZStack {
                    if let image {
                        Image(decorative: image, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                            .transition(.opacity)
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: slot.width, height: slot.height)
                .frame(maxWidth: .infinity, alignment: .center)
            } else if let textPreview {
                ScrollView {
                    Text(textPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(width: 440, height: min(320, max(120, CGFloat(textPreview.count / 4))))
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10, style: .continuous))
            } else {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: attachment.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                    Text(attachment.name)
                        .font(.callout)
                        .lineLimit(2)
                }
                .frame(width: 320, alignment: .leading)
                .padding(.vertical, 8)
            }

            HStack(spacing: 8) {
                Text(attachment.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let size = PreviewImages.fileSize(attachment.path) {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 12)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([attachment.url])
                }
                .buttonStyle(.link)
                .font(.caption)
                Button("Open") {
                    NSWorkspace.shared.open(attachment.url)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: 504)
        .task(id: attachment.path) {
            if attachment.isImage {
                let loaded = await ThumbnailCache.shared.thumbnail(for: attachment.path, pointSize: Self.imageBounds.width)?.image
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            } else {
                textPreview = Self.textPreview(for: attachment)
            }
        }
    }

    private static func textPreview(for attachment: Attachment) -> String? {
        let url = attachment.url
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 500_000 else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else { return nil }
        return String(text.prefix(8_000))
    }
}

/// Full-width image preview at the top of an expanded read tool row,
/// so it is clear which photo the agent looked at.
struct ToolImagePreview: View {
    let path: String

    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.45))
                if let image {
                    Image(decorative: image, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 420)
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
            HStack(spacing: 8) {
                Text((path as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Open") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .task(id: path) {
            image = await ThumbnailCache.shared.thumbnail(for: path, pointSize: 900)?.image
        }
    }
}
