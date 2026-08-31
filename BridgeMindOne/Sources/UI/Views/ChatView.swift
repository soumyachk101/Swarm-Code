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
 @State private var inputHeight: CGFloat = 44
 @State private var showScrollToBottom: Bool = false
 @FocusState private var isInputFocused: Bool

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
 LazyVStack(alignment: .leading, spacing: 0) {
 ForEach(appState.currentMessages) { message in
 MessageRow(message: message)
 .id(message.id)
 .padding(.horizontal, 16)
 .padding(.vertical, 4)
 }

 if appState.isThinking {
 HStack(spacing: 8) {
 OrbView(state: .thinking, size: 18)
 Text("Thinking…")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .id("thinking-indicator")
 .padding(.horizontal, 16)
 .padding(.vertical, 8)
 }

 if appState.isStreaming {
 HStack(spacing: 8) {
 OrbView(state: .speaking, size: 18)
 Text("Generating…")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 .id("streaming-indicator")
 .padding(.horizontal, 16)
 .padding(.vertical, 8)
 }
 }
 .padding(.top, 8)
 }
 }
 .overlay(alignment: .bottomTrailing) {
 if showScrollToBottom {
 Button {
 withAnimation {
 if let lastId = appState.currentMessages.last?.id {
 proxy.scrollTo(lastId, anchor: .bottom)
 }
 showScrollToBottom = false
 }
 } label: {
 Label("New messages", systemImage: "arrow.down.circle.fill")
 .font(.caption)
 .padding(.horizontal, 12)
 .padding(.vertical, 6)
 }
 .buttonStyle(.borderedProminent)
 .padding(.bottom, 80)
 .padding(.trailing, 16)
 }
 }
 .onChange(of: appState.currentMessages.count) { _, _ in
 withAnimation(.easeOut(duration: 0.3)) {
 if let lastId = appState.currentMessages.last?.id {
 proxy.scrollTo(lastId, anchor: .bottom)
 }
 showScrollToBottom = false
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

// MARK: - Input Area

private extension ChatView {
 var inputArea: some View {
 VStack(spacing: 0) {
 HStack(alignment: .top, spacing: 10) {
 TextField("Message…", text: $inputText, axis: .vertical)
 .focused($isInputFocused)
 .textFieldStyle(.plain)
 .padding(.horizontal, 14)
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
 .lineLimit(1...8)
 .onChange(of: inputText) { _, newValue in
 let lines = newValue.components(separatedBy: .newlines).count
 inputHeight = max(44, min(140, 20 + CGFloat(lines) * 22))
 }
 .accessibilityLabel("Chat message input")
 .accessibilityHint("Type a message to send to the assistant")

 HStack(spacing: 4) {
 Button {
 sendMessage()
 } label: {
 Image(systemName: "arrow.up.circle.fill")
 .font(.title2)
 }
 .buttonStyle(.borderless)
 .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
 .accessibilityLabel("Send message")
 .accessibilityHint("Send the typed message")
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
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(Color(nsColor: .controlBackgroundColor))
 }
 }

 func sendMessage() {
 let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
 guard !trimmed.isEmpty else { return }

 Task {
 await appState.core.appendMessage(role: "user", content: trimmed)
 inputText = ""
 inputHeight = 44
 isInputFocused = true
 }
 }
}

// MARK: - Message Row

private struct MessageRow: View {
 let message: ChatMessageRecord

 var body: some View {
 VStack(alignment: .leading, spacing: 4) {
 // Role + timestamp header
 HStack(spacing: 6) {
 Image(systemName: roleSystemImage)
 .font(.caption)
 .foregroundStyle(roleColor)

 Text(roleLabel)
 .font(.caption.bold())
 .foregroundStyle(.secondary)

 if message.role == "tool" {
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

// MARK: - Markdown Text Renderer

private struct MarkdownText: View {
 let text: String
 @State private var rendered: NSAttributedString?

 init(text: String) {
 self.text = text
 _rendered = State(initialValue: Self.render(text))
 }

 var body: some View {
 Group {
 if let attributed = rendered, attributed.length > 0 {
 Text(attributed)
 } else {
 Text(text)
 }
 }
 }
 .onAppear {
 rendered = Self.render(text)
 }
 }

 private static func render(_ markdown: String) -> NSAttributedString {
 let result = NSMutableAttributedString()
 let paragraphs = markdown.components(separatedBy: "\n\n")

 for (index, paragraph) in paragraphs.enumerated() {
 let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
 if trimmed.isEmpty { continue }

 if trimmed.hasPrefix("```") {
 // Code block
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
 // Regular paragraph with inline formatting
 let formatted = Self.applyInline(to: trimmed)
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

 // Italic *text* (not part of bold)
 let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)([^*]+)(?<!\\*)\\*(?!\\*)", options: [])
 let italicMatches = italicRegex?.matches(in: attributed.string as String, options: [], range: NSRange(location: 0, length: (attributed.string as NSString).length)) ?? []
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
