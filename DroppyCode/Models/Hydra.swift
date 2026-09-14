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
}

/// The shape a head's glyph takes. Twelve of them, one per name in the roster.
enum HydraShape: String, Codable, CaseIterable, Sendable {
    case triangle
    case square
    case circle
    case hexagon
    case diamond
    case pentagon
    case octagon
    case star
    case capsule
    case shield
    case drop
    case squircle
}

/// A head's identity: its name, its colour and the shape of its glyph.
struct HydraPersona: Hashable, Sendable {
    let name: String
    let shape: HydraShape
    /// The colour as 0xRRGGBB.
    let hex: UInt32

    init(_ name: String, _ shape: HydraShape, _ hex: UInt32) {
        self.name = name
        self.shape = shape
        self.hex = hex
    }

    var color: Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    var initial: String { String(name.prefix(1)) }
}

/// The names heads are given, in the order they are sent out. Past twelve the roster
/// starts over with a number after the name.
enum HydraRoster {
    static let personas: [HydraPersona] = [
        HydraPersona("Hank", .triangle, 0xFF8A3D),
        HydraPersona("Walter", .square, 0x3D8BFF),
        HydraPersona("Ada", .circle, 0x34C46A),
        HydraPersona("Otto", .hexagon, 0xA35BE0),
        HydraPersona("Nova", .diamond, 0xF25C9A),
        HydraPersona("Remy", .pentagon, 0x2BB5B0),
        HydraPersona("Iris", .octagon, 0xE8B430),
        HydraPersona("Milo", .star, 0xE84F4F),
        HydraPersona("Juno", .capsule, 0x6A5CFF),
        HydraPersona("Ezra", .shield, 0x4FD1A1),
        HydraPersona("Lena", .drop, 0x2FB8E6),
        HydraPersona("Bo", .squircle, 0xB0784A),
    ]

    static func persona(at index: Int) -> HydraPersona {
        let count = personas.count
        let base = personas[((index % count) + count) % count]
        let round = max(0, index) / count
        guard round > 0 else { return base }
        return HydraPersona("\(base.name) \(round + 1)", base.shape, base.hex)
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

    var persona: HydraPersona { HydraRoster.persona(at: index) }
    var isFinished: Bool { status.isFinished }

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
    }
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
}

/// The words Hydra puts in front of the lead and the heads, per provider.
enum HydraPrompts {
    static let workerAgentName = "droppy-worker"
    static let scoutAgentName = "droppy-scout"

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

        The user switched on Hydra for this chat: you lead a team of helper agents, called heads, that work in parallel on the same checkout. \(howToSpawn)

        Delegate only when it pays off: a request that bundles several independent tasks, changes across several unrelated parts of the codebase, or research that needs many files or sources read. For a simple or single-focus request, do it yourself and send out nothing.

        When you delegate:
        - \(howToWait)
        - Give each head one self-contained task with the exact files, symbols and acceptance criteria it needs. Heads share the checkout but not your context, so write the task as if to a capable colleague who has read nothing yet.
        - Split the work so no two heads edit the same file. Keep integration, verification and the final answer for yourself.
        - Tell the user in one line which heads you sent out and what each one does. When they report back, check anything that matters before you build on it, then finish the job.
        """
    }

    /// The system prompt a worker head runs with.
    static let workerPrompt = """
    You are a Hydra head in Droppy Code: one of several helpers working in parallel for a lead agent on the same checkout. Do exactly the task you were given, and only that: do not widen it, do not touch files it does not name unless the task cannot be done otherwise, and never revert or reformat work you did not do. Verify what you change with the narrowest check that proves it. If something blocks you, say so instead of guessing.

    Reply with a short report the lead can act on: what you did, the files you changed, how you verified it, and anything the lead must know. No preamble, no logs.
    """

    /// The system prompt a scout head runs with.
    static let scoutPrompt = """
    You are a Hydra head in Droppy Code: a read-only researcher working in parallel for a lead agent. Answer exactly the question you were given, from the code and sources you can read. Change nothing.

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

    /// Put in front of the user's prompt on providers that run no heads of their own: the
    /// lead may end its reply with a delegation block, which Droppy Code turns into heads.
    static func fallbackPreamble(maxHeads: Int) -> String {
        """
        [Hydra is on] You lead a team of up to \(maxHeads) helper agents ("heads"). For a simple or single-focus request, just do it yourself. If this request bundles several independent tasks or needs research across many files, delegate: finish your reply with one fenced block

        ```hydra
        [{"task": "short title", "prompt": "complete, self-contained instructions with the exact files and acceptance criteria"}]
        ```

        and stop there. Heads share the checkout but not your context, and no two may edit the same file. Their reports arrive as the next message; then integrate the results and finish the job.

        ---

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
    static func delegatedHeadPrompt(persona: HydraPersona, delegation: HydraDelegation) -> String {
        """
        You are \(persona.name), a Hydra head in Droppy Code: one of several helpers working in parallel for a lead agent on the same checkout. The lead delegated this task to you.

        ## Your task: \(delegation.task)
        \(delegation.prompt)

        Do exactly this task and only this: do not widen it, do not touch files it does not name unless the task cannot be done otherwise, and never revert or reformat work you did not do. Verify what you change with the narrowest check that proves it. If something blocks you, say so instead of guessing.

        Reply with a short report the lead can act on: what you did, the files you changed, how you verified it, and anything the lead must know. No preamble, no logs.
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
    static func queuedHeadPrompt(persona: HydraPersona, task: String, context: ChatContext) -> String {
        var lines: [String] = []
        if let prompt = context.lastUserPrompt, !prompt.isEmpty {
            lines.append("- The user last asked the lead: \(quoted(prompt, limit: 1_200))")
        }
        if let reply = context.lastReply, !reply.isEmpty {
            lines.append("- The lead's latest reply so far: \(quoted(reply, limit: 800))")
        }
        if !context.touchedPaths.isEmpty {
            let paths = context.touchedPaths.prefix(20).joined(separator: ", ")
            lines.append("- Files the lead has changed in its current turn: \(paths). Leave these alone; if your task cannot be done without touching one, keep the change minimal and say so in your report.")
        }
        let contextBlock = lines.isEmpty ? "The lead has not said anything yet." : lines.joined(separator: "\n")
        return """
        You are \(persona.name), a Hydra head in Droppy Code: a helper running in parallel with the lead agent on the same checkout. The user queued this task for you while the lead works on something else.

        ## What is going on in the main chat
        \(contextBlock)

        ## Your task
        \(task)

        Do exactly this task and only this: do not widen it, and never revert or reformat work you did not do. Verify what you change with the narrowest check that proves it. If something blocks you, say so instead of guessing.

        Reply with a short report for the lead: what you did, the files you changed, how you verified it, and anything the lead must know. No preamble, no logs.
        """
    }

    /// The message the lead receives once heads have reported: one section per head.
    static func reportMessage(_ reports: [HydraReport]) -> String {
        let names = reports.map { HydraRoster.persona(at: $0.headIndex).name }
        let who = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        var sections: [String] = []
        for report in reports {
            let persona = HydraRoster.persona(at: report.headIndex)
            let outcome = switch report.status {
            case .completed: ""
            case .failed: " (failed)"
            case .stopped: " (stopped before finishing)"
            case .running: ""
            }
            let body = report.text.trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append("## \(persona.name) — \(report.task)\(outcome)\n\(body.isEmpty ? "No report." : body)")
        }
        let queued = reports.contains { $0.origin == .queued }
        let closing = queued
            ? "The user queued that work for the heads while you were busy; take it into account and carry on with the main job."
            : "Fold these into your work, check anything that matters, and finish the job."
        return """
        Hydra reports: \(who) finished.

        \(sections.joined(separator: "\n\n"))

        \(closing)
        """
    }

    private static func quoted(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = trimmed.count > limit ? String(trimmed.prefix(limit)) + "…" : trimmed
        return "“\(cut)”"
    }
}
