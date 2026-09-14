import SwiftUI

/// A head's mark: its own dragon, in its colour. The same glyph stands for the head
/// everywhere it shows: the panel, the popover, the tool row that sent it out and the
/// report it hands back. The twenty-five heads are template images, so one colour tints
/// each whole.
struct HydraGlyph: View {
    let persona: HydraPersona
    var size: CGFloat = 20
    /// A soft ring breathes around a head still at work.
    var isRunning = false
    /// A finished head wears its outcome on the glyph's bottom-right corner: a green tick
    /// for done, red for failed, grey for stopped. Nil, or running, shows nothing.
    var status: HydraHeadInfo.Status?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if isRunning {
                Circle()
                    .stroke(persona.color.opacity(0.55), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .modifier(HydraBreath())
            }
            Image(persona.asset)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(persona.color)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let status, status.isFinished {
                badge(for: status)
            }
        }
        .accessibilityLabel(Text(status.map { "\(persona.name), \($0.rawValue)" } ?? persona.name))
    }

    /// The outcome as a small disc riding the corner, cut out from the glyph by a ring in
    /// the surface's colour, the way a presence badge sits on an avatar.
    private func badge(for status: HydraHeadInfo.Status) -> some View {
        let diameter = max(8, size * 0.5)
        let (symbol, color): (String, Color) = switch status {
        case .completed: ("checkmark", Chrome.success)
        case .failed: ("xmark", Chrome.danger)
        default: ("stop.fill", Chrome.secondaryText)
        }
        return ZStack {
            Circle()
                .fill(color)
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.55, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle().strokeBorder(colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.95), lineWidth: max(1, diameter * 0.12))
        }
        .offset(x: diameter * 0.3, y: diameter * 0.3)
        .transition(.scale.combined(with: .opacity))
    }
}

/// The ring around a working head: it swells and fades, over and over.
private struct HydraBreath: ViewModifier {
    @State private var swollen = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(swollen ? 1.5 : 1.05)
            .opacity(swollen ? 0 : 0.9)
            .onAppear {
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { swollen = true }
            }
    }
}

/// The Hydra mark: three heads on one body, a template that takes whatever colour it
/// is given. Sized by its frame.
struct HydraMarkImage: View {
    var body: some View {
        Image("hydra-mark")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
    }
}
