import AppKit
import SwiftUI

struct ComposerArea: View {
    let runtime: ThreadRuntime

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 12) {
                ForEach(runtime.approvals) { request in
                    ApprovalCard(request: request, runtime: runtime)
                }
                ForEach(runtime.questions) { request in
                    QuestionCard(request: request, runtime: runtime)
                }
                VStack(alignment: .center, spacing: -ThreadChangesTab.overlap) {
                    if let stats = runtime.changeStats {
                        ThreadChangesTab(stats: stats) {
                            if runtime.diffSelection != nil { runtime.diffSelection = nil }
                            // Set last so a redundant write never restarts the diff load
                            // or steals the panel-slide transaction.
                            if !runtime.isDiffVisible { runtime.isDiffVisible = true }
                        }
                        .transition(.softAppear)
                    }
                    ComposerView(runtime: runtime)
                }
                // NB: no .animation(..., value: changeStats) here on purpose. The tab's
                // insertion animates via its .softAppear transition, and a container-level
                // animation would hijack the outer panel-slide transaction, so the tab
                // would jump instead of gliding along when the diff panel opens.
                .task(id: runtime.diffRevision) { await runtime.refreshChangeStats() }
            }
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.25), value: runtime.approvals.map(\.id))
        .animation(.snappy(duration: 0.25), value: runtime.questions.map(\.id))
    }
}

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @Bindable var runtime: ThreadRuntime

    @State private var textHeight: CGFloat = 20
    @State private var controller = ComposerController()
    @State private var suggestions = SuggestionState()
    @State private var historyIndex: Int?
    @State private var showingRecents = false
    @State private var fileIndex = FileIndex()

    var body: some View {
        let thread = model.thread(runtime.threadID)
        VStack(alignment: .leading, spacing: 8) {
            if !runtime.draft.attachments.isEmpty {
                DraftAttachments(attachments: $runtime.draft.attachments)
            }
            ComposerTextView(
                text: $runtime.draft.text,
                height: $textHeight,
                placeholder: placeholder(for: thread),
                controller: controller,
                onKey: handleKey,
                onFiles: attach(urls:),
                onImage: attach(imageData:),
                onCursorChange: cursorMoved(to:)
            )
            .frame(height: min(max(textHeight, 20), 220))

            if let thread {
                HStack(spacing: 2) {
                    ModelEffortButton(thread: thread, hasHistory: !runtime.turns.isEmpty)
                    PlanToggle(thread: thread)
                    PermissionMenu(thread: thread)
                    Spacer(minLength: 8)
                    ContextMeter(
                        usage: runtime.usage,
                        provider: thread.provider,
                        rate: runtime.isRunning ? runtime.tokenRate : runtime.lastTokenRate,
                        live: runtime.isRunning && runtime.tokenRate != nil
                    )
                    Button {
                        if model.settings.recentDownloadsPicker {
                            showingRecents.toggle()
                        } else {
                            chooseFiles()
                        }
                    } label: {
                        Image(systemName: "paperclip")
                    }
                    .buttonStyle(.chip(active: showingRecents))
                    .help("Attach files")
                    .popover(isPresented: $showingRecents, arrowEdge: .top) {
                        DownloadsPopover(
                            pick: { showingRecents = false; attach(urls: [$0]) },
                            chooseOther: { showingRecents = false; chooseFiles() }
                        )
                    }
                    SendButton(runtime: runtime) { send() }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 9)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .popover(
            isPresented: Binding(
                get: { suggestions.isVisible },
                set: { if !$0 { suggestions = SuggestionState() } }
            ),
            arrowEdge: .top
        ) {
            PopoverMenu {
                PopoverSectionHeader(suggestions.kind == .command ? "Commands" : "Files")
                ForEach(Array(suggestions.items.enumerated()), id: \.element.id) { index, item in
                    SuggestionPopoverRow(
                        item: item,
                        isSelected: index == suggestions.selected,
                        select: { suggestions.selected = index },
                        pick: { pick(item) }
                    )
                }
            }
        }
        .task(id: workingDirectory(for: thread)) {
            if let directory = workingDirectory(for: thread) { fileIndex.prepare(directory) }
        }
    }

    private func workingDirectory(for thread: ChatThread?) -> String? {
        guard let thread, let project = model.project(thread.projectID) else { return nil }
        return thread.worktreePath ?? project.path
    }

    private func placeholder(for thread: ChatThread?) -> String {
        guard let thread else { return "" }
        if thread.interactionMode == .plan { return "Describe what you want to plan" }
        return "Ask \(thread.provider.displayName) to build, fix or explain. @ for files, / for commands"
    }

    // MARK: - Keys

    private func handleKey(_ key: ComposerKey) -> Bool {
        if suggestions.isVisible {
            switch key {
            case .up:
                suggestions.selected = max(0, suggestions.selected - 1)
                return true
            case .down:
                suggestions.selected = min(suggestions.items.count - 1, suggestions.selected + 1)
                return true
            case .tab, .submit:
                pick(suggestions.items[suggestions.selected])
                return true
            case .escape:
                suggestions = SuggestionState()
                return true
            }
        }
        switch key {
        case .submit:
            send()
            return true
        case .up:
            return recall(older: true)
        case .down:
            return recall(older: false)
        case .escape:
            guard runtime.isRunning else { return false }
            runtime.interrupt()
            return true
        case .tab:
            return false
        }
    }

    private func send() {
        guard !runtime.isRunning, !runtime.draft.isEmpty else { return }
        historyIndex = nil
        suggestions = SuggestionState()
        runtime.send()
    }

    private func recall(older: Bool) -> Bool {
        let prompts = runtime.sentPrompts.filter { !$0.isEmpty }
        guard !prompts.isEmpty, runtime.draft.attachments.isEmpty else { return false }
        let text = runtime.draft.text
        let recalledIndex = historyIndex.flatMap { prompts.indices.contains($0) && prompts[$0] == text ? $0 : nil }
        guard text.isEmpty || recalledIndex != nil else { return false }
        if older {
            let next = (recalledIndex ?? prompts.count) - 1
            guard next >= 0 else { return true }
            historyIndex = next
            runtime.draft.text = prompts[next]
        } else {
            guard let index = recalledIndex else { return false }
            if index + 1 < prompts.count {
                historyIndex = index + 1
                runtime.draft.text = prompts[index + 1]
            } else {
                historyIndex = nil
                runtime.draft.text = ""
            }
        }
        return true
    }

    // MARK: - Suggestions

    private func cursorMoved(to location: Int) {
        Task { @MainActor in refreshSuggestions(cursor: location) }
    }

    private func refreshSuggestions(cursor: Int) {
        let text = runtime.draft.text as NSString
        guard cursor > 0, cursor <= text.length else {
            if suggestions.isVisible { suggestions = SuggestionState() }
            return
        }
        var start = cursor
        while start > 0 {
            let character = text.character(at: start - 1)
            if character == 0x20 || character == 0x0A || character == 0x09 { break }
            start -= 1
        }
        let range = NSRange(location: start, length: cursor - start)
        let word = text.substring(with: range)
        var kind = SuggestionState.Kind.file
        var items: [Suggestion] = []
        if word.hasPrefix("@") {
            items = fileIndex.search(String(word.dropFirst())).map { path in
                Suggestion(value: "@\(path) ", title: (path as NSString).lastPathComponent, detail: path, symbol: "doc")
            }
        } else if word.hasPrefix("/"), start == 0 {
            kind = .command
            items = commandSuggestions(matching: String(word.dropFirst()))
        }
        guard !items.isEmpty else {
            if suggestions.isVisible { suggestions = SuggestionState() }
            return
        }
        let selected = suggestions.range.location == range.location ? min(suggestions.selected, items.count - 1) : 0
        suggestions = SuggestionState(kind: kind, range: range, items: items, selected: selected)
    }

    private func commandSuggestions(matching query: String) -> [Suggestion] {
        guard let thread = model.thread(runtime.threadID) else { return [] }
        var commands = [SlashCommand(name: "plan", detail: "Turn plan mode on or off", isBuiltIn: true)]
        if thread.provider == .codex || thread.provider == .claude || thread.provider == .deepseek {
            commands.append(SlashCommand(name: "compact", detail: "Summarize the conversation to free up context", isBuiltIn: true))
        }
        for command in model.providers.commands[thread.provider] ?? [] where !commands.contains(where: { $0.name == command.name }) {
            commands.append(command)
        }
        let needle = query.lowercased()
        let prefixed = commands.filter { needle.isEmpty || $0.name.lowercased().hasPrefix(needle) }
        let contained = needle.isEmpty ? [] : commands.filter { !$0.name.lowercased().hasPrefix(needle) && $0.name.lowercased().contains(needle) }
        return (prefixed + contained).prefix(8).map { command in
            Suggestion(value: "/\(command.name) ", title: "/\(command.name)", detail: command.detail, symbol: command.isBuiltIn ? "command" : "sparkles")
        }
    }

    private func pick(_ suggestion: Suggestion) {
        let range = suggestions.range
        suggestions = SuggestionState()
        controller.replaceCharacters(in: range, with: suggestion.value)
        controller.focus()
    }

    // MARK: - Attachments

    private func attach(urls: [URL]) {
        for url in urls {
            guard runtime.draft.attachments.count < 8 else { break }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let fileExtension = url.pathExtension.lowercased()
            if fileExtension == "heic" || fileExtension == "heif" {
                guard let image = NSImage(contentsOf: url), let data = image.jpegData,
                      let attachment = try? Storage.importAttachment(
                        data: data,
                        name: url.deletingPathExtension().lastPathComponent + ".jpg",
                        fileExtension: "jpg"
                      ) else { continue }
                runtime.draft.attachments.append(attachment)
            } else if let attachment = try? Storage.importAttachment(from: url) {
                runtime.draft.attachments.append(attachment)
            }
        }
        controller.focus()
    }

    private func attach(imageData data: Data) {
        guard runtime.draft.attachments.count < 8,
              let attachment = try? Storage.importAttachment(data: data, name: "Pasted image.png", fileExtension: "png") else { return }
        runtime.draft.attachments.append(attachment)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK else { return }
        attach(urls: panel.urls)
    }
}

// MARK: - Controls

private struct PlanToggle: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        let isPlanning = thread.interactionMode == .plan
        Button {
            model.updateThread(thread.id) { $0.interactionMode = isPlanning ? .build : .plan }
        } label: {
            Label("Plan", systemImage: "list.bullet.clipboard")
        }
        .buttonStyle(.chip(active: isPlanning))
        .help(isPlanning ? "Plan mode is on (⇧⌘P)" : "Plan before building (⇧⌘P)")
    }
}

private struct PermissionMenu: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread

    var body: some View {
        ChipPopoverButton(help: thread.runtimeMode.summary) {
            Label(thread.runtimeMode.title, systemImage: thread.runtimeMode.symbol)
        } content: {
            PopoverSectionHeader("Permissions")
            ForEach(RuntimeMode.allCases) { mode in
                PopoverItem(mode.title, symbol: mode.symbol, isChecked: thread.runtimeMode == mode) {
                    model.updateThread(thread.id) { $0.runtimeMode = mode }
                }
            }
        }
    }
}

/// The context ring. Clicking it opens the context window and the plan's usage limits.
private struct ContextMeter: View {
    let usage: ContextUsage?
    let provider: ProviderKind
    let rate: Double?
    let live: Bool

    @State private var isPresented = false

    var body: some View {
        let fraction = usage?.fraction
        if fraction != nil || PlanLimitsReader.exposesLimits(provider) {
            Button {
                isPresented.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction ?? 0)
                        .stroke((fraction ?? 0) > 0.85 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(fraction.map { "\(Int($0 * 100))% of the context window used" } ?? "Usage limits")
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                UsagePanel(usage: usage, provider: provider, rate: rate, live: live)
            }
        }
    }
}

private struct SendButton: View {
    let runtime: ThreadRuntime
    let send: () -> Void

    var body: some View {
        let isRunning = runtime.isRunning
        let isEnabled = isRunning || !runtime.draft.isEmpty
        Button {
            if isRunning { runtime.interrupt() } else { send() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.leading, 4)
        .help(isRunning ? "Stop (⌘.)" : "Send (Return)")
    }
}

private struct DraftAttachments: View {
    @Binding var attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment, size: 48)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                        }
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }
}

// MARK: - Suggestions

struct SuggestionState: Equatable {
    enum Kind {
        case file
        case command
    }

    var kind: Kind = .file
    var range = NSRange(location: 0, length: 0)
    var items: [Suggestion] = []
    var selected = 0

    var isVisible: Bool { !items.isEmpty }
}

struct Suggestion: Identifiable, Equatable {
    var value: String
    var title: String
    var detail: String
    var symbol: String

    var id: String { value }
}

private struct SuggestionPopoverRow: View {
    let item: Suggestion
    let isSelected: Bool
    let select: () -> Void
    let pick: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(verbatim: item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 16)
                Text(verbatim: item.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .lineLimit(1)
            }
            .foregroundStyle(Chrome.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected || isHovering ? Chrome.overlay(0.1) : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
            if hovering { select() }
        }
    }
}

/// Paths in the working directory for `@` mentions.
@MainActor
@Observable
final class FileIndex {
    private struct Entry {
        var path: String
        var lowercased: String
        var name: String
    }

    @ObservationIgnored private var entries: [Entry] = []
    @ObservationIgnored private var directory: String?

    func prepare(_ directory: String) {
        guard self.directory != directory else { return }
        self.directory = directory
        entries = []
        Task {
            let paths = await Self.list(directory)
            guard self.directory == directory else { return }
            entries = paths.map { path in
                let lowercased = path.lowercased()
                return Entry(path: path, lowercased: lowercased, name: (lowercased as NSString).lastPathComponent)
            }
        }
    }

    func search(_ query: String, limit: Int = 8) -> [String] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return entries.prefix(limit).map(\.path) }
        var scored: [(path: String, score: Int)] = []
        for entry in entries {
            let score: Int
            if entry.name == needle {
                score = 1_000
            } else if entry.name.hasPrefix(needle) {
                score = 800
            } else if entry.name.contains(needle) {
                score = 600
            } else if entry.lowercased.contains(needle) {
                score = 400
            } else if Self.isSubsequence(needle, of: entry.lowercased) {
                score = 100
            } else {
                continue
            }
            scored.append((entry.path, score - min(entry.path.count, 99)))
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.path)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    @concurrent
    private nonisolated static func list(_ directory: String) async -> [String] {
        let git = Git(directory)
        if await git.isRepository() {
            let files = await git.listFiles()
            if !files.isEmpty { return Array(files.prefix(60_000)) }
        }
        return enumerate(directory)
    }

    private nonisolated static func enumerate(_ directory: String) -> [String] {
        let root = URL(fileURLWithPath: directory)
        let skipped: Set<String> = ["node_modules", "build", "dist", ".build", "DerivedData", "Pods", "target"]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var results: [String] = []
        while let url = enumerator.nextObject() as? URL {
            if skipped.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            results.append(ToolTitles.relativePath(url.path, to: directory))
            if results.count >= 20_000 { break }
        }
        return results
    }
}
