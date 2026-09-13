import Foundation

enum AppInfo {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}

enum TextCleanup {
    static func stripANSI(_ text: String) -> String {
        text.replacing(#/\x1B\[[0-9;?]*[ -/]*[@-~]/#, with: "")
    }

    /// The last meaningful lines of process output, for error messages.
    static func lastLines(_ text: String, count: Int = 4) -> String? {
        let lines = stripANSI(text)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.suffix(count).joined(separator: "\n")
    }

    static func singleLine(_ text: String, limit: Int = 120) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}

enum SimpleDiff {
    /// A compact unified hunk between two texts, trimming the unchanged head and tail.
    static func unified(old: String, new: String) -> FileEdit.Stats {
        let oldLines = old.isEmpty ? [] : old.components(separatedBy: "\n")
        let newLines = new.isEmpty ? [] : new.components(separatedBy: "\n")
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLines.count - prefix, suffix < newLines.count - prefix,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }
        let removed = oldLines[prefix..<(oldLines.count - suffix)]
        let added = newLines[prefix..<(newLines.count - suffix)]
        let leading = oldLines[max(0, prefix - 3)..<prefix]
        let trailingEnd = min(oldLines.count, oldLines.count - suffix + 3)
        let trailing = oldLines[(oldLines.count - suffix)..<trailingEnd]
        let oldStart = prefix - leading.count + 1
        var lines = ["@@ -\(oldStart),\(leading.count + removed.count + trailing.count) +\(oldStart),\(leading.count + added.count + trailing.count) @@"]
        lines += leading.map { " " + $0 }
        lines += removed.map { "-" + $0 }
        lines += added.map { "+" + $0 }
        lines += trailing.map { " " + $0 }
        return FileEdit.Stats(diff: lines.joined(separator: "\n"), additions: added.count, deletions: removed.count)
    }
}

extension FileEdit {
    struct Stats {
        var diff: String
        var additions: Int
        var deletions: Int
    }

    init(path: String, old: String, new: String) {
        let stats = SimpleDiff.unified(old: old, new: new)
        self.init(path: path, diff: stats.diff, additions: stats.additions, deletions: stats.deletions)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
