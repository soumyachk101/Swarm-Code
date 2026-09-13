import Foundation

/// Matches the files an agent reported editing against the files a diff contains.
enum TouchedPaths {
    /// The repository-relative form of a path an agent reported, whether absolute or relative.
    nonisolated static func normalize(_ path: String, root: String) -> String {
        var path = path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) { path = String(path.dropFirst(prefix.count)) }
        if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        return path
    }

    /// Whether a diff file is one of the touched paths, allowing for a path reported relative to a subfolder.
    nonisolated static func matches(_ file: DiffFile, touched: Set<String>) -> Bool {
        [file.path, file.oldPath].compactMap { $0 }.contains { path in
            touched.contains(path) || touched.contains { $0.hasSuffix("/" + path) || path.hasSuffix("/" + $0) }
        }
    }
}
