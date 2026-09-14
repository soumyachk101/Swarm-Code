import AppKit
import SwiftUI

struct DiffInspector: View {
    let runtime: ThreadRuntime

    @State private var files: [DiffFile] = []
    @State private var isLoading = false
    @State private var collapsed: Set<String> = []
    @State private var isConfirmingRevert = false

    private var changedTurns: [TurnRecord] {
        runtime.turns.filter { $0.endCheckpoint != nil || $0.providerDiff != nil }
    }

    private var loadKey: String {
        "\(runtime.diffRevision)-\(runtime.diffSelection?.uuidString ?? "all")"
    }

    var body: some View {
        @Bindable var runtime = runtime
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 10) {
                    ChromeTextMenu(
                        symbol: "plusminus",
                        title: runtime.diffSelection
                            .flatMap { id in runtime.turns.first { $0.id == id } }
                            .map { "Turn \($0.index + 1)" } ?? "All changes",
                        help: "Choose which changes to show"
                    ) {
                        PopoverItem("All changes", isChecked: runtime.diffSelection == nil) {
                            runtime.diffSelection = nil
                        }
                        ForEach(changedTurns) { turn in
                            PopoverItem("Turn \(turn.index + 1)", isChecked: runtime.diffSelection == turn.id) {
                                runtime.diffSelection = turn.id
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if !files.isEmpty {
                        Text(files.count == 1 ? "1 file" : "\(files.count) files")
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                        DiffStatLabel(
                            additions: files.reduce(0) { $0 + $1.additions },
                            deletions: files.reduce(0) { $0 + $1.deletions }
                        )
                    }
                    ChromeCapsule {
                        ChromeMenuButton(symbol: "ellipsis", help: "More") {
                            PopoverItem("Expand all", symbol: "arrow.down.right.and.arrow.up.left") { collapsed.removeAll() }
                            PopoverItem("Collapse all", symbol: "arrow.up.left.and.arrow.down.right") { collapsed = Set(files.map(\.id)) }
                            if canRevertSelection {
                                PopoverDivider()
                                PopoverItem("Revert this turn…", symbol: "arrow.uturn.backward", isDestructive: true) {
                                    isConfirmingRevert = true
                                }
                            }
                        }
                        ChromeDivider()
                        ChromeIconButton(symbol: "xmark", help: "Hide changes (⌘D)") {
                            runtime.isDiffVisible = false
                        }
                    }
                }
            }
            .padding(.horizontal, Chrome.chromeHorizontalPadding)
            .padding(.top, Chrome.chromeTopPadding)
            .padding(.bottom, 10)

            if files.isEmpty {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        ContentUnavailableView(
                            "No changes yet",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Files the agent changes appear here after each turn.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(files) { file in
                            DiffFileCard(file: file, isCollapsed: collapsed.contains(file.id)) {
                                if collapsed.contains(file.id) { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task(id: loadKey) {
            // Let the popover appear first. Kicking off git + parse + a big view build
            // in the same transaction is what made opening feel laggy: the empty
            // popover appears cheaply, content fills in right after.
            // A diff the runtime already parsed skips the wait and fills in at once.
            if !runtime.hasCachedDiff(selection: runtime.diffSelection) {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .confirmationDialog("Revert this turn?", isPresented: $isConfirmingRevert) {
            Button("Revert files and conversation", role: .destructive) {
                guard let turnID = runtime.diffSelection else { return }
                Task { await runtime.revert(to: turnID, restoreFiles: true) }
            }
        } message: {
            Text("Files go back to how they were before this turn, and the turn leaves the conversation.")
        }
    }

    private var canRevertSelection: Bool {
        guard runtime.diffSelection != nil, !runtime.isRunning, let thread = runtime.thread else { return false }
        return thread.provider.supportsRewind
    }

    private func load() async {
        let selection = runtime.diffSelection
        let selectedTurns = selection.map { selection in runtime.turns.filter { $0.id == selection } } ?? runtime.turns
        let touched = Set(selectedTurns.flatMap { $0.touchedPaths ?? [] })
        // Turns recorded before edited files were tracked have none, and show everything as before.
        let filtersToThread = selectedTurns.contains { $0.touchedPaths != nil }
        isLoading = true
        defer { isLoading = false }
        let parsed = await runtime.parsedDiff(selection: selection)
        guard !Task.isCancelled else { return }
        let filtered = filtersToThread ? parsed.filter { TouchedPaths.matches($0, touched: touched) } : parsed
        files = Array(filtered.prefix(120))
        // Opening with every file expanded materializes thousands of rows in the same
        // transaction as the slide, which is the visible hitch. Keep the first file open
        // and collapse the rest when there are many; one tap expands any of them.
        if files.count > 6, collapsed.isEmpty {
            collapsed = Set(files.dropFirst().map(\.id))
        } else {
            collapsed = collapsed.intersection(files.map(\.id))
        }
    }
}

private struct DiffFileCard: View {
    let file: DiffFile
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                    Text("\(Text(file.directory).foregroundStyle(.secondary))\(file.name)")
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 8)
                    DiffStatLabel(additions: file.additions, deletions: file.deletions)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                if file.isBinary {
                    Text("Binary file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                } else {
                    DiffLinesView(file: file)
                        .padding(.bottom, 6)
                }
            }
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12, style: .continuous))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private var symbol: String {
        switch file.change {
        case .added: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed: "arrow.right.circle.fill"
        case .modified: "pencil.circle.fill"
        }
    }

    private var color: Color {
        switch file.change {
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .modified: .orange
        }
    }
}

struct DiffLinesView: View {
    let file: DiffFile
    var showsLineNumbers = true

    @State private var showsAll = false

    /// Large files render collapsed: materializing thousands of rows at once is what
    /// makes opening a diff feel laggy. The full diff is one instant tap away.
    private static let collapsedLineLimit = 200

    private var totalLines: Int {
        file.hunks.reduce(0) { $0 + $1.lines.count }
    }

    /// One visual row group: a hunk header, a joined tinted block, or plain lines.
    /// Tinted runs merge across hunk boundaries (edits often arrive as many
    /// single-line hunks), so only the block's top and bottom lines get corners.
    /// A header that would land inside a merged run is redundant, so it is dropped.
    private enum Section: Identifiable {
        case header(String, Int)
        case tinted([DiffLine])
        case plain([DiffLine])

        var id: String {
            switch self {
            case .header(let text, let index): "h\(index)-\(text)"
            case .tinted(let lines): "t\(lines.first?.id ?? 0)"
            case .plain(let lines): "p\(lines.first?.id ?? 0)"
            }
        }
    }

    private var sections: [Section] {
        var sections: [Section] = []
        var pending: [DiffLine] = []
        var remaining = showsAll ? Int.max : Self.collapsedLineLimit
        func flush() {
            if !pending.isEmpty {
                sections.append(.tinted(pending))
                pending = []
            }
        }
        for (hunkIndex, hunk) in file.hunks.enumerated() {
            guard !hunk.lines.isEmpty, remaining > 0 else { continue }
            let runs = lineBlocks(hunk.lines)
            // Continuing means the previous hunk ended mid-run; anything else
            // flushes and starts fresh below a new header.
            let continues = (runs.first?.isTinted == true) && !pending.isEmpty
            if !continues {
                flush()
                if showsLineNumbers {
                    sections.append(.header(hunk.header, hunkIndex))
                }
            }
            for run in runs {
                guard remaining > 0 else { break }
                if run.isTinted {
                    let take = Array(run.lines.prefix(remaining))
                    remaining -= take.count
                    pending += take
                } else {
                    flush()
                    let take = Array(run.lines.prefix(remaining))
                    remaining -= take.count
                    sections.append(.plain(take))
                }
            }
        }
        flush()
        return sections
    }

    var body: some View {
        // Lazy so a 200-line file only materializes the rows actually on screen;
        // an eager VStack here built every row during the panel-slide animation.
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                switch section {
                case .header(let text, _):
                    Text(text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.06))
                case .tinted(let lines):
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            DiffLineRow(
                                line: line,
                                showsLineNumbers: showsLineNumbers,
                                rounding: DiffLineRow.blockRounding(index: index, count: lines.count)
                            )
                        }
                    }
                case .plain(let lines):
                    ForEach(lines) { line in
                        DiffLineRow(line: line, showsLineNumbers: showsLineNumbers)
                    }
                }
            }
            if !showsAll, totalLines > Self.collapsedLineLimit {
                Button {
                    showsAll.toggle()
                } label: {
                    Text("Show all \(totalLines) lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.5), in: Capsule(style: .continuous))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .textSelection(.enabled)
    }
}

/// A maximal run of lines that share tinting, so a contiguous addition/deletion
/// block draws as one shape: corners only on its top and bottom lines.
private struct DiffLineBlock: Identifiable {
    var lines: [DiffLine]
    var isTinted: Bool

    var id: Int { lines.first?.id ?? 0 }
}

private func lineBlocks(_ lines: [DiffLine]) -> [DiffLineBlock] {
    var blocks: [DiffLineBlock] = []
    for line in lines {
        let tinted = line.kind == .addition || line.kind == .deletion
        if blocks.last?.isTinted == tinted {
            blocks[blocks.count - 1].lines.append(line)
        } else {
            blocks.append(DiffLineBlock(lines: [line], isTinted: tinted))
        }
    }
    return blocks
}

private struct DiffLineRow: View {
    let line: DiffLine
    let showsLineNumbers: Bool
    var rounding = UnevenRoundedRectangle(
        topLeadingRadius: 0, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous
    )

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if showsLineNumbers {
                Text(line.oldNumber.map(String.init) ?? "")
                    .frame(width: 38, alignment: .trailing)
                    .foregroundStyle(.tertiary)
                Text(line.newNumber.map(String.init) ?? "")
                    .frame(width: 38, alignment: .trailing)
                    .foregroundStyle(.tertiary)
            }
            Text(marker)
                .frame(width: 18)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .note ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .background(background, in: rounding)
    }

    /// Positional corners for a row inside its tinted block: only the block's
    /// top and bottom rows get corners, everything between is straight.
    static func blockRounding(index: Int, count: Int) -> UnevenRoundedRectangle {
        let radius: CGFloat = 8
        let top = index == 0
        let bottom = index == count - 1
        return UnevenRoundedRectangle(
            topLeadingRadius: top ? radius : 0,
            bottomLeadingRadius: bottom ? radius : 0,
            bottomTrailingRadius: bottom ? radius : 0,
            topTrailingRadius: top ? radius : 0,
            style: .continuous
        )
    }

    private var marker: String {
        switch line.kind {
        case .addition: "+"
        case .deletion: "−"
        case .context, .note: ""
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        default: .secondary
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        default: .clear
        }
    }
}

/// The thread's diff as a tall, wide popover anchored to the changes tab,
/// instead of a side panel. Semitransient with a pass-through monitor: taps
/// outside close it but still reach their target, so picking another turn's
/// Review opens its diff in a single tap. Closes on Escape, the X button,
/// ⌘D, tapping the tab, or the thread going away.
@MainActor
final class DiffPopoverCoordinator: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 640
    static let height: CGFloat = 540

    private let popover = NSPopover()
    private var anchor: WeakView?
    private var runtime: ThreadRuntime?
    private var desiredVisible = false
    private var monitors: [Any] = []
    /// Bumps on every show and close, so a stale didClose can never clobber a fresh open.
    private var session = 0
    private var pendingSession = 0

    override init() {
        super.init()
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
    }

    /// The changes tab's own view, captured from the tab's background.
    func setAnchor(_ view: NSView) {
        anchor = WeakView(view)
        if desiredVisible { show() }
    }

    /// Drives the popover from `runtime.isDiffVisible`. Call on change and on appear.
    func sync(isVisible: Bool, runtime: ThreadRuntime) {
        self.runtime = runtime
        desiredVisible = isVisible
        if isVisible { show() } else { close() }
    }

    func close() {
        stopMonitors()
        desiredVisible = false
        session += 1
        pendingSession = session
        if popover.isShown { popover.performClose(nil) }
    }

    /// The composer area itself, for when the changes tab is not on screen (the
    /// follow-up queue takes its slot) and the opener brought no view of its own.
    func setFallbackAnchor(_ view: NSView) {
        fallback = WeakView(view)
        if desiredVisible { show() }
    }

    private var fallback: WeakView?
    /// The view the open popover is anchored to.
    private weak var shownOn: NSView?

    /// A Review button asked for the popover: opens it there, moving it if it is
    /// already open on another view.
    func reopen(runtime: ThreadRuntime) {
        self.runtime = runtime
        desiredVisible = true
        if popover.isShown {
            if shownOn === resolvedAnchor() { return }
            stopMonitors()
            session += 1
            pendingSession = session
            popover.close()
        }
        show()
    }

    /// A Review button opens the popover on itself; the tab and ⌘D open it on
    /// the tab, or on the composer while the queue has the tab's slot.
    private func resolvedAnchor() -> NSView? {
        let candidates = [runtime?.diffAnchor?.value, anchor?.value, fallback?.value]
        return candidates.compactMap { $0 }.first { $0.window != nil }
    }

    private func show() {
        guard let runtime, let anchor = resolvedAnchor() else { return }
        session += 1
        guard !popover.isShown else { return }
        popover.setFixedContent(DiffInspector(runtime: runtime), size: NSSize(width: Self.width, height: Self.height))
        startMonitors()
        shownOn = anchor
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    // MARK: - Dismissal

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.stopMonitors()
            self.desiredVisible = false
            // Only the close that posted this may clear the flag: a Review tap
            // that already reopened (newer session) must survive.
            if self.session == self.pendingSession {
                self.runtime?.isDiffVisible = false
            }
        }
    }

    /// Clicks inside the panel pass through; any other click dismisses first
    /// but still reaches its target (e.g. another turn's Review button).
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        if event.window === popover.contentViewController?.view.window { return event }
        close()
        return event
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53 else { return event } // Escape
        close()
        return nil
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            self?.handleMouseDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }) {
            monitors.append(monitor)
        }
    }

    private func stopMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }
}
