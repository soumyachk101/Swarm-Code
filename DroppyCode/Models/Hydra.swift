import Foundation
import SwiftUI

// Hydra: one chat, many heads. With Hydra on, the chat's agent leads a team of helper
// agents ("heads") that it sends out on the parts of a big job, in parallel. Claude, Codex
// and Copilot run the heads natively, inside their own session, with the model and effort
// from the pair the user set up; every other provider gets Droppy-run heads, each a thread
// of its own, and hands their reports back to the lead as the next message.

/// A lead-and-heads pairing: which model runs the heads when a chat on this provider leads.
/// `orchestratorModel` nil means any model on the provider; a nil worker field means the
/// heads inherit the chat's own model or effort.
struct HydraPair: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var provider: ProviderKind
    var orchestratorModel: String?
    var orchestratorEffort: String?
    var workerModel: String?
    var workerEffort: String?
    /// How many heads may work at once.
    var maxHeads: Int

    static let defaultMaxHeads = 4
    static let maxHeadsRange = 1...8

    init(provider: ProviderKind) {
        id = UUID()
        self.provider = provider
        maxHeads = Self.defaultMaxHeads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.value(.id, default: UUID())
        provider = try container.decode(ProviderKind.self, forKey: .provider)
        orchestratorModel = container.value(.orchestratorModel, default: nil)
        orchestratorEffort = container.value(.orchestratorEffort, default: nil)
        workerModel = container.value(.workerModel, default: nil)
        workerEffort = container.value(.workerEffort, default: nil)
        maxHeads = min(max(container.value(.maxHeads, default: Self.defaultMaxHeads), Self.maxHeadsRange.lowerBound), Self.maxHeadsRange.upperBound)
    }
}

/// What a session launches with while Hydra is on: the heads' model and effort, resolved
/// from the pair, and how many may run at once.
struct HydraLaunch: Hashable, Sendable {
    /// The provider's own model id for the heads, or nil to inherit the lead's model.
    var workerModel: String?
    var workerEffort: String?
    var maxHeads: Int
    /// Whether Droppy-run heads get copies of the checkout of their own.
    var isolatesHeads = true
}

/// How much a Droppy-run head gets for one turn, on any provider: a nudge when it only
/// reads, a word to wrap up, then a stop and one more turn for its report, so the lead
/// always hears back. The API sessions pace themselves with these from inside the turn;
/// every other provider gets the stop from the head's runtime.
enum HydraBudget {
    /// Tools without a change before the head is asked to act.
    static let pacingTools = 24
    static let wrapUpTools = 50
    static let maxTools = 90
    static let wrapUpSeconds: TimeInterval = 12 * 60
    static let maxSeconds: TimeInterval = 20 * 60
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

    /// Delegated by the lead, or queued by the user while the lead worked.
    enum Origin: String, Codable, Sendable {
        case delegated
        case queued
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
        status = container.value(.status, default: .completed)
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
        canStop = container.value(.canStop, default: false)
        isBackground = container.value(.isBackground, default: true)
        baseTree = container.value(.baseTree, default: nil)
        landing = container.value(.landing, default: nil)
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
        patchPath = container.value(.patchPath, default: nil)
        error = container.value(.error, default: nil)
    }

    init() {}
}

/// A head the lead asked for through the delegation block, on a provider that runs no
/// heads of its own.
struct HydraDelegation: Hashable, Sendable {
    var task: String
    var prompt: String
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
            You have your own copy of the project at \(path): a git worktree Droppy Code made for you from the lead's checkout as it was when you were sent out, uncommitted work included. Work in it directly, on the files as they are; your tools already run there. When you report, Droppy Code carries your changes into the lead's checkout itself. So never commit, branch, stash, push, check out, reset, restore or clean anything, and never make or remove worktrees, whatever the project's own guidelines say about agents and worktrees: this copy already is yours. Do not use git to check your work either.
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
    - Do exactly this task and only this. Do not widen it, do not touch files it does not name unless it cannot be done otherwise, and never revert, reformat or clean up work that is not yours.
    - Check what you changed with the narrowest thing that proves it, a targeted parse, type check or test; leave the project's full build and test suite to the lead unless the task asks for them.
    - If something blocks you, stop and say so instead of guessing or working around it.
    """

    private static let howToReport = "Reply with a short report the lead can act on: what you did, the files you changed, how you checked it, and anything the lead must know. No preamble, no logs."

    /// Appended to the lead's system prompt on providers that run heads natively: when to
    /// delegate, how to split the work and what to do with the reports.
    static func policy(for provider: ProviderKind, maxHeads: Int) -> String {
        let howToSpawn: String
        let howToWait: String
        switch provider {
        case .claude:
            howToSpawn = "Two agent types are yours: `\(workerAgentName)` (edits files, runs commands, verifies) and `\(scoutAgentName)` (read-only research). Spawn them with the Agent tool and prefer them over other agents while Hydra is on: they run on the model and effort the user chose for heads."
            howToWait = "Launch every head for a job in one message so they run in parallel, in the foreground, and run at most \(maxHeads) at once."
        case .codex:
            howToSpawn = "Spawn heads with `spawn_agent`: the `worker` agent for anything that edits files or runs commands, the `explorer` agent for read-only research."
            howToWait = "Spawn every head for a job before waiting, so they run in parallel, and collect them with `wait_agent`; never leave a head running when you answer. Run at most \(maxHeads) at once."
        case .copilot:
            howToSpawn = "Two agents are yours: `\(workerAgentName)` (edits files, runs commands, verifies) and `\(scoutAgentName)` (read-only research). Start them with the task tool and prefer them over other agents while Hydra is on: they run on the model and effort the user chose for heads."
            howToWait = "Start every head for a job at once so they run in parallel, and run at most \(maxHeads) at a time."
        default:
            howToSpawn = ""
            howToWait = "Run at most \(maxHeads) heads at once."
        }
        return """
        # Hydra

        The user switched on Hydra for this chat: you lead a team of helper agents, called heads, that work in parallel in your checkout. \(howToSpawn)

        Delegate only when it pays off: a request that bundles several independent tasks, changes across several unrelated parts of the codebase, or research that needs many files or sources read. For a simple or single-focus request, do it yourself and send out nothing.

        When you delegate:
        - \(howToWait)
        - Give each head one self-contained task with the exact files, symbols and acceptance criteria it needs. Heads share the checkout but not your context, so write the task as if to a capable colleague who has read nothing yet.
        - Split the work so no two heads edit the same file. Keep integration, verification and the final answer for yourself: never send out a head to verify, redo or finish another head's work.
        - Tell the user in one line which heads you sent out and what each one does.

        When they report back:
        - The checkout changes under you while heads work, and the user may be editing too. Never use git status or git diff to check on a head, and never reconcile, revert, stash or move changes you did not make.
        - Take a report as done work: read the files it names if something matters, but do not redo the task and do not start it over because the tree looks different from what you expected. A head that failed leaves its part to you: do it or send it out again. A head the user stopped leaves its part alone unless the user asks.
        - Then finish the job: integrate, run one verification if it matters, and answer the user.
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
        return ["\(workerAgentName)": .object(worker), "\(scoutAgentName)": .object(scout)]
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
        return [
            agent(
                name: workerAgentName,
                display: "Hydra worker",
                description: "Hydra head that implements one delegated task: edits files, runs commands, verifies. Use when a request splits into independent pieces.",
                prompt: workerPrompt,
                tools: nil
            ),
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
    }

    /// Codex's config overrides for the thread: the heads' model and effort, and how many
    /// may run at once.
    static func codexConfig(_ launch: HydraLaunch) -> [String: JSONValue] {
        var agents: [String: JSONValue] = [
            "max_concurrent_threads_per_session": .int(launch.maxHeads),
        ]
        if let model = launch.workerModel, !model.isEmpty { agents["default_subagent_model"] = .string(model) }
        if let effort = launch.workerEffort, !effort.isEmpty { agents["default_subagent_reasoning_effort"] = .string(effort) }
        return ["agents": .object(agents), "features": ["multi_agent": true]]
    }

    // MARK: - Droppy-run heads

    /// How many times in a row a lead may send heads out for one request of the user's:
    /// the first round, and one more for what failed or what the reports showed was
    /// missing. Past that the lead finishes by itself, so no request can chain heads
    /// that verify heads that verify heads.
    static let maxDelegationRounds = 2

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
    static func fallbackPolicy(maxHeads: Int, isolated: Bool) -> String {
        let whereHeadsWork = isolated
            ? "Each head works in a copy of the project of its own and Droppy Code lands its changes in your checkout when it reports"
            : "The heads work in your checkout"
        return """
        [Hydra is on] You lead a team of up to \(maxHeads) helper agents ("heads"). For a simple or single-focus request, just do it yourself. If a request bundles several independent tasks or needs research across many files, delegate: finish your reply with one fenced block

        ```hydra
        [{"task": "short title", "prompt": "complete, self-contained instructions with the exact files and acceptance criteria"}]
        ```

        and stop there: do not wait, poll or verify anything after it. \(whereHeadsWork); heads never see your context, so write every prompt for a capable colleague who has read nothing yet, and give no two heads the same file. The reports arrive as a later message with the work already in place: build on them, do not redo them, never send out heads to verify or redo other heads, and never use git status or git diff to check on heads, since the checkout changes under you while they work. A message that opens with [Hydra] is from Droppy Code, not the user.
        """
    }

    /// In front of the user's own message: the team so far, when there is one.
    static func fallbackTurnNote(team: String?) -> String {
        guard let team else { return "" }
        return "[Hydra] \(team)\n\n---\n\n"
    }

    /// In front of a report message: the heads are back, and the lead's job is to
    /// finish, not to send out more. `canDelegate` leaves one more round open for what
    /// failed or turned out to be missing; otherwise the block is not offered at all.
    static func fallbackReportNote(team: String?, canDelegate: Bool) -> String {
        let more = canDelegate
            ? "If a head failed or the reports show a piece of the user's request still undone, you may send out heads once more for exactly that, with the same ```hydra block at the end of your reply; never for verifying, redoing or finishing what a head already did."
            : "Send out no more heads for this request; whatever is left, do yourself."
        return "[Hydra] Your heads reported back below.\(team.map { " " + $0 } ?? "") \(more)\n\n---\n\n"
    }

    /// Policy and note together, for a CLI provider with no system prompt to keep the
    /// policy in.
    static func fallbackPreamble(maxHeads: Int, isolated: Bool, team: String?) -> String {
        fallbackPolicy(maxHeads: maxHeads, isolated: isolated) + "\n\n" + (fallbackTurnNote(team: team).isEmpty ? "---\n\n" : fallbackTurnNote(team: team))
    }

    static func fallbackReportPreamble(maxHeads: Int, isolated: Bool, team: String?, canDelegate: Bool) -> String {
        fallbackPolicy(maxHeads: maxHeads, isolated: isolated) + "\n\n" + fallbackReportNote(team: team, canDelegate: canDelegate)
    }

    /// What the lead hears when its delegation block is refused: the request has had its
    /// rounds of heads, and the rest is the lead's own.
    static func heldBackMessage(count: Int) -> String {
        """
        Hydra held back \(count == 1 ? "a head" : "\(count) heads").
        None of the heads you asked for went out: this request has had its \(maxDelegationRounds) rounds of heads already. Do the rest yourself now, without git status or git diff on the heads' work, and answer the user.
        """
    }

    /// The delegation block at the end of a reply, if the lead wrote one.
    static func delegations(in text: String) -> [HydraDelegation]? {
        guard let match = text.firstMatch(of: #/```hydra\s*\n([\s\S]*?)```/#) else { return nil }
        let body = String(match.output.1)
        guard let json = JSONValue.parse(body) else { return nil }
        let entries: [JSONValue] = json.array ?? (json.object == nil ? [] : [json])
        let parsed = entries.compactMap { entry -> HydraDelegation? in
            guard let prompt = entry["prompt"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else { return nil }
            let task = entry["task"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return HydraDelegation(task: task.isEmpty ? TextCleanup.singleLine(prompt, limit: 60) : task, prompt: prompt)
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// The reply with its delegation block taken out, for what the lead said to the user.
    static func withoutDelegationBlock(_ text: String) -> String {
        text.replacing(#/```hydra\s*\n[\s\S]*?```/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// What a Droppy-run head is sent for a task the user queued while the lead worked.
    static func queuedHeadPrompt(persona: HydraPersona, task: String, context: ChatContext, workplace: Workplace) -> String {
        var lines: [String] = []
        if let prompt = context.lastUserPrompt, !prompt.isEmpty {
            lines.append("- The user last asked the lead: \(quoted(prompt, limit: 1_200))")
        }
        if let reply = context.lastReply, !reply.isEmpty {
            lines.append("- The lead's latest reply so far: \(quoted(reply, limit: 800))")
        }
        if !context.touchedPaths.isEmpty {
            let paths = context.touchedPaths.prefix(20).joined(separator: ", ")
            lines.append("- Files the lead is changing in its current turn: \(paths). Leave these alone; if your task cannot be done without touching one, keep the change minimal and say so in your report.")
        }
        let contextBlock = lines.isEmpty ? "The lead has not said anything yet." : lines.joined(separator: "\n")
        return """
        You are \(persona.name), a Hydra head in Droppy Code: a helper running in parallel with the lead agent. The user queued this task for you while the lead works on something else.

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
    /// landed where, and what to do about it. `stillWorking` names the heads yet to report.
    static func reportMessage(_ reports: [HydraReport], stillWorking: [String] = []) -> String {
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
            var lines = ["## \(persona.name) — \(report.task)\(outcome)\(took)"]
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
        closing.append("Do not check any of this with git status or git diff: the checkout changes under you while heads work, and the user may be editing too. Do not reconcile, revert or redo anything. Build on the reports, read the files they name if something matters, run one verification if it matters, and finish the job.")
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
        let files = landing.files.map { file -> String in
            var line = "\(file.path) (+\(file.additions) −\(file.deletions))"
            if landing.conflicts.contains(file.path) { line += " with conflicts" }
            return line
        }
        if landing.patchPath != nil { return "Did not land: \(files.joined(separator: ", "))." }
        if let error = landing.error { return "Did not land (\(error)): \(files.joined(separator: ", "))." }
        return "Landed in your checkout: \(files.joined(separator: ", "))."
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
