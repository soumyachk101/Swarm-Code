import AppKit
import SwiftUI

struct ThreadTimeline: View, Equatable {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    let scrollChrome: ChromeScrollModel
    let scrollState: TimelineScrollState
    let projectName: String?
    /// The folder the thread works in, for tool rows that resolve paths. Read once by the
    /// chat and handed down as a value, so rows never look the thread up themselves.
    let workingDirectory: String?
    /// Whether the thread's provider can rewind a conversation, for the revert controls.
    let supportsRewind: Bool
    /// Full chat-column height, so the rail stays centred when the composer
    /// or queue tab grows.
    let columnHeight: CGFloat

    /// The chat re-renders whenever its thread changes (a title, the effort, a mode); the
    /// timeline only follows when what it was handed changed.
    nonisolated static func == (lhs: ThreadTimeline, rhs: ThreadTimeline) -> Bool {
        lhs.runtime === rhs.runtime
            && lhs.scrollChrome === rhs.scrollChrome
            && lhs.scrollState === rhs.scrollState
            && lhs.projectName == rhs.projectName
            && lhs.workingDirectory == rhs.workingDirectory
            && lhs.supportsRewind == rhs.supportsRewind
            && lhs.columnHeight == rhs.columnHeight
    }

    /// Everything the scroll view and the rows report while the reader scrolls: which blocks
    /// are on screen and whether the timeline follows new text. It lives in an object rather
    /// than in view state on purpose. Rows write to it as they cross the viewport's edges and
    /// the scroll view writes to it as content grows, and only the rail reads it, so none of
    /// that ever re-runs this body. The one thing it tells the body is the rare request to
    /// check its own layout (`repairLayout`).
    @State private var tracking = TimelineScrollTracking()
    /// The scroll position stays view state, never a property of an observable object. A
    /// `scrollTo` request is consumed by the scroll view writing the resolved position back
    /// through the binding; on an observable, that write's `willSet` re-ran this body while
    /// the property still held the pending request, so the scroll view enqueued it again,
    /// without end. `@State` applies the write first and re-renders after.
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var viewportHeight: CGFloat = 0
    /// True while the reader drags or flicks the timeline. Rows neither hover nor hit-test
    /// then: with the pointer resting over content that slides under it, SwiftUI otherwise
    /// re-hit-tests every row's hover region each frame and the rows flip their hover state
    /// (and animate it) as they pass — a fifth of the main thread's scroll-time work.
    @State private var isReaderScrolling = false
    /// Watches for the scroll to settle once movement has been seen, so the freeze lifts
    /// 150ms after the last frame that moved, for wheel and trackpad alike.
    @State private var settleWatch: Task<Void, Never>?
    /// Which edge stays put when the content's height changes. At the conversation's end
    /// it is the bottom, so streaming text and the working line grow in place. Once the
    /// reader has scrolled up it is the top: a row expanded mid-thread then pushes what
    /// follows down and stays under the pointer, instead of the whole timeline lurching
    /// up by the expansion's height to keep the far-off bottom edge fixed.
    @State private var anchorsBottomOnGrowth = true
    /// Older history is about to be loaded above the viewport; that growth keeps the
    /// bottom fixed whatever the reader is doing, so the messages in view stay put.
    @State private var historyLoadPending = false
    /// Lazy-loading window: only the newest groups are materialized, so opening a long
    /// thread and scrolling through it stays instant no matter how much history it holds.
    @State private var visibleCount = TimelineWindow.firstPaint
    /// Changes to rebuild the lazy stack from scratch: the second repair for a viewport
    /// the stack has built nothing for (see `repairLayout`).
    @State private var stackGeneration = 0

    var body: some View {
        let entries = runtime.entries
        let meta = TimelineMeta.build(entries)
        let blocks = DisplayBlock.build(entries, meta: meta, showReasoning: model.settings.showReasoning)
        if blocks.isEmpty && !runtime.isRunning {
            NewThreadPrompt(threadID: runtime.threadID, projectName: projectName)
                .onAppear {
                    scrollChrome.update(travel: 0)
                    scrollState.showsJumpButton = false
                }
        } else {
            timeline(blocks)
        }
    }

    private func timeline(_ blocks: [DisplayBlock]) -> some View {
        // Only the newest window of blocks is rendered. Older history loads on demand,
        // so the view count stays bounded even for very long threads.
        let hidden = max(0, blocks.count - visibleCount)
        var visible = hidden == 0 ? blocks : Array(blocks.suffix(visibleCount))
        // While a turn runs and no reply has started, the working line is the last block, one
        // row like any other, so it arrives and leaves the way every row does. The moment the
        // reply it is waiting on arrives, the block goes and the reply takes its line; it comes
        // back below when the agent moves on to another step. The turn's trailing tool run is
        // not a block of its own meanwhile: the working line carries it (its summary beside the
        // spinner, its steps behind the chevron) until a reply follows, when it comes back as a
        // collapsed group above the answer.
        if runtime.isRunning, runtime.entries.last?.kind != .assistant {
            var liveWork: [TimelineEntry] = []
            if case .group(.work(_, let entries, false), _, _) = visible.last {
                liveWork = entries
                visible.removeLast()
            }
            visible.append(.working(turnID: runtime.entries.last?.turnID, liveWork: liveWork))
        }
        // The turns a row may offer to revert. Read here, once, so a turn record changing
        // (checkpoints, diffs, anchors) re-runs this body alone; rows get a plain flag that
        // only changes when their own answer does.
        let rewindable: Set<UUID> = supportsRewind && !runtime.isRunning ? Set(runtime.turns.map(\.id)) : []
        // The rail floats over the timeline's leading gutter instead of taking layout
        // space, so the conversation stays centered exactly like the composer.
        // Ticks centre in the full column height, so the queue tab opening never moves them.
        return ZStack(alignment: .leading) {
            timelineScroll(visible: visible, hidden: hidden, rewindable: rewindable)
            if blocks.count(where: \.hasUserMessage) > 1 {
                TimelineMinimapColumn(
                    blocks: blocks,
                    tracking: tracking,
                    centerHeight: columnHeight,
                    onNavigate: { id, animated in jump(to: id, in: blocks, animated: animated) }
                )
                .equatable()
                .frame(width: 30)
                .frame(maxHeight: .infinity)
                // The hover card reaches over the conversation instead of being painted under it.
            }
        }
    }

    /// Jump the timeline to a minimap block. A target above the loaded
    /// window first loads history down to it, then scrolls once layout
    /// exists. Jumping away from the latest unpins the follow behavior, so
    /// streaming text never yanks the reader back down.
    private func jump(to id: String, in blocks: [DisplayBlock], animated: Bool) {
        var needsExpand = false
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            let firstVisible = blocks.count - visibleCount
            if index < firstVisible {
                visibleCount = blocks.count - index
                needsExpand = true
                historyLoadPending = true
            }
            tracking.isPinnedToBottom = (id == blocks.last?.id)
            anchorsBottomOnGrowth = tracking.isPinnedToBottom || needsExpand
        }
        let scroll = { position.scrollTo(id: id, anchor: .top) }
        if animated {
            if needsExpand {
                DispatchQueue.main.async { withAnimation(.smooth(duration: 0.35)) { scroll() } }
            } else {
                withAnimation(.smooth(duration: 0.35)) { scroll() }
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            if needsExpand {
                DispatchQueue.main.async { withTransaction(transaction) { scroll() } }
            } else {
                withTransaction(transaction) { scroll() }
            }
        }
    }

    /// Brings more older blocks into the window: one page, or up to `count`. The bottom
    /// stays held while they land above the viewport, so what the reader is looking at
    /// does not move.
    private func loadEarlier(to count: Int? = nil) {
        guard !historyLoadPending else { return }
        let target = count ?? visibleCount + TimelineWindow.page
        guard target > visibleCount else { return }
        historyLoadPending = true
        anchorsBottomOnGrowth = true
        visibleCount = target
    }

    /// A scroll that lands at once, for following growth the reader is already looking at.
    private static var unanimated: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    /// Parses every finished reply's markdown off the main thread, so rows scrolling into
    /// view for the first time never parse on the frame. Cached texts are skipped.
    private func warmMarkdown() async {
        var texts: [String] = []
        for entry in runtime.entries {
            guard case .assistant(let message) = entry.item.content, !message.isStreaming else { continue }
            texts.append(message.text)
        }
        guard !texts.isEmpty else { return }
        await MarkdownView.warm(texts)
    }

    /// How a row arrives and leaves. It arrives softly, like everything in the app, and
    /// leaves at once: a row that lingered while it faded kept its height in the lazy
    /// stack a beat longer, and a turn folding dozens of rows into one block doubled the
    /// content for that beat, with the viewport anchored somewhere in the phantom half.
    /// The block a finished turn folds into gets no transition at all: it stands exactly
    /// where its rows stood, in the same frame, and a fade over a block that can run to
    /// thousands of points is a whole-layer composite the renderer may draw as nothing.
    private static func transition(for block: DisplayBlock) -> AnyTransition {
        if case .turn = block { return .identity }
        return .asymmetric(
            insertion: .modifier(active: SoftAppearModifier(isVisible: false), identity: SoftAppearModifier(isVisible: true))
                .animation(.softAppear),
            removal: .identity
        )
    }

    private func timelineScroll(visible: [DisplayBlock], hidden: Int, rewindable: Set<UUID>) -> some View {
        // The outline the rail resolves against, kept in step with what is laid out. Rows
        // coming and going is when the stack can lose its place; a look a beat from now
        // costs nothing and catches it whether or not any row says so.
        if tracking.setOutline(visible.map { ($0.id, $0.hasUserMessage) }) {
            tracking.armBlankWatch()
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                if hidden > 0 {
                    // Older history loads itself as the reader nears the top, a page at a
                    // time, so scrolling back never stops at a button; the pill is still
                    // there to tap for anyone who gets to it first.
                    Button {
                        loadEarlier()
                    } label: {
                        Label("Show \(hidden) earlier messages", systemImage: "chevron.up")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.quaternary.opacity(0.5), in: Capsule(style: .continuous))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, TimelineMetrics.rowSpacing)
                    .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                        if isVisible { loadEarlier() }
                    }
                }
                LazyVStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                    ForEach(visible) { block in
                        let context = RowContext(
                            workingDirectory: workingDirectory,
                            canRewind: block.turnID.map(rewindable.contains) ?? false
                        )
                        DisplayBlockView(block: block, runtime: runtime, context: context)
                            .equatable()
                            .id(block.id)
                            // Reported when a block enters or leaves the viewport, never per
                            // frame. (A geometry observer per block made the lazy stack
                            // re-measure every child on every scrolled frame.)
                            .onScrollVisibilityChange(threshold: 0.001) { isVisible in
                                tracking.setVisible(block.id, isVisible)
                            }
                            // A row the lazy stack throws away (scrolled far off, or gone
                            // from the conversation) reports nothing more, so it leaves
                            // the on-screen set here; the set is how the timeline knows
                            // when it is showing nothing at all.
                            .onDisappear { tracking.setVisible(block.id, false) }
                            .transition(Self.transition(for: block))
                    }
                }
                .id(stackGeneration)
                .allowsHitTesting(!isReaderScrolling)
                // The end of the conversation. While it is on screen the reader is at the latest message.
                Color.clear
                    .frame(height: 1)
                    .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                        guard scrollState.showsJumpButton == isVisible else { return }
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            scrollState.showsJumpButton = !isVisible
                        }
                    }
            }
            // The same column as the composer, so messages line up with its edges.
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, Chrome.contentTopInset)
            .padding(.bottom, 18)
            // A short conversation still fills the pane, with its messages resting at the bottom.
            .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
        }
        .id(runtime.threadID)
        .scrollIndicators(.never)
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(anchorsBottomOnGrowth ? .bottom : .top, for: .sizeChanges)
        .onGeometryChange(for: CGFloat.self, of: Self.visibleHeight) { viewportHeight = $0 }
        .onScrollPhaseChange { _, phase in
            // Fingers on the trackpad freeze the rows (no click can land then anyway); the
            // moment the scroll coasts or settles they come back, so a click that stops a
            // flick always reaches its target. Wheel scrolling reports no phases and is
            // caught by the movement below instead.
            tracking.notePhase(phase)
            if phase == .interacting {
                noteScrollMovement()
            } else {
                liftScrollFreeze()
            }
        }
        .onScrollGeometryChange(for: ScrollMetrics.self, of: ScrollMetrics.init(geometry:)) { old, new in
            scrollChrome.update(travel: new.travel)
            tracking.noteGeometry(offset: new.offset, distanceFromBottom: new.distanceFromBottom)
            // Movement with no phase behind it: wheel ticks. Content growing under a
            // resting reader is not scrolling.
            if new.centerY != old.centerY, new.contentHeight == old.contentHeight, !tracking.isCoasting {
                noteScrollMovement()
            }
            // The offset moving while nothing else did is the reader scrolling: a drag, a flick,
            // or wheel ticks, which report no phase at all. (A snap to the end below moves it
            // too, and lands pinned, which is right.)
            let scrolled = tracking.isUserScrolling
                || (new.offset != old.offset && new.contentHeight == old.contentHeight
                    && new.containerHeight == old.containerHeight && !tracking.isCoasting)
            let atRest = !tracking.isUserScrolling && !tracking.isCoasting
            if atRest, new.contentHeight < old.contentHeight - 1 {
                // The content shrank under the viewport: a turn folded, the working line
                // went. Whatever the rows report, the layout gets checked a beat from now.
                tracking.armBlankWatch()
            }
            if new.distanceFromBottom < -1, atRest {
                // Past the end of the conversation, showing nothing: the content shrank under
                // the offset. A finished turn folds its whole transcript into one block, and
                // with the reader's place anchored at the top that left the viewport hanging
                // in empty space until they came back to the thread. Never a valid place to
                // be, whether or not the reader was following, so it snaps to the end.
                withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
            } else if historyLoadPending, new.contentHeight > old.contentHeight {
                // The history landed above the viewport with the bottom held; growth
                // anchors by the reader's position again from here.
                historyLoadPending = false
                let pinned = tracking.isPinnedToBottom || new.distanceFromBottom < 48
                if pinned != anchorsBottomOnGrowth { anchorsBottomOnGrowth = pinned }
            } else if scrolled {
                // Only the reader's own scrolling decides whether the timeline follows new text.
                // Guarded, so measuring the scroll position never touches anything a body reads.
                let pinned = new.distanceFromBottom < 48
                if pinned != tracking.isPinnedToBottom { tracking.isPinnedToBottom = pinned }
                if pinned != anchorsBottomOnGrowth { anchorsBottomOnGrowth = pinned }
            } else if tracking.isPinnedToBottom, atRest, abs(new.distanceFromBottom) > 1 {
                // Pinned, at rest, and not at the end: the content grew or reflowed to a new
                // width, the chat box took height, or the scroll view lost its place (rows
                // measured after it anchored, a thread opened mid-animation) and is showing
                // empty space past the conversation. The end is where the reader is; the
                // timeline snaps back to it, never slides, so a new row lands in place and
                // fades in on its own.
                withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
            }
        }
        .task(id: runtime.threadID) {
            // The first frame shows only the newest few blocks, so a thread opens at once;
            // the rest of the initial window lands a beat later, above the viewport, while
            // the reader is already looking at the end.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            loadEarlier(to: TimelineWindow.initial)
            // A thread that opened on nothing (its first rows never laid out where the
            // bottom anchor put the viewport) is caught a beat from now.
            tracking.armBlankWatch()
            await warmMarkdown()
        }
        .onChange(of: tracking.checkRequest) {
            repairLayout()
        }
        .onChange(of: FrontMonitor.shared.revision) {
            // The reader is back: the app came to the front or the window was uncovered.
            // Whatever the conversation did unseen, the timeline checks itself now.
            tracking.noteReturnToFront()
        }
        .onChange(of: runtime.isRunning) { _, running in
            // Sending a message always brings the reader back to the conversation's end.
            guard running else {
                // The turn's end folds its rows into one block. A reader at the end is put
                // back on the end once that has laid out, with a real scroll request rather
                // than the anchor alone, so the stack lays out for where the viewport is.
                if tracking.isPinnedToBottom {
                    DispatchQueue.main.async {
                        withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
                    }
                }
                tracking.armBlankWatch()
                Task { await warmMarkdown() }
                return
            }
            let wasAtEnd = tracking.isPinnedToBottom
            tracking.isPinnedToBottom = true
            anchorsBottomOnGrowth = true
            if wasAtEnd {
                // Already there: the message and the working line appear in place.
                withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(edge: .bottom) }
            }
        }
        .onChange(of: scrollState.jumpRequest) {
            tracking.isPinnedToBottom = true
            anchorsBottomOnGrowth = true
            withAnimation(.smooth(duration: 0.35)) { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: runtime.threadID) {
            // A new thread starts with a fresh window on its newest messages, and no
            // block from the old one is on screen any more.
            visibleCount = TimelineWindow.firstPaint
            anchorsBottomOnGrowth = true
            historyLoadPending = false
            tracking.clearVisible()
        }
    }

    /// The content just moved under the pointer. Freezes hover and hit-testing on the
    /// rows if they are not already, and (re)arms the watch that lifts the freeze once
    /// no frame has moved for 150ms. The timestamp lives on the tracking object, so
    /// noting a frame's movement writes no view state.
    private func noteScrollMovement() {
        tracking.lastMovementAt = CACurrentMediaTime()
        guard !isReaderScrolling else { return }
        isReaderScrolling = true
        settleWatch?.cancel()
        settleWatch = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                if CACurrentMediaTime() - tracking.lastMovementAt >= 0.15 {
                    isReaderScrolling = false
                    return
                }
            }
        }
    }

    private func liftScrollFreeze() {
        settleWatch?.cancel()
        settleWatch = nil
        if isReaderScrolling { isReaderScrolling = false }
    }

    /// Puts the viewport back on the conversation when a layout pass has left it showing
    /// nothing. The lazy stack lays out rows for the viewport it was last told about, and
    /// nothing tells it when an anchor moves the offset under it: a finished turn folding
    /// its transcript into one block, the working line coming and going, rows reflowing to
    /// a new width. Left alone (the app in the back, another thread open) the conversation
    /// changes shape many times over, and the reader comes back to an empty pane that only
    /// their own scrolling fills in. This runs on request only: when no row has been on
    /// screen for a beat, when a scroll phase that never settled is cleared, and when the
    /// app or its window comes back to the front.
    ///
    /// Past the end, or pinned to the end and away from it, the timeline snaps to the end,
    /// as it does on any measured frame. On the conversation but showing nothing, it does
    /// what the reader would: scrolls, by a point, so the stack lays out for where the
    /// viewport really is. Still nothing a beat later, the stack is rebuilt; still nothing,
    /// the timeline goes to the end and stays pinned there. Rows coming back on screen
    /// end the sequence wherever it is, and a fourth blank in a row is left alone.
    private func repairLayout() {
        guard viewportHeight > 0, !tracking.isUserScrolling, !tracking.isCoasting else { return }
        let distance = tracking.distanceFromBottom
        if distance < -1 || (tracking.isPinnedToBottom && abs(distance) > 1) {
            withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
            // Rows on screen: the snap was all there was to do.
            guard tracking.showsNothing, tracking.blankRepairs < 3 else { return }
        } else if tracking.showsNothing {
            switch tracking.blankRepairs {
            case 0:
                // A scroll to a row the stack must lay out: the message the reader was on,
                // else the end. A point's nudge, the earlier repair, could leave a stack
                // that had dropped its heights exactly where it was.
                if let id = tracking.activeBlockID {
                    withTransaction(Self.unanimated) { position.scrollTo(id: id, anchor: .top) }
                } else {
                    withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
                }
            case 1:
                stackGeneration += 1
            case 2:
                tracking.isPinnedToBottom = true
                anchorsBottomOnGrowth = true
                withTransaction(Self.unanimated) { position.scrollTo(edge: .bottom) }
            default:
                return
            }
        } else {
            return
        }
        // Blank, and something was just done about it: checked again a beat from now.
        tracking.blankRepairs += 1
        tracking.armBlankWatch()
    }

    private nonisolated static func visibleHeight(_ proxy: GeometryProxy) -> CGFloat {
        max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
    }
}

/// Scroll-driven facts about the timeline, kept out of view state so reporting them never
/// re-renders the conversation. Every write is guarded against no-ops: an observable write
/// notifies its readers whether or not the value moved. It also keeps watch over the
/// layout: which rows are on screen, whether a scroll phase has really ended, and when the
/// timeline should check that it is showing anything at all.
@MainActor
@Observable
final class TimelineScrollTracking {
    /// Whether new text keeps the timeline at the conversation's end.
    var isPinnedToBottom = true
    /// True while the reader drags or flicks the timeline, as opposed to it following new text.
    @ObservationIgnored var isUserScrolling = false
    /// When the content last moved, for lifting the scroll freeze.
    @ObservationIgnored var lastMovementAt: CFTimeInterval = 0
    /// True while a flick coasts or a programmatic scroll animates: movement that must
    /// not freeze the rows, since a click may land any moment.
    @ObservationIgnored var isCoasting = false
    /// The message the reader is on, for the rail: the sent message at or above the block
    /// in the middle of what is on screen. Written only when it changes, so the rail
    /// re-renders when the lit tick moves and never else.
    private(set) var activeBlockID: String?
    /// The blocks as laid out, in order, and which of them are sent messages.
    @ObservationIgnored private var outlineIDs: [String] = []
    @ObservationIgnored private var outlineSet: Set<String> = []
    @ObservationIgnored private var userBlockIDs: Set<String> = []
    /// The blocks currently intersecting the viewport, from their own visibility callbacks.
    @ObservationIgnored private var visibleIDs: Set<String> = []
    /// The offset and the distance from the end as last measured, for a repair to read
    /// without waiting for another frame, and when the offset last moved.
    @ObservationIgnored private(set) var offset: CGFloat = 0
    @ObservationIgnored private(set) var distanceFromBottom: CGFloat = 0
    @ObservationIgnored private var lastOffsetChangeAt: CFTimeInterval = 0
    @ObservationIgnored private var phaseWatch: Task<Void, Never>?
    @ObservationIgnored private var blankWatch: Task<Void, Never>?
    /// How many repairs the current blank has had, so they escalate and then stop. Any
    /// row coming on screen starts the count over.
    @ObservationIgnored var blankRepairs = 0
    /// Bumped when the timeline should look at its own layout (`ThreadTimeline.repairLayout`).
    private(set) var checkRequest = 0

    /// Rows to show, and none of them on screen.
    var showsNothing: Bool {
        !outlineIDs.isEmpty && visibleIDs.isDisjoint(with: outlineSet)
    }

    /// Returns whether the outline changed.
    @discardableResult
    func setOutline(_ blocks: [(id: String, hasUserMessage: Bool)]) -> Bool {
        let ids = blocks.map(\.id)
        guard ids != outlineIDs else { return false }
        outlineIDs = ids
        outlineSet = Set(ids)
        userBlockIDs = Set(blocks.filter(\.hasUserMessage).map(\.id))
        resolveActive()
        return true
    }

    func setVisible(_ id: String, _ isVisible: Bool) {
        if isVisible {
            guard visibleIDs.insert(id).inserted else { return }
            // Something is on screen: no blank to repair, and the next one starts fresh.
            blankWatch?.cancel()
            blankWatch = nil
            blankRepairs = 0
        } else {
            guard visibleIDs.remove(id) != nil else { return }
            // The last row left the screen. A replacement normally lands within the
            // frame; the watch catches the case where nothing does.
            if showsNothing { armBlankWatch() }
        }
        resolveActive()
    }

    func clearVisible() {
        visibleIDs.removeAll()
        if activeBlockID != nil { activeBlockID = nil }
    }

    func noteGeometry(offset: CGFloat, distanceFromBottom: CGFloat) {
        if offset != self.offset { lastOffsetChangeAt = CACurrentMediaTime() }
        self.offset = offset
        self.distanceFromBottom = distanceFromBottom
    }

    /// A phase's end is not always delivered: content growing under an animated scroll
    /// cuts it short, and the app going to the back mid-flick loses the last event. Left
    /// as reported, the timeline would count itself as moving for good and never snap or
    /// repair again. Coasting with the offset at rest for 400ms is over, whatever was
    /// said, and the layout gets checked once it is.
    func notePhase(_ phase: ScrollPhase) {
        isUserScrolling = phase == .interacting || phase == .decelerating
        isCoasting = phase == .decelerating || phase == .animating
        phaseWatch?.cancel()
        phaseWatch = nil
        guard isCoasting else { return }
        lastOffsetChangeAt = CACurrentMediaTime()
        phaseWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                guard CACurrentMediaTime() - lastOffsetChangeAt >= 0.4 else { continue }
                isUserScrolling = false
                isCoasting = false
                checkRequest += 1
                return
            }
        }
    }

    /// Looks a beat from now for any row on screen; none, with rows to show, asks the
    /// timeline to repair its layout. Re-armed by every call; a row reporting itself
    /// visible disarms it.
    func armBlankWatch() {
        blankWatch?.cancel()
        blankWatch = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, showsNothing else { return }
            checkRequest += 1
        }
    }

    /// The reader is back in front of the timeline: whatever it did unseen, it checks
    /// itself now, with a full run of repairs available.
    func noteReturnToFront() {
        blankRepairs = 0
        checkRequest += 1
        armBlankWatch()
    }

    /// Takes the block in the middle of the on-screen run — a reply filling the viewport is
    /// that block on its own — and lights the sent message at or above it.
    private func resolveActive() {
        let onScreen = outlineIDs.enumerated().filter { visibleIDs.contains($0.element) }
        guard !onScreen.isEmpty else { return }
        let middle = onScreen[onScreen.count / 2].offset
        let resolved = outlineIDs[...middle].last { userBlockIDs.contains($0) }
        if resolved != activeBlockID { activeBlockID = resolved }
    }
}

/// Bumps when the app comes to the front or one of its windows is uncovered: the moments
/// a reader comes back to a timeline that has been changing unseen.
@MainActor
@Observable
private final class FrontMonitor {
    static let shared = FrontMonitor()
    private(set) var revision = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        })
        observers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Delivered on the main queue; the window is read on the main actor it belongs to.
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let window = object as? NSWindow, window.occlusionState.contains(.visible) else { return }
                self?.revision += 1
            }
        })
    }
}

/// Scroll measurements, built by a plain initializer rather than an inline closure.
/// Deliberately minimal: every stored field is compared every scroll frame, and any
/// write to view state here would re-render the timeline mid-scroll.
private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    var distanceFromBottom: CGFloat
    var travel: CGFloat
    /// The viewport's vertical centre in the content: the sign that it moved.
    var centerY: CGFloat
    /// The raw offset, which only a scroll changes; the centre moves with the viewport's height too.
    var offset: CGFloat

    init(geometry: ScrollGeometry) {
        centerY = geometry.visibleRect.midY
        offset = geometry.contentOffset.y
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
        let insets = geometry.contentInsets.top + geometry.contentInsets.bottom
        // Never more than the content can actually scroll. While the queue tab folds,
        // the bottom inset shrinks a frame ahead of the filler that keeps a short
        // conversation at the pane's bottom, so the bottom anchor briefly lifts empty
        // space under the chrome; the veil would flash over nothing.
        let excess = max(0, geometry.contentSize.height + insets - geometry.containerSize.height)
        travel = min(max(0, geometry.contentOffset.y + geometry.contentInsets.top), excess)
        if geometry.contentSize.height + insets <= geometry.containerSize.height + 1 {
            distanceFromBottom = 0
        } else {
            distanceFromBottom = geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.contentOffset.y - geometry.containerSize.height
        }
    }
}

enum TimelineGroup: Identifiable, Equatable {
    case single(TimelineEntry)
    /// A run of tool entries. `startsCollapsed` is true when reply text follows
    /// the run, so past work renders as one tappable summary line above the answer.
    case work(id: String, entries: [TimelineEntry], startsCollapsed: Bool)

    var id: String {
        switch self {
        case .single(let entry): entry.id
        case .work(let id, _, _): id
        }
    }

    @MainActor
    static func build(_ entries: [TimelineEntry], showReasoning: Bool) -> [TimelineGroup] {
        // Positions of replies. A work run sitting before one has been moved on from, so it
        // starts collapsed. Kind only, never the text: reading streaming content here made the
        // whole timeline regroup on every token. A reply row is created by its first delta.
        var replyIndices: [Int] = []
        for (index, entry) in entries.enumerated() where entry.kind == .assistant {
            replyIndices.append(index)
        }
        var groups: [TimelineGroup] = []
        var work: [TimelineEntry] = []
        var workStart = 0

        func flushWork() {
            guard let first = work.first else { return }
            let workEnd = workStart + work.count - 1
            let collapsed = replyIndices.contains { $0 > workEnd }
            groups.append(.work(id: "work-\(first.id)", entries: work, startsCollapsed: collapsed))
            work.removeAll()
        }

        for (index, entry) in entries.enumerated() {
            switch entry.kind {
            case .tool:
                if let last = work.last, last.turnID != entry.turnID { flushWork() }
                if work.isEmpty { workStart = index }
                work.append(entry)
            case .reasoning:
                // Thinking lives behind the working indicator's chevron, never as a row of its own.
                continue
            default:
                flushWork()
                groups.append(.single(entry))
            }
        }
        flushWork()
        return groups
    }
}

/// A finished turn collapses to its final response plus its file summary, so the
/// chat stays clean. The chevron re-opens the turn's full steps. Running turns
/// and entries without a turn render as plain groups, exactly as before.
///
/// Equatable, so a rebuilt timeline can tell an unchanged block from a changed one and
/// skip its row. Entries compare by identity: what a row shows of an entry it observes
/// itself, so the same entry object always means the same row.
enum DisplayBlock: Identifiable, Equatable {
    case turn(id: String, turnID: UUID, userEntries: [TimelineEntry], content: [TimelineEntry], summary: TurnSummary)
    /// A plain group, with the facts its row needs from the turn it belongs to: the turn's
    /// summary on the turn's last reply, and whether the turn produced a reply on its end marker.
    case group(TimelineGroup, summary: TurnSummary?, hasReply: Bool)
    /// The running turn's working line, with the tool run in progress it carries. Never built
    /// from the entries: the timeline appends it while the turn is waiting on a reply.
    case working(turnID: UUID?, liveWork: [TimelineEntry])

    var id: String {
        switch self {
        case .turn(let id, _, _, _, _): id
        case .group(let group, _, _): group.id
        case .working(let turnID, _): "working-\(turnID?.uuidString ?? "")"
        }
    }

    /// The turn the block belongs to, for the revert controls.
    var turnID: UUID? {
        switch self {
        case .turn(_, let turnID, _, _, _): turnID
        case .group(.single(let entry), _, _): entry.turnID
        case .group(.work, _, _), .working: nil
        }
    }

    /// Whether the block holds a message the user sent (a turn prompt or a
    /// standalone user message). Only these get rail ticks.
    var hasUserMessage: Bool {
        switch self {
        case .turn(_, _, let userEntries, _, _): !userEntries.isEmpty
        case .group(.single(let entry), _, _): entry.kind == .user
        case .group(.work, _, _), .working: false
        }
    }

    @MainActor
    static func build(_ entries: [TimelineEntry], meta: TimelineMeta, showReasoning: Bool) -> [DisplayBlock] {
        // Partition into contiguous runs sharing one turnID (nil groups together),
        // so a finished turn becomes one collapsible block.
        var runs: [(turnID: UUID?, entries: [TimelineEntry])] = []
        for entry in entries {
            if runs.last?.turnID == entry.turnID {
                runs[runs.count - 1].entries.append(entry)
            } else {
                runs.append((entry.turnID, [entry]))
            }
        }
        var blocks: [DisplayBlock] = []
        for run in runs {
            if let turnID = run.turnID, let summary = meta.summaryByTurn[turnID] {
                let users = run.entries.filter { $0.kind == .user }
                let content = run.entries.filter { $0.kind != .user && $0.kind != .turnEnd && $0.kind != .reasoning }
                blocks.append(.turn(id: "turn-\(turnID.uuidString)", turnID: turnID, userEntries: users, content: content, summary: summary))
            } else {
                for group in TimelineGroup.build(run.entries, showReasoning: showReasoning) {
                    blocks.append(.group(group, summary: meta.summary(for: group), hasReply: meta.hasReply(for: group)))
                }
            }
        }
        return blocks
    }
}

/// Lazy-loading window for the timeline: only the newest groups are materialized, so
/// the number of live views stays bounded even for very long threads.
/// Opening a thread builds and lays out every block in the window before the first
/// frame — the bottom anchor needs the content's full height, and a block costs several
/// milliseconds — so the window opens with a handful, grows to its resting size a beat
/// later, and then a page at a time as the reader scrolls back.
enum TimelineWindow {
    static let firstPaint = 6
    static let initial = 24
    static let page = 24
}

/// Per-turn facts computed once per timeline pass, so rows never scan the thread to
/// find their own summary. `kind`, `id` and `turnID` are fixed for a row's lifetime,
/// and finished turn summaries never change, so building this never costs renders
/// while streaming.
struct TimelineMeta {
    var lastAssistantIDByTurn: [UUID: String] = [:]
    var summaryByTurn: [UUID: TurnSummary] = [:]
    var turnsWithReply: Set<UUID> = []

    @MainActor
    static func build(_ entries: [TimelineEntry]) -> TimelineMeta {
        var meta = TimelineMeta()
        for entry in entries {
            switch entry.kind {
            case .assistant:
                if let turnID = entry.turnID {
                    meta.lastAssistantIDByTurn[turnID] = entry.id
                    meta.turnsWithReply.insert(turnID)
                }
            case .turnEnd:
                if case .turnEnd(let summary) = entry.item.content {
                    meta.summaryByTurn[summary.turnID] = summary
                }
            default:
                break
            }
        }
        return meta
    }

    /// The turn's summary, shown on the turn's last reply only. A dictionary lookup,
    /// so rows never scan the thread.
    @MainActor
    func summary(for group: TimelineGroup) -> TurnSummary? {
        guard case .single(let entry) = group, entry.kind == .assistant,
              let turnID = entry.turnID, lastAssistantIDByTurn[turnID] == entry.id else { return nil }
        return summaryByTurn[turnID]
    }

    /// Whether a turn-end marker's turn produced a reply; when it did, the duration lives
    /// on the reply's hover line instead.
    @MainActor
    func hasReply(for group: TimelineGroup) -> Bool {
        guard case .single(let entry) = group, entry.kind == .turnEnd, let turnID = entry.turnID else { return false }
        return turnsWithReply.contains(turnID)
    }
}

/// What a row needs from outside its block, as plain values. Rows never read the app
/// model or the runtime's turn list themselves, so a change anywhere else in the app
/// never re-renders them; only a change to these values does.
struct RowContext: Equatable {
    var workingDirectory: String?
    /// Whether the block's turn can be reverted right now.
    var canRewind: Bool
}

private struct DisplayBlockView: View, Equatable {
    let block: DisplayBlock
    let runtime: ThreadRuntime
    let context: RowContext

    nonisolated static func == (lhs: DisplayBlockView, rhs: DisplayBlockView) -> Bool {
        lhs.block == rhs.block && lhs.runtime === rhs.runtime && lhs.context == rhs.context
    }

    var body: some View {
        switch block {
        case .group(let group, let summary, let hasReply):
            TimelineGroupView(group: group, runtime: runtime, summary: summary, hasReply: hasReply, context: context)
        case .turn(_, let turnID, let userEntries, let content, let summary):
            TurnFinishedBlock(
                runtime: runtime,
                turnID: turnID,
                summary: summary,
                userEntries: userEntries,
                content: content,
                workingDirectory: context.workingDirectory,
                canUndo: context.canRewind
            )
        case .working(_, let liveWork):
            WorkingBlockView(runtime: runtime, liveWork: liveWork, workingDirectory: context.workingDirectory)
        }
    }
}

struct TimelineGroupView: View {
    let group: TimelineGroup
    let runtime: ThreadRuntime
    /// The turn's summary, when this group is the turn's last reply.
    let summary: TurnSummary?
    /// Whether the turn produced a reply, for a turn-end marker.
    let hasReply: Bool
    let context: RowContext

    var body: some View {
        switch group {
        case .single(let entry):
            switch entry.kind {
            case .user: UserMessageRow(entry: entry, runtime: runtime, canRevert: context.canRewind)
            case .assistant: AssistantMessageRow(entry: entry, summary: summary)
            case .reasoning: EmptyView()
            case .tool: WorkGroup(entries: [entry], runtime: runtime, workingDirectory: context.workingDirectory)
            case .plan: PlanCard(entry: entry, runtime: runtime)
            case .todos: TodoListRow(entry: entry)
            case .notice: NoticeRow(entry: entry)
            case .turnEnd:
                if case .turnEnd(let summary) = entry.item.content {
                    TurnEndRow(summary: summary, hasReply: hasReply)
                }
            }
        case .work(_, let entries, let startsCollapsed):
            WorkGroup(entries: entries, runtime: runtime, workingDirectory: context.workingDirectory, startsCollapsed: startsCollapsed)
        }
    }
}

/// The one line a running turn shows: Zeron's gradient pulse, what the agent is doing
/// right now (the live tool run's summary, or a word that changes every few seconds
/// before any tool starts) and the elapsed time. Collapsed by default; the chevron
/// opens the thinking (when shown) and the run's steps beneath it.
private struct WorkingIndicator: View {
    let runtime: ThreadRuntime
    let startedAt: Date
    let seed: UInt64
    /// The running turn's thinking. When there is any, a chevron opens it beneath the indicator.
    let thinkingSteps: [ThinkingStep]
    /// The tool run in progress, folded into this line while it runs.
    let liveWork: [TimelineEntry]
    var workingDirectory: String?
    @State private var now = Date.now
    @State private var isExpanded = false

    /// The one motion for whatever changes on the line: the words, the chevron.
    private static let change = Animation.smooth(duration: 0.3)

    var body: some View {
        let elapsed = now.timeIntervalSince(startedAt)
        let word = WorkingWords.word(seed: seed, elapsedSeconds: Int64(max(0, elapsed)))
        let label = liveWork.isEmpty ? "\(word)…" : WorkGroupSummary.text(for: liveWork)
        let canExpand = !thinkingSteps.isEmpty || !liveWork.isEmpty
        VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
            Button {
                guard canExpand else { return }
                withAnimation(.snappy(duration: 0.24)) { isExpanded.toggle() }
            } label: {
                // One piece: the pulse, the words, the time and the chevron are laid out
                // together and change together. The words cross-fade in place and the chevron
                // fades in its own slot, on one animation, so no part of the line ever appears
                // or moves on a beat of its own; the line itself arrives as one row, with the
                // transition every block gets.
                HStack(spacing: TimelineMetrics.iconSpacing) {
                    WorkingSpinner(cellSize: 3.5)
                        .frame(width: TimelineMetrics.iconWidth)
                    Text(verbatim: label)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                    Text(RelativeTime.duration(elapsed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(canExpand ? 1 : 0)
                        .accessibilityHidden(!canExpand)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(canExpand ? (isExpanded ? "Hide these steps" : "Show these steps") : "")
            .accessibilityHint(canExpand ? Text("Shows what the agent is doing") : Text(""))

            if isExpanded, canExpand {
                if !thinkingSteps.isEmpty {
                    VStack(alignment: .leading, spacing: TimelineMetrics.rowSpacing) {
                        ForEach(Array(thinkingSteps.enumerated()), id: \.offset) { _, step in
                            MarkdownView(text: step.text, isStreaming: step.isStreaming).equatable()
                        }
                    }
                    .foregroundStyle(.secondary)
                    .environment(\.markdownPointSize, 12)
                    .environment(\.markdownDimmed, true)
                    .padding(.leading, TimelineMetrics.iconWidth + TimelineMetrics.iconSpacing)
                    .transition(.softAppear)
                }
                if !liveWork.isEmpty {
                    WorkSteps(entries: liveWork, runtime: runtime, workingDirectory: workingDirectory)
                        .transition(.softAppear)
                }
            }
        }
        .animation(Self.change, value: label)
        .animation(Self.change, value: canExpand)
        .font(.callout)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = .now
            }
        }
    }
}

/// One piece of the running turn's thinking, and whether it is still arriving.
struct ThinkingStep: Equatable {
    var text: String
    var isStreaming: Bool
}

/// Whether the reader has scrolled away from the latest message, shared with the composer that shows the jump button.
@MainActor
@Observable
final class TimelineScrollState {
    var showsJumpButton = false
    private(set) var jumpRequest = 0

    func jumpToLatest() {
        jumpRequest += 1
    }
}

/// The working block's row: the indicator with the running turn's thinking behind its
/// chevron. The timeline appends and drops the block, so this holds no condition of its own
/// and no transition: the row arrives and leaves exactly like every other block. The indicator
/// is one row tall, like a reply, so the reply that takes its line begins where its text was.
private struct WorkingBlockView: View {
    @Environment(AppModel.self) private var model
    let runtime: ThreadRuntime
    /// The tool run in progress, shown on the working line instead of as a group.
    let liveWork: [TimelineEntry]
    let workingDirectory: String?

    var body: some View {
        WorkingIndicator(
            runtime: runtime,
            startedAt: runtime.turnStartedAt ?? .now,
            seed: WorkingWords.seed(runtime.threadID.uuidString),
            thinkingSteps: model.settings.showReasoning ? thinking : [],
            liveWork: liveWork,
            workingDirectory: workingDirectory
        )
    }

    /// The running turn's thinking. Kind and turn are fixed at creation, so they are checked before
    /// any content is read.
    private var thinking: [ThinkingStep] {
        guard let turnID = runtime.entries.last.flatMap(\.turnID) else { return [] }
        // Walks back from the end and stops at the previous turn, so streamed thinking never rescans the thread.
        var steps: [ThinkingStep] = []
        for entry in runtime.entries.reversed() {
            guard let entryTurn = entry.turnID else { continue }
            guard entryTurn == turnID else { break }
            guard entry.kind == .reasoning, case .reasoning(let block) = entry.item.content, !block.text.isEmpty else { continue }
            steps.append(ThinkingStep(text: block.text, isStreaming: block.isStreaming))
        }
        return steps.reversed()
    }
}
