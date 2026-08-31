//
// ThreadRowView.swift
// Individual thread row in sidebar
//

import SwiftUI

public struct ThreadRowView: View {
 let session: ChatSession

 public var body: some View {
 HStack(spacing: 8) {
 // Agent indicator
 if let agentId = session.agentId {
 Image(systemName: "person.circle.fill")
 .font(.caption)
 .foregroundStyle(.accent)
 }

 VStack(alignment: .leading, spacing: 2) {
 Text(session.title ?? "Untitled")
 .font(.system(size: 13, weight: .medium))
 .lineLimit(1)
 .foregroundStyle(.primary)

 Text(timeAgo(session.updatedAt))
 .font(.caption2)
 .foregroundStyle(.tertiary)
 }

 Spacer()
 }
 .padding(.horizontal, 8)
 .padding(.vertical, 4)
 .contentShape(Rectangle())
 }

 private func timeAgo(_ date: Date) -> String {
 let formatter = RelativeDateTimeFormatter()
 formatter.unitsStyle = .abbreviated
 return formatter.localizedString(for: date, relativeTo: Date())
 }
}
