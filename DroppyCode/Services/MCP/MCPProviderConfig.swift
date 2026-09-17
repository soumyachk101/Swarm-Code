import Foundation

enum MCPProviderConfig {
    static func claude(_ servers: [MCPResolvedServer]) -> JSONValue {
        var entries: [String: JSONValue] = [:]
        for server in servers {
            if server.isRemote {
                var entry: [String: JSONValue] = [
                    "type": "http",
                    "url": .string(server.url ?? ""),
                ]
                if !server.headers.isEmpty {
                    entry["headers"] = .object(server.headers.mapValues(JSONValue.string))
                }
                entries[server.id] = .object(entry)
            } else {
                var entry: [String: JSONValue] = [
                    "command": .string(server.command ?? ""),
                    "args": .array(server.args.map(JSONValue.string)),
                ]
                if !server.env.isEmpty {
                    entry["env"] = .object(server.env.mapValues(JSONValue.string))
                }
                entries[server.id] = .object(entry)
            }
        }
        return .object(["mcpServers": .object(entries)])
    }

    static func codex(_ servers: [MCPResolvedServer]) -> JSONValue {
        var entries: [String: JSONValue] = [:]
        for server in servers {
            if server.isRemote {
                var entry: [String: JSONValue] = ["url": .string(server.url ?? "")]
                if !server.headers.isEmpty {
                    entry["http_headers"] = .object(server.headers.mapValues(JSONValue.string))
                }
                entries[server.id] = .object(entry)
            } else {
                var entry: [String: JSONValue] = [
                    "command": .string(server.command ?? ""),
                    "args": .array(server.args.map(JSONValue.string)),
                ]
                if !server.env.isEmpty {
                    entry["env"] = .object(server.env.mapValues(JSONValue.string))
                }
                entries[server.id] = .object(entry)
            }
        }
        return .object(["mcp_servers": .object(entries)])
    }

    static func copilot(_ servers: [MCPResolvedServer]) -> JSONValue {
        var entries: [String: JSONValue] = [:]
        for server in servers {
            if server.isRemote {
                entries[server.id] = .object([
                    "type": "http",
                    "url": .string(server.url ?? ""),
                    "headers": .object(server.headers.mapValues(JSONValue.string)),
                    "tools": .array([.string("*")]),
                ])
            } else {
                let entry: [String: JSONValue] = [
                    "type": "local",
                    "command": .string(server.command ?? ""),
                    "args": .array(server.args.map(JSONValue.string)),
                    "env": .object(server.env.mapValues(JSONValue.string)),
                    "tools": .array([.string("*")]),
                ]
                entries[server.id] = .object(entry)
            }
        }
        return .object(["mcpServers": .object(entries)])
    }

    static func writeAll(_ servers: [MCPResolvedServer]) {
        if servers.isEmpty {
            for url in [MCPPaths.claudeConfigURL, MCPPaths.codexConfigURL, MCPPaths.copilotConfigURL] {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        write(claude(servers), to: MCPPaths.claudeConfigURL)
        write(codex(servers), to: MCPPaths.codexConfigURL)
        write(copilot(servers), to: MCPPaths.copilotConfigURL)
    }

    static func codexOverrides() -> JSONValue? {
        guard let data = try? Data(contentsOf: MCPPaths.codexConfigURL),
              let parsed = JSONValue.parse(data),
              let servers = parsed["mcp_servers"],
              let object = servers.object, !object.isEmpty
        else { return nil }
        return servers
    }

    static func claudeConfigPath() -> String? {
        guard serversPresent(in: MCPPaths.claudeConfigURL, key: "mcpServers") else { return nil }
        return MCPPaths.claudeConfigURL.path
    }

    static func copilotConfigJSON() -> String? {
        guard let data = try? Data(contentsOf: MCPPaths.copilotConfigURL),
              let parsed = JSONValue.parse(data),
              let object = parsed["mcpServers"]?.object, !object.isEmpty
        else { return nil }
        return parsed.compactString
    }

    private static func write(_ value: JSONValue, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? value.data(pretty: true).write(to: url, options: .atomic)
    }

    private static func serversPresent(in url: URL, key: String) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let parsed = JSONValue.parse(data),
              let object = parsed[key]?.object, !object.isEmpty
        else { return false }
        return true
    }
}
