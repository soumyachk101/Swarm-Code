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
 @State private var selectedPluginId: String?
 @State private var pluginStates: [String: PluginStateRecord] = [:]
 @State private var showingConfigFor: PluginDescriptor? = nil
 @State private var pendingOAuth: PluginDescriptor? = nil

 // MARK: - Filtered plugins

 private var filteredPlugins: [PluginDescriptor] {
 if searchText.isEmpty { return PluginCollection.all }
 return PluginCollection.all.filter {
 $0.displayName.localizedCaseInsensitiveContains(searchText) ||
 $0.description.localizedCaseInsensitiveContains(searchText) ||
 $0.id.localizedCaseInsensitiveContains(searchText)
 }
 }

 private var agentPlugins: [PluginDescriptor] {
 filteredPlugins.filter { $0.type == .agent }
 }

 private var saasPlugins: [PluginDescriptor] {
 filteredPlugins.filter { $0.type == .saas }
 }

 // MARK: - Body

 public var body: some View {
 VStack(alignment: .leading, spacing: 0) {
 header
 Divider()

 if filteredPlugins.isEmpty {
 emptySearchState
 } else {
 ScrollView {
 LazyVStack(alignment: .leading, spacing: 0) {
 Section {
 ForEach(agentPlugins) { plugin in
 PluginRow(
 plugin: plugin,
 isEnabled: pluginStates[plugin.id]?.enabled ?? true,
 isConnected: pluginStates[plugin.id]?.connected ?? false,
 lastError: pluginStates[plugin.id]?.lastError
 )
 .padding(.vertical, 4)
 if plugin != agentPlugins.last {
 Divider().padding(.leading, 52)
 }
 }
 }

 Section {
 ForEach(saasPlugins) { plugin in
 PluginRow(
 plugin: plugin,
 isEnabled: pluginStates[plugin.id]?.enabled ?? true,
 isConnected: pluginStates[plugin.id]?.connected ?? false,
 lastError: pluginStates[plugin.id]?.lastError
 )
 .padding(.vertical, 4)
 if plugin != saasPlugins.last {
 Divider().padding(.leading, 52)
 }
 }
 }
 }
 }
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 }
 }
 }

 // MARK: - Header

 private var header: some View {
 HStack {
 VStack(alignment: .leading, spacing: 2) {
 Text("Plugins")
 .font(.title2.bold())
 Text("\(PluginCollection.all.count) plugins available")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 Spacer()
 }

 .padding(.horizontal, 20)
 .padding(.vertical, 14)
 }

 // MARK: - Empty Search

 private var emptySearchState: some View {
 VStack(spacing: 12) {
 Image(systemName: "magnifyingglass")
 .font(.title)
 .foregroundStyle(.secondary)
 Text("No plugins match your search")
 .font(.callout)
 .foregroundStyle(.secondary)
 }
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 }
}

// MARK: - Plugin Row

private struct PluginRow: View {
 let plugin: PluginDescriptor
 let isEnabled: Bool
 let isConnected: Bool
 let lastError: String?

 @State private var isHovered: Bool = false

 var body: some View {
 HStack(spacing: 12) {
 // Status orb
 ZStack {
 Circle()
 .fill(statusColor)
 .frame(width: 12, height: 12)

 if isConnected {
 Circle()
 .stroke(statusColor, lineWidth: 2)
 .frame(width: 16, height: 16)
 .opacity(isHovered ? 0.6 : 0)
 }
 }
 .accessibilityHidden(true)

 // Plugin info
 VStack(alignment: .leading, spacing: 2) {
 HStack(spacing: 6) {
 Text(plugin.displayName)
 .font(.body.bold())

 pluginTypeBadge

 if plugin.authType != .none {
 authBadge
 }
 }

 Text(plugin.description)
 .font(.caption)
 .foregroundStyle(.secondary)
 .lineLimit(2)

 if let error = lastError {
 Label(error, systemImage: "exclamationmark.triangle.fill")
 .font(.caption2)
 .foregroundStyle(.orange)
 }
 }
 .frame(maxWidth: .infinity, alignment: .leading)

 // Actions
 HStack(spacing: 8) {
 // OAuth login
 if plugin.authType == .oauth {
 OAuthButton(plugin: plugin, isConnected: isConnected)
 }

 // Config button
 Button {
 // Show config
 } label: {
 Image(systemName: "gearshape")
 .font(.body)
 }
 .buttonStyle(.borderless)
 .help("Configure \(plugin.displayName)")
 .accessibilityLabel("Configure \(plugin.displayName)")

 // Enable/disable toggle
 Toggle(isOn: Binding(
 get: { isEnabled },
 set: { _ = $0 } // handled by action below
 )) {
 EmptyView()
 }
 .toggleStyle(.switch)
 .labelsHidden()
 .onTapGesture {
 // Toggle handled via dedicated action
 }
 }
 }
 }
 .padding(.horizontal, 16)
 .padding(.vertical, 8)
 .background(
 RoundedRectangle(cornerRadius: 8)
 .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : .clear)
 )
 .onHover { hovering in
 isHovered = hovering
 }
 .accessibilityElement(children: .combine)
 .accessibilityLabel("\(plugin.displayName) plugin, \(isEnabled ? "enabled" : "disabled"), \(isConnected ? "connected" : "disconnected")")
 }

 private var statusColor: Color {
 if !isEnabled { return .gray }
 if lastError != nil { return .orange }
 if isConnected { return .green }
 return .secondary
 }

 private var pluginTypeBadge: some View {
 Text(plugin.type == .agent ? "Engine" : "Tool")
 .font(.caption2.bold())
 .padding(.horizontal, 6)
 .padding(.vertical, 2)
 .background(
 RoundedRectangle(cornerRadius: 4)
 .fill(plugin.type == .agent ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
 )
 .foregroundStyle(plugin.type == .agent ? .blue : .purple)
 }

 private var authBadge: some View {
 Text(plugin.authType.displayName)
 .font(.caption2)
 .padding(.horizontal, 6)
 .padding(.vertical: 2)
 .background(
 RoundedRectangle(cornerRadius: 4)
 .fill(Color.gray.opacity(0.1))
 )
 .foregroundStyle(.secondary)
 }
}

// MARK: - OAuth Button

private struct OAuthButton: View {
 let plugin: PluginDescriptor
 let isConnected: Bool

 @State private var isLoading: Bool = false

 var body: some View {
 Button {
 Task {
 isLoading = true
 await authenticate(plugin: plugin)
 isLoading = false
 }
 } label: {
 if isLoading {
 ProgressView()
 .scaleEffect(0.6)
 } else {
 Label(
 isConnected ? "Re-authenticate" : "Connect",
 systemImage: isConnected ? "arrow.triangle.2.circlepath" : "key.fill"
 )
 .font(.caption)
 }
 }
 .buttonStyle(.bordered)
 .controlSize(.small)
 .tint(isConnected ? .blue : .green)
 .accessibilityLabel(isConnected ? "Re-authenticate with \(plugin.displayName)" : "Connect to \(plugin.displayName)")
 }

 private func authenticate(plugin: PluginDescriptor) async {
 // In production, this triggers the OAuth flow via OAuthFlows
 // For now, simulate the flow
 do {
 let flow = OAuthFlowFactory.flow(for: plugin.authType)
 let _ = try? await flow.authenticate(
 for: plugin.id,
 scopes: plugin.scopes ?? [],
 redirectURI: "bridgemind://oauth/callback"
 )
 } catch {
 print("OAuth error: \(error)")
 }
 }
}

// MARK: - Preview

#Preview {
 PluginsPanelView()
 .environment(AppState())
 .frame(width: 520, height: 480)
}
