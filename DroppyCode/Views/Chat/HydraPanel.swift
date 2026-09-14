import AppKit
import SwiftUI

/// The lead's team as a floating glass panel, in the same spot and size as the helper
/// panel: the head on stage in the middle, its conversation live as it works, and a strip
/// along the top that is the handle. The strip's left end counts the heads and opens
/// them in a popover, where any head can take the stage or be stopped; its right end
/// dismisses the panel. A Droppy-run head keeps its own chat box at the bottom, so it can
/// be steered or answered; a native head shows what it is up to instead.
struct HydraPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let runtime: ThreadRuntime
    let heads: [ChatThread]
    let size: CGSize
    let workingDirectory: String?
    let projectName: String?
    /// The pointer's travel since the handle was grabbed.
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let dismiss: () -> Void

    @State private var isHoveringHandle = false
    @State private var isDragging = false

    private static let cornerRadius: CGFloat = 22
    private static let stripHeight: CGFloat = Chrome.chromeTopPadding + Chrome.capsuleHeight + 6

    var body: some View {
        // The head on stage: the one picked, else the newest still working, else the newest.
        let selected = heads.first { $0.id == runtime.hydraSelectedHeadID }
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
                    shape.fill((isDark ? Color.black : Color.white).opacity(isDark ? 0.3 : 0.34))
                }
                .overlay {
                    shape.fill(Chrome.glassTint.opacity(isDark ? 0.22 : 0.16))
                }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Chrome.overlay(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.36 : 0.22), radius: 28, y: 10)
        .onDisappear {
            if isDragging { NSCursor.pop() }
            if isHoveringHandle { NSCursor.pop() }
        }
    }

    /// The handle across the top: the count and the head on stage at the left, the close
    /// button at the right, and the room between them drags the panel.
    private func strip(selected: ChatThread?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 8) {
                HydraHeadsButton(runtime: runtime, heads: heads, dismiss: dismiss)
                if let selected, let info = selected.hydra {
                    HStack(spacing: 6) {
                        HydraGlyph(persona: info.persona, size: 16, isRunning: info.status == .running)
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
                    .chromeGlassCapsule()
                    .transition(.softAppear)
                }
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.leading, Chrome.chromeHorizontalPadding)
            // The handle. Invisible, like a window's title bar with no title; the cursor
            // says what it does.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.stripHeight)
                .contentShape(.rect)
                .onHover { hovering in
                    isHoveringHandle = hovering
                    guard !isDragging else { return }
                    if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                NSCursor.closedHand.push()
                            }
                            onDrag(value.translation)
                        }
                        .onEnded { _ in
                            isDragging = false
                            NSCursor.pop()
                            if !isHoveringHandle { NSCursor.pop() }
                            onDragEnd()
                        }
                )
                .help("Drag to move")
                .accessibilityLabel(Text("Drag to move"))
            ChromeCircleButton(symbol: "xmark", help: "Dismiss the panel; heads keep working") {
                dismiss()
            }
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.trailing, Chrome.chromeHorizontalPadding)
        }
        .animation(Chrome.panelSlide, value: selected?.id)
    }
}

/// The count at the strip's left end: it opens the team in a popover.
private struct HydraHeadsButton: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let heads: [ChatThread]
    let dismiss: () -> Void

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        let running = heads.count { $0.hydra?.status == .running }
        Button {
            isPresented.toggle()
        } label: {
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
        }
        .buttonStyle(.plain)
        .fixedSize()
        .chromeGlassCapsule()
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help(heads.count == 1 ? "1 head" : "\(heads.count) heads")
        .accessibilityLabel(Text(heads.count == 1 ? "1 head" : "\(heads.count) heads"))
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

/// The lead-and-heads mark at capsule size.
private struct HydraSpokesMark: View {
    var body: some View {
        ZStack {
            HydraSpokes()
                .stroke(Chrome.primaryText.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            HydraMark()
                .fill(Chrome.primaryText.opacity(0.9))
        }
        .frame(width: 14, height: 14)
    }
}

/// One head in the popover: its glyph, its name and task, what it is doing, and a stop
/// button while it works.
private struct HydraHeadRow: View {
    @Environment(AppModel.self) private var model
    let head: ChatThread
    let isOnStage: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        if let info = head.hydra {
            HStack(spacing: 10) {
                Button(action: select) {
                    HStack(spacing: 10) {
                        HydraGlyph(persona: info.persona, size: 22, isRunning: info.status == .running)
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
                        if isOnStage {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Chrome.primaryText)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if info.status == .running, info.canStop {
                    Button {
                        model.stopHydraHead(head.id)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Chrome.secondaryText)
                            .frame(width: 22, height: 22)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Stop \(info.persona.name)")
                    .opacity(isHovering ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Chrome.overlay(0.1) : Color.clear)
            }
            .onHover { hovering in
                withAnimation(Chrome.hover) { isHovering = hovering }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(info.persona.name), \(HydraStatusText.long(info)), \(info.task)"))
        }
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
                ComposerArea(runtime: runtime, workingDirectory: workingDirectory)
                    .overlay(alignment: .top) {
                        JumpToLatestButton(scrollState: scrollState)
                    }
            } else if let info = head.hydra {
                HydraHeadFooter(info: info)
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
