import Foundation

enum MCPExternalSync {
    static func sync(_ servers: [MCPResolvedServer]) {
        let home = URL(fileURLWithPath: LoginEnvironment.homeDirectory, isDirectory: true)
        let byID = Dictionary(uniqueKeysWithValues: servers.map { ($0.id, $0) })
        var managed = readManaged()

        if merge(
            at: home.appendingPathComponent(".cursor/mcp.json"),
            rootKey: "mcpServers",
            previous: managed["cursor"] ?? [],
            servers: byID,
            entry: cursorEntry
        ) {
            managed["cursor"] = byID.keys.sorted()
        }

        if merge(
            at: home.appendingPathComponent(".config/opencode/opencode.json"),
            rootKey: "mcp",
            previous: managed["opencode"] ?? [],
            servers: byID,
            entry: opencodeEntry,
            ensureSchema: "https://opencode.ai/config.json"
        ) {
            managed["opencode"] = byID.keys.sorted()
        }

        if merge(
            at: home.appendingPathComponent(".gemini/settings.json"),
            rootKey: "mcpServers",
            previous: managed["gemini"] ?? [],
            servers: byID,
            entry: geminiEntry
        ) {
            managed["gemini"] = byID.keys.sorted()
        }

        writeManaged(managed)
    }

    private static func cursorEntry(for server: MCPResolvedServer) -> [String: Any] {
        if server.isRemote {
            return ["url": server.url ?? "", "headers": server.headers]
        }
        return ["command": server.command ?? "", "args": server.args, "env": server.env]
    }

    private static func opencodeEntry(for server: MCPResolvedServer) -> [String: Any] {
        if server.isRemote {
            return ["type": "remote", "url": server.url ?? "", "headers": server.headers, "enabled": true]
        }
        return [
            "type": "local",
            "command": [server.command ?? ""] + server.args,
            "environment": server.env,
            "enabled": true,
        ]
    }

    private static func geminiEntry(for server: MCPResolvedServer) -> [String: Any] {
        if server.isRemote {
            return ["httpUrl": server.url ?? "", "headers": server.headers]
        }
        return ["command": server.command ?? "", "args": server.args, "env": server.env]
    }

    /// Merges `servers` into the file's `rootKey` object, removing only ids this
    /// sync previously owned. Returns false when the file is invalid and skipped.
    @discardableResult
    private static func merge(
        at url: URL,
        rootKey: String,
        previous: [String],
        servers: [String: MCPResolvedServer],
        entry: (MCPResolvedServer) -> [String: Any],
        ensureSchema: String? = nil
    ) -> Bool {
        var root: [String: Any]
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            if let existing = parsed[rootKey], !(existing is [String: Any]) { return false }
            root = parsed
        } else {
            root = [:]
        }
        var entries = (root[rootKey] as? [String: Any]) ?? [:]
        for id in previous where servers[id] == nil {
            entries.removeValue(forKey: id)
        }
        for server in servers.values.sorted(by: { $0.id < $1.id }) {
            entries[server.id] = entry(server)
        }
        root[rootKey] = entries
        if let schema = ensureSchema, root["$schema"] == nil {
            root["$schema"] = schema
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return false
        }
        return true
    }

    private static let managedURL = MCPPaths.directory.appendingPathComponent("managed.json")

    private static func readManaged() -> [String: [String]] {
        guard let data = try? Data(contentsOf: managedURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: [String]] = [:]
        for key in ["cursor", "opencode", "gemini"] {
            out[key] = parsed[key] as? [String] ?? []
        }
        return out
    }

    private static func writeManaged(_ managed: [String: [String]]) {
        let full: [String: Any] = [
            "cursor": managed["cursor"] ?? [],
            "opencode": managed["opencode"] ?? [],
            "gemini": managed["gemini"] ?? [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: full, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: managedURL, options: .atomic)
    }
}
