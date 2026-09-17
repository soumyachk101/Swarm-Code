import Foundation
import SwiftUI

// Hydra: one chat, many heads. With Hydra on, the chat's agent leads a team of helper
// agents ("heads") that it sends out on the parts of a big job, in parallel. Claude, Codex
// and Copilot run the heads natively, inside their own session, with the model and effort
// from the pair the user set up; every other provider gets Droppy-run heads, each a thread
// of its own, and hands their reports back to the lead as the next message. A pair may
// also send the heads out on another provider than the lead's (a Claude lead over Gemini
// heads, say): then they are Droppy-run whatever the lead's provider, and the lead asks for
// them the way the other providers do.

/// A purpose-tuned head configuration on a pair ("quick", "deep"): the lead routes a
/// delegation to it by name and that head runs on the profile's model and effort instead
/// of the pair's shared worker fields. A nil field inherits the pair's: no provider keeps
/// the head on the pair's heads provider, no model or effort takes the pair's own.
struct HydraHeadProfile: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    /// The name the lead writes in a delegation's `profile` field; free-form, so the
    /// name itself carries the purpose ("quick", "visual", "docs").
    var name: String
    var provider: ProviderKind?
    var model: String?
    var effort: String?

    init(name: String) {
        id = UUID()
        self.name = name
    }

    /// The profile in words for the lead's brief: "deep (claude-opus-5 on Anthropic)".
    var briefLabel: String {
        let on = [model, provider?.displayName].compactMap { $0 }.joined(separator: " on ")
        return on.isEmpty ? name : "\(name) (\(on))"
    }

    /// The name as it appears in agent names ("Deep Work" gives "deep-work"), so the
    /// profile a native spawn names can be matched back whatever the spacing or case.
    var agentSlug: String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    /// Whether a delegation's `profile` names this one: case-insensitive, and blind to
    /// the whitespace a name typed in Settings or written in a lead's JSON can carry. An
    /// agent slug ("deep-work" from a spawned agent's name) matches the same way.
    func matches(_ name: String) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
            || agentSlug == wanted
    }
}

/// A lead-and-heads pairing: which model runs the heads when a chat on this provider leads.
/// `orchestratorModel` nil means any model on the provider; a nil worker field means the
/// heads inherit the chat's own model or effort. `workerProvider` nil keeps the heads on
/// the lead's provider; set, they run there instead, on `workerModel` or that provider's
/// default model, with `workerEffort` from that provider's own efforts.
struct HydraPair: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var provider: ProviderKind
    var orchestratorModel: String?
    var orchestratorEffort: String?
    var workerProvider: ProviderKind?
    var workerModel: String?
    var workerEffort: String?
    /// How many heads may work at once; nil puts no cap on them, as with no pair at all.
    var maxHeads: Int?
    /// The name the user gave the pair, shown wherever the pair is named in place of its models; nil or blank is none.
    var name: String?
    /// The purpose-tuned heads of the pair's advanced mode; empty, every head runs on the
    /// shared worker fields above, as before.
    var headProfiles: [HydraHeadProfile]

    static let maxHeadsRange = 1...8

    init(provider: ProviderKind) {
        id = UUID()
        self.provider = provider
        headProfiles = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.value(.id, default: UUID())
        provider = try container.decode(ProviderKind.self, forKey: .provider)
        orchestratorModel = container.value(.orchestratorModel, default: nil)
        orchestratorEffort = container.value(.orchestratorEffort, default: nil)
        workerProvider = container.value(.workerProvider, default: nil)
        workerModel = container.value(.workerModel, default: nil)
        workerEffort = container.value(.workerEffort, default: nil)
        name = container.value(.name, default: nil)
        maxHeads = Self.clampedCap(container.value(.maxHeads, default: nil))
        headProfiles = container.value(.headProfiles, default: [])
    }

    /// The provider the heads run on: the lead's, unless the pair sends them elsewhere.
    var headsProvider: ProviderKind { workerProvider ?? provider }

    /// Whether the heads run on another provider than the lead.
    var sendsHeadsElsewhere: Bool { workerProvider.map { $0 != provider } ?? false }

    /// The user's name for the pair, trimmed, or nil when there is none.
    var customName: String? {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A cap kept inside the range, or none.
    static func clampedCap(_ cap: Int?) -> Int? {
        cap.map { min(max($0, maxHeadsRange.lowerBound), maxHeadsRange.upperBound) }
    }

    /// The pair a project's new chats start on. The rule applies only when all three hold:
    /// Hydra is on, the project names a pair, and that pair is in `available` (the pairs
    /// the model picker can offer now). In every other case the result is nil and the
    /// caller uses its own fallback.
    static func projectPair(_ id: UUID?, hydraOn: Bool, in available: [HydraPair]) -> HydraPair? {
        guard hydraOn, let id else { return nil }
        return available.first { $0.id == id }
    }
}

/// What a session launches with while Hydra is on: where the heads run and on what,
/// resolved from the pair, and how many may run at once.
struct HydraLaunch: Hashable, Sendable {
    /// The provider the heads run on: the lead's own, unless the pair sends them out on
    /// another one (see `HydraPair.workerProvider`).
    var headsProvider: ProviderKind
    /// Whether the lead's provider runs the heads inside its own session: only with the
    /// heads on the lead's provider, and only where it has heads of its own (Claude, Codex,
    /// Copilot). Otherwise the heads are Droppy-run threads, whatever the lead runs on, and
    /// the lead asks for them with the delegation block.
    var runsNatively: Bool
    /// The heads' model and provider in words, for the lead's brief, when they run on
    /// another provider than the lead: "Gemini 3.8 Flash on Antigravity".
    var headsLabel: String?
    /// The heads' provider's own model id for the heads, or nil to inherit the lead's model
    /// (on the lead's provider) or take the heads' provider's default (elsewhere).
    var workerModel: String?
    var workerEffort: String?
    /// The cap on heads at work at once: the lower of the pair's and the Hydra page's;
    /// nil, with neither set, lets as many out as the work asks for.
    var maxHeads: Int?
    /// The pair's purpose-tuned heads (its advanced mode): a delegation naming one runs
    /// on that profile's model and effort. Empty, every head takes the worker fields.
    var headProfiles: [HydraHeadProfile] = []
    /// Whether Droppy-run heads get copies of the checkout of their own.
    var isolatesHeads = true
    /// Whether Droppy Code lands the team's finished work itself (see
    /// `AppModel.autoMergeHydraWork`); the lead is told so it never merges by hand.
    var autoMerges = false
    /// Whether the lead audits each head's landed work before it finishes (the
    /// `hydraReviewHeads` setting): it reads the files the reports name and corrects what
    /// is wrong itself, rather than trusting the reports or sending out a head to check.
    var reviewsHeads = false
    /// The projects in the sidebar, the chat's own first: the lead may send a head to any
    /// of them by name, and its work lands and merges there.
    var projects: [HydraProjectRef] = []

    /// How many Droppy-run heads may work at once for a pair with no cap of its own. The
    /// tasks past it wait their turn (`ThreadRuntime.spawnWaitingHeads`) and go out as
    /// heads finish, so a lead may still ask for as many as the job needs. Twenty-one heads
    /// at once each streaming into the app, each on its own copy of the checkout and its
    /// own CLI, kept the main thread and the GPU busy past the point of answering, and
    /// the app had to be force quit.
    static let uncappedConcurrency = 8

    /// Whether one more head may go out with `running` already at work.
    func hasRoom(running: Int) -> Bool {
        running < (maxHeads ?? Self.uncappedConcurrency)
    }

    /// The profile a delegation asked for; nil when the name matches none, and the head
    /// then runs on the worker fields like any unrouted one.
    func profile(named name: String) -> HydraHeadProfile? {
        headProfiles.first { $0.matches(name) }
    }
}

/// How much a Droppy-run head gets for one turn, on any provider: a nudge when it only
/// reads, a word to wrap up, then a stop and one more turn for its report, so the lead
/// always hears back. The API sessions pace themselves with these from inside the turn;
/// every other provider gets the stop from the head's runtime.
enum HydraBudget {
    /// Tools without a change before the head is asked to act.
    static let pacingTools = 24
    /// The wrap-up and the hard stop are wide enough for a real piece of work: a head cut
    /// off in the middle of a refactor costs the lead more than a slow head does.
    static let wrapUpTools = 120
    static let maxTools = 160
    static let wrapUpSeconds: TimeInterval = 25 * 60
    static let maxSeconds: TimeInterval = 35 * 60
    /// What a stopped head gets to write its report in.
    static let reportSeconds: TimeInterval = 3 * 60

    static let pacingNote = "[Droppy Code] You have run \(pacingTools) tools without changing a file. If the task is research, reply with your findings now. Otherwise act on what you know: make the change, or reply with what blocks you."
    static let wrapUpNote = "[Droppy Code] Your budget is nearly spent. Finish now: complete the smallest correct version of the task, then reply with your report."
    static let finalNote = "[Droppy Code] Your budget is spent and your tools are gone. Reply now with your report: what you changed, how far it got, and what is left."
}

/// A head's identity: its name, its colour and the dragon head that is its glyph.
struct HydraPersona: Hashable, Sendable {
    let name: String
    /// The asset with the head's own dragon: one of twenty-five, drawn as a template so
    /// it takes the head's colour.
    let asset: String
    /// The colour as 0xRRGGBB.
    let hex: UInt32

    init(_ name: String, _ asset: String, _ hex: UInt32) {
        self.name = name
        self.asset = asset
        self.hex = hex
    }

    var color: Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The names heads are given, in the order they are sent out, each with a dragon head
/// of its own. Past twenty-five the roster starts over with a number after the name.
enum HydraRoster {
    static let personas: [HydraPersona] = [
        HydraPersona("Hank", "hydra-head-01", 0xFF8A3D),
        HydraPersona("Walter", "hydra-head-02", 0x3D8BFF),
        HydraPersona("Ada", "hydra-head-03", 0x34C46A),
        HydraPersona("Otto", "hydra-head-04", 0xA35BE0),
        HydraPersona("Nova", "hydra-head-05", 0xF25C9A),
        HydraPersona("Remy", "hydra-head-06", 0x2BB5B0),
        HydraPersona("Iris", "hydra-head-07", 0xE8B430),
        HydraPersona("Milo", "hydra-head-08", 0xE84F4F),
        HydraPersona("Juno", "hydra-head-09", 0x6A5CFF),
        HydraPersona("Ezra", "hydra-head-10", 0x4FD1A1),
        HydraPersona("Lena", "hydra-head-11", 0x2FB8E6),
        HydraPersona("Bo", "hydra-head-12", 0xB0784A),
        HydraPersona("Kai", "hydra-head-13", 0x8FD14F),
        HydraPersona("Vera", "hydra-head-14", 0xD946EF),
        HydraPersona("Finn", "hydra-head-15", 0xF97316),
        HydraPersona("Mira", "hydra-head-16", 0xC084FC),
        HydraPersona("Odin", "hydra-head-17", 0xB45309),
        HydraPersona("Suki", "hydra-head-18", 0xF472B6),
        HydraPersona("Rex", "hydra-head-19", 0x2563EB),
        HydraPersona("Zola", "hydra-head-20", 0x65A30D),
        HydraPersona("Pip", "hydra-head-21", 0x94A3B8),
        HydraPersona("Ivo", "hydra-head-22", 0x0D9488),
        HydraPersona("Lux", "hydra-head-23", 0xFACC15),
        HydraPersona("Tova", "hydra-head-24", 0x059669),
        HydraPersona("Gus", "hydra-head-25", 0x7DD3FC),
    ]

    static func persona(at index: Int) -> HydraPersona {
        let count = personas.count
        let base = personas[((index % count) + count) % count]
        let round = max(0, index) / count
        guard round > 0 else { return base }
        return HydraPersona("\(base.name) \(round + 1)", base.asset, base.hex)
    }

    /// The roster index for an announced head name, case-insensitive, without any
    /// round suffix ("otto", "Otto 2"). Nil when the name is not on the roster (a
    /// lead inventing names says "Ives", say, which is nobody: the nearest roster
    /// name is "Ivo"). Only exact roster names are authoritative; anything else
    /// falls back to the next sequential head so an announcement never renames a
    /// stranger into the team.
    static func index(named name: String) -> Int? {
        var bare = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A trailing round number ("Otto 2") is the display suffix, not the name.
        if let space = bare.lastIndex(of: " "), Int(bare[bare.index(after: space)...]) != nil {
            bare = String(bare[..<space]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return personas.firstIndex { $0.name.compare(bare, options: .caseInsensitive) == .orderedSame }
    }
}

/// A head thread's place in its lead's team: who it is, what it was sent to do, how it
/// runs and how far it has got.
struct HydraHeadInfo: Codable, Hashable, Sendable {
    /// Native heads run inside the lead's own provider session; Droppy-run heads are
    /// sessions of their own that Droppy Code starts and reports back for.
    enum Kind: String, Codable, Sendable {
        case native
        case droppy
    }

    /// Delegated by the lead, queued by the user while the lead worked, or sent by the
    /// user straight to a head with "Every message goes to a head" on.
    enum Origin: String, Codable, Sendable {
        case delegated
        case queued
        case sent
    }

    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
        case stopped

        var isFinished: Bool { self != .running }
    }

    /// The head's place in the roster: its name, colour and shape.
    var index: Int
    var task: String
    var kind: Kind
    var origin: Origin
    var status: Status = .running
    /// The head's report, once it has one: the provider's summary for a native head, the
    /// final reply for a Droppy-run one.
    var summary: String?
    /// The provider's one-line progress note, or the last tool the head used.
    var activity: String?
    var toolCalls = 0
    var tokens = 0
    var startedAt = Date.now
    var finishedAt: Date?
    /// The provider's id for a native head: Claude's spawning tool call, Codex's child
    /// thread, Copilot's agent id.
    var nativeID: String?
    /// Claude's task id, which is what stops a running head.
    var nativeTaskID: String?
    /// The tool row in the lead's timeline that stands for this head.
    var toolUseID: String?
    /// The delegation a Droppy-run head belongs to: its report waits for the others.
    var batchID: UUID?
    /// The head profile the delegation routed this head to, when the pair has profiles:
    /// shown with the head and consulted again if the head is steered on.
    var profile: String?
    /// Whether Droppy Code can stop this head where it runs.
    var canStop = true
    /// A native head whose spawning tool call returned at once: only the provider's own
    /// word ends it, never the tool result.
    var isBackground = true
    /// Set on a Droppy-run head with a copy of the checkout of its own: the tree the copy
    /// started from, which its work is measured against when it lands. Moves on with
    /// every landing, so a head steered on afterwards lands only what is new.
    var baseTree: String?
    /// Where the head's work went the last time it reported.
    var landing: HydraLanding?
    /// When the auto-merge took this head's work out: the next merge leaves it be. The
    /// head is what remembers, not the lead's turns: a head can finish between two of the
    /// lead's turns, and a merge that only counted heads finished since its first
    /// unmerged turn began skipped exactly those, leaving their files in the checkout.
    var mergedAt: Date?

    var persona: HydraPersona { HydraRoster.persona(at: index) }
    var isFinished: Bool { status.isFinished }
    /// Whether the head works in a copy of the checkout that Droppy Code made for it.
    var hasOwnCopy: Bool { baseTree != nil }

    init(index: Int, task: String, kind: Kind, origin: Origin) {
        self.index = index
        self.task = task
        self.kind = kind
        self.origin = origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = container.value(.index, default: 0)
        task = container.value(.task, default: "")
        kind = container.value(.kind, default: .droppy)
        origin = container.value(.origin, default: .delegated)
        // A status that cannot be read (a record from a newer build, say) reads as
        // stopped, never as completed: a lead told a head is done when nobody knows what
        // became of it would answer the user for a team that never came back.
        status = container.value(.status, default: .stopped)
        summary = container.value(.summary, default: nil)
        activity = container.value(.activity, default: nil)
        toolCalls = container.value(.toolCalls, default: 0)
        tokens = container.value(.tokens, default: 0)
        startedAt = container.value(.startedAt, default: .now)
        finishedAt = container.value(.finishedAt, default: nil)
        nativeID = container.value(.nativeID, default: nil)
        nativeTaskID = container.value(.nativeTaskID, default: nil)
        toolUseID = container.value(.toolUseID, default: nil)
        batchID = container.value(.batchID, default: nil)
        profile = container.value(.profile, default: nil)
        // Droppy Code owns a Droppy-run head's turn, so it can always stop one; only a
        // native head depends on the provider having said so.
        canStop = container.value(.canStop, default: kind == .droppy)
        isBackground = container.value(.isBackground, default: true)
        baseTree = container.value(.baseTree, default: nil)
        landing = container.value(.landing, default: nil)
        mergedAt = container.value(.mergedAt, default: nil)
    }
}

/// Where a Droppy-run head's work went when it reported: into the lead's checkout, into
/// it with conflicts left to settle, or into a patch file when it would not apply.
struct HydraLanding: Codable, Hashable, Sendable {
    struct File: Codable, Hashable, Sendable {
        var path: String
        var additions: Int
        var deletions: Int
    }

    /// The files the head changed, with what the change amounted to.
    var files: [File] = []
    /// Files the three-way merge left conflict markers in.
    var conflicts: [String] = []
    /// Build-output diff sections left out before the patch was parsed.
    var droppedBuildOutputFiles = 0
    /// Where the patch went when none of it could be applied.
    var patchPath: String?
    var error: String?

    /// The head changed nothing.
    var isEmpty: Bool { files.isEmpty && patchPath == nil && error == nil }
    /// The work is in the checkout, conflict markers or not.
    var landed: Bool { !files.isEmpty && patchPath == nil && error == nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = container.value(.files, default: [])
        conflicts = container.value(.conflicts, default: [])
        droppedBuildOutputFiles = container.value(.droppedBuildOutputFiles, default: 0)
        patchPath = container.value(.patchPath, default: nil)
        error = container.value(.error, default: nil)
    }

    init() {}
}

/// A head the lead asked for through the delegation block, on a provider that runs no
/// heads of its own. `name` is the head's announced name when the lead gave one: it is
/// authoritative, so the spawned head carries exactly that roster name instead of the
/// next sequential one. Nil means the lead did not name it and the roster order decides.
struct HydraDelegation: Hashable, Sendable {
    var task: String
    var prompt: String
    var name: String?
    /// The project the head works in when the lead named one ("project": a sidebar
    /// project's name or path, or a repository's absolute path); nil keeps it in the
    /// chat's own project.
    var project: String?
    /// The head profile the lead routed the task to (`"profile"` in the block); nil runs
    /// the head on the pair's shared worker model and effort.
    var profile: String?
}

/// The stages a Hydra merge walks through, in this order, one dot each on the merging
/// pill's track. With several projects the merge runs the stages after the first once per
/// project, so the track starts over with the project's name on the words.
enum HydraMergeStage: Int, CaseIterable, Sendable {
    case gathering
    case committing
    case describing
    case pushing
    case opening
    case merging
    case syncing

    /// The stage in words, as the pill and the sidebar show it.
    var words: String {
        switch self {
        case .gathering: "Gathering the team's files"
        case .committing: "Writing the commit"
        case .describing: "Writing the commit message"
        case .pushing: "Pushing the branch"
        case .opening: "Opening the merge request"
        case .merging: "Merging"
        case .syncing: "Bringing the checkout up to date"
        }
    }
}

/// A project the lead may send heads to: its name in the sidebar and its folder.
struct HydraProjectRef: Hashable, Sendable {
    var name: String
    var path: String
}

/// What a head sends back to its lead.
struct HydraReport: Hashable, Sendable {
    var headIndex: Int
    var task: String
    var origin: HydraHeadInfo.Origin
    var status: HydraHeadInfo.Status
    var text: String
    /// Where a Droppy-run head's work went; nil for a head that changed nothing or has
    /// no copy of its own.
    var landing: HydraLanding?
    /// The head's own copy of the checkout, for work that did not land.
    var copyPath: String?
    var elapsed: TimeInterval?
    var toolCalls = 0
}

/// The words Hydra puts in front of the lead and the heads, per provider.
enum HydraPrompts {
    static let workerAgentName = "droppy-worker"
    static let scoutAgentName = "droppy-scout"

    /// The agent name a profile's worker variant is registered under on the native
    /// providers ("droppy-worker-deep"): the lead routes a task to the profile by
    /// spawning exactly it.
    static func workerAgentName(for profile: HydraHeadProfile) -> String {
        "\(workerAgentName)-\(profile.agentSlug)"
    }

    /// The profile an agent name routes to ("droppy-worker-deep" gives "deep"), slug
    /// included; the base worker and scout names, and anything else, route nowhere.
    static func profileName(forAgentName agentName: String?) -> String? {
        guard let agentName, agentName.hasPrefix("\(workerAgentName)-") else { return nil }
        return String(agentName.dropFirst(workerAgentName.count + 1))
    }

    /// The profiles a native lead can route to: only ones running on the heads' own
    /// provider (a profile that sends heads elsewhere is Droppy-run's business, the
    /// lead's agent tools cannot spawn it) and tuning something (one with neither model
    /// nor effort is the shared head under another name).
    static func nativeRoutableProfiles(of launch: HydraLaunch) -> [HydraHeadProfile] {
        launch.headProfiles.filter {
            ($0.provider == nil || $0.provider == launch.headsProvider)
                && ($0.model != nil || $0.effort != nil)
        }
    }

    /// Where a Droppy-run head works: a copy of the checkout made for it, or the checkout
    /// itself when the project cannot be copied (no git, no commits yet) or the user
    /// prefers it so.
    enum Workplace {
        case ownCopy(path: String)
        case shared(path: String)
    }

    /// What a head is told about the checkout it works in and what it may do to it. The
    /// shared case is what every head lives with on providers that run heads natively.
    private static func workplaceRules(_ workplace: Workplace) -> String {
        switch workplace {
        case .ownCopy(let path):
            """
            You have your own copy of the project at \(path): a git worktree Droppy Code made for you from the project's checkout as it was when you were sent out, uncommitted work included. Work in it directly, on the files as they are; your tools already run there. When you report, Droppy Code carries your changes into that checkout itself. So never commit, branch, stash, push, check out, reset, restore or clean anything, and never make or remove worktrees, whatever the project's own guidelines say about agents and worktrees: this copy already is yours. Do not use git to check your work either.
            Build only into a folder git ignores, such as `build.noindex/<your name>` with `-derivedDataPath`; never put build output in the project folder or the `.xcodeproj`, since everything not ignored in this copy lands in the lead's checkout.
            """
        case .shared(let path):
            """
            You work in the lead's checkout at \(path), alongside the lead and the other heads, who are changing other files at the same time. Changes you did not make are expected there: leave every one of them alone, never stash, check out, reset, restore or clean anything, and never move work into a branch or worktree, whatever the project's own guidelines say about agents and worktrees. Do not use git status or git diff to check your work: they show everyone's changes, and the lead does the verifying.
            """
        }
    }

    /// How a head goes about its task, whatever provider runs it.
    private static let howToWork = """
    - Start on the task right away: read what you need and no more, then make the change.
    - A brief that names the file, the line and the change needs no second reading: make that edit first, then the next. Think briefly between tool calls; if you find yourself weighing designs for minutes, take the simplest reading of the brief and do it, and mention the choice in your report.
    - Do exactly this task and only this. Do not widen it, do not touch files it does not name unless it cannot be done otherwise, and never revert, reformat or clean up work that is not yours.
    - Check what you changed with the narrowest thing that proves it, a targeted parse, type check or test; leave the project's full build and test suite to the lead unless the task asks for them.
    - If something blocks you, stop and say so instead of guessing or working around it.
    """

    private static let howToReport = "Reply with a short report the lead can act on: what you did, the files you changed, how you checked it, and anything the lead must know. No preamble, no logs. Report within one reply; a head that cannot finish says what is done and what is not, instead of continuing to think."

    /// What a lead is told about the shape of a brief: numbered mechanical steps with the
    /// file, the line, the symbol and the exact change, nothing left open. A brief that
    /// offers alternatives or asks the head to read and reason first leaves a head on a
    /// slow model thinking for minutes between tool calls, and some never make an edit.
    private static let briefRule = "A brief is a numbered list of mechanical steps a head can start on at once. Each step names the file and a line anchor, the symbol, and the exact change: the code shape, the new name, the value. Never a question, never two alternatives, never verify by reasoning or read the file fully: a head spends minutes weighing what a brief leaves open, and some never make an edit. When you have not decided something, decide it before you write the brief, or keep that part for yourself. A head should be able to make its first edit within its first few tool calls."

    /// Where heads work and where their work lands: this chat's project unless an entry
    /// names another, any project in the sidebar or any repository on the Mac, with the
    /// merge going out per project. The lead's own tools run in this chat's checkout, but
    /// nothing keeps it to that project.
    private static func projectRule(_ projects: [HydraProjectRef]) -> String {
        let own = projects.first.map { "this chat's project, \($0.name) (`\($0.path)`)" } ?? "this chat's project"
        let others = projects.dropFirst()
        let named = others.isEmpty ? "" : " The other projects in the sidebar: " + others.map { "\($0.name) (`\($0.path)`)" }.joined(separator: ", ") + "."
        return "Heads may work in any project. A head works in \(own) unless it is sent to another: an entry of the delegation block names it with \"project\" (a sidebar project's name or path, or the absolute path of any git repository on this Mac, which Droppy Code then adds to the sidebar), and a head spawned with your own agent tool is told the project's folder in its prompt.\(named) Whatever a head changes lands in the checkout of the project it worked in, and the team's work is merged per project, one merge request each. Your own tools run in this chat's checkout, and you may read and edit files in any project all the same: what you change elsewhere is merged along with that project's work. Run your own checks in the checkout itself: never make a worktree or a copy of the project for them."
    }

    /// What a lead is told when the setting has Droppy Code land the work: the merge is
    /// the app's, not the lead's, whatever else it has been told about merging, and asking
    /// for one is a job it finishes by replying.
    private static let autoMergeRule = "Droppy Code merges your finished work itself: the moment you answer and every head is back, the files the team changed go out as a merge request on a branch of their own, it is merged, and the checkout is brought up to date. So never commit, push, make a branch, or open or merge a merge request yourself, and never send out a head to, whatever the project's guidelines or the user's standing instructions say about merging. When the user asks you to merge, there is nothing to run: make sure the work is complete, reply that it lands by itself as soon as you finish, and stop."

    /// What a lead is told when the setting has it check the heads' work: a quick read of
    /// every file a report names, with the fixes made by the lead itself, so the check
    /// never turns into another round of heads checking heads.
    private static let reviewRule = "Before you finish, read each file a report names as changed, check the change does what the brief asked, fits the code around it and breaks nothing that calls it, and run the narrowest check that proves it builds. Correct what is wrong yourself, right there in the file, and say plainly in your answer what you changed yourself and why. Never send out a head to do this check or the corrections; a head that got it badly wrong may be sent out again with a sharper brief, but small fixes are yours."

    /// How the lead tells the user what the heads did: one short human sentence per
    /// head, head's name first, everyday words for what changed for the user, file
    /// details on one short second line only, no audit-speak, no icons.
    private static let reportStyleRule = "When you answer the user, open each head's part with one short plain sentence that names the head first and says in everyday words what changed for the user (for example: Otto fixed the timeline crash so replies no longer jump). Keep file details to one short second line, never in the opener. Never write stilted audit-speak like Audited Otto and Nova or both do what the briefs asked, and add no icons or glyphs: the interface already draws each head."

    /// Appended to the lead's system prompt on providers that run heads natively: when to
    /// delegate, how to split the work and what to do with the reports.
    static func policy(for provider: ProviderKind, _ launch: HydraLaunch) -> String {
        let maxHeads = launch.maxHeads
        let autoMerges = launch.autoMerges
        let reviewsHeads = launch.reviewsHeads
        let projects = launch.projects
        // The pair's routable profiles, in the words the lead routes with: on Claude and
        // Copilot the profile's agent variant, on Codex the model and effort to pass.
        let profiles = nativeRoutableProfiles(of: launch)
        let profileRule: String
        if profiles.isEmpty {
            profileRule = ""
        } else {
            switch provider {
            case .claude, .copilot:
                let variants = profiles.map { "`\(workerAgentName(for: $0))` for \($0.name)" }.joined(separator: ", ")
                profileRule = " Some heads are tuned for a purpose: route the task to \(variants) instead of the plain `\(workerAgentName)` when the work belongs to that purpose."
            case .codex:
                let routes = profiles.map { profile -> String in
                    var parts: [String] = []
                    if let model = profile.model { parts.append("`model` = \(model)") }
                    if let effort = profile.effort { parts.append("`reasoning_effort` = \(effort)") }
                    return "\(profile.name) (pass \(parts.joined(separator: " and ")))"
                }.joined(separator: ", ")
                profileRule = " Some heads are tuned for a purpose: route the task by passing the profile's own knobs in `spawn_agent` — \(routes) — when the work belongs to that purpose."
            default:
                profileRule = ""
            }
        }
        let howToSpawn: String
        let howToWait: String
        switch provider {
        case .claude:
            howToSpawn = "Two agent types are yours: `\(workerAgentName)` (edits files, runs commands, verifies) and `\(scoutAgentName)` (read-only research). Spawn them with the Agent tool and prefer them over other agents while Hydra is on: they run on the model and effort the user chose for heads.\(profileRule)"
            howToWait = "Launch every head for a job in one message so they run in parallel, in the foreground" + (maxHeads.map { ", and run at most \($0) at once." } ?? ".")
        case .codex:
            howToSpawn = "Spawn heads with `spawn_agent`: the `worker` agent for anything that edits files or runs commands, the `explorer` agent for read-only research.\(profileRule)"
            howToWait = "Spawn every head for a job before waiting, so they run in parallel, and collect them with `wait_agent`; never leave a head running when you answer." + (maxHeads.map { " Run at most \($0) at once." } ?? "")
        case .copilot:
            howToSpawn = "Two agents are yours: `\(workerAgentName)` (edits files, runs commands, verifies) and `\(scoutAgentName)` (read-only research). Start them with the task tool and prefer them over other agents while Hydra is on: they run on the model and effort the user chose for heads.\(profileRule)"
            howToWait = "Start every head for a job at once so they run in parallel" + (maxHeads.map { ", and run at most \($0) at a time." } ?? ".")
        default:
            howToSpawn = ""
            howToWait = maxHeads.map { "Run at most \($0) heads at once." } ?? "Send every head for a job out at once so they run in parallel."
        }
        return """
        # Hydra

        The user switched on Hydra for this chat: you lead a team of helper agents, called heads, that work in parallel in your checkout. Switching Hydra on is the user asking you to use them, so it overrides any standing rule that says not to spawn agents unless asked. \(howToSpawn) The agents you spawn this way are the Hydra heads themselves: Droppy Code shows each one in the team's panel under a roster name and posts its outcome in the chat. There is no other launcher and no other kind of head, so never tell the user that Hydra heads cannot be started here; when the user asks for heads, spawn them this way.

        Delegate first, work second. Anything bigger than a single obvious change to a single file is a job for heads: audits, reviews, a feature that spans files, a refactor, "check everything", research across many files or sources, several tasks in one message. In your first reply, look at the code only long enough to write good briefs, a minute and a handful of files rather than ten, then send out scouts for the reading and workers for the changes, all in that same message. Never spend minutes reading before you delegate, and never do inline what heads could be doing in parallel. Only a truly single-focus request, one file and one obvious change, is yours to do alone.

        When you delegate:
        - \(howToWait)
        - Give each head one self-contained task with the exact files, symbols and acceptance criteria it needs. Heads share the checkout but not your context, so write the task as if to a capable colleague who has read nothing yet.
        - \(briefRule)
        - \(projectRule(projects))
        - Split the work so no two heads edit the same file. Keep integration, verification and the final answer for yourself: never send out a head to verify, redo or finish another head's work.
        - Tell the user in one line which heads you sent out and what each one does. Droppy Code names the heads in roster order (Hank, Walter, Ada, Otto, Nova, Remy, Iris, Milo, Juno, Ezra, Lena, Bo, Kai, Vera, Finn, Mira, Odin, Suki, Rex, Zola, Pip, Ivo, Lux, Tova, Gus, then Hank 2 and so on): announce each head by its task and use exactly those names in that order, never invented ones. There is no head called Ives; the roster has Ivo.
        - While they work, prepare the integration rather than starting on their tasks: how the pieces fit together, and the one check you will run at the end.
        - Heads go out through the tools above, never through a fenced hydra block: that is the delegation format for providers without agent tools of their own. If you end a reply with one anyway, Droppy Code still sends those heads out as threads of their own, but your turn ends there and their reports come back as a later message.

        When they report back:
        - The checkout changes under you while heads work, and the user may be editing too. Never use git status or git diff to check on a head, and never reconcile, revert, stash or move changes you did not make.
        - Take a report as done work: read the files it names if something matters, but do not redo the task and do not start it over because the tree looks different from what you expected. A head that failed leaves its part to you: do it or send it out again. A head the user stopped leaves its part alone unless the user asks.
        \(reviewsHeads ? "- " + reviewRule + "\n" : "")- Then finish the job: integrate, run one verification if it matters, and answer the user. \(reportStyleRule)
        \(autoMerges ? "\n" + autoMergeRule + "\n" : "")
        """
    }

    /// The system prompt a worker head runs with.
    static let workerPrompt = """
    You are a Hydra head in Droppy Code: one of several helpers working in parallel for a lead agent, in the lead's own checkout, where the lead and the other heads are changing other files at the same time. Do exactly the task you were given, and only that: do not widen it, do not touch files it does not name unless the task cannot be done otherwise, and never revert, reformat or clean up work that is not yours. Changes you did not make are expected in the checkout: leave them alone, never stash, check out, reset, restore or clean anything, and never move work into a branch or worktree, whatever the project's own guidelines say about agents and worktrees. Do not use git status or git diff to check your work: they show everyone's changes. Check what you changed with the narrowest thing that proves it and leave the full build and test suite to the lead. If something blocks you, say so instead of guessing.

    \(howToReport)
    """

    /// The system prompt a scout head runs with.
    static let scoutPrompt = """
    You are a Hydra head in Droppy Code: a read-only researcher working in parallel for a lead agent, in the lead's own checkout, where the lead and other heads are changing files at the same time; uncommitted changes there are theirs and expected. Answer exactly the question you were given, from the code and sources you can read. Change nothing.

    Reply with a short report the lead can act on: the findings, with file paths and line references, and anything that contradicts what the lead assumed. No preamble.
    """

    /// Claude's `--agents` definitions: the two heads on the pair's model and effort.
    static func claudeAgents(_ launch: HydraLaunch) -> JSONValue {
        var worker: [String: JSONValue] = [
            "description": "Hydra head that implements one delegated task: edits files, runs commands, verifies. Use proactively when a request splits into independent pieces or touches several parts of the codebase.",
            "prompt": .string(workerPrompt),
            "background": false,
        ]
        var scout: [String: JSONValue] = [
            "description": "Hydra head for read-only research: finds files, reads code, gathers facts and reports back. Use proactively when a job needs many files or sources read.",
            "prompt": .string(scoutPrompt),
            "tools": ["Read", "Grep", "Glob", "WebFetch", "WebSearch"],
            "background": false,
        ]
        if let model = launch.workerModel, model != "default" {
            worker["model"] = .string(model)
            scout["model"] = .string(model)
        }
        if let effort = launch.workerEffort, !effort.isEmpty {
            worker["effort"] = .string(effort)
            scout["effort"] = .string(effort)
        }
        var agents: [String: JSONValue] = ["\(workerAgentName)": .object(worker), "\(scoutAgentName)": .object(scout)]
        // One worker variant per routable profile: the lead routes a task to the profile
        // by spawning the variant, whose model and effort are the profile's own.
        for profile in nativeRoutableProfiles(of: launch) {
            var variant = worker
            variant["description"] = .string("Hydra head that implements one delegated task, tuned as the '\(profile.name)' profile. Prefer it for work that belongs to '\(profile.name)' over the plain \(workerAgentName).")
            if let model = profile.model, model != "default" { variant["model"] = .string(model) }
            if let effort = profile.effort, !effort.isEmpty { variant["effort"] = .string(effort) }
            agents[workerAgentName(for: profile)] = .object(variant)
        }
        return .object(agents)
    }

    /// Copilot's `customAgents`: the same two heads, in the CLI's own shape.
    static func copilotAgents(_ launch: HydraLaunch) -> [JSONValue] {
        func agent(name: String, display: String, description: String, prompt: String, tools: [String]?) -> JSONValue {
            var object: [String: JSONValue] = [
                "name": .string(name),
                "displayName": .string(display),
                "description": .string(description),
                "prompt": .string(prompt),
                "infer": true,
            ]
            if let tools { object["tools"] = .array(tools.map(JSONValue.string)) }
            if let model = launch.workerModel, model != "auto" { object["model"] = .string(model) }
            if let effort = launch.workerEffort, !effort.isEmpty { object["reasoningEffort"] = .string(effort) }
            return .object(object)
        }
        let worker = agent(
            name: workerAgentName,
            display: "Hydra worker",
            description: "Hydra head that implements one delegated task: edits files, runs commands, verifies. Use when a request splits into independent pieces.",
            prompt: workerPrompt,
            tools: nil
        )
        var agents = [
            worker,
            // The scout's prompt keeps it read-only; the CLI's tool names are not pinned
            // here, since a name it does not know could refuse the whole session.
            agent(
                name: scoutAgentName,
                display: "Hydra scout",
                description: "Hydra head for read-only research: finds files, reads code and reports back. Use when a job needs many files or sources read.",
                prompt: scoutPrompt,
                tools: nil
            ),
        ]
        // One worker variant per routable profile, as on Claude: the lead routes a task
        // to the profile by starting the variant.
        for profile in nativeRoutableProfiles(of: launch) {
            guard case .object(var variant) = worker else { continue }
            variant["name"] = .string(workerAgentName(for: profile))
            variant["displayName"] = .string("Hydra worker · \(profile.name)")
            variant["description"] = .string("Hydra head that implements one delegated task, tuned as the '\(profile.name)' profile. Prefer it for work that belongs to '\(profile.name)' over the plain \(workerAgentName).")
            if let model = profile.model, model != "auto" { variant["model"] = .string(model) }
            if let effort = profile.effort, !effort.isEmpty { variant["reasoningEffort"] = .string(effort) }
            agents.append(.object(variant))
        }
        return agents
    }

    /// Codex's config overrides for the thread: the heads' model and effort, and how many
    /// may run at once; uncapped, Codex keeps its own limit. With profiles to route to,
    /// the spawn tool's model and effort knobs are exposed, so the lead can pass the
    /// profile's own when it spawns the head (the session matches them back).
    static func codexConfig(_ launch: HydraLaunch) -> [String: JSONValue] {
        var agents: [String: JSONValue] = [:]
        if let cap = launch.maxHeads { agents["max_concurrent_threads_per_session"] = .int(cap) }
        if let model = launch.workerModel, !model.isEmpty { agents["default_subagent_model"] = .string(model) }
        if let effort = launch.workerEffort, !effort.isEmpty { agents["default_subagent_reasoning_effort"] = .string(effort) }
        var features: [String: JSONValue] = ["multi_agent": true]
        if !nativeRoutableProfiles(of: launch).isEmpty {
            features["multi_agent_v2"] = .object(["expose_spawn_agent_model_overrides": true])
        }
        return ["agents": .object(agents), "features": .object(features)]
    }

    // MARK: - Droppy-run heads

    /// How many times in a row a lead may send heads out for one request of the user's: a
    /// big job wants scouts to read, workers to change, and one round for what failed or
    /// what the reports showed was missing. Past that the lead finishes by itself, so no
    /// request can chain heads that verify heads that verify heads.
    static let maxDelegationRounds = 3

    /// The lead's team in a line, for the front of its messages: it should never have to
    /// guess who is still out or what came back.
    static func teamStatus(_ heads: [HydraHeadInfo], now: Date = .now) -> String? {
        guard !heads.isEmpty else { return nil }
        let parts = heads.map { info -> String in
            let name = info.persona.name
            switch info.status {
            case .running:
                let minutes = Int(now.timeIntervalSince(info.startedAt) / 60)
                return "\(name) (working\(minutes > 0 ? " for \(minutes)m" : ""))"
            case .completed:
                if let landing = info.landing {
                    if landing.isEmpty { return "\(name) (done, changed nothing)" }
                    if landing.landed { return "\(name) (done, landed \(landing.files.count == 1 ? "1 file" : "\(landing.files.count) files"))" }
                    return "\(name) (done, patch kept)"
                }
                return "\(name) (done)"
            case .failed: return "\(name) (failed)"
            case .stopped: return "\(name) (stopped)"
            }
        }
        return "Your heads so far: " + parts.joined(separator: ", ") + "."
    }

    /// The standing rules for a lead on a provider that runs no heads of its own: when to
    /// delegate, how, and what the reports mean. An API session keeps this in its system
    /// prompt, once; a CLI session gets it in front of every message.
    static func fallbackPolicy(maxHeads: Int?, isolated: Bool, autoMerges: Bool = false, reviewsHeads: Bool = false, heads: String? = nil, projects: [HydraProjectRef] = [], profiles: [HydraHeadProfile] = []) -> String {
        let whereHeadsWork = isolated
            ? "Each head works in a copy of its project of its own and Droppy Code lands its changes in that project's checkout when it reports"
            : "The heads work in your checkout"
        let team = maxHeads.map { "a team of up to \($0) helper agents" } ?? "a team of helper agents"
        // Heads on another provider are a different model from the lead, chosen for speed
        // more often than not: the lead hears what they are, so it briefs them as such and
        // keeps the thinking, and it is told the block is the only way to them, since its own
        // agent tools would run heads on its own model instead.
        let whoTheHeadsAre = heads.map {
            " Your heads run on \($0), a different model from yours: it is quick, so give each one a well-bounded task with everything it needs written down, and keep the design, the judgement calls and the integration for yourself. The block is the only way to send heads out: never use an agent, task or sub-agent tool of your own, which would run heads on your own model instead of the one the user chose."
        } ?? ""
        // Whatever the provider, a head can read, edit and run: on the API providers the
        // app gives it those tools itself, so no head is ever a text-only researcher.
        let whatHeadsCanDo = " Every head, whatever its provider, can read files, edit files and run commands in its copy, with no permission prompts to wait on; brief it to do the work, not just to describe it."
        // A pair in advanced mode tunes some heads for a purpose: the lead hears which,
        // and routes a task to one by name. The profile's name is all the lead knows of
        // the purpose, so the wording keeps the routing on the name's own meaning.
        let profileRule = profiles.isEmpty ? "" : " Some heads are tuned for a purpose: \(profiles.map(\.briefLabel).joined(separator: ", ")). Route a task to one with \"profile\", as in `{\"task\": \"...\", \"prompt\": \"...\", \"profile\": \"\(profiles[0].name)\"}`; a task that fits none of them goes without a profile and runs on the heads' shared model, as does one whose profile names none of these."
        return """
        [Hydra is on] You lead \(team) ("heads"). Delegate first, work second: anything bigger than a single obvious change to a single file is a job for heads. Audits, reviews, a feature across several files, a refactor, "check everything", research across many files, several tasks in one message: in your first reply, look at the code only long enough to write good briefs, a minute and a handful of files rather than ten, and then send the heads out, all of them in that one block. Never spend minutes reading before you delegate, and never do inline what heads could be doing in parallel. Only a truly single-focus request, one file and one obvious change, is yours to do alone.         Finish your reply with one fenced block

        ```hydra
        [{"task": "short title", "prompt": "complete, self-contained instructions with the exact files and acceptance criteria"}]
        ```

        and stop there: do not wait, poll or verify anything after it. When a request is yours to do alone, do it and end with no block at all: an empty block sends no heads and is not needed. An entry may also carry its head's announced name, as in `{"task": "...", "prompt": "...", "name": "Otto"}`: the announced name is authoritative and the spawned head carries exactly it, so repeating the same block spawns the same names. An entry for work in another project carries `"project"` with that project's name or path, as in `{"task": "...", "prompt": "...", "project": "gaze-site"}`. Name new heads with the next roster names in order after the team listed above (Hank, Walter, Ada, Otto, Nova, Remy, Iris, Milo, Juno, Ezra, Lena, Bo, Kai, Vera, Finn, Mira, Odin, Suki, Rex, Zola, Pip, Ivo, Lux, Tova, Gus, then Hank 2 and so on), and omit the name when unsure: the next heads in order go out instead. Never invent names outside the roster: there is no head called Ives (the roster has Ivo), and an unknown name falls back to the next head in order rather than renaming anyone.\(profileRule) Inside a prompt never open a fenced code block of your own (three backticks would end the hydra block early and no head would go out): describe code in words, quote identifiers with single backticks, or indent a snippet by four spaces. Each entry goes out to a head the moment its closing brace streams, before the block is finished, so write the entries in the order the heads should start and complete one entry before beginning the next. \(whereHeadsWork); heads never see your context, so write every prompt for a capable colleague who has read nothing yet, with the exact files, symbols and acceptance criteria, and give no two heads the same file. \(briefRule) \(projectRule(projects)) A head can be sent to read and report as well as to change files, so the reading goes out in parallel too. Say in one line which heads you sent out and what each one does.\(whoTheHeadsAre)\(whatHeadsCanDo) The reports arrive as a later message with the work already in place: build on them, do not redo them, never send out heads to verify or redo other heads, and never use git status or git diff to check on heads, since the checkout changes under you while they work. A message that opens with [Hydra] is from Droppy Code, not the user.\(reviewsHeads ? " " + reviewRule : "")\(autoMerges ? " " + autoMergeRule : "") \(reportStyleRule)
        """
    }

    /// The policy for a lead whose session keeps it in its system prompt: the API
    /// providers, and the providers with heads of their own whose pair sends the heads out
    /// on another provider.
    static func fallbackPolicy(_ launch: HydraLaunch) -> String {
        fallbackPolicy(maxHeads: launch.maxHeads, isolated: launch.isolatesHeads, autoMerges: launch.autoMerges, reviewsHeads: launch.reviewsHeads, heads: launch.headsLabel, projects: launch.projects, profiles: launch.headProfiles)
    }

    /// In front of the user's own message: the team so far, when there is one.
    static func fallbackTurnNote(team: String?) -> String {
        guard let team else { return "" }
        return "[Hydra] \(team)\n\n---\n\n"
    }

    /// In front of a report message: the heads are back, and the lead's job is to
    /// finish, not to send out more. `canDelegate` says a round of heads is still left
    /// for what failed or turned out to be missing; otherwise the block is not offered.
    static func fallbackReportNote(team: String?, canDelegate: Bool) -> String {
        let more = canDelegate
            ? "If the reports open up the next stage of the work, or a head failed, or a piece of the user's request is still undone, send heads out again for exactly that, with the same ```hydra block at the end of your reply; never for verifying, redoing or finishing what a head already did."
            : "Send out no more heads for this request; whatever is left, do yourself."
        return "[Hydra] Your heads reported back below.\(team.map { " " + $0 } ?? "") \(more)\n\n---\n\n"
    }

    /// Policy and note together, for a CLI provider with no system prompt to keep the
    /// policy in.
    static func fallbackPreamble(_ launch: HydraLaunch, team: String?) -> String {
        fallbackPolicy(launch) + "\n\n" + (fallbackTurnNote(team: team).isEmpty ? "---\n\n" : fallbackTurnNote(team: team))
    }

    static func fallbackReportPreamble(_ launch: HydraLaunch, team: String?, canDelegate: Bool) -> String {
        fallbackPolicy(launch) + "\n\n" + fallbackReportNote(team: team, canDelegate: canDelegate)
    }

    /// What the lead hears when its delegation block is refused: the request has had its
    /// rounds of heads, and the rest is the lead's own.
    static func heldBackMessage(count: Int) -> String {
        """
        Hydra held back \(count == 1 ? "a head" : "\(count) heads").
        None of the heads you asked for went out: this request has had all \(maxDelegationRounds) of its rounds of heads already. Do the rest yourself now, without git status or git diff on the heads' work, and answer the user.
        """
    }

    /// The opening fence of a delegation block: three backticks, the word hydra in any
    /// case, and the end of that line.
    private static func delegationOpener(in text: String) -> Range<String.Index>? {
        text.firstMatch(of: #/```[ \t]*hydra(?:-sent|-leaving)?[ \t]*\r?\n/#.ignoresCase())?.range
    }

    /// Every three backticks that open a line from `start` on, in order. A fence with an
    /// info string after it counts too: inside a prompt that is what a quoted snippet
    /// looks like, and the parser needs those to know where not to cut.
    private static func lineStartFences(in text: String, from start: String.Index) -> [Range<String.Index>] {
        var fences: [Range<String.Index>] = []
        var cursor = start
        while let fence = text[cursor...].firstRange(of: "```") {
            if fence.lowerBound == text.startIndex || text[text.index(before: fence.lowerBound)].isNewline {
                fences.append(fence)
            }
            cursor = fence.upperBound
        }
        return fences
    }

    /// Where the delegation block sits in a reply: from its opening fence up to and
    /// including its closing fence, which is the last three backticks that open a line
    /// after the opener, never the first. A prompt may quote a fenced snippet of its own,
    /// and cutting at the first fence inside it lost the whole block. Without a closing
    /// fence at all (the reply is still streaming, or the lead forgot it) the block runs
    /// to the end of the text.
    static func delegationBlockRange(in text: String) -> Range<String.Index>? {
        guard let opener = delegationOpener(in: text) else { return nil }
        let end = lineStartFences(in: text, from: opener.upperBound).last?.upperBound ?? text.endIndex
        return opener.lowerBound..<end
    }

    /// Whether the reply has a delegation block at all, readable or not.
    static func hasDelegationBlock(in text: String) -> Bool { delegationBlockRange(in: text) != nil }

    /// The same test over a tail of a reply still streaming: a block is there once its
    /// opening fence is, so a reader that has scanned the text up to some point only
    /// needs to scan what arrived since (see `HydraButton`).
    static func hasDelegationOpener(in tail: Substring) -> Bool {
        tail.firstMatch(of: #/```[ \t]*hydra(?:-sent|-leaving)?[ \t]*\r?\n/#.ignoresCase()) != nil
    }

    /// The delegation block at the end of a reply, if the lead wrote one. The body up to
    /// the last fence is tried first; when that does not parse, a prompt has most likely
    /// quoted a fence of its own and the closer is somewhere else, so every earlier fence
    /// is tried in turn, from the last back to the first, and lastly the end of the text
    /// for a block whose closer never came. An empty array is a block that asks for no
    /// heads (the lead did the work itself) and comes back as an empty list, not as nil.
    /// While the reply streams, `streamedDelegations(in:)` reads the same block entry by entry.
    static func delegations(in text: String) -> [HydraDelegation]? {
        guard let opener = delegationOpener(in: text) else { return nil }
        let bodyStart = opener.upperBound
        var ends = lineStartFences(in: text, from: bodyStart).reversed().map(\.lowerBound)
        ends.append(text.endIndex)
        for end in ends {
            if let parsed = delegations(fromBody: String(text[bodyStart..<end])) { return parsed }
        }
        return nil
    }

    /// The heads a block body asks for: a JSON array of entries (or one bare entry),
    /// read by `delegation(fromEntry:)`, which holds the rules for which entries are kept
    /// and how they are titled and named.
    /// An empty array is read as asking for nothing; entries with nothing usable in them
    /// are not read at all.
    private static func delegations(fromBody body: String) -> [HydraDelegation]? {
        guard let json = JSONValue.parse(body) else { return nil }
        if let array = json.array, array.isEmpty { return [] }
        let entries: [JSONValue] = json.array ?? (json.object == nil ? [] : [json])
        let parsed = entries.compactMap(delegation(fromEntry:))
        return parsed.isEmpty ? nil : parsed
    }

    /// The reply with its delegation block taken out, for what the lead said to the user.
    static func withoutDelegationBlock(_ text: String) -> String {
        var kept = text
        if let range = delegationBlockRange(in: text) { kept.removeSubrange(range) }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How long the delegation card stays once its heads are out, wearing its done wave,
    /// before it leaves the reply.
    static let delegationSentHold: Duration = .seconds(3.2)

    /// How long the card takes to fade out in place, still holding its room in the reply,
    /// before the block goes and the text below closes up (see `markingDelegationBlockLeaving`).
    static let delegationLeaveFade: Duration = .milliseconds(450)

    /// Whether the reply holds a delegation block already marked sent or on its way out
    /// (see `markingDelegationBlockSent` and `markingDelegationBlockLeaving`).
    static func hasSentDelegationBlock(in text: String) -> Bool {
        text.contains(#/```[ \t]*hydra-(?:sent|leaving)[ \t]*\r?\n/#.ignoresCase())
    }

    /// Whether the reply's delegation block is fading out (its info string is `hydra-leaving`).
    static func hasLeavingDelegationBlock(in text: String) -> Bool {
        text.contains(#/```[ \t]*hydra-leaving[ \t]*\r?\n/#.ignoresCase())
    }

    /// The reply with its sent block's info string turned into `hydra-leaving`: the card fades
    /// where it stands, still taking up its room, so nothing below slides up under it. A
    /// removal that glided the card over the closing text read as a ghost of the card.
    static func markingDelegationBlockLeaving(_ text: String) -> String {
        guard hasSentDelegationBlock(in: text), !hasLeavingDelegationBlock(in: text), let opener = delegationOpener(in: text) else { return text }
        return text.replacingCharacters(in: opener, with: "```hydra-leaving\n")
    }

    /// The reply with its delegation block's info string turned from `hydra` into `hydra-sent`,
    /// so the timeline draws the card in its done state for a moment before the block goes.
    static func markingDelegationBlockSent(_ text: String) -> String {
        guard let opener = delegationOpener(in: text), !hasSentDelegationBlock(in: text) else { return text }
        return text.replacingCharacters(in: opener, with: "```hydra-sent\n")
    }

    /// What the lead hears when its block was there but could not be read: no heads went
    /// out, how to write the block so it can be read, and that the attempt cost it nothing.
    static func unreadableBlockMessage(reason: String?) -> String {
        var message = "[Hydra] Your delegation block could not be read, so no heads went out."
        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            message += " " + reason + (reason.last.map { ".!?".contains($0) } == true ? "" : ".")
        }
        return message + " Write the block again at the end of your reply: one fenced block whose info string is hydra, holding a JSON array of objects with a task string and a prompt string. Inside a prompt never open a fenced code block of your own (no three backticks): describe code in words, quote identifiers with single backticks, or indent snippets. This does not count as a round of heads."
    }

    /// What a Droppy-run head is sent for a task the lead delegated.
    static func delegatedHeadPrompt(persona: HydraPersona, delegation: HydraDelegation, workplace: Workplace) -> String {
        """
        You are \(persona.name), a Hydra head in Droppy Code: one of several helpers working in parallel for a lead agent. The lead delegated this task to you.

        ## Your task: \(delegation.task)
        \(delegation.prompt)

        ## Where you work
        \(workplaceRules(workplace))

        ## How to work
        \(howToWork)

        ## Your report
        \(howToReport)
        """
    }

    /// What the lead's chat looked like when a queued task was handed to a head, so the
    /// head knows what is going on without the lead's context. Built from the timeline,
    /// not from another model call, so a queued task costs nothing extra.
    struct ChatContext {
        var lastUserPrompt: String?
        var lastReply: String?
        var touchedPaths: [String] = []
    }

    /// What a Droppy-run head is sent for a task the user queued while the lead worked, or
    /// sent straight to a head; `leadIsWorking` says which, so the head is told the truth
    /// about the lead.
    static func queuedHeadPrompt(persona: HydraPersona, task: String, context: ChatContext, workplace: Workplace, leadIsWorking: Bool = true) -> String {
        var lines: [String] = []
        if let prompt = context.lastUserPrompt, !prompt.isEmpty {
            lines.append("- The user last asked the lead: \(quoted(prompt, limit: 1_200))")
        }
        if let reply = context.lastReply, !reply.isEmpty {
            lines.append("- The lead's latest reply\(leadIsWorking ? " so far" : ""): \(quoted(reply, limit: 800))")
        }
        if leadIsWorking, !context.touchedPaths.isEmpty {
            let paths = context.touchedPaths.prefix(20).joined(separator: ", ")
            lines.append("- Files the lead is changing in its current turn: \(paths). Leave these alone; if your task cannot be done without touching one, keep the change minimal and say so in your report.")
        }
        let contextBlock = lines.isEmpty ? "The lead has not said anything yet." : lines.joined(separator: "\n")
        let handoff = leadIsWorking
            ? "The user queued this task for you while the lead works on something else."
            : "The user sent this task straight to you; the lead is idle and will hear your report."
        return """
        You are \(persona.name), a Hydra head in Droppy Code: a helper running in parallel with the lead agent. \(handoff)

        ## What is going on in the main chat
        \(contextBlock)

        ## Your task
        \(task)

        ## Where you work
        \(workplaceRules(workplace))

        ## How to work
        \(howToWork)

        ## Your report
        \(howToReport)
        """
    }

    /// The message the lead receives once heads have reported: one section per head, what
    /// landed where, and what to do about it. `stillWorking` names the heads yet to report;
    /// `reviewsHeads` has the lead audit the files listed before it finishes.
    static func reportMessage(_ reports: [HydraReport], stillWorking: [String] = [], reviewsHeads: Bool = false) -> String {
        let names = reports.map { HydraRoster.persona(at: $0.headIndex).name }
        var opening = "Hydra reports: \(list(names)) finished."
        if !stillWorking.isEmpty {
            opening += " \(list(stillWorking)) \(stillWorking.count == 1 ? "is" : "are") still at work; \(stillWorking.count == 1 ? "its report comes" : "their reports come") as a later message."
        }

        var sections: [String] = []
        for report in reports {
            let persona = HydraRoster.persona(at: report.headIndex)
            let outcome = switch report.status {
            case .completed: ""
            case .failed: " (failed)"
            case .stopped: " (stopped by the user before finishing)"
            case .running: ""
            }
            var effort: [String] = []
            if let elapsed = report.elapsed, elapsed >= 1 { effort.append(duration(elapsed)) }
            if report.toolCalls > 0 { effort.append(report.toolCalls == 1 ? "1 tool" : "\(report.toolCalls) tools") }
            let took = effort.isEmpty ? "" : " (" + effort.joined(separator: ", ") + ")"
            var lines = ["## \(persona.name): \(report.task)\(outcome)\(took)"]
            if let landing = landingLine(for: report) { lines.append(landing) }
            let body = report.text.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(body.isEmpty ? "No report." : body)
            sections.append(lines.joined(separator: "\n"))
        }

        var closing: [String] = []
        if reports.contains(where: { $0.landing?.landed == true }) {
            closing.append("The changes listed above are in your checkout already; nothing needs applying.")
        }
        if reports.contains(where: { $0.copyPath == nil && $0.status == .completed }) {
            closing.append("The heads worked in your checkout, so their changes are there already.")
        }
        if reports.contains(where: { !($0.landing?.conflicts.isEmpty ?? true) }) {
            closing.append("A file listed with conflicts was merged three-way and keeps conflict markers: resolve those first.")
        }
        // Two heads on one file is the split the lead was told not to make; it hears
        // which file, so it reads the result instead of trusting it.
        var owners: [String: [String]] = [:]
        for report in reports {
            for file in report.landing?.files ?? [] {
                owners[file.path, default: []].append(HydraRoster.persona(at: report.headIndex).name)
            }
        }
        for (path, names) in owners.sorted(by: { $0.key < $1.key }) where names.count > 1 {
            closing.append("\(list(names)) both changed \(path): read it as it is now before you build on it.")
        }
        for report in reports {
            guard let landing = report.landing, let path = landing.patchPath else { continue }
            closing.append("\(HydraRoster.persona(at: report.headIndex).name)'s changes would not apply on their own; the patch is at \(path). Apply it with `git apply --3way \(path)` and settle what conflicts.")
        }
        if reports.contains(where: { $0.status == .failed }) {
            closing.append("A head that failed leaves its part to you: do it yourself or send it out again.")
        }
        if reports.contains(where: { $0.status == .stopped }) {
            closing.append("A head the user stopped leaves its part alone unless the user asks for it.")
        }
        if reports.contains(where: { $0.origin == .queued }) {
            closing.append("The user queued that work for the heads while you were busy; take it into account and carry on with the main job.")
        }
        if reports.contains(where: { $0.origin == .sent }) {
            closing.append("The user sent that work straight to the heads instead of to you; take it into account, and reply to the user on it as if they had asked you.")
        }
        // With the check on, the lead reads every file listed rather than only the ones
        // that matter, and fixes what it finds itself.
        if reviewsHeads {
            closing.append("Do not check any of this with git status or git diff: the checkout changes under you while heads work, and the user may be editing too. Do not reconcile or revert anything. Before you finish, read each file listed above, check the change does what the brief asked and fits the code around it, run the narrowest check that proves it builds, correct what is wrong yourself, and say plainly in your answer what you changed yourself. Never send out a head for the check or the corrections.")
        } else {
            closing.append("Do not check any of this with git status or git diff: the checkout changes under you while heads work, and the user may be editing too. Do not reconcile, revert or redo anything. Build on the reports, read the files they name if something matters, run one verification if it matters, and finish the job.")
        }
        closing.append(reportStyleRule)
        if !stillWorking.isEmpty {
            closing.append("Do not wait for \(list(stillWorking)) and do not take over \(stillWorking.count == 1 ? "its" : "their") tasks; tell the user \(stillWorking.count == 1 ? "it is" : "they are") still at work and that you will hear from \(stillWorking.count == 1 ? "it" : "them").")
        }

        return """
        \(opening)

        \(sections.joined(separator: "\n\n"))

        \(closing.joined(separator: " "))
        """
    }

    /// One line on where a head's work went, for its section of the report. Nothing for
    /// a head that worked in the checkout itself: its changes are simply there.
    private static func landingLine(for report: HydraReport) -> String? {
        guard let landing = report.landing else {
            guard let path = report.copyPath else { return nil }
            return report.status == .completed ? "Changed nothing." : "Nothing landed; its unfinished work is in its copy at \(path)."
        }
        if landing.isEmpty { return "Changed nothing." }
        let files = landing.files.prefix(25).map { file -> String in
            var line = "\(file.path) (+\(file.additions) −\(file.deletions))"
            if landing.conflicts.contains(file.path) { line += " with conflicts" }
            return line
        }
        let listed = files.joined(separator: ", ")
            + (landing.files.count > 25 ? ", and \(landing.files.count - 25) more" : "")
        let omitted = landing.droppedBuildOutputFiles == 0 ? "" : "; \(landing.droppedBuildOutputFiles) build-output file\(landing.droppedBuildOutputFiles == 1 ? " was" : "s were") left out"
        if landing.patchPath != nil { return "Did not land: \(listed)\(omitted)." }
        if let error = landing.error { return "Did not land (\(error)): \(listed)\(omitted)." }
        return "Landed in your checkout: \(listed)\(omitted)."
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
    }

    private static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    private static func quoted(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
        return "“\(cut)”"
    }
}
