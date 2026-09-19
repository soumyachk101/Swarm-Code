import Foundation
import SwiftUI

/// How an MCP server is reached once its fields are filled in.
enum MCPTransport: Sendable, Hashable {
    /// A local process speaking JSON-RPC over stdio. `args` may contain `{field}` placeholders
    /// that `MCPCatalogEntry.resolve` fills from the user's field values.
    case stdio(command: String, args: [String])
    /// A remote streamable-HTTP server. Header values may contain `{field}` placeholders.
    case http(url: String, headers: [String: String])
    /// A remote server behind OAuth. Swarm Code signs the user in itself (`MCPOAuth`) and
    /// every provider reaches the server through the app's local proxy (`MCPProxy`), which
    /// adds a fresh token to each request, so no token ever sits in a config file.
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

/// One of the servers Swarm Code knows how to connect: everything needed to show it, ask
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
    /// The page where the key or token is made, opened for the user as the key panel
    /// appears (see `MCPKeyPanel`). Nil for servers that need a path or a connection
    /// string rather than something from a website.
    var keysURL: String? = nil

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
    /// For an OAuth server, the remote address behind the proxy route in `url`, with the
    /// user's field values filled in (an instance address, for one).
    var oauthUpstream: String?

    var isRemote: Bool { url != nil }
}

extension MCPCatalogEntry {
    /// The launchable form, with `{key}` placeholders replaced by the user's values (or the
    /// field's default). OAuth servers resolve to their route on the app's proxy.

    /// The remote address an OAuth server is signed in to and proxied to, with `{key}`
    /// placeholders filled from `values` (or the field's default).
    func oauthURL(values: [String: String] = [:]) -> String? {
        if case .oauth(let url) = transport { return fill(url, values: values) }
        return nil
    }

    /// `text` with every `{key}` replaced by the user's value for that field, or the field's
    /// default when nothing was typed. A placeholder standing as the host of a URL takes a
    /// host: a value pasted as `https://gitlab.example.com/` loses its scheme and slash.
    func fill(_ text: String, values: [String: String]) -> String {
        var out = text
        for field in fields {
            var value = values[field.key].flatMap { $0.isEmpty ? nil : $0 } ?? field.defaultValue ?? ""
            let token = "{\(field.key)}"
            if out.contains("://" + token) {
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                for scheme in ["https://", "http://"] where value.lowercased().hasPrefix(scheme) {
                    value = String(value.dropFirst(scheme.count))
                }
                while value.hasSuffix("/") { value.removeLast() }
            }
            out = out.replacingOccurrences(of: token, with: value)
        }
        return out
    }

    func resolve(values: [String: String]) -> MCPResolvedServer {
        func fill(_ text: String) -> String { self.fill(text, values: values) }
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
            server.url = MCPProxy.url(for: id)
            server.oauthUpstream = fill(url)
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

/// A step the user must take outside the app before the server will answer: why it
/// refused, what to do, and the page to do it on. The card offers it as a floating panel.
struct MCPSetupGuide: Sendable, Hashable {
    /// Short headline, e.g. "Turn on GitLab's MCP server".
    var title: String
    /// One line saying why the server refused.
    var reason: String
    /// Plain-language steps, in order.
    var steps: [String]
    /// Label of the button that opens `pageURL`, e.g. "Open my groups".
    var pageLabel: String
    var pageURL: String
    /// Shown under the buttons after a check that still fails, e.g. why it may take a minute.
    var note: String?
}

/// The connection's state as the page and the composer show it.
enum MCPConnectionState: Sendable, Hashable {
    case notConnected
    case connecting
    case connected(toolCount: Int)
    case failed(message: String)
    /// Signed in or keyed correctly, but the server itself needs a step on its side first.
    case needsSetup(MCPSetupGuide)

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
    /// The user's own servers: `[MCPCustomServer]` as JSON (secret values never land here).
    static let customsURL = Storage.root.appendingPathComponent("custom-mcp.json")
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
