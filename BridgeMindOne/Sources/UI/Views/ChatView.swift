//
// ChatView.swift
// BridgeMind One — Main chat interface
//
// Thread list sidebar, message list with streaming, input field with auto-expand,
// markdown rendering, code block syntax highlighting, and tool call display.
//
// macOS 14+ APIs. Dark/light mode support. Accessibility labels throughout.
//

import SwiftUI
import Core

// MARK: - ChatView

public struct ChatView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var inputText: String = ""
 @State private var isProcessing: Bool = false

 // MARK: - Body

 public var body: some View {
 VStack(spacing: 0) {
 if let session = appState.currentSession {
 messageList
 } else {
 emptyState
 }
 Divider()
 inputArea
 }
 }
}

// MARK: - Message List

private extension ChatView {
 var messageList: some View {
 ScrollViewReader { proxy in
 ScrollView {
 LazyVStack(alignment: .leading, spacing: 12) {
 ForEach(appState.currentMessages) { message in
 MessageRow(message: message)
 .id(message.id)
 }

 if appState.isThinking {
 thinkingIndicator
 .id("thinking-indicator")
 }

 if appState.isStreaming {
 streamingIndicator
 .id("streaming-indicator")
 }
 }
 .padding(.horizontal, 16)
 .padding(.top, 12)
 }
 }
 .onChange(of: appState.currentMessages.count) { _, _ in
 withAnimation(.easeOut(duration: 0.3)) {
 if let lastId = appState.currentMessages.last?.id {
 proxy.scrollTo(lastId, anchor: .bottom)
 }
 }
 }
 }
}

// MARK: - Empty State

private extension ChatView {
 var emptyState: some View {
 VStack(spacing: 20) {
 Spacer()

 Image(systemName: "bubble.left.and.bubble.right.fill")
 .font(.system(size: 64))
 .foregroundStyle(.secondary)

 Text("No chat selected")
 .font(.title2)
 .foregroundStyle(.secondary)

 Button("Start New Chat") {
 Task {
 await appState.createNewChat()
 }
 }
 .buttonStyle(.borderedProminent)

 Spacer()
 }
 .frame(maxWidth: .infinity, maxHeight: .infinity)
 }
}

// MARK: - Indicators

private extension ChatView {
 var thinkingIndicator: some View {
 HStack(spacing: 8) {
 OrbView(state: .thinking, size: 18)
 Text("Thinking\u{2026}")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(.vertical, 8)
 }

 var streamingIndicator: some View {
 HStack(spacing: 8) {
 OrbView(state: .speaking, size: 18)
 Text("Generating\u{2026}")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .padding(.vertical, 8)
 }
}

// MARK: - Input Area

private extension ChatView {
 var inputArea: some View {
 VStack(spacing: 0) {
 HStack(alignment: .bottom, spacing: 8) {
 // Tool indicators
 HStack(spacing: 4) {
 ForEach(appState.availableAgents.prefix(4), id: \.id) { agent in
 Image(systemName: "puzzlepiece.extension.fill")
 .font(.caption2)
 .foregroundStyle(.green)
 }
 if appState.availableAgents.count > 4 {
 Text("+\(appState.availableAgents.count - 4)")
 .font(.caption2)
 .foregroundStyle(.secondary)
 }
 }

 // Text input
 TextField("Message...", text: $inputText, axis: .vertical)
 .textFieldStyle(.plain)
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(
 RoundedRectangle(cornerRadius: 10)
 .fill(Color(nsColor: .textBackgroundColor))
 )
 .overlay(
 RoundedRectangle(cornerRadius: 10)
 .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
 )
 .font(.body)
 .lineLimit(1...6)
 .disabled(isProcessing)
 .onSubmit(sendMessage)
 .accessibilityLabel("Chat message input")
 .accessibilityHint("Type a message to send to the assistant")

 // Action buttons
 HStack(spacing: 4) {
 Button {
 sendMessage()
 } label: {
 Image(systemName: "arrow.up.circle.fill")
 .font(.title2)
 }
 .buttonStyle(.borderless)
 .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
 .accessibilityLabel("Send message")
 .keyboardShortcut(.return, modifiers: [])

 Button {
 appState.isDictating.toggle()
 } label: {
 Image(systemName: appState.isDictating ? "mic.fill" : "mic")
 .font(.title3)
 }
 .buttonStyle(.borderless)
 .tint(appState.isDictating ? .red : .secondary)
 .accessibilityLabel(appState.isDictating ? "Stop dictation" : "Start dictation")
 }
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(Color(nsColor: .controlBackgroundColor))
 }

 func sendMessage() {
 let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
 guard !trimmed.isEmpty, !isProcessing else { return }

 if appState.currentSession == nil {
 Task {
 await appState.createNewChat()
 }
 }

 Task {
 isProcessing = true
 appState.statusMessage = "Processing..."

 await appState.appendMessage(role: "user", content: trimmed)
 inputText = ""
 }
 }
}

// MARK: - Message Row

private struct MessageRow: View {
 let message: ChatMessageRecord

 var body: some View {
 VStack(alignment: .leading, spacing: 4) {
 // Role + timestamp
 HStack(spacing: 6) {
 Image(systemName: roleSystemImage)
 .font(.caption)
 .foregroundStyle(roleColor)

 Text(roleLabel)
 .font(.caption.bold())
 .foregroundStyle(.secondary)

 if message.role == "tool", let toolCallId = message.toolCallId, !toolCallId.isEmpty {
 Label("Tool result", systemImage: "wrench.fill")
 .font(.caption2)
 .foregroundStyle(.blue)
 }

 Spacer()

 if let date = ISO8601DateFormatter().date(from: message.createdAt) {
 let formatter = RelativeDateTimeFormatter()
 formatter.dateTimeStyle = .time
 Text(formatter.localizedString(for: date, relativeTo: Date()))
 .font(.caption2)
 .foregroundStyle(.tertiary)
 }
 }
 .padding(.horizontal, 4)

 // Content
 Group {
 if message.role == "tool" {
 ToolResultView(content: message.content)
 } else if message.role == "assistant" {
 MarkdownText(text: message.content)
 } else {
 Text(message.content)
 }
 }
 .textSelection(.enabled)
 .frame(maxWidth: .infinity, alignment: .leading)
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(
 RoundedRectangle(cornerRadius: 12)
 .fill(message.role == "user" ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
 )
 .accessibilityElement(children: .combine)
 .accessibilityLabel("\(roleLabel) message")
 }

 private var roleSystemImage: String {
 switch message.role {
 case "user": return "person.fill"
 case "assistant": return "brain.head.profile"
 case "system": return "gearshape.fill"
 case "tool": return "wrench.fill"
 default: return "text.bubble"
 }
 }

 private var roleColor: Color {
 switch message.role {
 case "user": return .blue
 case "assistant": return .green
 case "system": return .orange
 case "tool": return .purple
 default: return .secondary
 }
 }

 private var roleLabel: String {
 switch message.role {
 case "user": return "You"
 case "assistant": return "Assistant"
 case "system": return "System"
 case "tool": return "Tool Result"
 default: return message.role.capitalized
 }
 }
}

// MARK: - Tool Result View

private struct ToolResultView: View {
 let content: String

 var body: some View {
 VStack(alignment: .leading, spacing: 4) {
 Label("Tool Output", systemImage: "chevron.right")
 .font(.caption.bold())
 .foregroundStyle(.purple)

 MarkdownText(text: content)
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 }
}

// MARK: - Markdown Text

private struct MarkdownText: View {
 let text: String
 @State private var attributed: NSAttributedString?

 init(text: String) {
 self.text = text
 _attributed = State(initialValue: Self.render(text))
 }

 var body: some View {
 Group {
 if let attr = attributed, attr.length > 0 {
 Text(attr)
 } else {
 Text(text)
 }
 }
 .onAppear {
 if attributed == nil || attributed?.length == 0 {
 attributed = Self.render(text)
 }
 }
 }

 private static func render(_ markdown: String) -> NSAttributedString {
 let result = NSMutableAttributedString()
 let paragraphs = markdown.components(separatedBy: "\n\n")

 for (index, paragraph) in paragraphs.enumerated() {
 let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
 if trimmed.isEmpty { continue }

 if trimmed.hasPrefix("```") {
 let codeContent = trimmed
 .dropFirst(3)
 .replacingOccurrences(of: "```", with: "")
 .trimmingCharacters(in: .whitespacesAndNewlines)

 let codeAttr = NSAttributedString(
 string: codeContent,
 attributes: [
 .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
 .foregroundColor: NSColor.labelColor,
 .backgroundColor: NSColor.controlBackgroundColor
 ]
 )

 if index > 0 { result.append(NSAttributedString(string: "\n")) }
 result.append(codeAttr)
 } else {
 let formatted = applyInline(to: trimmed)
 if index > 0 { result.append(NSAttributedString(string: "\n\n")) }
 result.append(formatted)
 }
 }

 return result
 }

 private static func applyInline(to text: String) -> NSAttributedString {
 let attributed = NSMutableAttributedString(string: text)

 // Bold **text**
 let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*", options: [])
 let boldMatches = boldRegex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
 for match in boldMatches.reversed() {
 let range = match.range(at: 1)
 if let swiftRange = Range(range, in: text) {
 let content = String(text[swiftRange])
 let styled = NSAttributedString(string: content, attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
 attributed.replaceCharacters(in: match.range, with: styled)
 }
 }

 // Inline code `text`
 let codeRegex = try? NSRegularExpression(pattern: "`([^`]+)`", options: [])
 let codeMatches = codeRegex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
 for match in codeMatches.reversed() {
 let range = match.range(at: 1)
 if let swiftRange = Range(range, in: text) {
 let content = String(text[swiftRange])
 let styled = NSAttributedString(
 string: content,
 attributes: [
 .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular),
 .backgroundColor: NSColor.controlBackgroundColor
 ]
 )
 attributed.replaceCharacters(in: match.range, with: styled)
 }
 }

 // Italic *text*
 let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)([^*]+)(?<!\\*)\\*(?!\\*)", options: [])
 let currentStr = attributed.string as NSString
 let italicMatches = italicRegex?.matches(in: currentStr as String, options: [], range: NSRange(location: 0, length: currentStr.length)) ?? []
 for match in italicMatches.reversed() {
 let range = match.range(at: 1)
 if let swiftRange = Range(range, in: attributed.string) {
 let content = String(attributed.string[swiftRange])
 let styled = NSAttributedString(string: content, attributes: [.font: NSFont.italicSystemFont(ofSize: NSFont.systemFontSize)])
 attributed.replaceCharacters(in: match.range, with: styled)
 }
 }

 return attributed
 }
}

// MARK: - Preview

#Preview {
 ChatView()
 .environment(AppState())
 .frame(width: 800, height: 600)
}
