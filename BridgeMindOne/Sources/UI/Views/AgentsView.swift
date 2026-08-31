//
// AgentsView.swift
// BridgeMind One — Agent management
//
// Agent switcher, engine status, agent creation, and auto-pilot mode toggle.
//
// macOS 14+ APIs. Dark/light mode support. Accessibility labels throughout.
//

import SwiftUI
import Core

// MARK: - AgentsView

public struct AgentsView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var selectedAgentId: String
 @State private var isCreatingAgent: Bool = false
 @State private var newAgentName: String = ""
 @State private var engineStatuses: [String: EngineStatus] = [:]
 @State private var showingCreateSheet: Bool = false

 public init() {
 _selectedAgentId = State(initialValue: appState.selectedAgentId)
 }

 // MARK: - Body

 public var body: some View {
 NavigationSplitView {
 agentList
 } detail: {
 if let agent = PluginCollection.byId(selectedAgentId) {
 AgentDetailView(agent: agent, status: engineStatuses[agent.id])
 } else {
 Text("Select an agent")
 }
 }
 .navigationSplitViewStyle(.balanced)
 }
}

// MARK: - Agent List

private extension AgentsView {
 var agentList: some View {
 List(selection: $selectedAgentId) {
 Section("Agent Engines") {
 ForEach(PluginCollection.agents) { agent in
 Label(agent.displayName, systemImage: "brain.head.profile")
 .tag(agent.id)
 .accessibilityLabel("\(agent.displayName) agent")
 }
 }
 }
 .navigationTitle("Agents")
 .frame(minWidth: 200)
 }
}

// MARK: - Agent Detail View

private struct AgentDetailView: View {
 let agent: PluginDescriptor
 let status: EngineStatus?

 @State private var isActive: Bool = true
 @State private var autoPilot: Bool = false

 var body: some View {
 ScrollView {
 VStack(alignment: .leading, spacing: 20) {
 headerSection

 Divider()

 SectionCard(title: "Status") {
 statusContent
 }

 SectionCard(title: "Configuration") {
 configContent
 }

 SectionCard(title: "Capabilities") {
 capabilitiesContent
 }
 }
 .padding(20)
 }
 .navigationTitle(agent.displayName)
 .navigationSubtitle(agent.id)
 }
}

// MARK: - Agent Detail Sections

private extension AgentDetailView {

 var headerSection: some View {
 HStack(spacing: 16) {
 ZStack {
 Circle()
 .fill(OrbView.stateColor(.idle))
 .frame(width: 48, height: 48)

 Image(systemName: "brain.head.profile")
 .font(.title2)
 .foregroundStyle(.white)
 }

 VStack(alignment: .leading, spacing: 4) {
 Text(agent.displayName)
 .font(.title.bold())

 Text("v\(AppConfig.version) • \(agent.type.displayName)")
 .font(.caption)
 .foregroundStyle(.secondary)

 statusBadge
 }
 }
 }

 var statusBadge: some View {
 HStack(spacing: 4) {
 Circle()
 .fill(statusColor)
 .frame(width: 8, height: 8)

 Text(statusLabel)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 }

 var statusColor: Color {
 guard let s = status else { return .gray }
 return s.isConnected ? .green : (s.lastError != nil ? .orange : .secondary)
 }

 var statusLabel: String {
 guard let s = status else { return "Unknown" }
 if s.isConnected { return "Connected" }
 if let err = s.lastError { return "Error: \(err)" }
 return "Idle"
 }

 var statusContent: some View {
 VStack(alignment: .leading, spacing: 12) {
 HStack {
 Text("Engine Status")
 Spacer()

 Toggle("Active", isOn: $isActive)
 .toggleStyle(.switch)
 }
 .accessibilityElement(children: .combine)
 .accessibilityLabel("Agent engine active toggle")

 HStack {
 Text("Auto-Pilot")
 Spacer()

 Toggle("Enabled", isOn: $autoPilot)
 .toggleStyle(.switch)
 }
 .accessibilityElement(children: .combine)
 .accessibilityLabel("Auto-pilot mode toggle")

 if let s = status, let lastActive = s.lastActiveFormatted {
 Text("Last active: \(lastActive)")
 .font(.caption)
 .foregroundStyle(.tertiary)
 }
 }
 }

 var configContent: some View {
 VStack(alignment: .leading, spacing: 12) {
 if let apiKeyEnv = agent.apiKeyEnv {
 HStack {
 Text("API Key")
 Spacer()

 Text("\(apiKeyEnv)")
 .font(.caption.monospaced())
 .foregroundStyle(.tertiary)
 }
 }

 if let scopes = agent.scopes, !scopes.isEmpty {
 VStack(alignment: .leading, spacing: 4) {
 Text("Scopes:")
 .font(.caption.bold())
 ForEach(scopes, id: \.self) { scope in
 Text("• \(scope)")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }
 }

 HStack(spacing: 8) {
 Button("Reset") {
 // Reset configuration
 }
 .buttonStyle(.bordered)
 .controlSize(.small)

 Button("Save") {
 // Save configuration
 }
 .buttonStyle(.borderedProminent)
 .controlSize(.small)
 }
 }
 }

 var capabilitiesContent: some View {
 VStack(alignment: .leading, spacing: 8) {
 Text(agent.description)
 .font(.callout)
 .foregroundStyle(.secondary)

 if agent.warnings.isEmpty {
 EmptyView()
 } else {
 VStack(alignment: .leading, spacing: 4) {
 ForEach(agent.warnings, id: \.self) { warning in
 Label(warning, systemImage: "exclamationmark.triangle.fill")
 .font(.caption2)
 .foregroundStyle(.orange)
 }
 }
 }
 }
 }
}

// MARK: - Engine Status

public struct EngineStatus: Identifiable, Equatable {
 public let id: String
 public var isConnected: Bool
 public var lastError: String?
 public var lastActive: Date?
 public var toolCount: Int = 0

 public var lastActiveFormatted: String? {
 guard let date = lastActive else { return nil }
 let formatter = RelativeDateTimeFormatter()
 return formatter.localizedString(for: date, relativeTo: Date())
 }

 public init(
 id: String,
 isConnected: Bool = false,
 lastError: String? = nil,
 lastActive: Date? = nil,
 toolCount: Int = 0
 ) {
 self.id = id
 self.isConnected = isConnected
 self.lastError = lastError
 self.lastActive = lastActive
 self.toolCount = toolCount
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
 AgentsView()
 .environment(AppState())
 .frame(width: 800, height: 600)
}
