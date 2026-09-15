import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowLiveResize.self) private var liveResize
    @Bindable var runtime: ThreadRuntime

    @State private var git = GitStatusModel()
    @State private var scrollChrome = ChromeScrollModel()
    @State private var scrollState = TimelineScrollState()
    /// Full column height. The timeline rail centres in this, so composer and
    /// queue growth never shifts it.
    @State private var columnHeight: CGFloat = 0
    /// The conversation pane (the timeline with the chat box, above any terminal), which
    /// the helper panel floats in.
    @State private var paneSize: CGSize = .zero
    /// The chat box with its tabs and cards, so a helper panel above it clears them.
    @State private var composerAreaHeight: CGFloat = 0
    /// The helper panel under the pointer while its handle is held; the same for the Hydra
    /// panel, and for the head popped out of it. Objects, so a move re-lays out one panel.
    @State private var subagentDrag = PanelDragState()
    @State private var hydraDrag = PanelDragState()
    @State private var poppedDrag = PanelDragState()
    @State private var usageDrag = PanelDragState()
    /// One grip held at a time, whichever panel it is on.
    @State private var panelResize = PanelResizeState()

    var body: some View {
        let thread = model.thread(runtime.threadID)
        let project = thread.flatMap { model.project($0.projectID) }
        // The thread and project are read here, once, and passed down as values: the timeline
        // rows and the composer never observe them, so a change to either re-renders this
        // body alone and the children only where what they were handed changed.
        let workingDirectory = thread.flatMap { $0.worktreePath ?? project?.path }
        let directory = workingDirectory ?? LoginEnvironment.homeDirectory
        let title = thread?.title ?? ""
        // Who is in a panel comes from the model and changes rarely; the geometry
        // comes from the measured pane and changes every frame of a live resize.
        // Split, so a resize frame recomputes docks and reserves only, never the
        // thread lists.
        let members = PanelMembers(runtime: runtime, model: model)
        let scene = PanelScene(members: members, runtime: runtime, model: model, paneSize: paneSize, composerAreaHeight: composerAreaHeight)
        VStack(spacing: 0) {
            ThreadTimeline(
                runtime: runtime,
                scrollChrome: scrollChrome,
                scrollState: scrollState,
                projectName: project?.name,
                workingDirectory: workingDirectory,
                supportsRewind: thread?.provider.supportsRewind ?? false,
                columnHeight: columnHeight,
                // A panel docked on the left takes the rail's edge; the rail goes with it. So
                // does a pane too narrow for both: the column reads at up to 820 points and the
                // rail floats over its gutter, so under about 900 the two would overlap.
                showsMinimap: !scene.dockedSides.contains(.leading)
                    && (paneSize == .zero || paneSize.width - scene.reserve.leading - scene.reserve.trailing >= 900)
            )
            .equatable()
            // The text size set in Settings, for the conversation alone: the row and the
            // chat box keep their own size. macOS ignores Dynamic Type, so the timeline
            // scales its fonts by this factor itself (see `Font.chat`).
            .environment(\.chatZoom, ChatZoom.scale(at: model.settings.chatZoom))
            // The room the docked panels take from either side; the conversation and the
            // box centre in the rest, so they stay lined up with each other. The slide is
            // keyed to what is docked, never to the measured room: a pane measured for the
            // first time then lays out in place instead of sliding in from nowhere, and a
            // window resize moves things at once, as it should.
            .padding(.leading, scene.reserve.leading)
            .padding(.trailing, scene.reserve.trailing)
            .animation(Chrome.panelSlide, value: scene.dockedSides)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerArea(runtime: runtime, workingDirectory: workingDirectory)
                    .overlay(alignment: .top) {
                        JumpToLatestButton(scrollState: scrollState)
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { composerAreaHeight = $0 }
                    .padding(.leading, scene.reserve.leading)
                    .padding(.trailing, scene.reserve.trailing)
                    .animation(Chrome.panelSlide, value: scene.dockedSides)
            }
            .overlay(alignment: .top) {
                PaneTopVeil(model: scrollChrome)
            }
            .overlay(alignment: .top) {
                ChatChromeRow(
                    runtime: runtime,
                    scrollChrome: scrollChrome,
                    title: title,
                    project: project,
                    directory: directory,
                    git: git
                )
            }
            .overlay(alignment: .topLeading) {
                // Not before the pane has a size: the panel's spot comes from it.
                if let subagent = scene.subagent, scene.isMeasured {
                    subagentPanel(subagent, scene: scene, project: project)
                }
            }
            .animation(Chrome.panelSlide, value: scene.subagent?.id)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    if scene.showsHydra {
                        hydraPanel(scene: scene, workingDirectory: workingDirectory, project: project)
                    }
                }
                // Toggled from the Hydra button or dismissed, the panel fades and scales
                // in place while the chat slides to make room or take it back.
                .animation(Chrome.panelSlide, value: scene.hasHeads)
            }
            // Keyed to the heads, not to whether the panel is on screen yet: that also flips
            // as the pane is first measured, and slid the whole chat into place from its
            // unmeasured layout every time a thread opened.
            .animation(Chrome.panelSlide, value: scene.hasHeads)
            .overlay(alignment: .topLeading) {
                if let popped = scene.popped, scene.showsPopped {
                    poppedPanel(popped, scene: scene, workingDirectory: workingDirectory, project: project)
                }
            }
            .animation(Chrome.panelSlide, value: scene.popped?.id)
            .overlay(alignment: .topLeading) {
                if let usage = scene.usage, scene.showsUsage {
                    usagePanel(usage, scene: scene)
                }
            }
            .animation(Chrome.panelSlide, value: scene.usage)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { paneSize = $0 }
            // Free-floating panels are kept inside the pane while it shrinks, with no
            // animation; when the resize ends they land docked exactly (see below).
            .onChange(of: paneSize) {
                guard liveResize.isActive else { return }
                let layout = PanelScene.geometry(
                    members: members, runtime: runtime, model: model,
                    paneSize: paneSize, composerAreaHeight: composerAreaHeight).layout
                subagentDrag.reclamp(in: layout)
                hydraDrag.reclamp(in: layout)
                poppedDrag.reclamp(in: layout)
                usageDrag.reclamp(in: layout)
            }
            // The pane's final size: docked panels land on their new docked spot, and
            // a free spot left outside is pulled back inside.
            .onChange(of: liveResize.isActive) { _, resizing in
                guard !resizing else { return }
                subagentDrag.reclamp(in: scene.layout)
                hydraDrag.reclamp(in: scene.layout)
                poppedDrag.reclamp(in: scene.layout)
                usageDrag.reclamp(in: scene.layout)
            }

            if runtime.isTerminalVisible {
                TerminalPanel(runtime: runtime, directory: directory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .detailSheet()
        // A thread switch swaps this whole column for another thread's (see
        // `DetailView`'s `.id(threadID)`): that swap must replace in place, never
        // slide or fade. Any transition here displaces every row, the composer and
        // the chrome row mid-flight, clips leading text, unseats the traffic lights
        // the chrome keeps room for, and doubles the title against itself.
        .transition(.identity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { columnHeight = $0 }
        .animation(Chrome.panelSlide, value: runtime.isTerminalVisible)
        // A merge or pull request link in this chat can hand its request to a helper, which
        // opens in the panel and lands it on the same provider and model as this thread.
        .environment(\.mergeRequestTarget, MergeRequestTarget(chatID: runtime.threadID) { link in
            model.spawnSubagent(from: runtime.threadID, title: link.title, prompt: link.prompt)
        })
        .task(id: directory) {
            await git.refresh(directory, force: false)
        }
        .onChange(of: runtime.diffRevision) {
            Task { await git.refresh(directory) }
        }
    }

    // MARK: - Floating panels

    /// The helper's panel, in its corner.
    private func subagentPanel(_ subagent: ChatThread, scene: PanelScene, project: Project?) -> some View {
        let rest = scene.docks[runtime.subagentPanelDock]
        return PlacedPanel(drag: subagentDrag, rest: rest, size: scene.layout.panelSize, content: SubagentPanel(
            thread: subagent,
            size: scene.layout.panelSize,
            // The helper works in the project folder, whatever this thread's worktree.
            workingDirectory: subagent.worktreePath ?? project?.path,
            projectName: project?.name,
            onDrag: { translation in
                let position = subagentDrag.move(by: translation, from: rest, in: scene.layout)
                dock(\.subagentPanelDock, nearest: position, scene: scene)
            },
            onDragEnd: {
                if let heading = subagentDrag.release() {
                    dock(\.subagentPanelDock, nearest: heading, scene: scene)
                }
            },
            close: {
                // The helper moves to the sidebar under this thread; its row opens with the
                // same slide as the panel leaving.
                withAnimation(Chrome.panelSlide) {
                    model.closeSubagent(subagent.id)
                }
            }
        )
        // Inside the offset, so the panel grows in and fades out in place.
        .transition(Self.panelTransition), resize: resizer(for: runtime.subagentPanelDock, scene: scene), isResizing: panelResize.isActive)
    }

    /// The team's panel: next to the helper panel when that one is in the same corner.
    private func hydraPanel(scene: PanelScene, workingDirectory: String?, project: Project?) -> some View {
        let corner = runtime.hydraPanelDock
        let rest = scene.docks.stacked(corner, below: scene.isDocked && runtime.subagentPanelDock == corner ? 1 : 0, layout: scene.layout)
        return PlacedPanel(drag: hydraDrag, rest: rest, size: scene.layout.panelSize, content: HydraPanel(
            runtime: runtime,
            heads: scene.heads,
            size: scene.layout.panelSize,
            workingDirectory: workingDirectory,
            projectName: project?.name,
            onDrag: { translation in
                let position = hydraDrag.move(by: translation, from: rest, in: scene.layout)
                dock(\.hydraPanelDock, nearest: position, scene: scene)
            },
            onDragEnd: {
                if let heading = hydraDrag.release() {
                    dock(\.hydraPanelDock, nearest: heading, scene: scene)
                }
            },
            popOut: { id in
                // The head's own panel opens docked across the column from the team
                // panel, so the two sit apart.
                withAnimation(Chrome.panelSlide) {
                    runtime.hydraPoppedHeadID = id
                    runtime.hydraPoppedPanelDock = runtime.hydraPanelDock.acrossTheColumn
                    if runtime.hydraSelectedHeadID == id { runtime.hydraSelectedHeadID = nil }
                }
            },
            dismiss: {
                withAnimation(Chrome.panelSlide) {
                    model.dismissHydraHeads(of: runtime.threadID)
                }
            }
        )
        // Where the panel sits, for the tour's captures only: the Hydra page zooms on it.
        // Skipped while the window is resized: the frame moves every frame and the
        // capture map is never read mid-drag.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            guard !liveResize.isActive else { return }
            if WebsiteCaptures.isEnabled { WebsiteCaptures.hydraPanelFrames[runtime.threadID] = frame }
        }
        .transition(Self.panelTransition), resize: resizer(for: corner, scene: scene), isResizing: panelResize.isActive)
    }

    /// The popped-out head's panel: beyond whichever panels are in the same corner.
    private func poppedPanel(_ popped: ChatThread, scene: PanelScene, workingDirectory: String?, project: Project?) -> some View {
        let corner = runtime.hydraPoppedPanelDock
        let below = [scene.isDocked && runtime.subagentPanelDock == corner, scene.isHydraDocked && runtime.hydraPanelDock == corner].count { $0 }
        let rest = scene.docks.stacked(corner, below: below, layout: scene.layout)
        return PlacedPanel(drag: poppedDrag, rest: rest, size: scene.layout.panelSize, content: HydraPanel(
            runtime: runtime,
            heads: [popped],
            size: scene.layout.panelSize,
            workingDirectory: workingDirectory,
            projectName: project?.name,
            isPoppedOut: true,
            onDrag: { translation in
                let position = poppedDrag.move(by: translation, from: rest, in: scene.layout)
                dock(\.hydraPoppedPanelDock, nearest: position, scene: scene)
            },
            onDragEnd: {
                if let heading = poppedDrag.release() {
                    dock(\.hydraPoppedPanelDock, nearest: heading, scene: scene)
                }
            },
            dismiss: {
                // Back into the team panel, and onto its stage.
                withAnimation(Chrome.panelSlide) {
                    runtime.hydraSelectedHeadID = popped.id
                    runtime.hydraPoppedHeadID = nil
                }
            }
        )
        .transition(Self.panelTransition), resize: resizer(for: corner, scene: scene), isResizing: panelResize.isActive)
        .id(popped.id)
    }

    /// The usage panel: beyond whichever panels are in the same corner, so it is the last
    /// of a stack. Across the column from the heads by default, at the left.
    private func usagePanel(_ usage: PanelUsage, scene: PanelScene) -> some View {
        let corner = runtime.usagePanelDock
        let below = [
            scene.isDocked && runtime.subagentPanelDock == corner,
            scene.isHydraDocked && runtime.hydraPanelDock == corner,
            scene.showsPopped && runtime.hydraPoppedPanelDock == corner,
        ].count { $0 }
        let rest = scene.docks.stacked(corner, below: below, layout: scene.layout)
        return PlacedPanel(drag: usageDrag, rest: rest, size: scene.layout.panelSize, content: UsageFloatingPanel(
            runtime: runtime,
            provider: usage.provider,
            headsProvider: usage.headsProvider,
            size: scene.layout.panelSize,
            onDrag: { translation in
                let position = usageDrag.move(by: translation, from: rest, in: scene.layout)
                dock(\.usagePanelDock, nearest: position, scene: scene)
            },
            onDragEnd: {
                if let heading = usageDrag.release() {
                    dock(\.usagePanelDock, nearest: heading, scene: scene)
                }
            },
            dismiss: {
                // For this chat alone; the usage popover's expand button brings it back.
                withAnimation(Chrome.panelSlide) {
                    runtime.isUsagePanelShown = false
                }
            }
        )
        .transition(Self.panelTransition), resize: resizer(for: corner, scene: scene), isResizing: panelResize.isActive)
    }

    /// The grips of a panel docked in `corner`. A pull on a free edge grows the panel away
    /// from its corner; the size is kept in Settings for every chat's panels, fitted to
    /// this pane's room, so it follows the pointer here and the window's size after.
    private func resizer(for corner: PanelDockCorner, scene: PanelScene) -> PanelResize {
        PanelResize(
            corner: corner,
            onResize: { translation, axes in
                let start = panelResize.begin(at: scene.layout.panelSize)
                // The pointer's travel runs right and down; a panel docked at the right
                // grows leftwards, one docked at the bottom grows upwards.
                let acrossSign: CGFloat = corner.side == .trailing ? -1 : 1
                let downSign: CGFloat = corner.isTop ? 1 : -1
                var next = start
                if axes.contains(.width) { next.width += translation.width * acrossSign }
                if axes.contains(.height) { next.height += translation.height * downSign }
                model.settings.panelSize = scene.layout.fitted(next)
            },
            onResizeEnd: { panelResize.end() },
            onReset: {
                withAnimation(Chrome.panelSlide) { model.settings.panelSize = nil }
            }
        )
    }

    /// A panel grows in and fades out in place.
    private static var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
    }

    /// Docks a panel in the corner nearest to `position`. Called as the panel is held as
    /// well as when it is let go, so the chat makes room on the new side while the panel
    /// is still under the pointer, and the panel has its spot the moment it is dropped.
    private func dock(_ corner: ReferenceWritableKeyPath<ThreadRuntime, PanelDockCorner>, nearest position: CGPoint, scene: PanelScene) {
        let next = scene.layout.dockCorner(nearest: position, keeping: runtime[keyPath: corner], docks: scene.docks)
        guard next != runtime[keyPath: corner] else { return }
        runtime[keyPath: corner] = next
    }
}

/// Which threads sit in the chat's floating panels. Read from the model once per
/// body, apart from the pane measurements: a live resize then re-lays out geometry
/// without walking any thread list again.
@MainActor
private struct PanelMembers {
    let subagent: ChatThread?
    let isDocked: Bool
    let heads: [ChatThread]
    let popped: ChatThread?
    let isHydraHidden: Bool
    /// The usage panel's providers, when this chat shows one: the chat's own, and the
    /// pair's heads provider when that is another, so both plans' limits stack.
    let usage: PanelUsage?

    init(runtime: ThreadRuntime, model: AppModel) {
        // Both lists come from this chat's own children (see `panelHeads(of:)`), so a head
        // of another chat writing its status leaves this whole body alone.
        subagent = model.panelSubagent(of: runtime.threadID)
        isDocked = subagent != nil
        isHydraHidden = runtime.isHydraPanelHidden
        let team = isHydraHidden ? [] : model.panelHeads(of: runtime.threadID)
        let poppedHead = team.count > 1 ? team.first { $0.id == runtime.hydraPoppedHeadID } : nil
        popped = poppedHead
        heads = team.filter { $0.id != poppedHead?.id }
        // The chat's own word first, the setting when it has none (see `isUsagePanelShown`).
        if let thread = model.thread(runtime.threadID), runtime.isUsagePanelShown ?? model.settings.showsUsagePanel {
            var headsProvider: ProviderKind?
            if model.hydraIsOn(thread), let pair = model.hydraPair(for: thread) {
                let provider = model.hydraHeadsProvider(of: pair)
                headsProvider = provider == thread.provider ? nil : provider
            }
            usage = PanelUsage(provider: thread.provider, headsProvider: headsProvider)
        } else {
            usage = nil
        }
    }
}

/// Whose limits the usage panel shows: the chat's provider, and the heads' when a pair
/// sends them out on another.
struct PanelUsage: Equatable {
    let provider: ProviderKind
    let headsProvider: ProviderKind?
}

/// Everything the chat's floating panels need in one place, worked out once per body:
/// which panels there are, which are docked where, the room they take, and their spots.
@MainActor
private struct PanelScene {
    let layout: SubagentPanelLayout
    /// The helper this thread spawned, if it still has its panel open. It sits in a corner
    /// and takes room from that side of the chat column, so the conversation and the box
    /// centre in the rest and sit beside it.
    let subagent: ChatThread?
    let isDocked: Bool
    /// The team, in its own panel: next to the helper panel when both dock in one corner.
    /// One head can be popped out into a second panel, which leaves the team panel's
    /// list; it only stays out while another head is left behind to keep that panel.
    let heads: [ChatThread]
    let popped: ChatThread?
    /// The usage panel's providers, when the chat shows one (see `PanelMembers`).
    let usage: PanelUsage?
    let isMeasured: Bool
    let showsHydra: Bool
    let showsPopped: Bool
    let showsUsage: Bool
    let isHydraDocked: Bool
    /// The sides with a panel docked on them, in a fixed order, as the key for the slides
    /// that make room: it changes with a dock, never with a measurement.
    let dockedSides: [PanelDockSide]
    let reserve: PanelReserve
    let docks: PanelDocks

    var hasHeads: Bool { !heads.isEmpty }

    init(members: PanelMembers, runtime: ThreadRuntime, model: AppModel, paneSize: CGSize, composerAreaHeight: CGFloat) {
        let geometry = Self.geometry(members: members, runtime: runtime, model: model, paneSize: paneSize, composerAreaHeight: composerAreaHeight)
        subagent = members.subagent
        isDocked = members.isDocked
        heads = members.heads
        popped = members.popped
        usage = members.usage
        isMeasured = geometry.isMeasured
        showsHydra = geometry.showsHydra
        showsPopped = geometry.showsPopped
        showsUsage = geometry.showsUsage
        isHydraDocked = geometry.isHydraDocked
        dockedSides = geometry.dockedSides
        layout = geometry.layout
        reserve = geometry.reserve
        docks = geometry.docks
    }

    /// The geometry alone, from the members and the measured pane: what a resize frame
    /// recomputes, with no model reads of its own.
    struct Geometry {
        let layout: SubagentPanelLayout
        let isMeasured: Bool
        let showsHydra: Bool
        let showsPopped: Bool
        let showsUsage: Bool
        let isHydraDocked: Bool
        let dockedSides: [PanelDockSide]
        let reserve: PanelReserve
        let docks: PanelDocks
    }

    static func geometry(members: PanelMembers, runtime: ThreadRuntime, model: AppModel, paneSize: CGSize, composerAreaHeight: CGFloat) -> Geometry {
        let isMeasured = paneSize != .zero
        let showsHydra = !members.heads.isEmpty && isMeasured
        let showsPopped = members.popped != nil && showsHydra
        let showsUsage = members.usage != nil && isMeasured
        let isHydraDocked = showsHydra
        let isPoppedDocked = showsPopped
        var corners: [PanelDockCorner] = []
        if members.isDocked { corners.append(runtime.subagentPanelDock) }
        if isHydraDocked { corners.append(runtime.hydraPanelDock) }
        if isPoppedDocked { corners.append(runtime.hydraPoppedPanelDock) }
        if showsUsage { corners.append(runtime.usagePanelDock) }
        let sides = Set(corners.map(\.side))
        let dockedSides = [PanelDockSide.leading, .trailing].filter(sides.contains)
        // Panels docked in one corner stack, so they share its height between them.
        let stackDepth = Dictionary(grouping: corners, by: { $0 }).values.map(\.count).max() ?? 1
        // Every panel shows a head's progress bar rather than a conversation: the heads'
        // with "Show what heads are doing" off, and the helper panel only when it holds a
        // head too (a helper of the user's own keeps its chat, so it keeps the full height).
        let helperShowsProgress = members.subagent?.isHydraHead ?? true
        let compact = !model.settings.hydraShowsHeadDetails && helperShowsProgress && (showsHydra || members.subagent != nil)
        let layout = SubagentPanelLayout(pane: paneSize, composerAreaHeight: composerAreaHeight, stackDepth: stackDepth, preferred: model.settings.panelSize, compact: compact)
        let reserve = PanelReserve(
            leading: sides.contains(.leading) ? layout.composerReserve : 0,
            trailing: sides.contains(.trailing) ? layout.composerReserve : 0
        )
        return Geometry(
            layout: layout,
            isMeasured: isMeasured,
            showsHydra: showsHydra,
            showsPopped: showsPopped,
            showsUsage: showsUsage,
            isHydraDocked: isHydraDocked,
            dockedSides: dockedSides,
            reserve: reserve,
            docks: PanelDocks(layout: layout, reserve: reserve)
        )
    }
}

/// The "jump to latest" button floating above the chat box while the reader is scrolled up.
struct JumpToLatestButton: View {
    let scrollState: TimelineScrollState

    var body: some View {
        if scrollState.showsJumpButton {
            ChromeCircleButton(symbol: "arrow.down", help: "Jump to latest") {
                scrollState.jumpToLatest()
            }
            .padding(.bottom, 10)
            .frame(height: 0, alignment: .bottom)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.6).combined(with: .opacity).combined(with: .offset(y: 10)),
                    removal: .scale(scale: 0.85).combined(with: .opacity).combined(with: .offset(y: 6))
                )
            )
        }
    }
}

/// The sticky glass controls across the top of the conversation.
private struct ChatChromeRow: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let title: String
    let project: Project?
    let directory: String
    let git: GitStatusModel

    var body: some View {
        // Follows the buttons, not the sidebar's state: they leave for the sidebar only once it
        // is wide enough to hold them, and the row closes up as they go.
        let sidebarVisible = model.sidebar.holdsTrafficLights
        // One glass pass for the whole row. The row floats over the conversation, so its
        // capsules sample fresh content on every scrolled frame; drawn separately, each was
        // a pass of its own. The spacing is well under the gaps, so nothing morphs together.
        GlassEffectContainer(spacing: 2) {
            HStack(alignment: .center, spacing: 10) {
                // With the sidebar away, its list is one press away: the button arrives with the
                // window buttons and leaves with them.
                if !sidebarVisible {
                    ThreadsButton()
                        .transition(.softAppear)
                }
                ChromeCircleButton(symbol: "square.and.pencil", help: "New thread" + ShortcutStore.hint(for: .newThread)) {
                    model.newThread(in: project)
                }
                if let thread = model.thread(runtime.threadID) {
                    // The team mark, once Hydra is on in Settings: always active in every
                    // chat until switched off there. A head leads no team of its own.
                    if model.settings.hydraEnabled, !thread.isHelper {
                        HydraButton(thread: thread, runtime: runtime)
                            .transition(.softAppear)
                    }
                    PermissionMenu(thread: thread)
                }
                if git.isRepository {
                    BranchMenu(runtime: runtime, directory: directory, git: git)
                }
                ChatChromeTitle(runtime: runtime, title: title)
                    // The thread's title cuts on a switch; it must never crossfade.
                    // Animated, the old and new titles ghost over each other
                    // mid-flight. Scroll progress still drives it per frame.
                    .animation(nil, value: title)
                HStack(spacing: 8) {
                    ChromeCapsule {
                        OpenInMenu(directory: directory)
                        if let project {
                            ChromeDivider()
                            ScriptsMenu(project: project, runtime: runtime, directory: directory)
                        }
                        if git.isRepository {
                            ChromeDivider()
                            GitActionsMenu(runtime: runtime, directory: directory, git: git)
                        }
                    }
                    ChromeCapsule {
                        ChromeIconButton(symbol: "terminal", isActive: runtime.isTerminalVisible, help: "Terminal" + ShortcutStore.hint(for: .toggleTerminal)) {
                            runtime.isTerminalVisible.toggle()
                        }
                        ChromeDivider()
                        ChromeIconButton(symbol: "plusminus", isActive: runtime.isDiffVisible, help: "Changes" + ShortcutStore.hint(for: .toggleChanges)) {
                            runtime.toggleDiff()
                        }
                    }
                }
            }
        }
        // With the sidebar hidden the native window buttons sit over this row, so it steps clear of them.
        .padding(.leading, sidebarVisible ? 0 : Chrome.trafficLightsWidth + Chrome.trafficLightClearance)
        .padding(.horizontal, Chrome.chromeHorizontalPadding)
        .padding(.top, Chrome.chromeTopPadding)
        .animation(Chrome.panelSlide, value: sidebarVisible)
    }
}

/// The thread title in the chrome row, next to the branch picker. A real Button so the
/// extended title bar (which drags the window from this row's gaps) never swallows the
/// click: buttons take their presses while the gaps around them still move the window.
/// Always visible; the scroll-faded compact title it replaces stayed invisible and
/// untappable at rest.
private struct ChatChromeTitle: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let title: String

    @State private var isPresented = false
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        Button {
            renameText = title
            isPresented.toggle()
        } label: {
            Text(verbatim: title.isEmpty ? "New thread" : title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(title.isEmpty ? Chrome.secondaryText : Chrome.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help("Thread title — click to copy or rename")
        .accessibilityLabel(Text("Thread title"))
        .accessibilityAddTraits(.isButton)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PopoverMenu {
                PopoverSectionHeader("Thread title")
                PopoverItem("Copy title", symbol: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(title, forType: .string)
                }
                PopoverItem("Rename…", symbol: "pencil") {
                    renameText = title
                    isRenaming = true
                }
            }
        }
        .alert("Rename thread", isPresented: $isRenaming) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                model.rename(runtime.threadID, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// The sidebar's list in a popover, for a hidden sidebar: the same search, the same rows,
/// the same footer, at the sidebar's own width. Picking a thread closes it.
private struct ThreadsButton: View {
    @Environment(AppModel.self) private var model
    @State private var isPresented = false

    var body: some View {
        ChromeCircleButton(symbol: "list.bullet", help: "Threads") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SidebarView(inPopover: true, dismiss: { isPresented = false })
                .frame(width: model.sidebar.width, height: 560)
                .presentedChrome()
        }
    }
}

@MainActor
@Observable
final class GitStatusModel {
    private(set) var isRepository = false
    private(set) var status: GitStatus?
    private(set) var branches: [GitBranch] = []
    private(set) var remoteURL: URL?
    private(set) var activity: String?

    private struct Snapshot {
        var isRepository = false
        var status: GitStatus?
        var branches: [GitBranch] = []
        var remoteURL: URL?
        var fetchedAt = Date.now
    }

    /// The last read per directory, shared by every chat. Switching threads shows the branch at
    /// once and only runs git again when the read is stale, a turn changed files, or forced.
    private static var snapshots: [String: Snapshot] = [:]
    private static let freshness: TimeInterval = 30

    func refresh(_ directory: String, force: Bool = true) async {
        if let cached = Self.snapshots[directory] {
            apply(cached)
            if !force, Date.now.timeIntervalSince(cached.fetchedAt) < Self.freshness { return }
        }
        let git = Git(directory)
        var snapshot = Snapshot(isRepository: await git.isRepository())
        if snapshot.isRepository {
            async let status = git.status()
            async let branches = git.branches()
            async let remoteURL = git.remoteWebURL()
            snapshot.status = await status
            snapshot.branches = await branches
            snapshot.remoteURL = await remoteURL
        }
        snapshot.fetchedAt = .now
        Self.snapshots[directory] = snapshot
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        isRepository = snapshot.isRepository
        status = snapshot.status
        branches = snapshot.branches
        remoteURL = snapshot.remoteURL
    }

    func perform(_ activity: String, _ work: () async throws -> Void) async -> Error? {
        self.activity = activity
        defer { self.activity = nil }
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }
}

/// The thread's permission level: how much the agent may do without asking.
private struct PermissionMenu: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        ChromeCircleMenu(symbol: thread.runtimeMode.symbol, help: "\(thread.runtimeMode.title) · \(thread.runtimeMode.summary)") {
            PopoverSectionHeader("Permissions")
            ForEach(RuntimeMode.allCases) { mode in
                PopoverItem(mode.title, symbol: mode.symbol, isChecked: thread.runtimeMode == mode) {
                    model.updateThread(thread.id) { $0.runtimeMode = mode }
                }
            }
        }
    }
}

private struct BranchMenu: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var isNamingBranch = false
    @State private var branchName = ""

    var body: some View {
        ChromeTextMenu(
            symbol: "arrow.triangle.branch",
            title: git.activity ?? git.status?.branch ?? "Detached",
            help: "Branch"
        ) {
            PopoverSectionHeader("Switch branch")
            ForEach(git.branches.prefix(25)) { branch in
                PopoverItem(
                    branch.name,
                    isChecked: branch.isCurrent,
                    isEnabled: !branch.isCurrent && !runtime.isRunning
                ) {
                    switchBranch(branch.name)
                }
            }
            PopoverDivider()
            PopoverItem("New branch…", symbol: "plus") {
                branchName = ""
                isNamingBranch = true
            }
            if runtime.thread?.worktreePath == nil, runtime.turns.isEmpty {
                PopoverItem("Use a new worktree for this thread", symbol: "square.stack.3d.up") {
                    Task { await model.createWorktree(for: runtime.threadID) }
                }
            }
        }
        .alert("New branch", isPresented: $isNamingBranch) {
            TextField("Branch name", text: $branchName)
            Button("Create") { createBranch() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func switchBranch(_ name: String) {
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Switching", { try await repository.switchBranch(name) }) {
                model.alert = AppAlert(title: "Could not switch branch", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }

    private func createBranch() {
        let name = branchName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        guard !name.isEmpty else { return }
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Creating", { try await repository.createBranch(name) }) {
                model.alert = AppAlert(title: "Could not create branch", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }
}

private struct OpenInMenu: View {
    let directory: String

    var body: some View {
        ChromeMenuButton(symbol: "arrow.up.forward.app", help: "Open in another app") {
            PopoverSectionHeader("Open in")
            PopoverItem("Finder", image: Workspace.finderIcon) {
                NSWorkspace.shared.open(URL(fileURLWithPath: directory))
            }
            ForEach(Workspace.installedEditors) { editor in
                PopoverItem(editor.name, symbol: "chevron.left.forwardslash.chevron.right", image: Workspace.icon(for: editor)) {
                    Workspace.open(directory, with: editor)
                }
            }
            PopoverDivider()
            PopoverItem("Copy path", symbol: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(directory, forType: .string)
            }
        }
    }
}

private struct ScriptsMenu: View {
    @Environment(AppModel.self) private var model
    let project: Project
    let runtime: ThreadRuntime
    let directory: String

    @State private var isEditing = false

    var body: some View {
        ChromeMenuButton(symbol: "play", help: "Run a project script") {
            if !project.scripts.isEmpty {
                PopoverSectionHeader("Scripts")
                ForEach(project.scripts) { script in
                    PopoverItem(script.name, symbol: script.symbol) {
                        model.terminals.run(script, threadID: runtime.threadID, directory: directory)
                        runtime.isTerminalVisible = true
                    }
                }
                PopoverDivider()
            }
            PopoverItem(project.scripts.isEmpty ? "Add a script…" : "Edit scripts…", symbol: project.scripts.isEmpty ? "plus" : "pencil") {
                isEditing = true
            }
        }
        .sheet(isPresented: $isEditing) {
            ScriptsEditor(projectID: project.id)
                .presentedChrome()
        }
    }
}

private struct GitActionsMenu: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var isCommitting = false

    var body: some View {
        let changed = git.status?.changedFiles ?? 0
        ChromeMenuButton(symbol: "arrow.triangle.pull", help: changed == 0 ? "Commit, push and open pull requests" : "\(changed) changed files") {
            PopoverNote(changed == 1 ? "1 changed file" : "\(changed) changed files")
            PopoverDivider()
            PopoverItem("Commit…", symbol: "checkmark.circle", isEnabled: changed > 0) { isCommitting = true }
            PopoverItem("Push", symbol: "arrow.up.circle") { push() }
            PopoverItem("Create pull request", symbol: "arrow.triangle.pull") { openPullRequest() }
            if let url = git.remoteURL {
                PopoverDivider()
                PopoverItem("Open repository", symbol: "safari") { NSWorkspace.shared.open(url) }
            }
        }
        .sheet(isPresented: $isCommitting) {
            CommitSheet(runtime: runtime, directory: directory, git: git)
                .presentedChrome()
        }
    }

    private func push() {
        Task {
            let repository = Git(directory)
            if let error = await git.perform("Pushing", { try await repository.push() }) {
                model.alert = AppAlert(title: "Push failed", message: error.localizedDescription)
            }
            await git.refresh(directory)
        }
    }

    private func openPullRequest() {
        Task {
            let repository = Git(directory)
            var url: URL?
            let error = await git.perform("Opening pull request") {
                try await repository.push()
                let subject = (try? await repository.output(["log", "-1", "--pretty=%s"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let body = (try? await repository.output(["log", "-1", "--pretty=%b"]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                url = try await repository.createPullRequest(
                    title: subject.isEmpty ? "Update" : subject,
                    body: body.isEmpty ? "Opened from Droppy Code." : body
                )
            }
            if let error {
                model.alert = AppAlert(title: "Could not open a pull request", message: error.localizedDescription)
            } else if let url {
                NSWorkspace.shared.open(url)
            }
            await git.refresh(directory)
        }
    }
}

private struct CommitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let runtime: ThreadRuntime
    let directory: String
    let git: GitStatusModel

    @State private var message = ""
    @State private var summary = ""
    @State private var isGenerating = false
    @State private var isCommitting = false
    @State private var pushesAfterCommit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Commit changes")
                .font(.system(size: 17, weight: .semibold))
            if !summary.isEmpty {
                ScrollView {
                    Text(summary)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
                .padding(10)
                .background(Chrome.overlay(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if message.isEmpty {
                    Text(isGenerating ? "Writing a message…" : "Commit message")
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 130)
            .background(Chrome.overlay(0.05), in: .rect(cornerRadius: 12, style: .continuous))
            HStack(spacing: 12) {
                // Nothing writes the message with text generation off or its provider signed
                // out, so the button says where to turn it on instead of doing nothing.
                let canGenerate = model.textEngine(preferring: runtime.thread?.provider) != nil
                Button {
                    Task { await generate() }
                } label: {
                    Label {
                        Text("Write for me")
                    } icon: {
                        if isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                }
                .buttonStyle(.glass)
                .disabled(isGenerating || !canGenerate)
                .help(canGenerate ? "Write a commit message from these changes" : "Turn on text generation in Settings > Source control")
                Toggle("Push after committing", isOn: $pushesAfterCommit)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                Button("Commit") { Task { await commit() } }
                    .buttonStyle(.glassProminent)
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCommitting)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            let changes = await Git(directory).workingChanges()
            summary = changes.summary
            if message.isEmpty { await generate(changes: changes) }
        }
    }

    private func generate(changes: (summary: String, patch: String)? = nil) async {
        guard let engine = model.textEngine(preferring: runtime.thread?.provider) else { return }
        isGenerating = true
        defer { isGenerating = false }
        let resolved: (summary: String, patch: String)
        if let changes {
            resolved = changes
        } else {
            resolved = await Git(directory).workingChanges()
        }
        if let text = await TextGeneration.commitMessage(
            summary: resolved.summary,
            patch: resolved.patch,
            instructions: model.settings.commitInstructions,
            engine: engine,
            directory: URL(fileURLWithPath: directory)
        ) {
            message = text
        }
    }

    private func commit() async {
        isCommitting = true
        defer { isCommitting = false }
        let repository = Git(directory)
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let pushes = pushesAfterCommit
        let error = await git.perform("Committing") {
            try await repository.commitAll(message: text)
            if pushes { try await repository.push() }
        }
        await git.refresh(directory)
        if let error {
            model.alert = AppAlert(title: "Commit failed", message: error.localizedDescription)
        } else {
            dismiss()
        }
    }
}

private struct ScriptsEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID

    @State private var scripts: [ProjectScript] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Project scripts")
                .font(.system(size: 17, weight: .semibold))
            Text("Scripts run in a terminal at the project root. Droppy Code also picks up scripts from droppy-code.json.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($scripts) { $script in
                        ChromeCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TextField("Name", text: $script.name)
                                        .textFieldStyle(.roundedBorder)
                                    Button(role: .destructive) {
                                        scripts.removeAll { $0.id == script.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                TextField("Command", text: $script.command)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                    // A script with no command used to be dropped on save
                                    // without a word; the row says what it is missing.
                                    .overlay {
                                        if Self.isIncomplete(script) {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(Chrome.danger.opacity(0.65), lineWidth: 1)
                                        }
                                    }
                                Toggle("Run when a worktree is created", isOn: $script.runOnWorktreeCreate)
                                    .toggleStyle(.checkbox)
                            }
                            .padding(14)
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button {
                    scripts.append(ProjectScript(name: "New script", command: ""))
                } label: {
                    Label("Add script", systemImage: "plus")
                }
                .buttonStyle(.glass)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                let incomplete = scripts.contains(where: Self.isIncomplete)
                Button("Save") {
                    model.updateProject(projectID) { $0.scripts = scripts }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .disabled(incomplete)
                .help(incomplete ? "Every script needs a command." : "Save these scripts")
            }
        }
        .padding(20)
        .frame(width: 580, height: 460)
        .onAppear { scripts = model.project(projectID)?.scripts ?? [] }
    }

    /// A script with nothing to run. Saving is held until every row has a command.
    private static func isIncomplete(_ script: ProjectScript) -> Bool {
        script.command.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
