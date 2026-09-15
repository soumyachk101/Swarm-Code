import AppKit
import SwiftUI

/// The sizes the conversation reads at, smallest to largest. The chrome row's zoom slider
/// steps through them and the setting keeps the index.
enum ChatZoom {
    /// What each step reads as against the default, in percent. macOS has no Dynamic Type,
    /// so the conversation scales its own fonts by this, through the `chatZoom` environment
    /// value and `Font.chat`.
    private static let percentages = [80, 90, 95, 100, 110, 125, 135]
    static var stepCount: Int { percentages.count }
    /// The 100% step: a fresh install reads exactly as it did before the slider.
    static let defaultIndex = 3

    /// The index brought into range, for a stored value from another build.
    static func clamped(_ index: Int) -> Int {
        min(stepCount - 1, max(0, index))
    }

    static func percentage(at index: Int) -> Int {
        percentages[clamped(index)]
    }

    /// The factor the conversation's type is drawn at for a step: 1 at the default step.
    static func scale(at index: Int) -> CGFloat {
        CGFloat(percentage(at: index)) / 100
    }
}

private struct ChatZoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// The factor the conversation's text is drawn at, from the chrome row's zoom slider.
    /// Views outside the conversation never see it and keep their size.
    var chatZoom: CGFloat {
        get { self[ChatZoomKey.self] }
        set { self[ChatZoomKey.self] = newValue }
    }
}

extension Font {
    /// The point size macOS lays a text style out at, for `chat`.
    static func chatBaseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }

    /// A text style at the conversation's zoom: the plain style at zoom 1, so the default
    /// reads exactly as before, and the same size scaled otherwise. `headline` keeps its
    /// semibold weight unless another is asked for.
    static func chat(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default, zoom: CGFloat) -> Font {
        let resolvedWeight = weight ?? (style == .headline ? .semibold : nil)
        if zoom == 1 {
            let font = Font.system(style, design: design)
            return resolvedWeight.map { font.weight($0) } ?? font
        }
        let size = (chatBaseSize(style) * zoom).rounded()
        return Font.system(size: size, weight: resolvedWeight ?? .regular, design: design)
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
            let step = (width - inset * 2) / CGFloat(ChatZoom.stepCount - 1)
            let restingX = inset + CGFloat(ChatZoom.clamped(index)) * step
            let x = min(max(dragX ?? restingX, inset), width - inset)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Chrome.overlay(0.1))
                    .frame(width: width, height: Self.trackHeight)
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
            .frame(width: width, height: proxy.size.height, alignment: .leading)
            .contentShape(.rect)
            // The catcher sits behind the track and owns its presses and drags in AppKit:
            // the chrome row lives under the window's extended title bar, which moves the
            // window for any view that lets it, and a SwiftUI gesture alone does not stop
            // it. Handling mouse down here captures the drag exclusively for zoom.
            .background {
                ChatZoomTrackCatcher(
                    onPress: { press(at: $0, inset: inset, step: step) },
                    onDrag: { move(to: $0, inset: inset, step: step) },
                    onEnd: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { dragX = nil }
                    }
                )
                .frame(width: width, height: proxy.size.height)
            }
        }
    }

    private func press(at x: CGFloat, inset: CGFloat, step: CGFloat) {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { dragX = x }
        snap(to: x, inset: inset, step: step)
    }

    private func move(to x: CGFloat, inset: CGFloat, step: CGFloat) {
        dragX = x
        snap(to: x, inset: inset, step: step)
    }

    private func snap(to x: CGFloat, inset: CGFloat, step: CGFloat) {
        let nearest = nearestStep(to: x, inset: inset, step: step)
        if nearest != index {
            index = nearest
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func nearestStep(to x: CGFloat, inset: CGFloat, step: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        return ChatZoom.clamped(Int(((x - inset) / step).rounded()))
    }
}

/// Catches the zoom track's mouse in AppKit so a thumb drag zooms and nothing
/// else: `mouseDownCanMoveWindow` refuses the extended title bar's window drag,
/// and the mouse-down view keeps receiving the drag exclusively until release.
private struct ChatZoomTrackCatcher: NSViewRepresentable {
    var onPress: (CGFloat) -> Void
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> ChatZoomTrackCatcherView {
        let view = ChatZoomTrackCatcherView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ChatZoomTrackCatcherView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ChatZoomTrackCatcherView) {
        view.onPress = onPress
        view.onDrag = onDrag
        view.onEnd = onEnd
    }
}

private final class ChatZoomTrackCatcherView: NSView {
    var onPress: ((CGFloat) -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    /// A press on the track zooms the conversation; the window stays put.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onPress?(x(of: event))
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(x(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }

    private func x(of event: NSEvent) -> CGFloat {
        convert(event.locationInWindow, from: nil).x
    }
}
