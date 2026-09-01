//
// ThreadRowView.swift
// Individual thread row in sidebar
//

import SwiftUI
import Core

public struct ThreadRowView: View {
    let session: ChatSession

    public init(session: ChatSession) {
        self.session = session
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.circle.fill")
                .font(.caption)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Untitled" : session.title)
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
