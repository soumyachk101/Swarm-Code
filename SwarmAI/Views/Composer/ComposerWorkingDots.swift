import AppKit
import QuartzCore
import SwiftUI

/// The composer's working animation: a field of accent-tinted dots along the pill's
/// bottom, pulsing in a wave that flows left to right and fades out upward.
///
/// One dot layer carries one repeating opacity keyframe; two replicator layers stamp it
/// across the columns and rows with a per-instance delay, which is what makes the wave
/// travel. Once on screen the render server plays it alone: no timer, no view update
/// and no drawing on the main thread, however long a turn runs.
struct ComposerWorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DotFieldLayerView.Representable(color: Chrome.accentNSColor, animated: !reduceMotion)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

final class DotFieldLayerView: NSView {
    struct Representable: NSViewRepresentable {
        let color: NSColor
        let animated: Bool

        func makeNSView(context: Context) -> DotFieldLayerView {
            let view = DotFieldLayerView()
            view.configure(color: color, animated: animated)
            return view
        }

        func updateNSView(_ view: DotFieldLayerView, context: Context) {
            view.configure(color: color, animated: animated)
        }
    }

    private let rows = CAReplicatorLayer()
    private let columns = CAReplicatorLayer()
    private let dot = CALayer()
    private var color: NSColor = .controlAccentColor
    private var animated = true
    private var laidOutSize: CGSize = .zero

    private static let dotSize: CGFloat = 2
    private static let pitch: CGFloat = 8
    /// The field never grows past this many rows however tall the pill gets, so a
    /// five-line draft does not multiply the layers the render server composites.
    private static let maxRows = 3
    /// One pulse per dot; the column delay spreads it into a travelling wave.
    private static let period: Double = 2.2
    private static let columnDelay: Double = 0.045
    private static let rowDelay: Double = 0.09
    private static let animationKey = "pulse"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        dot.actions = ["opacity": NSNull(), "bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
        dot.cornerRadius = Self.dotSize / 2
        dot.bounds = CGRect(x: 0, y: 0, width: Self.dotSize, height: Self.dotSize)
        for replicator in [columns, rows] {
            replicator.actions = ["bounds": NSNull(), "position": NSNull(), "instanceCount": NSNull(), "instanceTransform": NSNull()]
        }
        columns.addSublayer(dot)
        rows.addSublayer(columns)
        layer?.addSublayer(rows)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(color: NSColor, animated: Bool) {
        let colorChanged = color != self.color
        let motionChanged = animated != self.animated
        self.color = color
        self.animated = animated
        if colorChanged { dot.backgroundColor = color.cgColor }
        if motionChanged { installAnimation() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { installAnimation() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The system accent is dynamic; re-resolve it for the new appearance.
        dot.backgroundColor = color.cgColor
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size != laidOutSize, size.width > 0, size.height > 0 else { return }
        laidOutSize = size
        let columnCount = Int(ceil(size.width / Self.pitch)) + 1
        let rowCount = min(Self.maxRows, max(1, Int(ceil(size.height / Self.pitch))))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rows.frame = bounds
        columns.frame = CGRect(x: 0, y: 0, width: size.width, height: Self.pitch)
        // The base dot sits at the bottom-left; columns march right and rows stack upward,
        // each row a little fainter, so the field dissolves before it reaches the text.
        dot.position = CGPoint(x: Self.pitch / 2, y: Self.pitch / 2)
        columns.instanceCount = columnCount
        columns.instanceTransform = CATransform3DMakeTranslation(Self.pitch, 0, 0)
        columns.instanceDelay = Self.columnDelay
        rows.instanceCount = rowCount
        rows.instanceTransform = CATransform3DMakeTranslation(0, Self.pitch, 0)
        rows.instanceDelay = Self.rowDelay
        rows.instanceAlphaOffset = -Float(1) / Float(rowCount)
        CATransaction.commit()
    }

    private func installAnimation() {
        dot.removeAnimation(forKey: Self.animationKey)
        guard animated else {
            dot.opacity = 0.28
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [0.08, 0.75, 0.08]
        animation.keyTimes = [0, 0.35, 1]
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        animation.duration = Self.period
        animation.repeatCount = .infinity
        // The shared clock, so every pill's field runs in step with the spinners.
        animation.beginTime = dot.convertTime(1, from: nil)
        animation.isRemovedOnCompletion = false
        dot.add(animation, forKey: Self.animationKey)
    }
}
