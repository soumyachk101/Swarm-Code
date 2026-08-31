//
// PluginsPanelView.swift
// BridgeMind One — Plugin management panel
//
// Plugin list with enable/disable toggles, connection status indicators,
// OAuth login buttons, and per-plugin configuration.
//
// macOS 14+ APIs. Dark/light mode support. Accessibility labels throughout.
//

import SwiftUI
import Core

// MARK: - PluginsPanelView

public struct PluginsPanelView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var searchText: String = ""
 @State private var selectedPlugin: PluginIdentity?
 @State private var pluginStates: [PluginIdentity: PluginState] = [:]

 // MARK: - Computed

 private var filteredPlugins: [PluginIdentity] {
 if searchText.isEmpty { return PluginRegistry.builtinPlugins }
 return PluginRegistry.builtinPlugins.filter {
 $0.displayName.localizedCaseInsensitiveContains(searchText) ||
 $0.id.localizedCaseInsensitiveContains(searchText)
 }
 }

 // MARK: - Body

 public var body: some View {
 NavigationSplitView {
 pluginList
 } detail: {
 if let plugin = selectedPlugin {
 PluginDetailView(plugin: plugin, state: state(for: plugin))
 } else {
 placeholderDetail
 }
 }
 .navigationSplitViewStyle(.balanced)
 }
}

// MARK: - Plugin List

private extension PluginsPanelView {
 var pluginList: some View {
 VStack(spacing: 0) {
 header
 searchField
 List(selection: $selectedPlugin) {
 ForEach(filteredPlugins) { plugin in
 PluginListRow(
 plugin: plugin,
 state: state(for: plugin)
 )
 .tag(plugin)
 }
 }
 }
 .navigationTitle("Plugins")
 .frame(minWidth: 240)
 }

 var header: some View {
 HStack {
 Text("Plugins")
 .font(.headline)
 Spacer()
 Text("\(filteredPlugins.count) available")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 12)
 }

 var searchField: some View {
 TextField("Search plugins...", text: $searchText)
 .textFieldStyle(.roundedBorder)
 .padding(.horizontal, 12)
 .padding(.bottom, 8)
 }

 func state(for plugin: PluginIdentity) -> PluginState {
 if let existing = pluginStates[plugin] { return existing }
 let state = PluginState(pluginId: plugin, enabled: true, connected: false)
 pluginStates[plugin] = state
 return state
 }

 var placeholderDetail: some View {
 VStack(spacing: 16) {
 Image(systemName: "puzzlepiece.extension")
 .font(.system(size: 48))
 .foregroundStyle(.secondary)

 Text("Select a plugin")
 .font(.title3)
 .foregroundStyle(.secondary)

 Text("Choose a plugin from the list to view details and configure it.")
 .font(.caption)
 .foregroundStyle(.tertiary)
 .multilineTextAlignment(.center)
 }
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 }
}

// MARK: - Plugin List Row

private struct PluginListRow: View {
 let plugin: PluginIdentity
 let state: PluginState

 @State private var isHovered: Bool = false

 var body: some View {
 HStack(spacing: 10) {
 Circle()
 .fill(connectionColor)
 .frame(width: 10, height: 10)

 VStack(alignment: .leading, spacing: 1) {
 Text(plugin.displayName)
 .font(.body.weight(.medium))

 Text(plugin.type.rawValue.capitalized)
 .font(.caption2)
 .foregroundStyle(.secondary)
 }

 Spacer()

 if plugin.authType == .oauth {
 Image(systemName: "key.fill")
 .font(.caption2)
 .foregroundStyle(.orange)
 } else if plugin.authType == .apiKey {
 Image(systemName: "key")
 .font(.caption2)
 .foregroundStyle(.blue)
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 6)
 .background(
 RoundedRectangle(cornerRadius: 6)
 .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : .clear)
 )
 .onHover { isHovered = $0 }
 }

 private var connectionColor: Color {
 if !state.enabled { return .gray }
 if state.connected { return .green }
 return .orange
 }
}

// MARK: - Plugin Detail View

private struct PluginDetailView: View {
 let plugin: PluginIdentity
 let state: PluginState

 @State private var isConnecting: Bool = false
 @State private var isEnabled: Bool = true
 @State private var configText: String = ""

 init(plugin: PluginIdentity, state: PluginState) {
 self.plugin = plugin
 self.state = state
 _isEnabled = State(initialValue: state.enabled)
 }

 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 20) {
 // Header
 HStack(spacing: 14) {
 ZStack {
 Circle()
 .fill(OrbView.stateColor(.idle))
 .frame(width: 44, height: 44)
 Image(systemName: pluginIcon)
 .font(.title3)
 .foregroundStyle(.white)
 }

 VStack(alignment: .leading, spacing: 2) {
 Text(plugin.displayName)
 .font(.title2.bold())
 Text(plugin.id)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 }

 Divider()

 // Status
 SectionCard(title: "Status") {
 HStack(spacing: 12) {
 Label(
 state.connected ? "Connected" : "Disconnected",
 systemImage: state.connected ? "checkmark.circle.fill" : "xmark.circle.fill"
 )
 .foregroundStyle(state.connected ? .green : .secondary)

 Spacer()

 Button {
 Task {
 await connectPlugin()
 }
 } label: {
 if isConnecting {
 ProgressView()
 .scaleEffect(0.7)
 } else {
 Label(
 state.connected ? "Reconnect" : "Connect",
 systemImage: "arrow.triangle.2.circlepath"
 )
 }
 }
 .buttonStyle(.bordered)
 .disabled(isConnecting)
 }
 }

 Toggle("Enabled", isOn: $isEnabled)
 .accessibilityLabel("Enable or disable \(plugin.displayName)")
 }

 // Auth
 if plugin.authType != .none {
 SectionCard(title: "Authentication") {
 VStack(alignment: .leading, spacing: 8) {
 Text("Type: \(plugin.authType.rawValue.capitalized)")
 .font(.caption)
 .foregroundStyle(.secondary)

 if plugin.authType == .apiKey, let envVar = plugin.apiKeyEnv {
 Text("Environment variable: \(envVar)")
 .font(.caption.monospaced())
 .foregroundStyle(.tertiary)
 }

 if let scopes = plugin.scopes, !scopes.isEmpty {
 Text("Required scopes:")
 .font(.caption.bold())
 ForEach(scopes, id: \.self) { scope in
 Text("• \(scope)")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }
 }
 }
 }

 // Transport
 SectionCard(title: "Transport") {
 VStack(alignment: .leading, spacing: 6) {
 Text("Type: \(plugin.authType.rawValue.capitalized)")
 .font(.caption)

 if let mcpURL = plugin.mcpURL {
 Text("URL: \(mcpURL.absoluteString)")
 .font(.caption.monospaced())
 .foregroundStyle(.tertiary)
 }
 }
 }

 // Configuration
 SectionCard(title: "Configuration") {
 TextEditor(text: $configText)
 .font(.caption.monospaced())
 .frame(height: 120)
 .border(Color(nsColor: .separatorColor), width: 0.5)
 .accessibilityLabel("Plugin configuration text")

 HStack {
 Spacer()
 Button("Save Configuration") { }
 .buttonStyle(.borderedProminent)
 .controlSize(.small)
 }
 }

 Spacer()
 }
 .padding(20)
 }
 }

 private func connectPlugin() async {
 isConnecting = true
 defer { isConnecting = false }

 if plugin.authType == .oauth {
 let redirectURI = "bridgemind://oauth/callback"
 let scopes = (plugin.scopes ?? []).joined(separator: " ")
 let urlString = "https://auth.bridgemind.ai/authorize?client_id=\(plugin.id)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scopes)"
 if let url = URL(string: urlString) {
 NSWorkspace.shared.open(url)
 }
 }
 }

 private var pluginIcon: String {
 switch plugin.type {
 case .remote: return "globe"
 case .local: return "desktopcomputer"
 case .oauth: return "key"
 case .builtin: return "puzzlepiece.extension.fill"
 }
 }
}

// MARK: - Section Card

private struct SectionCard: View {
 let title: String
 let content: some View

 var body: some View {
 VStack(alignment: .leading, spacing: 0) {
 Text(title)
 .font(.headline)
 .padding(.bottom, 8)

 content
 .padding()
 .frame(maxWidth: .infinity, alignment: .leading)
 .background(
 RoundedRectangle(cornerRadius: 8)
 .fill(Color(nsColor: .controlBackgroundColor))
 )
 }
 }
}

// MARK: - Preview

#Preview {
 PluginsPanelView()
 .environment(AppState())
 .frame(width: 700, height: 500)
}
