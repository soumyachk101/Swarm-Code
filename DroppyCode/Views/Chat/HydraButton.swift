import AppKit
import SwiftUI

/// The chat's Hydra mark, first in the chrome row: one dragon head in profile. With Hydra on
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
            // The badge is part of the glass's own content, which is the one place that
            // draws above the glass: the chrome row's container composites every glass in
            // it over everything else in it, so a badge laid over the button after the
            // glass, as an overlay or a later sibling, came out underneath.
            .overlay(alignment: .topTrailing) {
                if running > 0 {
                    HydraRunningBadge(running: running)
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: running)
        }
        .buttonStyle(.plain)
        .chromeGlassCircle()
        .onGeometryChange(for: CGPoint.self, of: {
            let frame = $0.frame(in: .named(GenieAnimator.coordinateSpace))
            return CGPoint(x: frame.midX, y: frame.midY)
        }) { runtime.hydraButtonCenterInWindow = $0 }
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help(help(isOn: isOn, running: running))
        .accessibilityLabel(Text(panelHelp(running: running)))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    /// Opens the floating panel; open, hides it back into this button with a genie morph.
    /// Either way the panel itself comes or goes with no transition of its own: a ghost of
    /// it does the flying, out of this button into the panel's place, or from the panel's
    /// place down into this button. Heads keep working either way. Nothing to show yet,
    /// nothing happens.
    private func togglePanel() {
        guard !model.hydraHeads(of: thread.id).isEmpty else { return }
        let morphs = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if runtime.isHydraPanelHidden {
            // The panel launches its own arrival once it knows where it sits.
            runtime.hydraPanelMorphs = morphs
            withAnimation(Chrome.panelSlide) { runtime.isHydraPanelHidden = false }
        } else {
            var flew = false
            if morphs, let frame = runtime.hydraPanelFrameInWindow, let target = runtime.hydraButtonCenterInWindow {
                flew = GenieAnimator.shared.launch(frame: frame, colorScheme: colorScheme, target: target) {
                    HydraPanelGhost(isDark: colorScheme == .dark)
                }
            }
            runtime.hydraPanelMorphs = flew
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

/// The dragon-head mark: quiet when Hydra is off, full when it is on or under the pointer.
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

/// The count of heads at work, above the button's top-right: tapping it is tapping the
/// button.
private struct HydraRunningBadge: View {
    let running: Int

    var body: some View {
        Text(verbatim: "\(running)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(Chrome.accent, in: Capsule())
            .contentShape(Capsule())
            .help(running == 1 ? "1 head working · Show or hide the Hydra panel" : "\(running) heads working · Show or hide the Hydra panel")
            .accessibilityHidden(true)
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
