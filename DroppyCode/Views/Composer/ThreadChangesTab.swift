import AppKit
import SwiftUI

/// The thread's changes as a small tab rising from the top of the chat box. The composer draws
/// over its lower edge, so it reads as part of the box. Clicking it opens the changes popover.
struct ThreadChangesTab: View {
    static let overlap: CGFloat = 14

    let stats: ThreadRuntime.ChangeStats
    /// Receives the tab's own view, so the popover can anchor to it.
    let anchor: (NSView) -> Void
    let action: () -> Void

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
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: shape)
        .background {
            AttachmentAnchorCapture(onResolve: anchor)
        }
        .fixedSize()
        .help("Show this thread's changes")
        .accessibilityLabel(Text(verbatim: "\(stats.files) files changed, \(stats.additions) added, \(stats.deletions) removed"))
    }
}
