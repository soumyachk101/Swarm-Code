//
// ExactChatView.swift
// BridgeMind One — Exact Chat Timeline & Input Container matching screenshot
//

import SwiftUI
import Core

public struct ExactChatView: View {
    @Environment(AppState.self) private var appState
    @State private var inputText: String = ""
    @State private var isThoughtExpanded: Bool = false

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Agent Header Banner
            HStack(alignment: .center, spacing: 12) {
                // Agent Orange Starburst Icon
                ZStack {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BMColors.claudeOrange)
                }
                .frame(width: 28, height: 28)
                .background(BMColors.claudeOrange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.selectedAgent.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text(appState.selectedAgent.engineSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)
                }

                Spacer()

                // • 0 working status pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(BMColors.textMuted)
                        .frame(width: 5, height: 5)
                    Text("\(appState.workingCount) working")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                .clipShape(Capsule())

                // Sub-tabs [ Chats | Skills 2 | Settings ]
                HStack(spacing: 2) {
                    ForEach(AppState.MiddleSubTab.allCases) { tab in
                        Button {
                            appState.middleSubTab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: appState.middleSubTab == tab ? .semibold : .regular))
                                .foregroundStyle(appState.middleSubTab == tab ? .white : BMColors.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    appState.middleSubTab == tab ?
                                    Color(red: 0.22, green: 0.22, blue: 0.25) : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // New chat dropdown button
                Button {
                    appState.createNewChat()
                } label: {
                    HStack(spacing: 4) {
                        Text("New chat")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BMColors.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(BMColors.chatBackground)
            .overlay(
                Divider().background(BMColors.borderSubtle),
                alignment: .bottom
            )

            // Timeline Message Area
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if let thread = appState.currentThread {
                        ForEach(thread.messages) { message in
                            if message.role == .user {
                                // User Message Card
                                HStack {
                                    Text(message.content)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .lineSpacing(4)
                                    Spacer()
                                }
                                .padding(14)
                                .background(BMColors.userMessage)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(BMColors.borderSubtle, lineWidth: 1)
                                )
                            } else {
                                // Assistant Response Timeline
                                VStack(alignment: .leading, spacing: 12) {
                                    // Collapsible Thought block
                                    if let thought = message.thoughtTime {
                                        HStack(spacing: 6) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(BMColors.textMuted)
                                            Text(thought)
                                                .font(.system(size: 12))
                                                .foregroundStyle(BMColors.textMuted)
                                        }
                                    }

                                    // Previous tool calls count
                                    if let prevCount = message.previousToolCount {
                                        HStack(spacing: 6) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(BMColors.textMuted)
                                            Text("+\(prevCount) previous tool calls")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(BMColors.textMuted)
                                        }
                                    }

                                    // Tool Call Execution Cards
                                    ForEach(message.toolCalls) { tool in
                                        HStack(spacing: 8) {
                                            Image(systemName: toolIcon(for: tool.type))
                                                .font(.system(size: 11))
                                                .foregroundStyle(BMColors.textSecondary)

                                            Text(tool.type)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)

                                            Text(tool.detail)
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundStyle(BMColors.textSecondary)

                                            Spacer()

                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(BMColors.textMuted)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }

                                    // Text Content
                                    if !message.content.isEmpty {
                                        Text(LocalizedStringKey(message.content))
                                            .font(.system(size: 13))
                                            .foregroundStyle(.white)
                                            .lineSpacing(5)
                                            .textSelection(.enabled)
                                            .padding(.top, 4)
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }

            // Bottom Floating Input Box
            VStack(alignment: .leading, spacing: 10) {
                // Top text input line
                TextField("Ask anything...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .onSubmit(sendCurrentMessage)

                // Bottom Action Controls
                HStack(spacing: 12) {
                    // Model Dropdown
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(BMColors.claudeOrange)

                        Text(appState.selectedModel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(BMColors.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                    // Effort Level (High)
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(BMColors.textSecondary)

                        Text(appState.effortLevel)
                            .font(.system(size: 11))
                            .foregroundStyle(BMColors.textSecondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundStyle(BMColors.textMuted)
                    }

                    // Auto-accept edits
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(BMColors.textSecondary)

                        Text("Auto-accept edits")
                            .font(.system(size: 11))
                            .foregroundStyle(BMColors.textSecondary)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                            .foregroundStyle(BMColors.textMuted)
                    }

                    // Build
                    HStack(spacing: 4) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(BMColors.textMuted)

                        Text("Build")
                            .font(.system(size: 11))
                            .foregroundStyle(BMColors.textMuted)
                    }

                    Spacer()

                    // Token count
                    Text(appState.tokenCountText)
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)

                    // Audio dictation waveform button
                    Button {} label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 28, height: 28)

                            Image(systemName: "waveform")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black)
                        }
                    }
                    .buttonStyle(.plain)

                    // Send Button
                    Button(action: sendCurrentMessage) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.20, blue: 0.23))
                                .frame(width: 28, height: 28)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .background(BMColors.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(BMColors.border, lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(BMColors.chatBackground)
    }

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsg = RichChatMessage(role: .user, content: text)
        if let idx = appState.threads.firstIndex(where: { $0.id == appState.selectedThreadId }) {
            appState.threads[idx].messages.append(userMsg)
        }
        inputText = ""

        // Simulate tool execution & assistant response
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let reply = RichChatMessage(
                role: .assistant,
                content: "Executing plan with **\(appState.selectedAgent.name)**:\n\n• Verified environment and dependencies.\n• Connected to MCP protocol bridge.",
                thoughtTime: "Thought for 3s",
                toolCalls: [
                    ToolCallItem(type: "Run", detail: "bridgemind agent exec --target \(appState.selectedAgent.id)")
                ]
            )
            if let idx = appState.threads.firstIndex(where: { $0.id == appState.selectedThreadId }) {
                appState.threads[idx].messages.append(reply)
            }
        }
    }

    private func toolIcon(for type: String) -> String {
        switch type {
        case "Search": return "magnifyingglass"
        case "Run": return "terminal"
        case "Draft": return "doc.text"
        default: return "wrench"
        }
    }
}
