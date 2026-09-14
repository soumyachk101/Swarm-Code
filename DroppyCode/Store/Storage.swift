import Foundation

/// Where the app keeps its library, thread histories and attachments.
enum Storage {
    static let root: URL = {
        if let captures = WebsiteCaptures.storageRoot { return captures }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Droppy Code", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var libraryURL: URL { root.appendingPathComponent("library.json") }

    static var threadsDirectory: URL { directory("threads") }

    static var attachmentsDirectory: URL { directory("attachments") }

    static var worktreesDirectory: URL {
        let url = URL(fileURLWithPath: LoginEnvironment.homeDirectory)
            .appendingPathComponent(".droppy-code/worktrees", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Where a head's work is kept as a patch when it would not land in the checkout.
    static var patchesDirectory: URL {
        let url = URL(fileURLWithPath: LoginEnvironment.homeDirectory)
            .appendingPathComponent(".droppy-code/patches", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func threadURL(_ id: UUID) -> URL {
        threadsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func directory(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadLibrary() -> Library {
        guard let data = try? Data(contentsOf: libraryURL) else { return Library() }
        return (try? JSONDecoder.storage.decode(Library.self, from: data)) ?? Library()
    }

    /// A thread's history. Taken from the prefetch when it was decoded ahead of time, so
    /// opening a thread the sidebar warmed costs no parse on the main thread.
    static func loadDocument(_ id: UUID) -> ThreadDocument {
        DocumentPrefetch.shared.take(id) ?? decodeDocument(id) ?? ThreadDocument(threadID: id)
    }

    /// Reads and decodes a thread file. Safe from any thread: the decoder is made here.
    nonisolated static func decodeDocument(_ id: UUID) -> ThreadDocument? {
        guard let data = try? Data(contentsOf: threadURL(id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ThreadDocument.self, from: data)
    }

    static func deleteDocument(_ id: UUID) {
        DocumentPrefetch.shared.forget(id)
        try? FileManager.default.removeItem(at: threadURL(id))
    }

    /// Copies a file into app storage so a message keeps its attachment after the original moves.
    static func importAttachment(from source: URL) throws -> Attachment {
        let id = UUID()
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        let destination = attachmentsDirectory.appendingPathComponent("\(id.uuidString).\(ext)")
        try FileManager.default.copyItem(at: source, to: destination)
        return Attachment(id: id, name: source.lastPathComponent, path: destination.path, mimeType: MimeType.of(ext))
    }

    static func importAttachment(data: Data, name: String, fileExtension: String) throws -> Attachment {
        let id = UUID()
        let destination = attachmentsDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
        try data.write(to: destination, options: .atomic)
        return Attachment(id: id, name: name, path: destination.path, mimeType: MimeType.of(fileExtension))
    }
}

enum MimeType {
    static func of(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "heic": "image/heic"
        case "pdf": "application/pdf"
        case "json": "application/json"
        case "md", "markdown": "text/markdown"
        default: "text/plain"
        }
    }
}

/// Thread histories decoded ahead of time, off the main thread. A thread's file can run to a
/// megabyte, and decoding that inside the click that opens it is a visible hitch. Launch
/// warms the threads most likely to be opened next and the sidebar warms a row the pointer
/// rests on; a runtime takes its document from here when it is ready and decodes on the
/// spot when it is not. A document is handed out once: the runtime that took it owns the
/// history from then on, and a decode that lands after that is dropped.
final class DocumentPrefetch: @unchecked Sendable {
    static let shared = DocumentPrefetch()

    private let lock = NSLock()
    private var ready: [UUID: ThreadDocument] = [:]
    private var pending: Set<UUID> = []
    private var claimed: Set<UUID> = []

    func warm(_ ids: [UUID]) {
        let fresh: [UUID] = lock.withLock {
            let fresh = ids.filter { ready[$0] == nil && !pending.contains($0) && !claimed.contains($0) }
            pending.formUnion(fresh)
            return fresh
        }
        guard !fresh.isEmpty else { return }
        Task.detached(priority: .utility) { [self] in
            for id in fresh {
                let document = Storage.decodeDocument(id)
                lock.withLock {
                    pending.remove(id)
                    if let document, !claimed.contains(id) { ready[id] = document }
                }
            }
        }
    }

    func take(_ id: UUID) -> ThreadDocument? {
        lock.withLock {
            claimed.insert(id)
            return ready.removeValue(forKey: id)
        }
    }

    func forget(_ id: UUID) {
        lock.withLock {
            ready[id] = nil
            claimed.remove(id)
        }
    }
}

/// Serializes disk writes off the main actor, dropping superseded snapshots.
actor DiskWriter {
    static let shared = DiskWriter()

    /// Encodes off the main actor, so saving a long thread never stalls the interface.
    func encodeAndWrite<Value: Encodable & Sendable>(_ value: Value, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        write(data, to: url)
    }

    func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Droppy Code could not save %@: %@", url.lastPathComponent, error.localizedDescription)
        }
    }
}
