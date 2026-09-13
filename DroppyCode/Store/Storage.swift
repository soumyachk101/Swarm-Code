import Foundation

/// Where the app keeps its library, thread histories and attachments.
enum Storage {
    static let root: URL = {
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

    static func loadDocument(_ id: UUID) -> ThreadDocument {
        guard let data = try? Data(contentsOf: threadURL(id)),
              let document = try? JSONDecoder.storage.decode(ThreadDocument.self, from: data) else {
            return ThreadDocument(threadID: id)
        }
        return document
    }

    static func deleteDocument(_ id: UUID) {
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
