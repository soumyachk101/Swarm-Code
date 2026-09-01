//
// MiddlePaneView.swift
// BridgeMind One — Middle Agent & Chat Sub-Pane
//

import SwiftUI

public struct MiddlePaneView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Header for Middle Pane
            HStack {
                Text("Chats")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BMColors.textMuted)

                Spacer()

                Button {
                    appState.createNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Thread List
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.threads) { thread in
                        Button {
                            appState.selectedThreadId = thread.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(thread.title)
                                        .font(.system(size: 11))
                                        .foregroundStyle(BMColors.textMuted)

                                    Spacer()

                                    Text(thread.timeAgo)
                                        .font(.system(size: 10))
                                        .foregroundStyle(BMColors.textMuted)
                                }

                                Text(thread.previewSnippet)
                                    .font(.system(size: 12, weight: thread.id == appState.selectedThreadId ? .semibold : .regular))
                                    .foregroundStyle(thread.id == appState.selectedThreadId ? .white : BMColors.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                thread.id == appState.selectedThreadId ?
                                Color(red: 0.16, green: 0.16, blue: 0.18) : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
            }

            Spacer()
        }
        .frame(width: 180)
        .background(BMColors.middlePane)
        .overlay(
            Divider().background(BMColors.borderSubtle),
            alignment: .trailing
        )
    }
}
