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

 @State private var selectedEngine: EngineType = .claude
 @State private var engineStatuses: [EngineType: EngineHealth] = [:]

 // MARK: - Body

 public var body: some View {
 NavigationSplitView {
 agentList
 } detail: {
 AgentDetailView(engine: selectedEngine, status: engineStatuses[selectedEngine])
 }
 .navigationSplitViewStyle(.balanced)
 }
}

// MARK: - Agent List

private extension AgentsView {
 var agentList: some View {
 List(selection: $selectedEngine) {
 Section("Agent Engines") {
 ForEach(EngineType.allCases, id: \.self) { engineType in
 Label(engineType.displayName, systemImage: engineIcon(for: engineType))
 .tag(engineType)
 .accessibilityLabel("\(engineType.displayName) agent engine")
 }
 }
 }
 .navigationTitle("Agents")
 .frame(minWidth: 200)
 }

 func engineIcon(for engine: EngineType) -> String {
 switch engine {
 case .claude: return "brain.head.profile"
 case .codex: return "chevron.left.forwardslash.chevron.right"
 case .cursor: return "cursor.rays"
 case .aider: return "hammer"
 case .deepseek: return "dot.radiowaves.left.and.right"
 case .gemini: return "sparkles"
 case .grok: return "bolt"
 case .opencode: return "terminal"
 default: return "cpu"
 }
 }
}

// MARK: - Agent Detail View

private struct AgentDetailView: View {
 let engine: EngineType
 let status: EngineHealth?

 @State private var isActive: Bool = false
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

 SectionCard(title: "Description") {
 Text(engineDescription(for: engine))
 .font(.callout)
 .foregroundStyle(.secondary)
 }

 Spacer()
 }
 .padding(20)
 }
 .navigationTitle(engine.displayName)
 .navigationSubtitle(engine.rawValue.capitalized)
 }
}

// MARK: - Agent Detail Sections

private extension AgentDetailView {

 var headerSection: some View {
 HStack(spacing: 16) {
 ZStack {
 Circle()
 .fill(OrbView.stateColor(statusState))
 .frame(width: 48, height: 48)

 Image(systemName: engineIcon)
 .font(.title2)
 .foregroundStyle(.white)
 }

 VStack(alignment: .leading, spacing: 4) {
 Text(engine.displayName)
 .font(.title.bold())

 Text("v\(AppConfig.version) \u{2022} \(engine.rawValue.capitalized)")
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
 .accessibilityLabel("Status: \(statusLabel)")
 }

 var statusColor: Color {
 guard let s = status else { return .gray }
 switch s.status {
 case .healthy: return .green
 case .degraded: return .orange
 case .offline: return .red
 case .unknown: return .gray
 }
 }

 var statusLabel: String {
 guard let s = status else { return "Unknown" }
 switch s.status {
 case .healthy: return "Healthy"
 case .degraded: return "Degraded"
 case .offline: return "Offline"
 case .unknown: return "Unknown"
 }
 }

 var statusState: OrbState {
 guard let s = status else { return .idle }
 switch s.status {
 case .healthy: return .idle
 case .degraded: return .thinking
 case .offline: return .error
 case .unknown: return .idle
 }
 }

 var engineIcon: String {
 switch engine {
 case .claude: return "brain.head.profile"
 case .codex: return "chevron.left.forwardslash.chevron.right"
 case .cursor: return "cursor.rays"
 case .aider: return "hammer"
 case .deepseek: return "dot.radiowaves.left.and.right"
 case .gemini: return "sparkles"
 case .grok: return "bolt"
 case .opencode: return "terminal"
 default: return "cpu"
 }
 }
}

private extension AgentDetailView {
 var statusContent: some View {
 VStack(alignment: .leading, spacing: 12) {
 Toggle("Active", isOn: $isActive)
 .toggleStyle(.switch)
 .accessibilityElement(children: .combine)
 .accessibilityLabel("Agent engine active toggle")

 Toggle("Auto-Pilot", isOn: $autoPilot)
 .toggleStyle(.switch)
 .accessibilityElement(children: .combine)
 .accessibilityLabel("Auto-pilot mode toggle")

 if let s = status, let latency = s.latencyMs {
 Text("Latency: \(String(format: "%.0f", latency))ms")
 .font(.caption)
 .foregroundStyle(.tertiary)
 }

 if let s = status, let message = s.message {
 Text(message)
 .font(.caption)
 .foregroundStyle(.tertiary)
 }
 }
 }

 var configContent: some View {
 VStack(alignment: .leading, spacing: 12) {
 HStack {
 Text("Binary path")
 Spacer()
 Text("/usr/local/bin/\(engine.rawValue)")
 .font(.caption.monospaced())
 .foregroundStyle(.tertiary)
 }

 Stepper(value: .constant, in: 1024...128000, step: 1024) {
 Text("Max tokens: 4096")
 }
 .accessibilityLabel("Maximum tokens per request")

 Picker("Model", selection: .constant("default")) {
 Text("Default").tag("default")
 Text("Latest").tag("latest")
 }
 .accessibilityLabel("Model selection")
 }
 }
}

// MARK: - Helpers

private func engineDescription(for engine: EngineType) -> String {
 switch engine {
 case .claude: return "Anthropic's Claude via Claude Code CLI"
 case .codex: return "OpenAI's Codex CLI"
 case .cursor: return "Cursor IDE integration"
 case .aider: return "Aider coding assistant"
 case .deepseek: return "DeepSeek AI models"
 case .gemini: return "Google Gemini CLI"
 case .grok: return "xAI's Grok"
 case .opencode: return "OpenCode terminal agent"
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
