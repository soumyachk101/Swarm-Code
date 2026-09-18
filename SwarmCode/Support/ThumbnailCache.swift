import CoreGraphics
import Foundation
import ImageIO

/// Downsampled image attachments, decoded off the main actor and kept for reuse, so scrolling past
/// a message with images never reads or decodes a file while drawing.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    struct Thumbnail: @unchecked Sendable {
        let image: CGImage
    }

    private var thumbnails: [String: Thumbnail] = [:]
    private let limit = 240

    func thumbnail(for path: String, pointSize: CGFloat) -> Thumbnail? {
        let pixels = Int((pointSize * 2).rounded(.up))
        let key = "\(path)#\(pixels)"
        if let cached = thumbnails[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        if thumbnails.count >= limit { thumbnails.removeAll(keepingCapacity: true) }
        let thumbnail = Thumbnail(image: image)
        thumbnails[key] = thumbnail
        return thumbnail
    }
}

/// Thumbnails already decoded, readable on the main actor without a hop. A row scrolling
/// back into view shows its photos in the pass that builds it, instead of a frame later
/// with a fade, and never asks the cache actor for something it has shown before.
@MainActor
enum ThumbnailMemory {
    private static var images = RecentCache<String, CGImage>(limit: 240)

    private static func key(_ path: String, pointSize: CGFloat) -> String {
        "\(path)#\(Int((pointSize * 2).rounded(.up)))"
    }

    static func image(for path: String, pointSize: CGFloat) -> CGImage? {
        images.value(for: key(path, pointSize: pointSize))
    }

    static func store(_ image: CGImage, for path: String, pointSize: CGFloat) {
        images.insert(image, for: key(path, pointSize: pointSize))
    }
}
