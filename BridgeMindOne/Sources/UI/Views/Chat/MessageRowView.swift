//
// MessageRowView.swift
// Individual message bubble
//

import SwiftUI
import Core

public struct MessageRowView: View {
    let message: ChatMessage
    @Environment(AppState.self) private var appState

    public init(message: ChatMessage) {
        self.message = message
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 28, height: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if message.role != .user {
                    Text(roleLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(messageBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private var avatarView: some View {
        Group {
            switch message.role {
            case .user:
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
            case .assistant:
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.green)
            case .tool:
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            case .system:
                Image(systemName: "gear")
                    .font(.title3)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return appState.activeAgent.displayName
        case .tool: return "Tool"
        case .system: return "System"
        }
    }

    private var messageBackground: Color {
        switch message.role {
        case .user: return Color.blue.opacity(0.08)
        case .assistant: return Color.green.opacity(0.08)
        case .tool: return Color.orange.opacity(0.08)
        case .system: return Color.gray.opacity(0.08)
        }
    }
}
