import AppKit
import SwiftUI

/// The sizes the conversation reads at, smallest to largest. The chrome row's zoom slider
/// steps through them and the setting keeps the index.
enum ChatZoom {
    static let steps: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    /// The 1.0 step: `.large` is the size SwiftUI lays text styles out at when nothing asks
    /// for another, so a fresh install reads exactly as it did before the slider.
    static let defaultIndex = 3
    /// What each step reads as against the 1.0 step, for VoiceOver.
    private static let percentages = [80, 90, 95, 100, 110, 125, 135]

    /// The index brought into range, for a stored value from another build.
    static func clamped(_ index: Int) -> Int {
        min(steps.count - 1, max(0, index))
    }

    static func size(at index: Int) -> DynamicTypeSize {
        steps[clamped(index)]
    }

    static func percentage(at index: Int) -> Int {
        percentages[clamped(index)]
    }
}

/// A compact glass slider for the chrome row that zooms the conversation: a type-size mark
/// and a short track whose knob snaps to each zoom step. A drag follows the pointer; a click
/// on the track jumps to the nearest step.
struct ChatZoomSlider: View {
    @Binding var index: Int

    static let trackWidth: CGFloat = 72
    static let trackHeight: CGFloat = 4
    static let knobSize: CGFloat = 14

    /// The knob's centre while the pointer holds it, so it follows the pointer between the
    /// steps and settles on one when let go.
    @State private var dragX: CGFloat?

    var body: some View {
        ChromeCapsule {
            Image(systemName: "textformat.size")
                .font(Chrome.iconFont)
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: Chrome.capsuleContentHeight, height: Chrome.capsuleContentHeight)
            track
                .frame(width: Self.trackWidth, height: Chrome.capsuleContentHeight)
                // Room for the knob at the far end to sit clear of the capsule's curve.
                .padding(.trailing, 8)
        }
        .help("Zoom the conversation")
        .accessibilityElement()
        .accessibilityLabel(Text("Conversation zoom"))
        .accessibilityValue(Text(verbatim: "\(ChatZoom.percentage(at: index))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = ChatZoom.clamped(index + 1)
            case .decrement: index = ChatZoom.clamped(index - 1)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let inset = Self.knobSize / 2
            let step = (width - inset * 2) / CGFloat(ChatZoom.steps.count - 1)
            let restingX = inset + CGFloat(ChatZoom.clamped(index)) * step
            let x = min(max(dragX ?? restingX, inset), width - inset)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Chrome.overlay(0.1))
                    .frame(height: Self.trackHeight)
                Capsule(style: .continuous)
                    .fill(Chrome.primaryText.opacity(0.35))
                    .frame(width: x + inset, height: Self.trackHeight)
                // The knob is a Liquid Glass lens over the track, as the effort slider's is.
                // It gets a glass group of its own: in the row's shared pass a lens inside the
                // capsule would be folded into the capsule's shape and vanish.
                GlassEffectContainer {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .frame(width: Self.knobSize, height: Self.knobSize)
                .scaleEffect(dragX == nil ? 1 : 1.12)
                .position(x: x, y: proxy.size.height / 2)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragX == nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { dragX = value.location.x }
                        } else {
                            dragX = value.location.x
                        }
                        let nearest = nearestStep(to: value.location.x, inset: inset, step: step)
                        if nearest != index {
                            index = nearest
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { dragX = nil }
                    }
            )
        }
    }

    private func nearestStep(to x: CGFloat, inset: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        return ChatZoom.clamped(Int(((x - inset) / step).rounded()))
    }
}
