import SwiftUI

/// A head's mark: its shape in its colour, with its initial. The same glyph stands for the
/// head everywhere it shows: the panel, the popover, the tool row that sent it out and the
/// report it hands back.
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
                HydraShapeView(shape: persona.shape)
                    .stroke(persona.color.opacity(0.55), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .modifier(HydraBreath())
            }
            HydraShapeView(shape: persona.shape)
                .fill(persona.color)
                .frame(width: size, height: size)
            Text(verbatim: persona.initial)
                .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                // The triangle's centre of mass sits low; the letter follows it.
                .offset(y: persona.shape == .triangle ? size * 0.08 : 0)
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

/// The twelve shapes of the roster, each drawn to fill its rect with rounded corners.
struct HydraShapeView: Shape {
    let shape: HydraShape

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Circle().path(in: rect)
        case .square:
            return RoundedRectangle(cornerRadius: rect.width * 0.24, style: .continuous).path(in: rect)
        case .squircle:
            return RoundedRectangle(cornerRadius: rect.width * 0.42, style: .continuous).path(in: rect)
        case .capsule:
            let inset = rect.insetBy(dx: 0, dy: rect.height * 0.14)
            return Capsule(style: .continuous).path(in: inset)
        case .triangle:
            return Self.roundedPolygon(sides: 3, in: rect, rotation: -.pi / 2, radius: rect.width * 0.12)
        case .diamond:
            return Self.roundedPolygon(sides: 4, in: rect, rotation: -.pi / 2, radius: rect.width * 0.1)
        case .pentagon:
            return Self.roundedPolygon(sides: 5, in: rect, rotation: -.pi / 2, radius: rect.width * 0.09)
        case .hexagon:
            return Self.roundedPolygon(sides: 6, in: rect, rotation: 0, radius: rect.width * 0.08)
        case .octagon:
            return Self.roundedPolygon(sides: 8, in: rect, rotation: .pi / 8, radius: rect.width * 0.06)
        case .star:
            return Self.roundedStar(in: rect)
        case .shield:
            return Self.shield(in: rect)
        case .drop:
            return Self.drop(in: rect)
        }
    }

    /// A regular polygon with its corners rounded off.
    private static func roundedPolygon(sides: Int, in rect: CGRect, rotation: CGFloat, radius: CGFloat) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Inscribed so the widest span fills the rect; a triangle sits a touch lower.
        let outer = min(rect.width, rect.height) / 2
        let points = (0..<sides).map { index -> CGPoint in
            let angle = rotation + CGFloat(index) * 2 * .pi / CGFloat(sides)
            let offset = sides == 3 ? outer * 0.12 : 0
            return CGPoint(x: center.x + outer * cos(angle), y: center.y + offset + outer * sin(angle))
        }
        return roundedPath(points, radius: radius)
    }

    private static func roundedStar(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.52
        var points: [CGPoint] = []
        for index in 0..<10 {
            let angle = -.pi / 2 + CGFloat(index) * .pi / 5
            let radius = index.isMultiple(of: 2) ? outer : inner
            points.append(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        return roundedPath(points, radius: outer * 0.1)
    }

    private static func shield(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY * 0.92))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: CGPoint(x: rect.minX, y: rect.maxY * 0.92))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }

    private static func drop(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width * 0.38
        let center = CGPoint(x: rect.midX, y: rect.maxY - radius)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius * 0.9, y: center.y - radius * 1.1))
        path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.04), control: CGPoint(x: center.x - radius * 0.9, y: center.y - radius * 1.1))
        path.closeSubpath()
        return path
    }

    /// Joins points with arcs cut into each corner, so the shape reads as soft at any size.
    private static func roundedPath(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        let count = points.count
        guard count > 2 else { return path }
        for index in 0..<count {
            let previous = points[(index + count - 1) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let toPrevious = CGVector(dx: previous.x - current.x, dy: previous.y - current.y)
            let toNext = CGVector(dx: next.x - current.x, dy: next.y - current.y)
            let lengthPrevious = max(hypot(toPrevious.dx, toPrevious.dy), 0.001)
            let lengthNext = max(hypot(toNext.dx, toNext.dy), 0.001)
            let cut = min(radius, lengthPrevious / 2, lengthNext / 2)
            let start = CGPoint(x: current.x + toPrevious.dx / lengthPrevious * cut, y: current.y + toPrevious.dy / lengthPrevious * cut)
            let end = CGPoint(x: current.x + toNext.dx / lengthNext * cut, y: current.y + toNext.dy / lengthNext * cut)
            if index == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: current)
        }
        path.closeSubpath()
        return path
    }
}

/// Hydra's own mark: a lead with three heads around it. The chrome button and the settings
/// row wear it; on, the button's ring runs the roster's colours around it.
struct HydraMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let orbit = min(rect.width, rect.height) * 0.36
        let core = min(rect.width, rect.height) * 0.14
        let head = min(rect.width, rect.height) * 0.11
        path.addEllipse(in: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2))
        for index in 0..<3 {
            let angle = -.pi / 2 + CGFloat(index) * 2 * .pi / 3
            let point = CGPoint(x: center.x + orbit * cos(angle), y: center.y + orbit * sin(angle))
            path.addEllipse(in: CGRect(x: point.x - head, y: point.y - head, width: head * 2, height: head * 2))
        }
        return path
    }
}

/// The spokes of the mark, from the lead to each head, drawn as a stroke.
struct HydraSpokes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let orbit = min(rect.width, rect.height) * 0.36
        let core = min(rect.width, rect.height) * 0.14
        let head = min(rect.width, rect.height) * 0.11
        for index in 0..<3 {
            let angle = -.pi / 2 + CGFloat(index) * 2 * .pi / 3
            path.move(to: CGPoint(x: center.x + (core + 1) * cos(angle), y: center.y + (core + 1) * sin(angle)))
            path.addLine(to: CGPoint(x: center.x + (orbit - head - 1) * cos(angle), y: center.y + (orbit - head - 1) * sin(angle)))
        }
        return path
    }
}
