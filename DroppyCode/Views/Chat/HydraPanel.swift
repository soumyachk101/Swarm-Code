import AppKit
import SwiftUI

/// The lead's team as a floating glass panel, in the same spot and size as the helper
/// panel: the head on stage in the middle, its conversation live as it works, and a strip
/// along the top that is the handle. The strip's left end counts the heads and opens
/// them in a popover, where any head can take the stage or be stopped; its right end
/// pops the head on stage out into a second panel of its own, and dismisses the panel. A
/// Droppy-run head keeps its own chat box at the bottom, so it can be steered or answered;
/// a native head shows what it is up to instead.
///
/// Popped out, the panel holds one head: no count at the left, and its right end puts the
/// head back in the team panel.
struct HydraPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let runtime: ThreadRuntime
    let heads: [ChatThread]
    let size: CGSize
    let workingDirectory: String?
    let projectName: String?
    /// A second panel holding one head popped out of the team panel.
    var isPoppedOut = false
    /// The pointer's travel since the handle was grabbed.
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    /// Pops the head on stage out into its own panel; nil where it cannot go anywhere.
    var popOut: ((UUID) -> Void)? = nil
    /// Dismisses the panel; for a popped-out one, puts its head back in the team panel.
    let dismiss: () -> Void

    /// Out of sight while a surface grows out of the button into the panel's shape. Opened
    /// from the button, the panel starts unseen, so it never shows for a frame before the
    /// surface sets off; its first layout starts the morph or, if none can run, shows it.
    @State private var isArriving: Bool

    init(
        runtime: ThreadRuntime,
        heads: [ChatThread],
        size: CGSize,
        workingDirectory: String?,
        projectName: String?,
        isPoppedOut: Bool = false,
        onDrag: @escaping (CGSize) -> Void,
        onDragEnd: @escaping () -> Void,
        popOut: ((UUID) -> Void)? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.runtime = runtime
        self.heads = heads
        self.size = size
        self.workingDirectory = workingDirectory
        self.projectName = projectName
        self.isPoppedOut = isPoppedOut
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        self.popOut = popOut
        self.dismiss = dismiss
        // Only the team panel grows out of the button; a popped-out head just appears.
        _isArriving = State(initialValue: !isPoppedOut && runtime.hydraPanelMorphs)
    }

    static let cornerRadius: CGFloat = 22
    private static let stripHeight: CGFloat = Chrome.chromeTopPadding + Chrome.capsuleHeight + 6

    var body: some View {
        // The head on stage: the one picked, else the newest still working, else the newest.
        // A popped-out panel holds one head, and that one is on stage.
        let selected = isPoppedOut
            ? heads.first
            : heads.first { $0.id == runtime.hydraSelectedHeadID }
                ?? heads.last { $0.hydra?.status == .running }
                ?? heads.last
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        ZStack {
            if let selected {
                HydraHeadTranscript(
                    head: selected,
                    height: size.height,
                    workingDirectory: workingDirectory,
                    projectName: projectName
                )
                .id(selected.id)
            }
        }
        .overlay(alignment: .top) {
            strip(selected: selected)
        }
        .frame(width: size.width, height: size.height)
        .background {
            // The helper panel's recipe: one glass surface, a scrim for the text over
            // whatever the panel floats above, the theme's tint, and a hairline.
            let isDark = colorScheme == .dark
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Chrome.overlay(0.14), lineWidth: 1)
        }
        // The scrim sits under the glass and carries the panel's shadow: a plain filled
        // shape, so its shadow is drawn once and kept. A shadow on the whole panel was
        // blurred again with every token the transcript streamed under it.
        .background {
            let isDark = colorScheme == .dark
            shape
                .fill((isDark ? Color.black : Color.white).opacity(isDark ? 0.3 : 0.34))
                .shadow(color: .black.opacity(isDark ? 1 : 0.65), radius: 28, y: 10)
        }
        .opacity(isArriving ? 0 : 1)
        .onGeometryChange(for: CGRect.self, of: {
            $0.frame(in: .named(GenieAnimator.coordinateSpace))
        }) { frame in
            // The morph runs to and from the team panel; the popped-out one just fades.
            if !isPoppedOut {
                runtime.hydraPanelFrameInWindow = frame
                if runtime.hydraPanelMorphs { arrive(at: frame) }
            }
        }
        .onDisappear {
            // Gone into the button: the surface is on its way, and the next showing starts clean.
            runtime.hydraPanelMorphs = false
        }
    }

    /// Opened from the button, the panel appears where it will sit but stays out of sight
    /// while a surface grows out of the button's circle into the panel's rounded rectangle,
    /// there; the panel fades in under it as it lands. The panel's first layout is the
    /// earliest the morph can start, since only then is the destination known. No morph,
    /// no wait.
    private func arrive(at frame: CGRect) {
        runtime.hydraPanelMorphs = false
        guard let button = runtime.hydraButtonFrameInWindow else {
            isArriving = false
            return
        }
        let isDark = colorScheme == .dark
        let grew = GenieAnimator.shared.morph(
            from: button, radius: button.height / 2,
            to: frame, radius: Self.cornerRadius,
            fadeIn: 0.08
        ) { radius in
            HydraPanelGhost(isDark: isDark, cornerRadius: radius)
        }
        guard grew else {
            isArriving = false
            return
        }
        isArriving = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(GenieAnimator.morphDuration - GenieAnimator.morphCrossfade))
            withAnimation(.easeOut(duration: GenieAnimator.morphCrossfade)) { isArriving = false }
        }
    }

    /// The handle across the top: the count and the head on stage at the left, the pop-out
    /// and close buttons at the right, and the room between them drags the panel.
    private func strip(selected: ChatThread?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                if !isPoppedOut {
                    HydraHeadsButton(runtime: runtime, heads: heads, dismiss: dismiss)
                }
                if let selected, let info = selected.hydra {
                    HStack(spacing: 6) {
                        HydraGlyph(persona: info.persona, size: 16, isRunning: info.status == .running, status: info.status)
                        Text(verbatim: info.persona.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Chrome.primaryText.opacity(0.92))
                            .lineLimit(1)
                        Text(verbatim: HydraStatusText.short(info))
                            .font(.system(size: 12))
                            .foregroundStyle(Chrome.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Chrome.capsuleHorizontalPadding)
                    .frame(height: Chrome.capsuleContentHeight)
                    .padding(.vertical, Chrome.capsuleVerticalPadding)
                    .fixedSize()
                    .chromeGlassCapsule()
                    // The name is a label, not a control, so it drags the panel too:
                    // it is where the hand goes when there is little room beside it.
                    .overlay {
                        PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
                    }
                    .transition(.softAppear)
                }
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.leading, Chrome.chromeHorizontalPadding)
            // The handle. Invisible, like a window's title bar with no title; the cursor
            // says what it does.
            PanelDragHandle(onDrag: onDrag, onDragEnd: onDragEnd)
                .frame(maxWidth: .infinity)
                .frame(height: Self.stripHeight)
                .help("Drag to move")
                .accessibilityLabel(Text("Drag to move"))
            HStack(spacing: 8) {
                if isPoppedOut {
                    ChromeCircleButton(symbol: "arrow.down.left", help: "Put \(selected?.hydra?.persona.name ?? "the head") back in the team panel") {
                        dismiss()
                    }
                } else {
                    // The head on stage pops out into a second panel, as long as another
                    // head stays behind to keep this one.
                    if let selected, let popOut, heads.count > 1 {
                        ChromeCircleButton(symbol: "arrow.up.right", help: "Pop \(selected.hydra?.persona.name ?? "this head") out into its own panel") {
                            popOut(selected.id)
                        }
                        .transition(.softAppear)
                    }
                    ChromeCircleButton(symbol: "xmark", help: "Dismiss the panel; heads keep working") {
                        dismiss()
                    }
                }
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.trailing, Chrome.chromeHorizontalPadding)
        }
        .animation(Chrome.panelSlide, value: selected?.id)
        .animation(Chrome.panelSlide, value: heads.count > 1)
    }
}

/// The flat stand-in the Hydra panel becomes while it morphs out of or into the button:
/// the panel's scrim, tint, hairline and shadow in its shape at whatever corner radius the
/// morph has reached, minus its glass and transcript. Glass would sample the chat afresh
/// on every frame of the morph, so the scrim stands in for it, a little denser to match.
struct HydraPanelGhost: View {
    let isDark: Bool
    var cornerRadius: CGFloat = HydraPanel.cornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill((isDark ? Color.black : Color.white).opacity(isDark ? 0.62 : 0.7))
            shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
            shape.strokeBorder(Chrome.overlay(0.14), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(isDark ? 0.7 : 0.4), radius: 22, y: 8)
    }
}

/// The count at the strip's left end: it opens the team in a popover. Not a Button: a
/// plain-style Button keeps the click to itself and the glass never sees it, so the capsule
/// sat still under the pointer while the name capsule beside it, bare interactive glass,
/// pressed like a native control. The tap rides along with the glass's own tracking instead,
/// so the whole capsule presses the native way.
private struct HydraHeadsButton: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let heads: [ChatThread]
    let dismiss: () -> Void

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        let running = heads.count { $0.hydra?.status == .running }
        HStack(spacing: 6) {
            HydraSpokesMark()
            Text(verbatim: "\(heads.count)")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            if running > 0 {
                MiniSpinner()
            }
            Image(systemName: "chevron.down")
                .font(Chrome.chevronFont)
                .foregroundStyle(Chrome.secondaryText)
        }
        .foregroundStyle(Chrome.primaryText.opacity(isHovering || isPresented ? 1 : 0.92))
        .padding(.horizontal, Chrome.capsuleHorizontalPadding)
        .frame(height: Chrome.capsuleContentHeight)
        .padding(.vertical, Chrome.capsuleVerticalPadding)
        .contentShape(Capsule(style: .continuous))
        .fixedSize()
        .chromeGlassCapsule()
        .simultaneousGesture(TapGesture().onEnded { isPresented.toggle() })
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help(heads.count == 1 ? "1 head" : "\(heads.count) heads")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(heads.count == 1 ? "1 head" : "\(heads.count) heads"))
        .accessibilityAction { isPresented.toggle() }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PopoverMenu {
                PopoverSectionHeader(running == 0 ? "Heads" : (running == 1 ? "1 head working" : "\(running) heads working"))
                ForEach(heads) { head in
                    HydraHeadRow(head: head, isOnStage: head.id == runtime.hydraSelectedHeadID) {
                        runtime.hydraSelectedHeadID = head.id
                        isPresented = false
                    }
                }
                if running > 1 || heads.contains(where: { $0.hydra?.isFinished == true }) {
                    PopoverDivider()
                }
                if running > 1 {
                    PopoverItem("Stop all heads", symbol: "stop.circle") {
                        model.stopAllHydraHeads(of: runtime.threadID)
                        isPresented = false
                    }
                }
                if heads.contains(where: { $0.hydra?.isFinished == true }) {
                    PopoverItem("Clear finished heads", symbol: "checkmark.circle") {
                        withAnimation(Chrome.panelSlide) {
                            model.clearFinishedHydraHeads(of: runtime.threadID)
                        }
                    }
                }
            }
        }
    }
}

/// The dragon-head mark at capsule size.
private struct HydraSpokesMark: View {
    var body: some View {
        HydraMarkImage()
            .foregroundStyle(Chrome.primaryText.opacity(0.9))
            .frame(width: 15, height: 15)
    }
}

/// One head in the popover: its glyph (wearing its outcome once it is done), its name and
/// task, what it is doing, and a stop button while it works. The head on stage sits on a
/// tinted row.
private struct HydraHeadRow: View {
    @Environment(AppModel.self) private var model
    let head: ChatThread
    let isOnStage: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        if let stored = head.hydra {
            // A running native head's note and counts live on its runtime, off the thread
            // record; this row is the one view that follows them.
            let info = model.existingRuntime(for: head.id).map { $0.hydraLiveInfo(stored) } ?? stored
            HStack(spacing: 10) {
                Button(action: select) {
                    HStack(spacing: 10) {
                        HydraGlyph(persona: info.persona, size: 22, isRunning: info.status == .running, status: info.status)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(verbatim: info.persona.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Chrome.primaryText)
                                Text(verbatim: HydraStatusText.long(info))
                                    .font(.system(size: 11))
                                    .foregroundStyle(info.status == .failed ? Chrome.danger : Chrome.secondaryText)
                                    .lineLimit(1)
                            }
                            Text(verbatim: info.task.isEmpty ? "Waiting for a task" : info.task)
                                .font(.system(size: 12))
                                .foregroundStyle(Chrome.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if info.status == .running, info.canStop {
                    HydraStopButton(name: info.persona.name) {
                        model.stopHydraHead(head.id)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOnStage ? Chrome.overlay(0.14) : (isHovering ? Chrome.overlay(0.08) : Color.clear))
            }
            .onHover { hovering in
                withAnimation(Chrome.hover) { isHovering = hovering }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(info.persona.name), \(HydraStatusText.long(info)), \(info.task)\(isOnStage ? ", on stage" : "")"))
        }
    }
}

/// The stop button beside a working head: the same tinted circle with the white stop
/// mark the composer shows while a turn runs.
private struct HydraStopButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "stop.fill")
                .font(Chrome.iconFont)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.tint, in: .circle)
        }
        .buttonStyle(.plain)
        .help("Stop \(name)")
        .accessibilityLabel(Text("Stop \(name)"))
    }
}

/// A head's conversation, live as it works, with what it can be told below.
private struct HydraHeadTranscript: View {
    @Environment(AppModel.self) private var model
    let head: ChatThread
    let height: CGFloat
    let workingDirectory: String?
    let projectName: String?

    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollState = TimelineScrollState()

    var body: some View {
        let runtime = model.runtime(for: head.id)
        ThreadTimeline(
            runtime: runtime,
            scrollChrome: scrollChrome,
            scrollState: scrollState,
            projectName: projectName,
            workingDirectory: workingDirectory,
            supportsRewind: false,
            columnHeight: height
        )
        .equatable()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if head.hydra?.kind == .droppy {
                // A head of Droppy Code's own can be steered and answered like any chat.
                ComposerArea(runtime: runtime, workingDirectory: workingDirectory, compactModelChip: true, takesFocusOnAppear: false)
                    .overlay(alignment: .top) {
                        JumpToLatestButton(scrollState: scrollState)
                    }
            } else if let stored = head.hydra {
                HydraHeadFooter(info: runtime.hydraLiveInfo(stored))
                    .overlay(alignment: .top) {
                        JumpToLatestButton(scrollState: scrollState)
                    }
            }
        }
        .overlay(alignment: .top) {
            PaneTopVeil(model: scrollChrome)
        }
    }
}

/// What a native head is up to, in place of a chat box: its progress note or last tool,
/// its tool count and its time.
private struct HydraHeadFooter: View {
    let info: HydraHeadInfo

    var body: some View {
        HStack(spacing: 8) {
            if info.status == .running {
                MiniSpinner()
            } else {
                Image(systemName: info.status == .completed ? "checkmark.circle.fill" : (info.status == .failed ? "xmark.circle.fill" : "stop.circle.fill"))
                    .font(.system(size: 12))
                    .foregroundStyle(info.status == .completed ? Chrome.success : (info.status == .failed ? Chrome.danger : Chrome.secondaryText))
            }
            Text(verbatim: HydraStatusText.footer(info))
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if info.toolCalls > 0 {
                Text(verbatim: info.toolCalls == 1 ? "1 step" : "\(info.toolCalls) steps")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Chrome.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }
}

/// The words for a head's state.
enum HydraStatusText {
    static func short(_ info: HydraHeadInfo) -> String {
        switch info.status {
        case .running: "working"
        case .completed: "done"
        case .failed: "failed"
        case .stopped: "stopped"
        }
    }

    static func long(_ info: HydraHeadInfo) -> String {
        switch info.status {
        case .running:
            return info.activity.map { "· " + TextCleanup.singleLine($0, limit: 40) } ?? "· working"
        case .completed:
            return "· done" + elapsed(info) + steps(info) + (landed(info).map { " · " + $0 } ?? "")
        case .failed:
            return "· failed"
        case .stopped:
            return "· stopped"
        }
    }

    static func footer(_ info: HydraHeadInfo) -> String {
        switch info.status {
        case .running:
            return info.activity.map { TextCleanup.singleLine($0, limit: 80) } ?? "Working"
        case .completed:
            return "Done" + elapsed(info) + steps(info) + (landed(info).map { " · " + $0 } ?? "") + (info.summary.map { " · " + TextCleanup.singleLine($0, limit: 80) } ?? "")
        case .failed:
            return "Failed" + (info.summary.map { " · " + TextCleanup.singleLine($0, limit: 80) } ?? "")
        case .stopped:
            return "Stopped"
        }
    }

    /// Where a Droppy-run head's work went, in a few words; nil for a head with no copy
    /// of its own.
    static func landed(_ info: HydraHeadInfo) -> String? {
        guard let landing = info.landing else { return nil }
        if landing.isEmpty { return "changed nothing" }
        let files = landing.files.count == 1 ? "1 file" : "\(landing.files.count) files"
        if landing.patchPath != nil { return "kept as a patch" }
        if landing.error != nil { return "did not land" }
        if !landing.conflicts.isEmpty {
            return "landed \(files), " + (landing.conflicts.count == 1 ? "1 conflict" : "\(landing.conflicts.count) conflicts")
        }
        return "landed \(files)"
    }

    private static func steps(_ info: HydraHeadInfo) -> String {
        guard info.toolCalls > 0 else { return "" }
        return info.toolCalls == 1 ? " · 1 step" : " · \(info.toolCalls) steps"
    }

    private static func elapsed(_ info: HydraHeadInfo) -> String {
        guard let finished = info.finishedAt else { return "" }
        let seconds = Int(finished.timeIntervalSince(info.startedAt))
        guard seconds > 0 else { return "" }
        return seconds < 60 ? " in \(seconds)s" : " in \(seconds / 60)m \(seconds % 60)s"
    }
}
