//
// ThreadSidebarView.swift
// BridgeMind One — Main Navigation & Thread Sidebar
//

import SwiftUI
import Core

public struct ThreadSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Brand & Status Header
            HStack(spacing: 10) {
                OrbView(state: $state.orbState)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BridgeMind")
                        .font(.system(size: 14, weight: .bold))
                    Text("v\(AppConfig.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    appState.createNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("New Conversation (⌘N)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Main Workspace Navigation Items
            VStack(spacing: 2) {
                ForEach(AppState.SidebarItem.allCases) { item in
                    NavigationTabButton(
                        item: item,
                        isSelected: appState.sidebarSelection == item,
                        badgeCount: badgeCount(for: item)
                    ) {
                        appState.sidebarSelection = item
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            // If in Chat mode, show Chat Threads List
            if appState.sidebarSelection == .chat {
                VStack(spacing: 0) {
                    HStack {
                        Text("Recent Chats")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    List(selection: $state.selectedThreadId) {
                        ForEach(filteredSessions) { session in
                            ThreadRowView(session: session)
                                .tag(session.id)
                        }
                        .onDelete(perform: deleteSessions)
                    }
                    .listStyle(.sidebar)
                    .searchable(text: $searchText, prompt: "Search chats")
                }
            } else {
                Spacer()
            }

            Divider()

            // Bottom Engine Status & Switcher
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)

                Text(appState.activeAgent.displayName)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button("Switch") {
                    appState.isAgentSwitcherPresented = true
                }
                .font(.caption2.bold())
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .onChange(of: appState.selectedThreadId) { _, newId in
            appState.selectSession(id: newId)
        }
    }

    private func badgeCount(for item: AppState.SidebarItem) -> Int? {
        switch item {
        case .plugins: return appState.allPlugins.count
        case .skills: return 7
        default: return nil
        }
    }
}

// MARK: - Navigation Tab Button

private struct NavigationTabButton: View {
    let item: AppState.SidebarItem
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 20)

                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Spacer()

                if let badge = badgeCount {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filtered Sessions

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
        let current = filteredSessions
        for index in offsets {
            if current.indices.contains(index) {
                appState.deleteSession(current[index])
            }
        }
    }
}
