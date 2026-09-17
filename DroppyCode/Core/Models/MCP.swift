import Foundation
import SwiftUI

/// How an MCP server is reached once its fields are filled in.
enum MCPTransport: Sendable, Hashable {
    /// A local process speaking JSON-RPC over stdio. `args` may contain `{field}` placeholders
    /// that `MCPCatalogEntry.resolve` fills from the user's field values.
    case stdio(command: String, args: [String])
    /// A remote streamable-HTTP server. Header values may contain `{field}` placeholders.
    case http(url: String, headers: [String: String])
    /// A remote server behind OAuth: reached as a local `npx -y mcp-remote <url>` process,
    /// which opens the browser for sign-in on first use and keeps the token in `~/.mcp-auth`.
    case oauth(url: String)
}

/// One thing the user has to type before a server can connect: a key, a token, a path.
struct MCPField: Sendable, Hashable, Identifiable {
    enum Kind: Sendable, Hashable {
        case secret
        case text
        case path
    }

    /// The placeholder name, as used in `{key}` inside args, env values and headers.
    var key: String
    var label: String
    var placeholder: String
    var kind: Kind = .secret
    /// Where to get it, shown under the field.
    var help: String? = nil
    /// Prefilled when the user has typed nothing.
    var defaultValue: String? = nil
    var isRequired = true

    var id: String { key }
}

enum MCPCategory: String, CaseIterable, Sendable, Identifiable {
    case developer
    case browser
    case search
    case work
    case data
    case cloud
    case knowledge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: "Developer"
        case .browser: "Browser"
        case .search: "Search"
        case .work: "Work"
        case .data: "Data"
        case .cloud: "Cloud"
        case .knowledge: "Knowledge"
        }
    }
}

/// One of the servers Droppy Code knows how to connect: everything needed to show it, ask
/// for its credentials, launch it and recognise its tool calls in a conversation.
struct MCPCatalogEntry: Sendable, Hashable, Identifiable {
    /// The server's key in every provider's config, and so the server part of a tool call's
    /// name (`mcp__github__list_issues`). Lowercase, hyphens only.
    var id: String
    var name: String
    var vendor: String
    /// One line, under the name on its card.
    var summary: String
    var category: MCPCategory
    /// The image set in Assets.xcassets (`mcp-<id>`), a template SVG tinted with `color`.
    var asset: String
    /// The brand tint, as 0xRRGGBB.
    var colorValue: UInt32
    /// Brands whose mark is black or white wear the text colour instead of `colorValue`.
    var isMonochrome = false
    var transport: MCPTransport
    var fields: [MCPField] = []
    /// Environment variables for a stdio server; values may hold `{field}` placeholders.
    var env: [String: String] = [:]
    var docsURL: String
    /// Three or four tools the user can expect, for the card's fine print.
    var sampleTools: [String] = []

    var color: Color { Color(rgb: colorValue) }

    /// Whether the server needs something typed before it can connect.
    var needsInput: Bool { fields.contains { $0.isRequired } }

    var isOAuth: Bool {
        if case .oauth = transport { return true }
        return false
    }
}

/// A server with its fields filled in: what every provider config and the probe are built from.
struct MCPResolvedServer: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    /// Set for a local server.
    var command: String?
    var args: [String] = []
    var env: [String: String] = [:]
    /// Set for a remote streamable-HTTP server.
    var url: String?
    var headers: [String: String] = [:]

    var isRemote: Bool { url != nil }
}

extension MCPCatalogEntry {
    /// The launchable form, with `{key}` placeholders replaced by the user's values (or the
    /// field's default). OAuth servers resolve to an `mcp-remote` process.
    func resolve(values: [String: String]) -> MCPResolvedServer {
        func fill(_ text: String) -> String {
            var out = text
            for field in fields {
                let value = values[field.key].flatMap { $0.isEmpty ? nil : $0 } ?? field.defaultValue ?? ""
                out = out.replacingOccurrences(of: "{\(field.key)}", with: value)
            }
            return out
        }
        var server = MCPResolvedServer(id: id, name: name)
        switch transport {
        case .stdio(let command, let args):
            server.command = command
            server.args = args.map(fill)
            // An optional field left empty drops its variable rather than passing "".
            server.env = env.mapValues(fill).filter { !$0.value.isEmpty }
        case .http(let url, let headers):
            server.url = fill(url)
            server.headers = headers.mapValues(fill).filter { !$0.value.isEmpty }
        case .oauth(let url):
            server.command = "npx"
            server.args = ["-y", "mcp-remote", url]
        }
        return server
    }
}

/// One tool a connected server announced.
struct MCPToolSummary: Codable, Sendable, Hashable, Identifiable {
    var name: String
    var summary: String?
    var id: String { name }
}

/// What the probe found when it spoke to a server.
struct MCPProbeResult: Sendable, Hashable {
    var serverName: String?
    var serverVersion: String?
    var tools: [MCPToolSummary]
}

/// The user's state for one catalog server, kept in `Storage.root/mcp.json`. Secrets live in
/// the Keychain (`MCPKeychain`), never here.
struct MCPConnection: Codable, Sendable, Hashable, Identifiable {
    var catalogID: String
    /// Whether the server is handed to providers at launch.
    var isEnabled = true
    /// Non-secret field values (paths, team ids); secret fields are in the Keychain.
    var values: [String: String] = [:]
    var connectedAt: Date?
    var serverVersion: String?
    var tools: [MCPToolSummary] = []

    var id: String { catalogID }
}

/// The connection's state as the page and the composer show it.
enum MCPConnectionState: Sendable, Hashable {
    case notConnected
    case connecting
    case connected(toolCount: Int)
    case failed(message: String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isConnecting: Bool { self == .connecting }
}

/// Where the config files providers read at launch are written. Each holds every enabled
/// server in that provider's own format; a missing or empty file means no servers.
enum MCPPaths {
    static let directory: URL = {
        let url = Storage.root.appendingPathComponent("mcp", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Kept for the Keychain-free settings: `[MCPConnection]` as JSON.
    static let connectionsURL = Storage.root.appendingPathComponent("mcp.json")
    /// `{"mcpServers": {...}}` for `claude --mcp-config`.
    static let claudeConfigURL = directory.appendingPathComponent("claude.json")
    /// `{"mcp_servers": {...}}` for Codex's app-server `config` overrides.
    static let codexConfigURL = directory.appendingPathComponent("codex.json")
    /// `{"mcpServers": {...}}` for `copilot --additional-mcp-config`.
    static let copilotConfigURL = directory.appendingPathComponent("copilot.json")
}

extension Color {
    init(rgb hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
