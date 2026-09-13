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
                Picker("Changes", selection: $runtime.diffSelection) {
                    Text("All changes").tag(UUID?.none)
                    if !changedTurns.isEmpty { Divider() }
                    ForEach(changedTurns) { turn in
                        Text("Turn \(turn.index + 1)").tag(UUID?.some(turn.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                if !files.isEmpty {
                    Text(files.count == 1 ? "1 file" : "\(files.count) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DiffStatLabel(
                        additions: files.reduce(0) { $0 + $1.additions },
                        deletions: files.reduce(0) { $0 + $1.deletions }
                    )
                }
                Menu {
                    Button("Expand all") { collapsed.removeAll() }
                    Button("Collapse all") { collapsed = Set(files.map(\.id)) }
                    if canRevertSelection {
                        Divider()
                        Button("Revert this turn…", role: .destructive) { isConfirmingRevert = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
        files = await Self.parse(patch)
    }

    @concurrent
    private nonisolated static func parse(_ patch: String) async -> [DiffFile] {
        DiffParser.parse(patch)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(file.hunks) { hunk in
                if showsLineNumbers {
                    Text(hunk.header)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.06))
                }
                ForEach(hunk.lines) { line in
                    DiffLineRow(line: line, showsLineNumbers: showsLineNumbers)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .textSelection(.enabled)
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let showsLineNumbers: Bool

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
        .background(background)
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
