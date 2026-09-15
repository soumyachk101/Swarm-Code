import AppKit
import SwiftUI

/// One file in ~/Downloads.
struct RecentDownload: Identifiable, Hashable {
    var url: URL
    var name: String
    var size: String?
    var isImage: Bool

    var id: String { url.path }
}

/// The user's latest downloads with previews, loaded once per popover opening.
@MainActor
@Observable
final class RecentDownloads {
    nonisolated static let limit = 15
    nonisolated static let previewPointSize: CGFloat = 30

    private(set) var items: [RecentDownload] = []
    private(set) var thumbnails: [String: CGImage] = [:]
    private(set) var isLoaded = false

    var directory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private nonisolated static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
    ]

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    func load() async {
        guard let directory else { return }
        let urls = await Task.detached(priority: .userInitiated) {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isHiddenKey]
            let found = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )) ?? []
            return found
                .compactMap { url -> (URL, Date, Int)? in
                    guard let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isDirectory == false else { return nil }
                    return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(RecentDownloads.limit)
                .map { ($0.0, $0.2) }
        }.value
        var items: [RecentDownload] = []
        var thumbnails: [String: CGImage] = [:]
        await withTaskGroup(of: (String, CGImage)?.self) { group in
            for (url, size) in urls {
                let isImage = Self.imageExtensions.contains(url.pathExtension.lowercased())
                items.append(RecentDownload(
                    url: url,
                    name: url.lastPathComponent,
                    size: size > 0 ? Self.sizeFormatter.string(fromByteCount: Int64(size)) : nil,
                    isImage: isImage
                ))
                if isImage {
                    group.addTask {
                        guard let thumbnail = await ThumbnailCache.shared.thumbnail(
                            for: url.path,
                            pointSize: Self.previewPointSize
                        ) else { return nil }
                        return (url.path, thumbnail.image)
                    }
                }
            }
            for await result in group {
                guard let (path, image) = result else { continue }
                thumbnails[path] = image
            }
        }
        self.items = items
        self.thumbnails = thumbnails
        isLoaded = true
    }
}

/// The attach button's popover: the latest downloads with native icons and photo
/// previews, plus a way out to Finder.
struct DownloadsPopover: View {
    let pick: (URL) -> Void
    let chooseOther: () -> Void

    @State private var downloads = RecentDownloads()

    var body: some View {
        // A ScrollView in a popover collapses to a couple of rows on its own, so the
        // rows' own height is forced on it. It is measured rather than fixed: a fixed
        // one left an empty Downloads folder, and the spinner before the folder is
        // read, in a popover most of a screen tall.
        PopoverMenu(maxHeight: 700, idealHeight: idealHeight) {
            PopoverSectionHeader("Recent downloads")
            if !downloads.isLoaded {
                HStack {
                    Spacer(minLength: 0)
                    ProgressView().controlSize(.small)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
            } else if downloads.items.isEmpty {
                PopoverNote("No downloads yet. Anything you download appears here.")
            } else {
                ForEach(downloads.items) { item in
                    DownloadRow(
                        item: item,
                        thumbnail: downloads.thumbnails[item.url.path],
                        pick: { pick(item.url) }
                    )
                }
            }
            PopoverDivider()
            PopoverItem("Show in Finder", symbol: "folder") {
                if let directory = downloads.directory {
                    NSWorkspace.shared.open(directory)
                }
            }
            PopoverItem("Choose Files…", symbol: "doc.on.doc") {
                chooseOther()
            }
        }
        // Wide enough for long file names and their sizes: without a fixed width the
        // popover shrinks to PopoverMenu's minimum and truncates every row.
        .frame(width: 360)
        .task { await downloads.load() }
    }

    /// The rows' own height, so the popover is exactly as tall as it has downloads to
    /// show. Nil while there is nothing to scroll: the spinner and the empty note size
    /// themselves.
    private var idealHeight: CGFloat? {
        guard downloads.isLoaded, !downloads.items.isEmpty else { return nil }
        let rows = CGFloat(downloads.items.count) * DownloadRow.height
        // The section header, the divider and the two ways out below the rows.
        return min(700, rows + 106)
    }
}

private struct DownloadRow: View {
    /// One row's slot, so the popover can size itself to its rows.
    static let height: CGFloat = 38

    let item: RecentDownload
    let thumbnail: CGImage?
    let pick: () -> Void

    @State private var isHovering = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
            // Runs after the popover closes, matching PopoverItem behavior.
            Task { @MainActor in pick() }
        } label: {
            HStack(spacing: 10) {
                preview
                Text(verbatim: item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 16)
                if let size = item.size {
                    Text(verbatim: size)
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Chrome.primaryText)
            .padding(.horizontal, 8)
            .frame(height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Chrome.overlay(0.1) : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
        }
    }
}
