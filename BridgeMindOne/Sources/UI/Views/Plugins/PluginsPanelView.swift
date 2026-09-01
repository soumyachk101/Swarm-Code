//
// PluginsPanelView.swift
// Plugin management panel
//

import SwiftUI
import Core

public struct PluginsPanelView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPlugin: PluginIdentity?
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        NavigationSplitView {
            // Plugin list
            VStack(spacing: 0) {
                Text("Plugins")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)

                List(filteredPlugins, selection: $selectedPlugin) { plugin in
                    PluginListRow(plugin: plugin, state: appState.plugins[plugin] ?? PluginState(pluginId: plugin.id))
                        .tag(plugin)
                }
            }
            .frame(minWidth: 220)
        } detail: {
            if let plugin = selectedPlugin {
                PluginDetailView(plugin: plugin)
            } else {
                Text("Select a plugin to view details")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedPlugin == nil {
                selectedPlugin = filteredPlugins.first
            }
        }
    }

    private var filteredPlugins: [PluginIdentity] {
        let all = appState.allPlugins
        if searchText.isEmpty { return all }
        return all.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
    }
}

// MARK: - Plugin List Row

private struct PluginListRow: View {
    let plugin: PluginIdentity
    let state: PluginState

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(plugin.type.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.connected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        if !state.enabled { return .gray }
        if state.connected { return .green }
        return .orange
    }
}

// MARK: - Plugin Detail View

private struct PluginDetailView: View {
    let plugin: PluginIdentity
    @Environment(AppState.self) private var appState

    var body: some View {
        let state = appState.plugins[plugin] ?? PluginState(pluginId: plugin.id)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading) {
                    Text(plugin.displayName)
                        .font(.title.bold())

                    Text(plugin.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                // Status
                HStack {
                    StatusBadge(
                        text: state.connected ? "Connected" : "Disconnected",
                        color: state.connected ? .green : .secondary
                    )
                    Spacer()
                }

                Divider()

                // Auth info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Authentication")
                        .font(.headline)

                    Text("Type: \(plugin.authType.rawValue)")
                        .font(.caption)

                    if let url = plugin.mcpURL {
                        Text("URL: \(url.absoluteString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let env = plugin.apiKeyEnv {
                        Text("Env: \(env)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let scopes = plugin.scopes {
                        Text("Scopes:")
                            .font(.caption)
                        ForEach(scopes, id: \.self) { scope in
                            Text("• \(scope)")
                                .font(.caption2)
                        }
                    }
                }

                Divider()

                // Actions
                VStack(spacing: 8) {
                    if !state.connected {
                        Button("Connect") {
                            var updated = state
                            updated.connected = true
                            appState.plugins[plugin] = updated
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Disconnect") {
                            var updated = state
                            updated.connected = false
                            appState.plugins[plugin] = updated
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}
