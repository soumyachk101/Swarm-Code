import SwiftUI

/// A row control of two or three tiles, each a zoomed-in mock of what the option
/// does with a short caption under it, the way macOS Appearance offers
/// Light / Dark / Auto; the chosen tile wears an accent ring.

enum ChromeVisualTileMetrics {
    static let height: CGFloat = 48
    static let regularWidth: CGFloat = 100
    static let denseWidth: CGFloat = 72
    static let cornerRadius: CGFloat = 6
    static let ringInset: CGFloat = 3
    static let ringWidth: CGFloat = 2
    static let spacing: CGFloat = 12
    static let captionGap: CGFloat = 5
}

struct ChromeVisualPicker<Value: Hashable, Preview: View>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @ViewBuilder var preview: (Value) -> Preview

    init(options: [(value: Value, title: String)], selection: Binding<Value>, @ViewBuilder preview: @escaping (Value) -> Preview) {
        self.options = options
        self._selection = selection
        self.preview = preview
    }

    private var tileWidth: CGFloat {
        options.count >= 3 ? ChromeVisualTileMetrics.denseWidth : ChromeVisualTileMetrics.regularWidth
    }

    var body: some View {
        HStack(alignment: .top, spacing: ChromeVisualTileMetrics.spacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                ChromeVisualTile(title: option.title, isSelected: option.value == selection, width: tileWidth) {
                    withAnimation(Chrome.hover) { selection = option.value }
                } content: {
                    preview(option.value)
                }
            }
        }
        .fixedSize()
        .background { NoWindowDragArea() }
    }
}

struct ChromeVisualTile<Content: View>: View {
    let title: String
    let isSelected: Bool
    var width: CGFloat = ChromeVisualTileMetrics.regularWidth
    let action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: ChromeVisualTileMetrics.captionGap) {
                stage
                caption
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var stage: some View {
        content()
            .frame(width: width, height: ChromeVisualTileMetrics.height)
            .background(
                RoundedRectangle(cornerRadius: ChromeVisualTileMetrics.cornerRadius, style: .continuous)
                    .fill(Chrome.overlay(isHovering ? 0.10 : 0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: ChromeVisualTileMetrics.cornerRadius, style: .continuous))
            .padding(ChromeVisualTileMetrics.ringInset)
            .overlay(
                RoundedRectangle(
                    cornerRadius: ChromeVisualTileMetrics.cornerRadius + ChromeVisualTileMetrics.ringInset,
                    style: .continuous
                )
                .strokeBorder(isSelected ? Chrome.accent : Color.clear, lineWidth: ChromeVisualTileMetrics.ringWidth)
            )
            .contentShape(Rectangle())
    }

    private var caption: some View {
        Text(verbatim: title)
            .font(.system(size: 11, weight: isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? Chrome.primaryText : Chrome.secondaryText)
            .lineLimit(1)
            .frame(width: width + ChromeVisualTileMetrics.ringInset * 2)
    }
}
