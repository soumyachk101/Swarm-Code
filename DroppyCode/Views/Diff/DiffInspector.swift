import SwiftUI

struct DiffInspector: View {
    @Environment(AppModel.self) private var model
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
        .task(id: loadKey) { await load() }
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
        guard let thread = model.thread(runtime.threadID), let project = model.project(thread.projectID) else { return }
        let git = Git(thread.worktreePath ?? project.path)
        let selectedTurns = runtime.diffSelection.map { selection in runtime.turns.filter { $0.id == selection } } ?? runtime.turns
        let touched = Set(selectedTurns.flatMap { $0.touchedPaths ?? [] })
        // Turns recorded before edited files were tracked have none, and show everything as before.
        let filtersToThread = selectedTurns.contains { $0.touchedPaths != nil }
        isLoading = true
        defer { isLoading = false }
        let turns = runtime.turns
        var patch = ""
        if let selection = runtime.diffSelection, let turn = turns.first(where: { $0.id == selection }) {
            if let base = turn.baseCheckpoint, let end = turn.endCheckpoint {
                patch = (try? await git.diff(from: base, to: end)) ?? ""
            } else {
                patch = turn.providerDiff ?? ""
            }
        } else {
            let captured = turns.filter { $0.baseCheckpoint != nil && $0.endCheckpoint != nil }
            if let first = captured.first?.baseCheckpoint, let last = captured.last?.endCheckpoint {
                patch = (try? await git.diff(from: first, to: last)) ?? ""
            } else {
                patch = turns.compactMap(\.providerDiff).joined(separator: "\n")
            }
        }
        files = await Self.parse(patch, touched: filtersToThread ? touched : nil)
    }

    @concurrent
    private nonisolated static func parse(_ patch: String, touched: Set<String>?) async -> [DiffFile] {
        let files = DiffParser.parse(patch)
        guard let touched else { return files }
        return files.filter { TouchedPaths.matches($0, touched: touched) }
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
        VStack(alignment: .leading, spacing: 0) {
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
                    VStack(alignment: .leading, spacing: 0) {
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
