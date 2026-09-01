//
// ChatView.swift
// Main chat interface with streaming and tool usage
//

import SwiftUI
import Core

public struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var messageText = ""
    @State private var isProcessing = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Messages
            if let session = appState.currentSession, !session.messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(session.messages) { message in
                                MessageRowView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: session.messages.count) { _, _ in
                        if let lastMessage = session.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            } else {
                // Welcome screen
                WelcomeView()
            }

            // Input area
            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                // Text input
                TextField("Message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .disabled(isProcessing)
                    .onSubmit(sendMessage)

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isProcessing || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        let message = ChatMessage(
            role: .user,
            content: text
        )

        if appState.currentSession == nil {
            appState.createNewChat()
        }

        appState.currentSession?.messages.append(message)
        messageText = ""
        isProcessing = true
        appState.isProcessing = true
        appState.orbState = .thinking

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let reply = ChatMessage(
                    role: .assistant,
                    content: "I received your request: \"\(text)\". Connecting to the engine..."
                )
                appState.currentSession?.messages.append(reply)
                appState.orbState = .idle
            } catch {
                appState.orbState = .error
                appState.statusMessage = error.localizedDescription
            }

            isProcessing = false
            appState.isProcessing = false
        }
    }
}
