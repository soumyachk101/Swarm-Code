import AppKit
import SwiftUI

struct ComposerArea: View {
    let runtime: ThreadRuntime
    /// The folder the thread works in, for the `@` file index. Read once by the chat and
    /// handed down, so the composer never observes the project itself.
    let workingDirectory: String?
    /// Floating panels are narrow: the model chip collapses to the provider's icon.
    var compactModelChip: Bool = false
    /// Whether the box takes typing focus as it appears; a floating panel's does not.
    var takesFocusOnAppear = true

    /// The changes popover presented from the tab. Driven by
    /// `runtime.isDiffVisible`, so every opener (tab, Review, ⌘D) shares it.
    @State private var diffPopover = DiffPopoverCoordinator()

    var body: some View {
        // The top of the box is the tabs' slot: the agent's question while it asks one, else
        // the queue while any follow-ups are queued, else the changes.
        let question = runtime.questions.first
        let slotHasTab = question != nil || !runtime.followUps.isEmpty || runtime.changeStats != nil
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 12) {
                ForEach(runtime.approvals) { request in
                    ApprovalCard(request: request, runtime: runtime)
                }
                VStack(alignment: .center, spacing: -ThreadChangesTab.overlap) {
                    // One slot, its tabs stacked on the box's top edge rather than on each
                    // other: the tab leaving fades where it stood while the one arriving
                    // fades in over it, and the slot's height glides from one to the other.
                    // The slot exists only while a tab does, or the stack's overlap would
                    // pull an empty slot's box up by that much.
                    if slotHasTab {
                        ZStack(alignment: .bottom) {
                            if let question {
                                // A question takes the slot from whatever held it and stays until
                                // it is answered; the answer hands the slot straight back.
                                QuestionTab(request: question, runtime: runtime)
                                    .id(question.id)
                                    .transition(.softAppear)
                            } else if !runtime.followUps.isEmpty {
                                // The queued steering prompts take the tab slot while any are queued:
                                // the changes tab hides behind them and reappears once the queue empties.
                                FollowUpQueueTab(runtime: runtime)
                                    .transition(.softAppear)
                            } else if let stats = runtime.changeStats {
                                ThreadChangesTab(
                                    stats: stats,
                                    anchor: { diffPopover.setAnchor($0) }
                                ) {
                                    runtime.clearDiffFocus()
                                    runtime.diffAnchor = nil
                                    if runtime.diffSelection != nil { runtime.diffSelection = nil }
                                    // Set last so a redundant write never restarts the diff load
                                    // or steals the presentation.
                                    if !runtime.isDiffVisible { runtime.isDiffVisible = true }
                                }
                                .transition(.softAppear)
                            }
                        }
                        .transition(.softAppear)
                    }
                    ComposerView(runtime: runtime, workingDirectory: workingDirectory, compactModelChip: compactModelChip, takesFocusOnAppear: takesFocusOnAppear)
                }
                // NB: no .animation(..., value: changeStats) here on purpose: the tab's
                // insertion animates via its .softAppear transition, and opening the
                // popover moves nothing, so there is nothing else to drive. A question is
                // the exception: it is taller than the tab it replaces and the one that
                // comes back, so the box and the conversation above it slide to fit.
                .animation(Chrome.panelSlide, value: question?.id)
                .background {
                    AttachmentAnchorCapture { diffPopover.setFallbackAnchor($0) }
                }
                .background { ChangeStatsRefresh(runtime: runtime) }
                .onAppear { diffPopover.sync(isVisible: runtime.isDiffVisible, runtime: runtime) }
                .onChange(of: runtime.isDiffVisible) { _, visible in
                    diffPopover.sync(isVisible: visible, runtime: runtime)
                }
                .onChange(of: runtime.diffOpenRequest) {
                    diffPopover.reopen(runtime: runtime)
                }
                .onDisappear { diffPopover.close() }
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

/// Keeps the changes tab's stats fresh without making the composer area's own body depend
/// on the diff revision. A file-editing tool call bumps that revision several times a turn,
/// and reading it up there re-ran the whole box, tabs and pill included, for each bump.
private struct ChangeStatsRefresh: View {
    let runtime: ThreadRuntime

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: runtime.diffRevision) { await runtime.refreshChangeStats() }
    }
}

struct ComposerView: View {
    @Environment(AppModel.self) private var model
    @Bindable var runtime: ThreadRuntime
    let workingDirectory: String?
    /// Floating panels are narrow: the model chip collapses to the provider's icon.
    var compactModelChip: Bool = false
    var takesFocusOnAppear = true

    @State private var textHeight: CGFloat = 20
    @State private var controller = ComposerController()
    @State private var suggestions = SuggestionState()
    @State private var historyIndex: Int?
    @State private var showingRecents = false
    @State private var fileIndex = FileIndex()
    /// Why an attach did not take everything it was handed. Shown over the text for a few
    /// seconds: files used to be dropped at the cap with nothing said about it.
    @State private var attachmentNotice: String?

    /// How many files one message carries.
    static let maxAttachments = 8

    private static let minComposerHeight: CGFloat = 20
    private static let maxComposerLines = 5
    private static var maxComposerHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: 14)
        let line = ceil(font.ascender - font.descender + font.leading)
        // Matches ComposerTextView's textContainerInset.height * 2.
        return line * CGFloat(maxComposerLines) + 4
    }

    private var composerHeight: CGFloat {
        min(max(textHeight, Self.minComposerHeight), Self.maxComposerHeight)
    }

    var body: some View {
        let thread = model.thread(runtime.threadID)
        // One pill: the text on the left, the controls tucked into its trailing end. The
        // controls sit on the pill's bottom line, so they stay put while the text grows upward.
        HStack(alignment: .bottom, spacing: 8) {
            // Spacing 0 and the strip carries its own gap: the strip reads the draft
            // itself, so it stays a zero-height subview while there is nothing attached
            // and the composer never has to look at the draft to decide whether to
            // stack it. Reading the draft here would re-render the text view on every
            // keystroke, since text and attachments are one observable property.
            VStack(alignment: .leading, spacing: 0) {
                DraftAttachments(runtime: runtime)
                if let attachmentNotice {
                    Text(verbatim: attachmentNotice)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.warning)
                        .lineLimit(1)
                        .padding(.bottom, 6)
                        .transition(.softAppear)
                }
                ComposerTextView(
                    text: $runtime.draft.text,
                    height: $textHeight,
                    placeholder: placeholder(for: thread),
                    controller: controller,
                    onKey: handleKey,
                    onFiles: attach(urls:),
                    onImage: attach(imageData:),
                    onCursorChange: cursorMoved(to:),
                    onBlur: {
                        // Clicking a row focuses the popover; only dismiss when
                        // focus truly left both the text and the suggestions.
                        if !controller.isClickInsideSuggestions() { suggestions = SuggestionState() }
                    },
                    takesFocusOnAppear: takesFocusOnAppear
                )
                // The text view itself takes its new height at once, so it lays out
                // every line with nothing to scroll; only the clip around it grows
                // and shrinks. Animating the scroll view's own frame made AppKit
                // scroll the caret into a too-short view and then snap back.
                .frame(height: composerHeight)
                .transaction { $0.animation = nil }
                .frame(height: composerHeight, alignment: .top)
                .clipped()
                .animation(.smooth(duration: 0.28), value: composerHeight)
            }
            // A single line of text is as tall as the send button, so an empty pill is 44 high.
            .padding(.vertical, 4)

            if let thread {
                HStack(spacing: 2) {
                    Button {
                        if model.settings.recentDownloadsPicker {
                            showingRecents.toggle()
                        } else {
                            chooseFiles()
                        }
                    } label: {
                        Image(systemName: "paperclip")
                            .font(Chrome.iconFont)
                    }
                    .buttonStyle(.chip(active: showingRecents))
                    .help("Attach files")
                    .accessibilityLabel(Text("Attach files"))
                    .popover(isPresented: $showingRecents, arrowEdge: .bottom) {
                        DownloadsPopover(
                            pick: { showingRecents = false; attach(urls: [$0]) },
                            chooseOther: { showingRecents = false; chooseFiles() }
                        )
                    }
                    ModelEffortSlot(runtime: runtime, thread: thread, compact: compactModelChip)
                    ContextMeter(runtime: runtime, provider: thread.provider)
                    SendButton(runtime: runtime, goesToHead: goesToHead(thread)) { send() }
                }
                .fixedSize()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        // While a turn runs, accent dots flow along the pill's bottom two-fifths, behind
        // the text. They must live inside the glass content: a glass view renders in its
        // own pass above ordinary siblings, so glass as a separate background layer
        // covered the composer instead of sitting under it.
        .background {
            if runtime.isRunning {
                GeometryReader { proxy in
                    ComposerWorkingDots()
                        .frame(height: proxy.size.height * 0.4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
        .onChange(of: suggestions) { _, new in
            if new.isVisible {
                controller.showSuggestions(AnyView(suggestionMenu()), itemCount: new.items.count)
            } else {
                controller.hideSuggestions()
            }
        }
        .onDisappear { controller.hideSuggestions() }
        .onChange(of: runtime.threadID) { _, _ in controller.hideSuggestions() }
        .task(id: workingDirectory) {
            if let workingDirectory { fileIndex.prepare(workingDirectory) }
        }
        // The notice says its piece and goes; a second drop restarts the wait.
        .task(id: attachmentNotice) {
            guard attachmentNotice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(Chrome.panelSlide) { attachmentNotice = nil }
        }
    }

    /// The slash/@ list hosted in a caret-anchored NSPopover (see ComposerController).
    @ViewBuilder
    private func suggestionMenu() -> some View {
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

    private func placeholder(for thread: ChatThread?) -> String {
        guard let thread else { return "" }
        if thread.interactionMode == .plan { return "Describe what you want to plan" }
        if model.hydraIsOn(thread) {
            // With every message sent to a head, the lead never works the message itself:
            // it goes straight out and comes back as a report, which is worth saying here
            // because nothing else in the box shows it.
            if model.settings.hydraAlwaysHeads {
                return "Goes to a head; \(thread.provider.displayName) leads and reports back"
            }
            return "Ask \(thread.provider.displayName) for anything; big jobs go out to a team of heads"
        }
        return "Ask \(thread.provider.displayName) to build, fix or explain. @ for files, / for commands"
    }

    /// Whether the next message is handed to a head rather than worked by the lead.
    private func goesToHead(_ thread: ChatThread) -> Bool {
        model.settings.hydraAlwaysHeads && model.hydraIsOn(thread)
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
            case .tab, .submit, .steer:
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
        case .steer:
            steer()
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
        guard !runtime.draft.isEmpty else { return }
        historyIndex = nil
        suggestions = SuggestionState()
        if runtime.isRunning {
            // Return while the turn runs stops it and sends right away.
            runtime.interruptAndSend()
        } else {
            runtime.send()
        }
    }

    /// Command-Return: steer the running turn by queueing the draft behind it.
    /// Idle, there is nothing to steer behind, so it just sends. The menu owns
    /// the chord while a turn runs; this path only sees it when the command is
    /// disabled or rebound, so it falls back to send once the chord moves.
    private func steer() {
        guard !runtime.draft.isEmpty else { return }
        historyIndex = nil
        suggestions = SuggestionState()
        if runtime.isRunning,
           ShortcutStore.shared.chord(for: .queueChat) == KeyChord(keyCode: 36, modifiers: .command) {
            runtime.queueDraftAsFollowUp()
        } else {
            runtime.send()
        }
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
        if thread.provider == .codex || thread.provider == .claude || thread.provider == .copilot || thread.provider == .deepseek || thread.provider == .meta {
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
        var dropped = 0
        for url in urls {
            guard runtime.draft.attachments.count < Self.maxAttachments else {
                dropped += 1
                continue
            }
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
        if dropped > 0 {
            note(dropped == 1
                ? "One file was left out: a message holds \(Self.maxAttachments) attachments"
                : "\(dropped) files were left out: a message holds \(Self.maxAttachments) attachments")
        }
        controller.focus()
    }

    private func attach(imageData data: Data) {
        guard runtime.draft.attachments.count < Self.maxAttachments else {
            note("The image was left out: a message holds \(Self.maxAttachments) attachments")
            return
        }
        guard let attachment = try? Storage.importAttachment(data: data, name: "Pasted image.png", fileExtension: "png") else { return }
        runtime.draft.attachments.append(attachment)
    }

    private func note(_ message: String) {
        withAnimation(Chrome.panelSlide) { attachmentNotice = message }
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

/// The model and effort chip. It reads the thread's turns itself rather than taking a flag
/// from the composer: a turn record is rewritten several times per turn (its checkpoints,
/// its anchor, its diff), and the composer would re-render whole for each of them.
private struct ModelEffortSlot: View {
    let runtime: ThreadRuntime
    let thread: ChatThread
    let compact: Bool

    var body: some View {
        ModelEffortButton(thread: thread, hasHistory: !runtime.turns.isEmpty, compact: compact)
    }
}

/// The context ring. Clicking it opens the context window and whatever else the provider
/// reports: its plan's usage limits, or a pay-as-you-go key's remaining credits.
///
/// Usage is read here rather than handed down, so a usage report repaints the ring alone.
private struct ContextMeter: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let provider: ProviderKind

    @State private var isPresented = false

    var body: some View {
        let usage = runtime.usage
        let fraction = usage?.fraction
        // A key with credit behind it has something to show from the first turn, before any
        // usage has been reported, so the ring is not waiting on a context window to exist.
        let hasCredits = CreditsReader.exposesCredits(provider) && model.settings.hasAPIKey(for: provider)
        if fraction != nil || PlanLimitsReader.exposesLimits(provider) || hasCredits {
            Button {
                isPresented.toggle()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction ?? 0)
                        .stroke((fraction ?? 0) > 0.85 ? AnyShapeStyle(Chrome.warning) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(helpText(fraction: fraction, hasCredits: hasCredits))
            .accessibilityLabel(Text(label(fraction: fraction, hasCredits: hasCredits)))
            // The ring is the only reading of the context window on screen, so the number
            // behind it is spoken rather than left to the tooltip.
            .accessibilityValue(Text(fraction.map { "\(Int($0 * 100))% of the context window used" } ?? ""))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                UsagePanel(usage: usage, provider: provider)
            }
        }
    }

    private func helpText(fraction: Double?, hasCredits: Bool) -> String {
        if let fraction { return "\(Int(fraction * 100))% of the context window used" }
        return hasCredits ? "Remaining credits" : "Usage limits"
    }

    private func label(fraction: Double?, hasCredits: Bool) -> String {
        if fraction != nil { return "Context window" }
        return hasCredits ? "Remaining credits" : "Usage limits"
    }
}

private struct SendButton: View {
    let runtime: ThreadRuntime
    /// With every message going to a head, the send hands the message on rather than
    /// starting the lead's own turn, so the help says where it lands.
    let goesToHead: Bool
    let send: () -> Void

    var body: some View {
        let isRunning = runtime.isRunning
        let isEnabled = isRunning || !runtime.draft.isEmpty
        Button {
            if isRunning { runtime.interrupt() } else { send() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                .font(Chrome.iconFont)
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .padding(.leading, 4)
        .help(helpText(isRunning: isRunning))
        .accessibilityLabel(Text(isRunning ? "Stop" : (goesToHead ? "Send to a head" : "Send")))
    }

    /// The chords come from the shortcut store, so a remap or a cleared chord never leaves
    /// the help promising a key the app no longer answers to.
    private func helpText(isRunning: Bool) -> String {
        let queues = ShortcutStore.label(for: .queueChat)
        if isRunning {
            var parts = ["Stop\(ShortcutStore.hint(for: .stopTurn))", "Return steers"]
            if let queues { parts.append("\(queues) queues") }
            return parts.joined(separator: " · ")
        }
        var parts = [goesToHead ? "Send to a head (Return) · the lead reports back" : "Send (Return)"]
        if let queues { parts.append("\(queues) queues while running") }
        return parts.joined(separator: " · ")
    }
}

private struct DraftAttachments: View {
    let runtime: ThreadRuntime

    /// Same shape as the chat strip: one preview panel for the strip, so every
    /// draft photo opens in a single tap.
    @State private var preview = AttachmentPreviewSlot()

    var body: some View {
        let attachments = runtime.draft.attachments
        if !attachments.isEmpty {
            strip(attachments)
                // The strip's own gap to the text below it: the composer stacks with no
                // spacing, so an empty strip takes no room at all.
                .padding(.bottom, 8)
        }
    }

    private func strip(_ attachments: [Attachment]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // The delete badge straddles the thumbnail's far top-right corner.
            // The cell's own top/trailing padding reserves that overhang, so the
            // badge sits inside its own cell — never in the gap where a later
            // sibling could cover it — and every photo stays deletable. On top
            // only the 2 pt the badge's circle shows above the photo: the pill
            // already leaves 12 above the strip, and 12 + 2 puts the photo 14
            // from the pill's top edge, the same inset it has from the leading
            // edge, where it lines up with the text.
            HStack(spacing: 0) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment, size: 48, preview: preview)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                runtime.draft.attachments.removeAll { $0.id == attachment.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(Text("Remove \(attachment.name)"))
                        }
                        .padding(.top, 2)
                        .padding(.trailing, 8)
                }
            }
            .background {
                AttachmentAnchorCapture { preview.setAnchor($0) }
            }
        }
        .onChange(of: attachments) {
            preview.retire(except: Set(attachments.map(\.id)))
        }
        .onDisappear { preview.close() }
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

    /// Built indexes per directory, shared by every composer, so switching threads in a project
    /// never lists and lowercases its files again. A stale index is served and rebuilt behind it.
    private static var built: [String: (entries: [Entry], builtAt: Date)] = [:]
    private static var building: Set<String> = []
    private static let freshness: TimeInterval = 60

    func prepare(_ directory: String) {
        guard self.directory != directory else { return }
        self.directory = directory
        if let cached = Self.built[directory] {
            entries = cached.entries
            guard Date.now.timeIntervalSince(cached.builtAt) > Self.freshness else { return }
        } else {
            entries = []
        }
        guard !Self.building.contains(directory) else { return }
        Self.building.insert(directory)
        Task {
            let fresh = await Self.build(directory)
            Self.building.remove(directory)
            Self.built[directory] = (fresh, .now)
            guard self.directory == directory else { return }
            entries = fresh
        }
    }

    @concurrent
    private nonisolated static func build(_ directory: String) async -> [Entry] {
        await list(directory).map { path in
            let lowercased = path.lowercased()
            return Entry(path: path, lowercased: lowercased, name: (lowercased as NSString).lastPathComponent)
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
