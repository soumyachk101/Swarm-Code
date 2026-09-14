import AppKit
import SwiftUI

/// The chat's Hydra mark, first in the chrome row: three heads on one body. With Hydra on
/// in Settings it is always active in every chat: charged, a ring of the roster's colours
/// turning around it and a soft glow breathing behind, so the chat reads as a team at
/// work. The badge above it counts the heads at work; tapping the badge (or the mark)
/// opens the floating panel, tapping again hides it back into the button with a genie morph.
struct HydraButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let thread: ChatThread
    let runtime: ThreadRuntime

    @State private var isHovering = false

    var body: some View {
        let isOn = model.hydraIsOn(thread)
        let running = model.hydraHeads(of: thread.id).count { $0.hydra?.status == .running }
        // Siblings, badge last: the badge always draws above the button's glass, and each
        // keeps its own tap. Nested, the badge sat under the glass and its taps went to the mark.
        ZStack(alignment: .topTrailing) {
            Button {
                togglePanel()
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
            .onGeometryChange(for: CGPoint.self, of: {
                let frame = $0.frame(in: .named(GenieAnimator.coordinateSpace))
                return CGPoint(x: frame.midX, y: frame.midY)
            }) { runtime.hydraButtonCenterInWindow = $0 }
            .help(help(isOn: isOn, running: running))
            .accessibilityLabel(Text(panelHelp(running: running)))
            .accessibilityValue(Text(isOn ? "On" : "Off"))
            if running > 0 {
                Button {
                    togglePanel()
                } label: {
                    Text(verbatim: "\(running)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Chrome.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .transition(.scale.combined(with: .opacity))
                .help(running == 1 ? "1 head working · Show or hide the Hydra panel" : "\(running) heads working · Show or hide the Hydra panel")
                .accessibilityLabel(Text(running == 1 ? "1 head working, show or hide the Hydra panel" : "\(running) heads working, show or hide the Hydra panel"))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: running)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
    }

    /// Opens the floating panel; open, hides it back into this button with a genie morph.
    /// Heads keep working either way. Nothing to show yet, nothing happens.
    private func togglePanel() {
        guard !model.hydraHeads(of: thread.id).isEmpty else { return }
        if runtime.isHydraPanelHidden {
            withAnimation(Chrome.panelSlide) { runtime.isHydraPanelHidden = false }
        } else {
            if let frame = runtime.hydraPanelFrameInWindow, let target = runtime.hydraButtonCenterInWindow {
                GenieAnimator.shared.launch(frame: frame, colorScheme: colorScheme, target: target) {
                    HydraPanelGhost(isDark: colorScheme == .dark)
                }
            }
            withAnimation(Chrome.panelSlide) { runtime.isHydraPanelHidden = true }
        }
    }

    private func panelHelp(running: Int) -> String {
        if running == 0 { return "Hydra is on, show the panel" }
        return running == 1 ? "Hydra is on, 1 head working, show or hide the panel" : "Hydra is on, \(running) heads working, show or hide the panel"
    }

    private func help(isOn: Bool, running: Int) -> String {
        guard isOn else { return "Hydra is on in Settings" }
        var parts = ["Hydra is on"]
        if let pair = model.hydraPair(for: thread) {
            parts.append(HydraPairSummary.workers(pair, registry: model.providers))
        } else {
            parts.append("Heads run on this chat's model")
        }
        if running > 0 { parts.append(running == 1 ? "1 head working" : "\(running) heads working") }
        parts.append(runtime.isHydraPanelHidden ? "Show the panel" : "Hide the panel into the button")
        return parts.joined(separator: " · ")
    }
}

/// The three-headed mark: quiet when Hydra is off, full when it is on or under the pointer.
private struct HydraMarkView: View {
    let isOn: Bool
    let isHovering: Bool

    var body: some View {
        HydraMarkImage()
            .foregroundStyle(Chrome.primaryText.opacity(isOn || isHovering ? 1 : 0.6))
            .frame(width: 18, height: 18)
    }
}

/// The charge around an active Hydra button: a ring of the roster's colours that keeps
/// turning, and a glow behind the mark that breathes. Both are animations the render
/// server runs on its own (a rotation and an opacity, repeating), so a charged button
/// costs the main thread nothing while it sits there; an earlier version re-rendered the
/// view thirty times a second for as long as Hydra was on. Both stop with reduced motion
/// and leave a still ring, so the state still shows.
struct HydraCharge: View {
    private static let colors: [Color] = HydraRoster.personas.prefix(6).map(\.color)

    @State private var isTurning = false
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Chrome.accent.opacity(0.46), Chrome.accent.opacity(0)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 15
                    )
                )
                .padding(2)
                .opacity(isBreathing ? 1 : 0.6)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: Self.colors + [Self.colors[0]]),
                        center: .center
                    ),
                    lineWidth: 2
                )
                .padding(1)
                .rotationEffect(.degrees(isTurning ? 360 : 0))
                .opacity(isBreathing ? 1 : 0.85)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { isTurning = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { isBreathing = true }
        }
    }
}

/// The flat stand-in the Hydra panel becomes while it hides into the button: the
/// panel's own glass, scrim, tint and hairline, minus its transcript, so the genie
/// flight carries its glow rather than a blank tile.
private struct HydraPanelGhost: View {
    let isDark: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ZStack {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill((isDark ? Color.black : Color.white).opacity(isDark ? 0.3 : 0.34))
                }
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .overlay {
            shape.strokeBorder(Chrome.overlay(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isDark ? 0.36 : 0.22), radius: 28, y: 10)
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
