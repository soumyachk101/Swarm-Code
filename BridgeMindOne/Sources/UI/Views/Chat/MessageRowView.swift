//
// MessageRowView.swift
// Individual message bubble
//

import SwiftUI

public struct MessageRowView: View {
 let message: ChatMessage

 public var body: some View {
 HStack(alignment: .top, spacing: 8) {
 // Avatar
 avatarView
 .frame(width: 28, height: 28)

 // Content
 VStack(alignment: .leading, spacing: 4) {
 if message.role != .user {
 Text(roleLabel)
 .font(.caption2)
 .foregroundStyle(.secondary)
 }

 Text(displayContent)
 .font(.system(size: 14))
 .textSelection(.enabled)
 .frame(maxWidth: .infinity, alignment: .leading)
 }
 }
 .padding(.horizontal, 12)
 .padding(.vertical, 8)
 .background(messageBackground)
 .clipShape(RoundedRectangle(cornerRadius: 12))
 .padding(.horizontal, 16)
 .padding(.vertical, 2)
 }

 private var avatarView: some View {
 Group {
 switch message.role {
 case .user:
 Image(systemName: "person.circle.fill")
 .foregroundStyle(.blue)
 case .assistant:
 Image(systemName: "brain.head.profile")
 .foregroundStyle(.green)
 case .tool:
 Image(systemName: "wrench.and.screwdriver.fill")
 .foregroundStyle(.orange)
 case .system:
 Image(systemName: "gear")
 .foregroundStyle(.gray)
 }
 }
 }

 private var roleLabel: String {
 switch message.role {
 case .user: return "You"
 case .assistant: return appState?.activeAgent?.name ?? "Assistant"
 case .tool: return "Tool"
 case .system: return "System"
 }
 }

 private var messageBackground: some ShapeStyle {
 switch message.role {
 case .user: return AnyShapeStyle(.blue.opacity(0.1))
 case .assistant: return AnyShapeStyle(.green.opacity(0.1))
 case .tool: return AnyShapeStyle(.orange.opacity(0.1))
 case .system: return AnyShapeStyle(.gray.opacity(0.1))
 }
 }

 private var displayContent: AttributedString {
 // Simple markdown-ish rendering
 var result = message.content

 // Replace code blocks with styled text
 if result.contains("```") {
 // In production, use a proper Markdown renderer
 }

 return AttributedString(result)
 }
}
