import AppKit
import SwiftUI

/// The chat's Hydra mark, first in the chrome row: one dragon head in profile. With Hydra on
/// in Settings it is always active in every chat: charged, a ring of the roster's colours
/// turning around it and a soft glow breathing behind, so the chat reads as a team at
/// work. The badge above it counts the heads at work; tapping the badge (or the mark)
/// opens the floating panel, tapping again dismisses it.
struct HydraButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let thread: ChatThread
    let runtime: ThreadRuntime

    @State private var isHovering = false
    /// With Hydra on and nothing out yet, the button says so rather than doing nothing.
    @State private var isExplaining = false
    /// Briefly true after heads go out, so the badge first shows the sending pulse
    /// inside its own box before morphing into the working count.
    @State private var isSending = false
    /// Right-tapping the mark opens the per-chat Hydra switch in place.
    @State private var isHydraSwitchShown = false

    var body: some View {
        let isOn = model.hydraIsOn(thread)
        // This chat's own heads, read through its child cells: another lead's head
        // starting or finishing never re-renders this button.
        let heads = model.panelHeads(of: thread.id)
        let running = heads.count { $0.hydra?.status == .running }
        // The lead writing head briefs, before any head status is running: a native
        // agent tool at work, or a delegation block in the reply. Derived from the
        // lead's own timeline, so the badge pulses as soon as delegation starts.
        let isDelegating = isOn && running == 0 && runtime.isRunning && Self.isLeadDelegating(runtime.entries)
        Button {
            if heads.isEmpty { isExplaining = true } else { togglePanel() }
        } label: {
            ZStack {
                if isOn {
                    HydraCharge(isWorking: running > 0)
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
                if running > 0 || isSending || isDelegating {
                    HydraSendWorkingBadge(running: running, isSending: isSending || isDelegating)
                        .offset(x: 3, y: -3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: running)
            .animation(Chrome.panelSlide, value: isSending)
            .animation(Chrome.panelSlide, value: isDelegating)
            .onChange(of: running) { old, new in
                guard new > old else { return }
                isSending = true
            }
            .task(id: isSending) {
                guard isSending else { return }
                try? await Task.sleep(for: .seconds(0.9))
                guard !Task.isCancelled else { return }
                isSending = false
            }
        }
        .buttonStyle(.plain)
        .chromeGlassCircle()
        .background {
            HydraRightTap { isHydraSwitchShown = true }
        }
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            HydraIdlePopover(thread: thread)
        }
        .popover(isPresented: $isHydraSwitchShown, arrowEdge: .bottom) {
            HydraSwitchPopover(thread: thread, isOn: isOn, isHydraSwitchShown: $isHydraSwitchShown)
        }
        .help(help(isOn: isOn, running: running, hasHeads: !heads.isEmpty))
        .accessibilityLabel(Text(panelHelp(running: running, hasHeads: !heads.isEmpty)))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }

    /// Shows the floating panel; shown, hides it. The panel fades and scales in and out
    /// in place while the chat slides to make room or take it back. Heads keep working
    /// either way. With nothing out yet the popover explains instead (see the body).
    private func togglePanel() {
        withAnimation(Chrome.panelSlide) { runtime.isHydraPanelHidden.toggle() }
    }

    /// Whether the lead's own timeline shows delegation under way: a native agent tool
    /// still running, or a delegation block in a reply (streaming briefs, or written
    /// while the heads have yet to go out; the block leaves the reply once they do).
    @MainActor
    private static func isLeadDelegating(_ entries: [TimelineEntry]) -> Bool {
        guard let lastEntry = entries.last else { return false }
        // The row's own turn, fixed for its lifetime: reading it through `item` would make
        // this button observe the last row of the turn before as well.
        let lastTurnID = lastEntry.turnID
        for entry in entries.reversed() {
            guard entry.turnID == lastTurnID else { break }
            switch entry.item.content {
            case .tool(let call) where call.kind == .agent && call.status == .running:
                return true
            case .assistant(let message):
                // The reply still streaming changed with this render, so it is read afresh;
                // the finished ones before it have not, and their answers are kept.
                let hasBlock = message.isStreaming
                    ? HydraPrompts.hasDelegationBlock(in: message.text)
                    : hasDelegationBlock(in: message.text, rowID: entry.id)
                if hasBlock { return true }
            default:
                break
            }
        }
        return false
    }

    /// Whether a finished reply holds a delegation block, remembered by its row. Every
    /// streamed token of the turn re-renders this button (the rows it reads are observed),
    /// and running the fence regex over every finished reply of the turn again for each
    /// token was a whole turn's worth of text on the main thread per token. The row's id
    /// is the key rather than its text: a finished reply's text no longer changes, and
    /// hashing a long reply per render would be a walk over it too.
    @MainActor private static var delegationChecks = RecentCache<String, Bool>(limit: 32)

    @MainActor
    private static func hasDelegationBlock(in text: String, rowID: String) -> Bool {
        if let known = delegationChecks.value(for: rowID) { return known }
        let found = HydraPrompts.hasDelegationBlock(in: text)
        delegationChecks.insert(found, for: rowID)
        return found
    }

    private func panelHelp(running: Int, hasHeads: Bool) -> String {
        guard hasHeads else { return "Hydra is on, no heads out yet" }
        if running == 0 { return "Hydra is on, show the panel" }
        return running == 1 ? "Hydra is on, 1 head working, show or hide the panel" : "Hydra is on, \(running) heads working, show or hide the panel"
    }

    private func help(isOn: Bool, running: Int, hasHeads: Bool) -> String {
        guard isOn else { return "Hydra is on in Settings" }
        var parts = ["Hydra is on"]
        if let pair = model.hydraPair(for: thread) {
            parts.append(HydraPairSummary.workers(pair, registry: model.providers))
        } else {
            parts.append("Heads run on this chat's model")
        }
        if running > 0 { parts.append(running == 1 ? "1 head working" : "\(running) heads working") }
        guard hasHeads else {
            parts.append("No heads out yet")
            return parts.joined(separator: " · ")
        }
        parts.append(runtime.isHydraPanelHidden ? "Show the panel" : "Hide the panel")
        return parts.joined(separator: " · ")
    }
}

/// What a right-tap on the Hydra mark offers, in place: the per-chat switch, on or
/// off for this chat only. Left-click keeps opening the panel; this only flips the chat.
private struct HydraSwitchPopover: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let isOn: Bool
    @Binding var isHydraSwitchShown: Bool

    var body: some View {
        PopoverMenu {
            if !model.settings.hydraEnabled {
                PopoverSectionHeader("Hydra is off in Settings")
                PopoverItem("Turn Hydra on") {
                    model.settings.hydraEnabled = true
                    model.setHydra(true, for: thread.id)
                    isHydraSwitchShown = false
                }
            } else {
                PopoverSectionHeader(isOn ? "Hydra is on for this chat" : "Hydra is off for this chat")
                PopoverItem("Turn Hydra on for this chat", isChecked: isOn) {
                    model.setHydra(true, for: thread.id)
                    isHydraSwitchShown = false
                }
                PopoverItem("Turn Hydra off for this chat", isChecked: !isOn) {
                    model.setHydra(false, for: thread.id)
                    isHydraSwitchShown = false
                }
            }
        }
    }
}

/// Catches a right-tap, a right-click or a control-click, on the Hydra mark. A
/// background with no size of its own, so the button's left-click, badge, hover and
/// help text are exactly as they were: it only hangs a right-button click recognizer
/// on the container SwiftUI gives it, which observes without delaying or swallowing
/// the primary button's events. Control-click arrives as a secondary click, so the
/// one recognizer covers both.
private struct HydraRightTap: NSViewRepresentable {
    var action: () -> Void

    func makeNSView(context: Context) -> HydraRightTapHost {
        HydraRightTapHost(action: action)
    }

    func updateNSView(_ nsView: HydraRightTapHost, context: Context) {
        nsView.action = action
    }
}

private final class HydraRightTapHost: NSView {
    var action: () -> Void
    private var installed = false

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard let host = superview else {
            installed = false
            return
        }
        guard !installed else { return }
        installed = true
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(fire))
        // `buttonMask` is a plain bit mask: bit 0 is the left button, bit 1 the right.
        recognizer.buttonMask = 0x2
        recognizer.delaysPrimaryMouseButtonEvents = false
        host.addGestureRecognizer(recognizer)
    }

    @objc private func fire() { action() }
}

/// What the Hydra mark says while the team is on but nothing is out: that it is on, which
/// pair leads, and what sends heads out. The button has no panel to show yet, and a mark
/// that swallowed the click said none of this.
private struct HydraIdlePopover: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        PopoverMenu {
            PopoverSectionHeader("Hydra is on")
            if let pair = model.hydraPair(for: thread) {
                PopoverNote(HydraPairSummary.title(pair, registry: model.providers))
                PopoverNote(HydraPairSummary.workers(pair, registry: model.providers))
            } else {
                PopoverNote("Heads run on this chat's model and effort.")
            }
            PopoverDivider()
            PopoverNote("No heads are out yet. Ask for something big enough to split up and this chat sends them out, each with a panel of its own.")
        }
        .frame(width: 290)
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

/// The charge around an active Hydra button: a ring of the roster's colours and a glow
/// behind the mark. While a head works the ring keeps turning and the glow breathes;
/// both are animations the render server runs on its own (a rotation and an opacity,
/// repeating), so a working team costs the main thread nothing. With no head out the
/// ring stands still: the button sits inside a glass surface, and glass redraws with
/// every frame its content moves, so a ring that turned all day kept the compositor
/// busy for every chat with Hydra on. Reduced motion keeps the still ring too.
struct HydraCharge: View {
    /// Whether any head is at work: the ring turns and the glow breathes only then.
    var isWorking = true

    private static let colors: [Color] = HydraRoster.personas.prefix(6).map(\.color)

    var body: some View {
        ZStack {
            if isWorking, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                HydraChargeMotion()
            } else {
                Self.glow(breathing: false)
                Self.ring(turned: false)
            }
        }
        .allowsHitTesting(false)
    }

    static func glow(breathing: Bool) -> some View {
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
            .opacity(breathing ? 1 : 0.6)
    }

    static func ring(turned: Bool, bright: Bool = false) -> some View {
        Circle()
            .strokeBorder(
                AngularGradient(
                    gradient: Gradient(colors: colors + [colors[0]]),
                    center: .center
                ),
                lineWidth: 2
            )
            .padding(1)
            .rotationEffect(.degrees(turned ? 360 : 0))
            .opacity(bright ? 1 : 0.85)
    }
}

/// The charge in motion. A view of its own, so the repeating animations start when a head
/// goes out and are torn down with it when the last one is back.
private struct HydraChargeMotion: View {
    @State private var isTurning = false
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            HydraCharge.glow(breathing: isBreathing)
            HydraCharge.ring(turned: isTurning, bright: isBreathing)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { isTurning = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { isBreathing = true }
        }
    }
}

/// The count of heads at work, above the button's top-right: tapping it is tapping the
/// button. While the lead delegates it first shows the sending pulse, then morphs in
/// place into the working count: the same anchor, the same capsule at the same size, the
/// existing mini spinner and the panel slide for motion, so nothing jumps and no second
/// row ever appears.
private struct HydraSendWorkingBadge: View {
    let running: Int
    let isSending: Bool

    var body: some View {
        Group {
            if isSending {
                MiniSpinner(cellSize: 2.4)
            } else {
                Text(verbatim: "\(running)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
            }
        }
        .frame(minWidth: 14, minHeight: 14)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        // The pulse reads on glass, the count on accent: the same capsule either
        // way, so the send-to-working change is a tint crossfade, never a jump.
        .background(isSending ? Chrome.glassTint : Chrome.accent, in: Capsule())
        .contentShape(Capsule())
        .animation(Chrome.panelSlide, value: isSending)
        .help(running == 1 ? "1 head working · Show or hide the Hydra panel" : "\(running) heads working · Show or hide the Hydra panel")
        .accessibilityHidden(true)
    }
}

/// One-line summaries of a pair, for tooltips and rows.
enum HydraPairSummary {
    /// The heads' model by name: the pair's own, or, on another provider than the lead's
    /// with none chosen, that provider's default, which is what the heads run there.
    @MainActor
    static func workerModel(_ pair: HydraPair, registry: ProviderRegistry) -> String? {
        if let model = pair.workerModel { return registry.model(model, for: pair.headsProvider)?.shortName ?? model }
        guard pair.sendsHeadsElsewhere else { return nil }
        return registry.defaultModel(for: pair.headsProvider)?.shortName
    }

    /// "Heads on Opus · High effort", "Heads on Gemini 3.8 Flash (Antigravity)", or what
    /// they inherit.
    @MainActor
    static func workers(_ pair: HydraPair, registry: ProviderRegistry) -> String {
        var parts: [String] = []
        if let model = workerModel(pair, registry: registry) {
            parts.append("Heads on " + model + (pair.sendsHeadsElsewhere ? " (\(pair.headsProvider.displayName))" : ""))
        } else if pair.sendsHeadsElsewhere {
            parts.append("Heads on \(pair.headsProvider.displayName)")
        } else {
            parts.append("Heads on the chat's model")
        }
        if let effort = pair.workerEffort { parts.append(ModelOption.effortTitle(effort) + " effort") }
        return parts.joined(separator: " · ")
    }

    /// "Fable + Opus", "Any model + Sonnet", "Opus + itself", and across
    /// providers "Fable + Gemini 3.8 Flash".
    @MainActor
    static func title(_ pair: HydraPair, registry: ProviderRegistry) -> String {
        let lead = pair.orchestratorModel.map { registry.model($0, for: pair.provider)?.shortName ?? $0 } ?? "Any \(pair.provider.displayName) model"
        guard let worker = workerModel(pair, registry: registry) ?? (pair.sendsHeadsElsewhere ? pair.headsProvider.displayName : nil) else {
            return "\(lead) + itself"
        }
        return "\(lead) + \(worker)"
    }
}
