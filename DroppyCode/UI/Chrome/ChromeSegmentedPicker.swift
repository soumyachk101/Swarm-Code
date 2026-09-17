import SwiftUI

// A row control that shows every option as a small button in one glass capsule strip,
// the chosen one filled. For rows whose options are a few short words or numbers and
// need no picture.

/// The row control: one small button per option, the chosen one filled.
struct ChromeSegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    init(options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                ChromeSegment(title: option.title, isSelected: option.value == selection) {
                    withAnimation(Chrome.hover) { selection = option.value }
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(height: Chrome.capsuleContentHeight)
        .chromeGlassCapsule()
        .fixedSize()
        .accessibilityElement(children: .contain)
        .background { NoWindowDragArea() }
    }
}

/// One segment: a small capsule button, filled while chosen.
private struct ChromeSegment: View {
    let title: String
    let isSelected: Bool
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Chrome.primaryText : Chrome.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(minWidth: 26)
                .frame(height: 22)
                .background(Capsule(style: .continuous).fill(isSelected ? Chrome.accent.opacity(0.22) : Chrome.overlay(isHovering ? 0.08 : 0)))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(Text(verbatim: title))
    }
}
