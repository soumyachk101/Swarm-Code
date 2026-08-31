//
// ChatView.swift
// Main chat interface with streaming
//

import SwiftUI

public struct ChatView: View {
 @EnvironmentObject private var appState: AppState
 @State private var messageText = ""
 @State private var isProcessing = false

 public var body: some View {
 VStack(spacing: 0) {
 // Messages
 if let session = appState.currentSession {
 ScrollViewReader { proxy in
 ScrollView {
 LazyVStack(alignment: .leading, spacing: 12) {
 ForEach(session.messages) { message in
 MessageRowView(message: message)
 .id(message.id)
 }
 }
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
 // Tool availability indicator
 HStack(spacing: 4) {
 ForEach(appState.activePlugins.prefix(4), id: \.id) { plugin in
 Image(systemName: "puzzlepiece.extension.fill")
 .font(.caption2)
 .foregroundStyle(.green)
 }
 if appState.activePlugins.count > 4 {
 Text("+\(appState.activePlugins.count - 4)")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }

 // Text input
 TextField("Message...", text: $messageText, axis: .vertical)
 .textFieldStyle(.roundedBorder)
 .lineLimit(3...6)
 .disabled(isProcessing)
 .onSubmit(sendMessage)

 // Send button
 Button(action: sendMessage) {
 Image(systemName: "arrow.up.circle.fill")
 .font(.title2)
 .foregroundStyle(isProcessing ? .secondary : .accent)
 }
 .keyboardShortcut(.return, modifiers: [])
 .disabled(messageText.isEmpty || isProcessing)
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 }
 }

 private func sendMessage() {
 let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
 guard !text.isEmpty, !isProcessing else { return }

 // Create user message
 let message = ChatMessage(
 role: .user,
 content: text
 )

 // Add to session
 if appState.currentSession == nil {
 appState.createNewChat()
 }

 appState.currentSession?.messages.append(message)
 messageText = ""
 isProcessing = true
 appState.isProcessing = true
 appState.orbState = .thinking

 // Execute turn
 Task {
 do {
 let engine = BatchedChatTurnEngine(
 llmProvider: MockLLMProvider(),
 toolRouter: MockToolRouter()
 )

 for try await event in engine.executeTurn(
 session: appState.currentSession!,
 message: message,
 tools: []
 ) {
 switch event {
 case .chunk(let text):
 if appState.currentSession?.messages.last?.role != .assistant {
 appState.currentSession?.messages.append(ChatMessage(
 role: .assistant,
 content: text
 ))
 } else {
 appState.currentSession?.messages[appState.currentSession!.messages.count - 1].content += text
 }
 case .message(let msg):
 appState.currentSession?.messages.append(msg)
 case .done:
 appState.orbState = .idle
 case .error(let error):
 appState.orbState = .error
 appState.statusMessage = error.localizedDescription
 }
 }

 appState.saveCurrentChat()
 } catch {
 appState.statusMessage = error.localizedDescription
 }

 isProcessing = false
 appState.isProcessing = false
 }
 }
}
