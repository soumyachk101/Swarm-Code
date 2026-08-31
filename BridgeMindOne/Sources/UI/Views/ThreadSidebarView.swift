//
// ThreadSidebarView.swift
// Chat thread list in sidebar
//

import SwiftUI

public struct ThreadSidebarView: View {
 @EnvironmentObject private var appState: AppState
 @Environment(\.dismiss) private var dismiss
 @State private var searchText = ""

 public var body: some View {
 VStack(spacing: 0) {
 // Header
 HStack {
 Text("Chats")
 .font(.headline)
 Spacer()
 Button(action: { appState.createNewChat() }) {
 Image(systemName: "plus")
 }
 .help("New Chat")
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(.ultraThinMaterial)

 // Search
 if !searchText.isEmpty {
 TextField("Search chats...", text: $searchText)
 .textFieldStyle(.roundedBorder)
 .padding(.horizontal, 8)
 .padding(.vertical, 4)
 }

 // Thread list
 List(selection: $appState.selectedThreadId) {
 ForEach(filteredSessions) { session in
 ThreadRowView(session: session)
 .tag(session.id)
 }
 .onDelete(perform: deleteSessions)
 }
 .listStyle(.sidebar)
 .searchable(text: $searchText, prompt: "Search conversations")

 Divider()

 // Agent selector at bottom
 VStack(spacing: 4) {
 Divider()
 HStack {
 if let agent = appState.activeAgent {
 Text(agent.name)
 .font(.caption)
 .foregroundStyle(.secondary)
 Image(systemName: agentIcon(for: agent.engine))
 .foregroundStyle(.accent)
 }
 Spacer()
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 6)
 .background(.ultraThinMaterial)
 }
 }
 }
}

private extension ThreadSidebarView {
 var filteredSessions: [ChatSession] {
 if searchText.isEmpty {
 return appState.sessions
 }
 return appState.sessions.filter { session in
 session.title?.localizedCaseInsensitiveContains(searchText) ?? false ||
 session.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
 }
 }

 func deleteSessions(at offsets: IndexSet) {
 for index in offsets {
 if let session = filteredSessions[safe: index] {
 appState.deleteSession(session)
 }
 }
 }

 func agentIcon(for engine: AgentEngineType) -> String {
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

extension Collection {
 subscript(safe index: Index) -> Element? {
 indices.contains(index) ? self[index] : nil
 }
}
