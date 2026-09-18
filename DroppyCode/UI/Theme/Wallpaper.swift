import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// An NSImage crossing from the detached decode work back to the main actor. The picture
/// is fully decoded before it crosses and only ever touched on the main actor after.
private struct DecodedPicture: @unchecked Sendable {
    let image: NSImage
}

/// The window's picked picture: one file kept in the library, handed out decoded,
/// downsampled and optionally softened for the backdrop.
@MainActor @Observable
final class WallpaperStore {
    static let shared = WallpaperStore()

    private enum Key {
        static let softness = "wallpaperSoftness"
        static let file = "wallpaperFile"
    }

    /// One blur context for every render: making one per picture stalls the softness slider.
    /// The context draws from any thread, so it sits outside the main actor.
    nonisolated(unsafe) static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static let acceptedTypes: [UTType] = [.image]

    /// The rendered picture for the backdrop, downsampled and blurred per `softness`.
    /// Nil when no wallpaper is set.
    private(set) var image: NSImage?
    /// True while a picked file is being copied and decoded.
    private(set) var isInstalling = false
    /// A short sentence for the settings card when a pick fails. Nil otherwise.
    private(set) var lastError: String?

    /// How soft the picture renders, 0 crisp to 1 fully blurred. Saved, and a change
    /// re-renders shortly after while the current picture stays on screen.
    var softness: Double {
        didSet {
            // Writing the property from its own observer calls the observer again, and an
            // unconditional clamp here recursed until the stack ran out: dragging the
            // softness slider crashed the app. Only write back a value that was really out
            // of range, and let that one extra pass do the saving and the re-render.
            let clamped = min(1, max(0, softness))
            guard clamped == softness else {
                softness = clamped
                return
            }
            defaults.set(softness, forKey: Key.softness)
            scheduleRerender()
        }
    }

    var hasWallpaper: Bool { image != nil || fileURL != nil }

    /// The installed file inside the library. Ignored by observation: views watch `image`.
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private let defaults = WebsiteCaptures.defaults ?? .standard
    @ObservationIgnored private var softnessTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    private init() {
        let stored = defaults.object(forKey: Key.softness) as? Double ?? 0
        softness = min(1, max(0, stored))
        if let name = defaults.string(forKey: Key.file), !name.isEmpty {
            let url = Storage.wallpaperDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                fileURL = url
                render()
            }
        }
    }

    /// True when the URL points at a picture, by its extension or its content type.
    nonisolated static func accepts(_ url: URL) -> Bool {
        if !url.pathExtension.isEmpty,
           let type = UTType(filenameExtension: url.pathExtension),
           type.conforms(to: .image) {
            return true
        }
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .image) {
            return true
        }
        return false
    }

    /// Copies a picked picture into the library and renders it. A pick that is not a
    /// picture or cannot be used reports a sentence and leaves the current wallpaper alone.
    func install(from source: URL) {
        guard Self.accepts(source) else {
            lastError = "That is not a picture."
            return
        }
        isInstalling = true
        lastError = nil
        renderTask?.cancel()
        softnessTask?.cancel()
        let softness = self.softness
        Task.detached(priority: .userInitiated) { [softness] in
            // The panel hands over a scoped URL, which dies with the panel, so the copy
            // takes its access with it.
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let ext = source.pathExtension.isEmpty ? "jpg" : source.pathExtension.lowercased()
            let destination = Storage.wallpaperDirectory.appendingPathComponent("wallpaper-\(UUID().uuidString).\(ext)")
            do {
                try FileManager.default.createDirectory(at: Storage.wallpaperDirectory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                await WallpaperStore.shared.failInstall()
                return
            }
            guard let decoded = Self.decode(destination, softness: softness) else {
                try? FileManager.default.removeItem(at: destination)
                await WallpaperStore.shared.failInstall()
                return
            }
            await WallpaperStore.shared.finishInstall(file: destination, picture: DecodedPicture(image: decoded))
        }
    }

    /// Drops the wallpaper: the file goes, the backdrop clears, the complaint clears.
    func remove() {
        renderTask?.cancel()
        softnessTask?.cancel()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        self.fileURL = nil
        defaults.removeObject(forKey: Key.file)
        withAnimation(.easeOut(duration: 0.25)) {
            image = nil
        }
        lastError = nil
    }

    /// Re-decodes the installed file off the main actor and swaps it in when ready, so the
    /// old picture stays up until the new one exists. A newer render cancels this one.
    private func render() {
        guard let fileURL else { return }
        let softness = self.softness
        renderTask?.cancel()
        renderTask = Task { [weak self, fileURL, softness] in
            let carried = await Task.detached(priority: .userInitiated) {
                Self.decode(fileURL, softness: softness).map(DecodedPicture.init)
            }.value
            guard let self, !Task.isCancelled, self.fileURL == fileURL else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.image = carried?.image
            }
        }
    }

    /// A softness change waits a beat before re-rendering, so a slider drag renders once.
    private func scheduleRerender() {
        softnessTask?.cancel()
        guard fileURL != nil else { return }
        softnessTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }
            self.softnessTask = nil
            self.render()
        }
    }

    private func finishInstall(file: URL, picture: DecodedPicture) {
        if let previous = fileURL { try? FileManager.default.removeItem(at: previous) }
        fileURL = file
        defaults.set(file.lastPathComponent, forKey: Key.file)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            image = picture.image
        }
        isInstalling = false
    }

    private func failInstall() {
        isInstalling = false
        lastError = "Could not use that picture."
    }

    /// Downsamples the file to at most 3200 px and softens it per `softness`. Runs anywhere:
    /// ImageIO and Core Image do the work, and nothing here touches the main actor.
    nonisolated static func decode(_ url: URL, softness: Double) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3200,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let size = NSSize(width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height))
        guard softness > 0 else { return NSImage(cgImage: thumbnail, size: size) }
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return NSImage(cgImage: thumbnail, size: size) }
        // The blur shrinks opaque edges toward transparent, so the image is clamped first
        // and cropped back to its own extent: the middle softens while the frame stays solid.
        let extent = CGRect(origin: .zero, size: CGSize(width: thumbnail.width, height: thumbnail.height))
        blur.setValue(CIImage(cgImage: thumbnail).clampedToExtent(), forKey: kCIInputImageKey)
        blur.setValue(softness * 28, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage?.cropped(to: extent),
              let rendered = ciContext.createCGImage(output, from: extent) else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: CGFloat(rendered.width), height: CGFloat(rendered.height)))
    }
}
