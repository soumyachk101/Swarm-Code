//
// ThreadSidebarView.swift
// Chat thread list in sidebar
//

import SwiftUI
import Core

public struct ThreadSidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        @Bindable var state = appState

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

            // Thread list
            List(selection: $state.selectedThreadId) {
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
                HStack {
                    Text(appState.activeAgent.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: engineIcon(for: appState.activeAgent))
                        .foregroundStyle(.tint)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
        .onChange(of: appState.selectedThreadId) { _, newId in
            if let newId {
                appState.selectSession(id: newId)
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
            session.title.localizedCaseInsensitiveContains(searchText) ||
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

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
