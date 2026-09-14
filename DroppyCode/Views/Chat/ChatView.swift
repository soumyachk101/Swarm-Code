import AppKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model
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
    /// The helper panel's corner while its handle is held: where it was grabbed, and where
    /// it is now, moved without animation. Nil at rest.
    @State private var panelGrab: CGPoint?
    @State private var panelDrag: CGPoint?
    /// The same for the Hydra panel, and for the head popped out of it.
    @State private var hydraGrab: CGPoint?
    @State private var hydraDrag: CGPoint?
    @State private var poppedGrab: CGPoint?
    @State private var poppedDrag: CGPoint?

    var body: some View {
        let thread = model.thread(runtime.threadID)
        let project = thread.flatMap { model.project($0.projectID) }
        // The thread and project are read here, once, and passed down as values: the timeline
        // rows and the composer never observe them, so a change to either re-renders this
        // body alone and the children only where what they were handed changed.
        let workingDirectory = thread.flatMap { $0.worktreePath ?? project?.path }
        let directory = workingDirectory ?? LoginEnvironment.homeDirectory
        let title = thread?.title ?? ""
        let scene = PanelScene(runtime: runtime, model: model, paneSize: paneSize, composerAreaHeight: composerAreaHeight)
        VStack(spacing: 0) {
            ThreadTimeline(
                runtime: runtime,
                scrollChrome: scrollChrome,
                scrollState: scrollState,
                projectName: project?.name,
                workingDirectory: workingDirectory,
                supportsRewind: thread?.provider.supportsRewind ?? false,
                columnHeight: columnHeight
            )
            .equatable()
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
                // Toggled from the Hydra button, a ghost of the panel does the moving, so
                // the panel itself comes and goes with no transition of its own while the
                // chat still slides to make room or take it back; dismissed, it fades.
                .animation(runtime.hydraPanelMorphs ? nil : Chrome.panelSlide, value: scene.hasHeads)
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
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { paneSize = $0 }

            if runtime.isTerminalVisible {
                TerminalPanel(runtime: runtime, directory: directory)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .detailSheet()
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

    /// The helper's panel, docked or where it was dragged.
    private func subagentPanel(_ subagent: ChatThread, scene: PanelScene, project: Project?) -> some View {
        let layout = scene.layout
        let origin = panelDrag ?? runtime.subagentPanelOrigin.map(layout.clamped) ?? scene.docks[runtime.subagentPanelDock]
        return SubagentPanel(
            thread: subagent,
            size: layout.panelSize,
            // The helper works in the project folder, whatever this thread's worktree.
            workingDirectory: subagent.worktreePath ?? project?.path,
            projectName: project?.name,
            onDrag: { translation in
                panelDrag = dragged(from: origin, by: translation, grab: &panelGrab, layout: layout)
            },
            onDragEnd: {
                // Dropped into a corner, the panel docks there; anywhere else it stays put.
                let dropped = panelDrag ?? origin
                if let corner = layout.dockCorner(forDrop: dropped, docks: scene.docks) {
                    runtime.subagentPanelDock = corner
                    runtime.subagentPanelOrigin = nil
                } else {
                    runtime.subagentPanelOrigin = dropped
                }
                panelGrab = nil
                panelDrag = nil
            },
            close: {
                // The helper moves to the sidebar under this thread; its row opens with the
                // same slide as the panel leaving.
                withAnimation(Chrome.panelSlide) {
                    model.closeSubagent(subagent.id)
                    runtime.subagentPanelOrigin = nil
                }
            }
        )
        // Inside the offset, so the panel grows in and fades out in place.
        .transition(Self.panelTransition)
        .offset(x: origin.x, y: origin.y)
        // The handle moves it live; only a drop and a resize settle it with a slide.
        .animation(panelDrag == nil ? Chrome.panelSlide : nil, value: origin)
    }

    /// The team's panel: next to the helper panel when that one is docked in the same corner.
    private func hydraPanel(scene: PanelScene, workingDirectory: String?, project: Project?) -> some View {
        let layout = scene.layout
        let corner = runtime.hydraPanelDock
        let dock = scene.docks.stacked(corner, below: scene.isDocked && runtime.subagentPanelDock == corner ? 1 : 0, layout: layout)
        let origin = hydraDrag ?? runtime.hydraPanelOrigin.map(layout.clamped) ?? dock
        return HydraPanel(
            runtime: runtime,
            heads: scene.heads,
            size: layout.panelSize,
            workingDirectory: workingDirectory,
            projectName: project?.name,
            onDrag: { translation in
                hydraDrag = dragged(from: origin, by: translation, grab: &hydraGrab, layout: layout)
            },
            onDragEnd: {
                let dropped = hydraDrag ?? origin
                if let corner = layout.dockCorner(forDrop: dropped, docks: scene.docks) {
                    runtime.hydraPanelDock = corner
                    runtime.hydraPanelOrigin = nil
                } else {
                    runtime.hydraPanelOrigin = dropped
                }
                hydraGrab = nil
                hydraDrag = nil
            },
            popOut: { id in
                // The head's own panel opens docked across the column from the team
                // panel, so the two sit apart.
                withAnimation(Chrome.panelSlide) {
                    runtime.hydraPoppedHeadID = id
                    runtime.hydraPoppedPanelOrigin = nil
                    runtime.hydraPoppedPanelDock = runtime.hydraPanelDock.acrossTheColumn
                    if runtime.hydraSelectedHeadID == id { runtime.hydraSelectedHeadID = nil }
                }
            },
            dismiss: {
                withAnimation(Chrome.panelSlide) {
                    model.dismissHydraHeads(of: runtime.threadID)
                    runtime.hydraPanelOrigin = nil
                }
            }
        )
        .transition(Self.panelTransition)
        .offset(x: origin.x, y: origin.y)
        .animation(hydraDrag == nil ? Chrome.panelSlide : nil, value: origin)
    }

    /// The popped-out head's panel: beyond whichever panels are docked in the same corner.
    private func poppedPanel(_ popped: ChatThread, scene: PanelScene, workingDirectory: String?, project: Project?) -> some View {
        let layout = scene.layout
        let corner = runtime.hydraPoppedPanelDock
        let below = [scene.isDocked && runtime.subagentPanelDock == corner, scene.isHydraDocked && runtime.hydraPanelDock == corner].count { $0 }
        let dock = scene.docks.stacked(corner, below: below, layout: layout)
        let origin = poppedDrag ?? runtime.hydraPoppedPanelOrigin.map(layout.clamped) ?? dock
        return HydraPanel(
            runtime: runtime,
            heads: [popped],
            size: layout.panelSize,
            workingDirectory: workingDirectory,
            projectName: project?.name,
            isPoppedOut: true,
            onDrag: { translation in
                poppedDrag = dragged(from: origin, by: translation, grab: &poppedGrab, layout: layout)
            },
            onDragEnd: {
                let dropped = poppedDrag ?? origin
                if let corner = layout.dockCorner(forDrop: dropped, docks: scene.docks) {
                    runtime.hydraPoppedPanelDock = corner
                    runtime.hydraPoppedPanelOrigin = nil
                } else {
                    runtime.hydraPoppedPanelOrigin = dropped
                }
                poppedGrab = nil
                poppedDrag = nil
            },
            dismiss: {
                // Back into the team panel, and onto its stage.
                withAnimation(Chrome.panelSlide) {
                    runtime.hydraSelectedHeadID = popped.id
                    runtime.hydraPoppedHeadID = nil
                    runtime.hydraPoppedPanelOrigin = nil
                }
            }
        )
        .id(popped.id)
        .transition(Self.panelTransition)
        .offset(x: origin.x, y: origin.y)
        .animation(poppedDrag == nil ? Chrome.panelSlide : nil, value: origin)
    }

    /// A panel grows in and fades out in place.
    private static var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92).combined(with: .opacity),
            removal: .scale(scale: 0.96).combined(with: .opacity)
        )
    }

    /// Where a panel's corner is once the pointer has travelled `translation` from where
    /// its handle was grabbed; the grab is remembered from the first move.
    private func dragged(from origin: CGPoint, by translation: CGSize, grab: inout CGPoint?, layout: SubagentPanelLayout) -> CGPoint {
        let start = grab ?? origin
        if grab == nil { grab = start }
        return layout.clamped(CGPoint(x: start.x + translation.width, y: start.y + translation.height))
    }
}

/// Everything the chat's floating panels need in one place, worked out once per body:
/// which panels there are, which are docked where, the room they take, and their spots.
@MainActor
private struct PanelScene {
    let layout: SubagentPanelLayout
    /// The helper this thread spawned, if it still has its panel open. Docked in a corner,
    /// it takes room from that side of the chat column, so the conversation and the box
    /// centre in the rest and sit beside it; dragged away, they have the column to
    /// themselves again.
    let subagent: ChatThread?
    let isDocked: Bool
    /// The team, in its own panel: next to the helper panel when both dock in one corner.
    /// One head can be popped out into a second panel, which leaves the team panel's
    /// list; it only stays out while another head is left behind to keep that panel.
    let heads: [ChatThread]
    let popped: ChatThread?
    let isMeasured: Bool
    let showsHydra: Bool
    let showsPopped: Bool
    let isHydraDocked: Bool
    /// The sides with a panel docked on them, in a fixed order, as the key for the slides
    /// that make room: it changes with a dock and a drag out, never with a measurement.
    let dockedSides: [PanelDockSide]
    let reserve: PanelReserve
    let docks: PanelDocks

    var hasHeads: Bool { !heads.isEmpty }

    init(runtime: ThreadRuntime, model: AppModel, paneSize: CGSize, composerAreaHeight: CGFloat) {
        layout = SubagentPanelLayout(pane: paneSize, composerAreaHeight: composerAreaHeight)
        isMeasured = paneSize != .zero
        subagent = model.subagent(of: runtime.threadID)
        isDocked = subagent != nil && runtime.subagentPanelOrigin == nil
        let team = runtime.isHydraPanelHidden ? [] : model.hydraHeads(of: runtime.threadID)
        let poppedHead = team.count > 1 ? team.first { $0.id == runtime.hydraPoppedHeadID } : nil
        let teamHeads = team.filter { $0.id != poppedHead?.id }
        popped = poppedHead
        heads = teamHeads
        showsHydra = !teamHeads.isEmpty && isMeasured
        showsPopped = poppedHead != nil && showsHydra
        isHydraDocked = showsHydra && runtime.hydraPanelOrigin == nil
        let isPoppedDocked = showsPopped && runtime.hydraPoppedPanelOrigin == nil
        var corners: [PanelDockCorner] = []
        if isDocked { corners.append(runtime.subagentPanelDock) }
        if isHydraDocked { corners.append(runtime.hydraPanelDock) }
        if isPoppedDocked { corners.append(runtime.hydraPoppedPanelDock) }
        let sides = Set(corners.map(\.side))
        dockedSides = [PanelDockSide.leading, .trailing].filter(sides.contains)
        reserve = PanelReserve(
            leading: sides.contains(.leading) ? layout.composerReserve : 0,
            trailing: sides.contains(.trailing) ? layout.composerReserve : 0
        )
        docks = PanelDocks(layout: layout, reserve: reserve)
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
                ChromeCircleButton(symbol: "square.and.pencil", help: "New thread (⌘N)") {
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
                ChromeCompactTitle(title: title, model: scrollChrome)
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
                        ChromeIconButton(symbol: "terminal", isActive: runtime.isTerminalVisible, help: "Terminal (⌘J)") {
                            runtime.isTerminalVisible.toggle()
                        }
                        ChromeDivider()
                        ChromeIconButton(symbol: "plusminus", isActive: runtime.isDiffVisible, help: "Changes (⌘D)") {
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
                Button {
                    Task { await generate() }
                } label: {
                    Label("Write for me", systemImage: "sparkles")
                }
                .buttonStyle(.glass)
                .disabled(isGenerating)
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
                Button("Save") {
                    let cleaned = scripts.filter { !$0.command.trimmingCharacters(in: .whitespaces).isEmpty }
                    model.updateProject(projectID) { $0.scripts = cleaned }
                    dismiss()
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 580, height: 460)
        .onAppear { scripts = model.project(projectID)?.scripts ?? [] }
    }
}
