import SwiftUI

/// The thread's changes as a small tab rising from the top of the chat box. The composer draws
/// over its lower edge, so it reads as part of the box. Clicking it opens the changes panel.
struct ThreadChangesTab: View {
    static let overlap: CGFloat = 14

    let stats: ThreadRuntime.ChangeStats
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plusminus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Chrome.secondaryText)
                Text(verbatim: stats.files == 1 ? "1 file" : "\(stats.files) files")
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                Text(verbatim: "+\(stats.additions)")
                    .foregroundStyle(Color(red: 0.36, green: 0.84, blue: 0.5))
                Text(verbatim: "\u{2212}\(stats.deletions)")
                    .foregroundStyle(Color(red: 0.95, green: 0.42, blue: 0.42))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.top, 7)
            .padding(.bottom, 7 + Self.overlap)
            .background {
                // Scoped to the fill: clicking the tab opens the diff panel and slides the tab out
                // from under the cursor, and a withAnimation on that hover exit would replace the
                // panel-slide transaction, so the tab popped left instead of gliding.
                shape.fill(Chrome.overlay(isHovering ? 0.1 : 0.07))
                    .animation(Chrome.hover, value: isHovering)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            if hovering != isHovering { isHovering = hovering }
        }
        .help("Show this thread's changes")
        .accessibilityLabel(Text(verbatim: "\(stats.files) files changed, \(stats.additions) added, \(stats.deletions) removed"))
    }
}
