import AppKit
import SwiftUI

/// Archived rows fly into the window's bottom-left corner with a genie effect.
///
/// The row is rendered once into a flat image, and that image is what flies: a small GPU
/// distortion over one layer for about half a second, with nothing left running afterwards.
@MainActor
@Observable
final class GenieAnimator {
    static let shared = GenieAnimator()
    nonisolated static let coordinateSpace = "droppy-code-window"
    nonisolated static let duration: Double = 0.58

    struct Flight: Identifiable {
        let id = UUID()
        let image: NSImage
        let frame: CGRect
    }

    private(set) var flights: [Flight] = []

    /// Flies a ghost of a row from `frame`. The ghost is drawn once from `ghost`, on an opaque row fill.
    func launch<Ghost: View>(frame: CGRect, colorScheme: ColorScheme, @ViewBuilder ghost: () -> Ghost) {
        guard frame.width > 1, frame.height > 1,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let renderer = ImageRenderer(content: GenieGhost(size: frame.size, content: ghost())
            .environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        flights.append(Flight(image: image, frame: frame))
    }

    func finish(_ id: UUID) {
        flights.removeAll { $0.id == id }
    }
}

/// The flat stand-in a row becomes for its flight. Its fill is opaque, so rows sliding up underneath
/// are hidden by it instead of mixing with its text.
private struct GenieGhost<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGSize
    let content: Content

    var body: some View {
        content
            .frame(width: size.width, height: size.height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Chrome.rowCornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(white: 0.21) : Color(white: 0.9))
            )
    }
}

/// The window-wide layer the flights draw in. It never takes clicks.
struct GenieLayer: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(GenieAnimator.shared.flights) { flight in
                    GenieFlightView(flight: flight, canvas: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GenieFlightView: View {
    let flight: GenieAnimator.Flight
    let canvas: CGSize

    @State private var hasStarted = false

    var body: some View {
        let target = CGPoint(x: 24, y: canvas.height - 12)
        let frame = flight.frame
        Image(nsImage: flight.image)
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .keyframeAnimator(initialValue: 0.0, trigger: hasStarted) { content, progress in
                content
                    .distortionEffect(
                        ShaderLibrary.genie(
                            .float(progress),
                            .float4(frame.minX, frame.minY, frame.width, frame.height),
                            .float2(target.x, target.y)
                        ),
                        maxSampleOffset: canvas
                    )
                    .opacity(progress > 0.9 ? max(0, (1 - progress) / 0.1) : 1)
            } keyframes: { _ in
                CubicKeyframe(1.0, duration: GenieAnimator.duration)
            }
            .onAppear { hasStarted = true }
            .task {
                // Removed just before the keyframes finish, so the flight never springs back.
                try? await Task.sleep(for: .seconds(GenieAnimator.duration - 0.03))
                GenieAnimator.shared.finish(flight.id)
            }
    }
}
