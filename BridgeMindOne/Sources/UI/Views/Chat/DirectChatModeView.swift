//
// DirectChatModeView.swift
// BridgeMind One — Direct Conversational AI Chat Mode
//

import SwiftUI
import Core

public struct DirectChatModeView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var selectedModel: String = "Claude 3.7 Sonnet"
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            content: "Hello! I am your AI assistant in direct chat mode. You can ask questions, brainstorm ideas, analyze data, or query any attached knowledge."
        )
    ]

    let availableModels = [
        "Claude 3.7 Sonnet",
        "Claude 3.5 Haiku",
        "OpenAI Codex / GPT-4o",
        "Gemini 2.0 Flash",
        "DeepSeek R1",
        "Grok 3"
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                // Model Picker
                Menu {
                    ForEach(availableModels, id: \.self) { model in
                        Button(model) {
                            selectedModel = model
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(BMColors.claudeOrange)

                        Text(selectedModel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(BMColors.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 0.14, green: 0.14, blue: 0.17))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    messages = [
                        ChatMessage(role: .assistant, content: "Chat cleared. What would you like to explore?")
                    ]
                } label: {
                    Label("Clear Chat", systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(BMColors.sidebar)
            .overlay(
                Divider().background(BMColors.borderSubtle),
                alignment: .bottom
            )

            // Chat Timeline
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(messages) { msg in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(msg.role == .user ? BMColors.accentBlue : BMColors.claudeOrange)
                                        .frame(width: 26, height: 26)

                                    Image(systemName: msg.role == .user ? "person.fill" : "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(msg.role == .user ? "You" : selectedModel)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(BMColors.textSecondary)

                                    Text(LocalizedStringKey(msg.content))
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(msg.role == .user ? BMColors.userMessage : BMColors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(BMColors.borderSubtle, lineWidth: 1)
                            )
                            .id(msg.id)
                        }
                    }
                    .padding(20)
                }
                .background(BMColors.chatBackground)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Bottom Prompt Input Box
            HStack(spacing: 10) {
                TextField("Message \(selectedModel)...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .onSubmit(sendChatMessage)

                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Button(action: sendChatMessage) {
                    ZStack {
                        Circle()
                            .fill(BMColors.accentBlue)
                            .frame(width: 30, height: 30)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
            .background(BMColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(BMColors.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(BMColors.chatBackground)
        }
    }

    private func sendChatMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: text))
        inputText = ""
        isGenerating = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let reply = ChatMessage(
                role: .assistant,
                content: "Here is what I found regarding **\"\(text)\"**:\n\n1. **Direct Reasoning**: Evaluated against current architecture standards.\n2. **Synthesis**: Formulated structured insight without hallucinations.\n3. **Recommendation**: You can switch to **Code Mode** to apply edits or **Agent Mode** to execute multi-tool automations."
            )
            messages.append(reply)
            isGenerating = false
        }
    }
}
