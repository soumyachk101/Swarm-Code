import AppKit
import SwiftUI

/// The chat's Hydra switch, first in the chrome row. Off, it is a quiet mark of a lead with
/// three heads. On, it charges up: the heads take the roster's colours, a ring of those
/// colours runs around the button and a soft glow breathes behind it, so the chat reads as
/// a team at work. A badge counts the heads out right now.
struct HydraButton: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    @State private var isHovering = false

    var body: some View {
        let isOn = thread.hydraEnabled
        let running = model.hydraHeads(of: thread.id).count { $0.hydra?.status == .running }
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                model.setHydra(!isOn, for: thread.id)
            }
        } label: {
            ZStack {
                if isOn {
                    HydraCharge()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                HydraMarkView(isOn: isOn, isHovering: isHovering)
            }
            .frame(width: Chrome.capsuleHeight, height: Chrome.capsuleHeight)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .chromeGlassCircle()
        .overlay(alignment: .topTrailing) {
            if running > 0 {
                Text(verbatim: "\(running)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(Chrome.accent, in: Capsule())
                    .offset(x: 3, y: -3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: running)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help(help(isOn: isOn, running: running))
        .accessibilityLabel(Text(isOn ? "Turn off Hydra" : "Turn on Hydra"))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    private func help(isOn: Bool, running: Int) -> String {
        guard isOn else { return "Turn on Hydra: the agent leads a team of heads on big jobs" }
        var parts = ["Hydra is on"]
        if let pair = model.hydraPair(for: thread) {
            parts.append(HydraPairSummary.workers(pair, registry: model.providers))
        } else {
            parts.append("Heads run on this chat's model")
        }
        if running > 0 { parts.append(running == 1 ? "1 head working" : "\(running) heads working") }
        return parts.joined(separator: " · ")
    }
}

/// The lead-and-heads mark. On, each head wears one of the roster's first colours.
private struct HydraMarkView: View {
    let isOn: Bool
    let isHovering: Bool

    var body: some View {
        let base = Chrome.primaryText.opacity(isHovering || isOn ? 1 : 0.92)
        let size: CGFloat = 17
        ZStack {
            HydraSpokes()
                .stroke(base.opacity(isOn ? 0.9 : 0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            HydraCore()
                .fill(base)
            ForEach(0..<3, id: \.self) { index in
                HydraHeadDot(index: index)
                    .fill(isOn ? HydraRoster.personas[index].color : base.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
    }
}

/// The lead at the centre of the mark.
private struct HydraCore: Shape {
    func path(in rect: CGRect) -> Path {
        let core = min(rect.width, rect.height) * 0.15
        return Path(ellipseIn: CGRect(x: rect.midX - core, y: rect.midY - core, width: core * 2, height: core * 2))
    }
}

/// One head of the mark, on its orbit.
private struct HydraHeadDot: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let orbit = min(rect.width, rect.height) * 0.36
        let head = min(rect.width, rect.height) * 0.12
        let angle = -.pi / 2 + CGFloat(index) * 2 * .pi / 3
        let point = CGPoint(x: rect.midX + orbit * cos(angle), y: rect.midY + orbit * sin(angle))
        return Path(ellipseIn: CGRect(x: point.x - head, y: point.y - head, width: head * 2, height: head * 2))
    }
}

/// The charge around an active Hydra button: a ring of the roster's colours that keeps
/// turning, and a glow behind the mark that breathes. Both stop with reduced motion and
/// leave a still ring, so the state still shows.
struct HydraCharge: View {
    private static let colors: [Color] = HydraRoster.personas.prefix(6).map(\.color)

    var body: some View {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let turn = reduceMotion ? 0 : time.truncatingRemainder(dividingBy: 4) / 4
            let breath = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(time * 2.2)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Chrome.accent.opacity(0.28 + 0.18 * breath), Chrome.accent.opacity(0)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 15
                        )
                    )
                    .padding(2)
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: Self.colors + [Self.colors[0]]),
                            center: .center,
                            angle: .degrees(turn * 360)
                        ),
                        lineWidth: 2
                    )
                    .padding(1)
                    .opacity(0.85 + 0.15 * breath)
            }
        }
        .allowsHitTesting(false)
    }
}

/// One-line summaries of a pair, for tooltips and rows.
enum HydraPairSummary {
    /// "Heads on Opus · High effort", or what they inherit.
    @MainActor
    static func workers(_ pair: HydraPair, registry: ProviderRegistry) -> String {
        var parts: [String] = []
        if let model = pair.workerModel {
            parts.append("Heads on " + (registry.model(model, for: pair.provider)?.shortName ?? model))
        } else {
            parts.append("Heads on the chat's model")
        }
        if let effort = pair.workerEffort { parts.append(ModelOption.effortTitle(effort) + " effort") }
        return parts.joined(separator: " · ")
    }

    /// "Fable leads Opus", "Any model leads Sonnet", "Opus leads itself".
    @MainActor
    static func title(_ pair: HydraPair, registry: ProviderRegistry) -> String {
        func name(_ id: String?) -> String? {
            guard let id else { return nil }
            return registry.model(id, for: pair.provider)?.shortName ?? id
        }
        let lead = name(pair.orchestratorModel) ?? "Any \(pair.provider.displayName) model"
        guard let worker = name(pair.workerModel) else { return "\(lead) leads itself" }
        return "\(lead) leads \(worker)"
    }
}
