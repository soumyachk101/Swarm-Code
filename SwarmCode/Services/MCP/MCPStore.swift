import Foundation
import Observation

/// The user's MCP connections: which catalog servers are connected, their field values,
/// and what each announced when it was last probed. Persists to `MCPPaths.connectionsURL`
/// (secrets to the Keychain) and, on every change, rewrites the provider config files under
/// `MCPPaths.directory` and syncs the file-based CLIs (Cursor, OpenCode, Gemini).
@MainActor
@Observable
final class MCPStore {
    /// Every connection the user has made, connected or not, keyed by catalog id.
    private(set) var connections: [String: MCPConnection] = [:]
    /// Live state per catalog id; a server with no entry here is `.notConnected`.
    private(set) var states: [String: MCPConnectionState] = [:]
    /// Field values the user is typing on a card before connecting, keyed by catalog id then field key.
    var drafts: [String: [String: String]] = [:]

    @ObservationIgnored private var probes: [String: Task<Void, Never>] = [:]

    init() {
        load()
        // Up before anything resolves a route to it: the probe, the hub and every launch
        // reach signed-in servers through the proxy.
        MCPProxy.shared.start()
        exportAll()
    }

    // MARK: Reading

    func state(for id: String) -> MCPConnectionState {
        states[id] ?? .notConnected
    }

    func connection(for id: String) -> MCPConnection? {
        connections[id]
    }

    /// Connected and enabled servers, resolved with their field values: what providers get.
    var enabledServers: [MCPResolvedServer] {
        connections.values
            .filter { $0.isEnabled && $0.connectedAt != nil }
            .compactMap { connection in
                guard let entry = MCPCatalog.entry(id: connection.catalogID) else { return nil }
                return entry.resolve(values: storedValues(for: entry))
            }
            .sorted { $0.id < $1.id }
    }

    /// The value the card shows for a field: the draft, else the stored value (secrets from the Keychain).
    func value(for field: MCPField, of entry: MCPCatalogEntry) -> String {
        if let draft = drafts[entry.id]?[field.key] { return draft }
        if field.kind == .secret {
            if let secret = MCPKeychain.value(server: entry.id, field: field.key) { return secret }
        } else if let stored = connections[entry.id]?.values[field.key] {
            return stored
        }
        return field.defaultValue ?? ""
    }

    func setDraft(_ value: String, for field: MCPField, of entry: MCPCatalogEntry) {
        drafts[entry.id, default: [:]][field.key] = value
    }

    /// Whether every required field of the entry has a value (draft or stored).
    func canConnect(_ entry: MCPCatalogEntry) -> Bool {
        entry.fields.filter { $0.isRequired }.allSatisfy { !value(for: $0, of: entry).isEmpty }
    }

    // MARK: Connecting

    /// Stores the drafts (secrets to the Keychain), probes the server, and on success marks it
    /// connected with its tools; on failure keeps the values and records the message.
    func connect(_ entry: MCPCatalogEntry) {
        probes[entry.id]?.cancel()
        var connection = connections[entry.id] ?? MCPConnection(catalogID: entry.id)
        connection.isEnabled = true
        // A sign-in belongs to one address: pointing the server elsewhere (another GitLab
        // instance) drops the old token so the browser flow runs against the new one.
        if entry.isOAuth, let draft = drafts[entry.id],
           entry.oauthURL(values: connection.values) != entry.oauthURL(values: connection.values.merging(draft) { $1 }) {
            MCPOAuth.signOut(serverID: entry.id)
            MCPProxy.shared.unregister(serverID: entry.id)
        }
        // A Try again after a rejection must not reuse the rejected token: a failed
        // OAuth entry starts signed out so the browser flow runs afresh.
        if entry.isOAuth, case .failed = states[entry.id] {
            MCPOAuth.signOut(serverID: entry.id)
            MCPProxy.shared.unregister(serverID: entry.id)
        }
        if let draft = drafts[entry.id] {
            for field in entry.fields {
                guard let text = draft[field.key] else { continue }
                if field.kind == .secret {
                    MCPKeychain.set(text, server: entry.id, field: field.key)
                } else {
                    connection.values[field.key] = text
                }
            }
        }
        connections[entry.id] = connection
        drafts[entry.id] = nil
        save()
        states[entry.id] = .connecting
        startProbe(entry)
    }

    /// Forgets the connection, its values and its secrets, and removes it from every provider config.
    func disconnect(_ entry: MCPCatalogEntry) {
        probes[entry.id]?.cancel()
        probes[entry.id] = nil
        MCPKeychain.deleteAll(server: entry.id)
        if entry.isOAuth {
            MCPOAuth.signOut(serverID: entry.id)
            MCPProxy.shared.unregister(serverID: entry.id)
        }
        connections[entry.id] = nil
        states[entry.id] = nil
        drafts[entry.id] = nil
        save()
        exportAll()
    }

    /// Re-probes a connected server without changing its values.
    func refresh(_ entry: MCPCatalogEntry) {
        probes[entry.id]?.cancel()
        states[entry.id] = .connecting
        startProbe(entry)
    }

    func setEnabled(_ enabled: Bool, for entry: MCPCatalogEntry) {
        guard var connection = connections[entry.id] else { return }
        connection.isEnabled = enabled
        connections[entry.id] = connection
        save()
        exportAll()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: MCPPaths.connectionsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([MCPConnection].self, from: data) else { return }
        for connection in list {
            connections[connection.catalogID] = connection
            if connection.connectedAt != nil {
                states[connection.catalogID] = .connected(toolCount: connection.tools.count)
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let list = connections.values.sorted { $0.catalogID < $1.catalogID }
        guard let data = try? encoder.encode(list) else { return }
        try? data.write(to: MCPPaths.connectionsURL, options: .atomic)
    }

    /// Rewrites every provider's config from `enabledServers` and runs the one-time external-CLI cleanup.
    private func exportAll() {
        let servers = enabledServers
        // The proxy's routes follow the enabled list: one per signed-in server.
        MCPProxy.shared.replaceAll(servers.compactMap { server in
            guard let remote = server.oauthUpstream else { return nil }
            return (serverID: server.id, upstream: remote, headers: [:], usesOAuth: true)
        })
        MCPProviderConfig.writeAll(servers)
        MCPExternalSync.sync(servers)
        // The in-app clients (API providers) pick the new list up on their next use.
        Task { await MCPHub.shared.reload() }
    }

    /// Non-secret values from the connection, overlaid with the Keychain's secrets.
    private func storedValues(for entry: MCPCatalogEntry) -> [String: String] {
        var values = connections[entry.id]?.values ?? [:]
        for field in entry.fields where field.kind == .secret {
            if let secret = MCPKeychain.value(server: entry.id, field: field.key) {
                values[field.key] = secret
            }
        }
        return values
    }

    private func probeOnce(_ entry: MCPCatalogEntry, resolved: MCPResolvedServer) async throws -> MCPProbeResult {
        // A server that signs in: the browser flow first (SwarmAI's own, with its
        // branded page), then its route on the proxy, and only then the probe, which
        // goes through that route like every provider will.
        if let remote = resolved.oauthUpstream {
            if !MCPOAuth.isSignedIn(serverID: entry.id) {
                try await MCPOAuth.signIn(serverID: entry.id, serverName: entry.name, url: remote)
            }
            MCPProxy.shared.register(serverID: entry.id, upstream: remote, headers: [:], usesOAuth: true)
        }
        return try await MCPProbe.probe(resolved)
    }

    private func startProbe(_ entry: MCPCatalogEntry) {
        probes[entry.id] = Task {
            do {
                let resolved = entry.resolve(values: storedValues(for: entry))
                let result: MCPProbeResult
                do {
                    result = try await probeOnce(entry, resolved: resolved)
                } catch MCPProbeError.unauthorizedOAuth where resolved.oauthUpstream != nil {
                    MCPOAuth.signOut(serverID: entry.id)
                    MCPProxy.shared.unregister(serverID: entry.id)
                    result = try await probeOnce(entry, resolved: resolved)
                } catch MCPProbeError.http(let status, _) where resolved.oauthUpstream != nil && (status == 401 || status == 403) {
                    MCPOAuth.signOut(serverID: entry.id)
                    MCPProxy.shared.unregister(serverID: entry.id)
                    result = try await probeOnce(entry, resolved: resolved)
                }
                if var connection = connections[entry.id] {
                    connection.connectedAt = .now
                    connection.serverVersion = result.serverVersion
                    connection.tools = result.tools
                    connections[entry.id] = connection
                }
                states[entry.id] = .connected(toolCount: result.tools.count)
                save()
                exportAll()
            } catch is CancellationError {
            } catch {
                states[entry.id] = .failed(message: error.localizedDescription)
            }
        }
    }
}
