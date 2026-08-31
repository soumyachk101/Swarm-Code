//
// AgentSwitcherView.swift
// Agent selection and switching UI
//

import SwiftUI

public struct AgentSwitcherView: View {
 @EnvironmentObject private var appState: AppState
 @State private var selectedEngine: AgentEngineType = .claude

 public var body: some View {
 VStack(spacing: 20) {
 Text("Select Agent Engine")
 .font(.title.bold())

 // Engine grid
 LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)], spacing: 16) {
 ForEach(availableEngines, id: \.self) { engine in
 EngineCard(engine: engine, isSelected: selectedEngine == engine)
 .onTapGesture {
 selectedEngine = engine
 }
 }
 }

 Divider()

 // Selected engine details
 if let engine = availableEngines.first(where: { $0 == selectedEngine }) {
 VStack(alignment: .leading, spacing: 8) {
 Text(engine.displayName)
 .font(.headline)

 Text(engine.description)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .frame(maxWidth: .infinity, alignment: .leading)
 }

 Button("Switch Agent") {
 let agent = AgentIdentity(
 id: UUID().uuidString,
 name: selectedEngine.displayName,
 engine: selectedEngine
 )
 appState.switchAgent(to: agent)
 }
 .buttonStyle(.borderedProminent)
 .disabled(selectedEngine == appState.activeAgent?.engine)

 Spacer()
 }
 .padding(24)
 .frame(width: 400, height: 500)
 }
}

private struct EngineCard: View {
 let engine: AgentEngineType
 let isSelected: Bool

 public var body: some View {
 VStack(spacing: 8) {
 Image(systemName: engineIcon)
 .font(.system(size: 36))
 .foregroundStyle(isSelected ? .accent : .secondary)

 Text(engine.displayName)
 .font(.caption.bold())
 }
 .frame(maxWidth: .infinity)
 .padding(.vertical, 16)
 .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
 .clipShape(RoundedRectangle(cornerRadius: 12))
 .overlay(
 RoundedRectangle(cornerRadius: 12)
 .stroke(isSelected ? Color.accent : Color.clear, lineWidth: 2)
 )
 }

 private var engineIcon: String {
 switch engine {
 case .claude: return "brain.head.profile"
 case .codex: return "chevron.left.forwardslash.chevron.right"
 case .cursor: return "cursor.rays"
 case .copilot: return "octagon"
 case .aider: return "hammer"
 case .deepseek: return "dot.radiowaves.left.and.right"
 case .gemini: return "sparkles"
 case .grok: return "bolt"
 case .opencode: return "terminal"
 case .antigravity: return "airplane"
 case .droid: return "star.fill"
 }
 }
}

private extension AgentEngineType {
 var displayName: String {
 switch self {
 case .claude: return "Claude"
 case .codex: return "Codex"
 case .copilot: return "Copilot"
 case .cursor: return "Cursor"
 case .aider: return "Aider"
 case .deepseek: return "DeepSeek"
 case .gemini: return "Gemini"
 case .grok: return "Grok"
 case .opencode: return "OpenCode"
 case .antigravity: return "Antigravity"
 case .droid: return "Droid"
 }
 }

 var description: String {
 switch self {
 case .claude: return "Anthropic's Claude via Claude Code CLI"
 case .codex: return "OpenAI's Codex CLI"
 case .copilot: return "GitHub Copilot via MCP"
 case .cursor: return "Cursor IDE integration"
 case .aider: return "Aider coding assistant"
 case .deepseek: return "DeepSeek AI models"
 case .gemini: return "Google Gemini"
 case .grok: return "xAI's Grok"
 case .opencode: return "OpenCode terminal agent"
 case .antigravity: return "Antigravity AI"
 case .droid: return "Factory.ai Droid"
 }
 }
}
