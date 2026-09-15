import SwiftUI

/// A pill like the Hydra badges in the conversation: a glyph, a title, an
/// optional caption and a chevron, opening its detail in a popover.
/// `needsAttention` means the reader has to do something here: the accent dot
/// wave runs along the badge's top quarter, in the theme's accent, until it is
/// dealt with.
struct ChatBadge<Glyph: View, Detail: View>: View {
    let title: String
    var caption: String? = nil
    var showsChevron = true
    var needsAttention = false
    var isEnabled = true
    @Binding var isPresented: Bool
    @ViewBuilder let glyph: () -> Glyph
    @ViewBuilder let detail: () -> Detail

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatZoom) private var zoom

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                glyph()
                    .frame(width: 18, height: 18)
                Text(verbatim: title)
                    .font(.chat(.callout, weight: .medium, zoom: zoom))
                    .foregroundStyle(Chrome.primaryText.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let caption {
                    Text(verbatim: caption)
                        .font(.chat(.caption, zoom: zoom))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.chat(.caption2, weight: .semibold, zoom: zoom))
                        .foregroundStyle(.tertiary)
                }
            }
            // The whole pill takes the click, padding included, as the Hydra pills do.
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .overlay(alignment: .top) {
            if needsAttention {
                GeometryReader { proxy in
                    DotFieldLayerView.Representable(color: Chrome.accentNSColor, animated: !reduceMotion)
                        .scaleEffect(y: -1)
                        .frame(height: proxy.size.height * 0.25)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            detail().presentedChrome()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 96)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(needsAttention ? "Needs your attention" : ""))
    }
}
