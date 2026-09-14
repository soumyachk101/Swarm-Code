import Foundation

struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var path: String
    var addedAt: Date
    var isExpanded: Bool
    var scripts: [ProjectScript]

    init(name: String, path: String) {
        id = UUID()
        self.name = name
        self.path = path
        addedAt = .now
        isExpanded = true
        scripts = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = container.value(.name, default: URL(fileURLWithPath: path).lastPathComponent)
        addedAt = container.value(.addedAt, default: .now)
        isExpanded = container.value(.isExpanded, default: true)
        scripts = container.value(.scripts, default: [])
    }

    var url: URL { URL(fileURLWithPath: path) }
}

struct ProjectScript: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var command: String
    var symbol: String
    var runOnWorktreeCreate: Bool

    init(name: String, command: String, symbol: String = "play", runOnWorktreeCreate: Bool = false) {
        id = UUID()
        self.name = name
        self.command = command
        self.symbol = symbol
        self.runOnWorktreeCreate = runOnWorktreeCreate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.value(.id, default: UUID())
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        symbol = container.value(.symbol, default: "play")
        runOnWorktreeCreate = container.value(.runOnWorktreeCreate, default: false)
    }
}

struct ChatThread: Codable, Identifiable, Hashable, Sendable {
    static let untitled = "New thread"

    var id: UUID
    var projectID: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var provider: ProviderKind
    var model: String?
    var effort: String?
    var fastMode: Bool
    var runtimeMode: RuntimeMode
    var interactionMode: InteractionMode
    var worktreePath: String?
    var branch: String?
    var providerSessionID: String?
    var isPinned: Bool
    var isArchived: Bool
    /// Finished, as far as the sidebar is concerned: the thread sits at the bottom of its
    /// list as a small grey row until it is reopened, by hand or by a new turn.
    var isSettled = false
    /// When it settled; the latest settled thread sits first among them.
    var settledAt: Date?
    var hasUnread: Bool
    var hasCustomTitle: Bool
    /// The thread's place once its project has been reordered by dragging; nil keeps newest first.
    var sortOrder: Double?
    /// The thread's place within its group in the activity layout once dragged there.
    var activityOrder: Double?
    /// The day that place was given; a thread active on a later day is newest first again.
    var activityOrderDay: Date?
    var lastStatus: TurnStatus?
    /// The thread this one was spawned from, for a helper (a merge, for now). A helper opens
    /// in its parent's floating panel and, once that closes, sits under its parent in the
    /// sidebar as a smaller row for as long as the parent is there.
    var parentThreadID: UUID?
    /// Whether the helper is showing in its parent's floating panel. While it is, it is kept
    /// out of the sidebar, the palette, the recent picks and the unread count.
    var isInPanel = false
    /// Whether this thread's helpers are folded away under it in the sidebar.
    var foldsHelpers = false
    /// Whether Hydra is on for this chat: with the app-wide switch on too, the chat's agent
    /// leads a team of heads on big jobs.
    var hydraEnabled = false
    /// The pair the heads run on while Hydra is on, when one was picked for this chat.
    var hydraPairID: UUID?
    /// How many heads this chat has sent out so far: the next one's place in the roster.
    var hydraSpawnCount = 0
    /// Set on a head: the thread is one of its parent's team.
    var hydra: HydraHeadInfo?

    /// Spawned from another thread, whichever side of the panel it is on.
    var isHelper: Bool { parentThreadID != nil }

    /// A Hydra head, whichever side of the panel it is on.
    var isHydraHead: Bool { hydra != nil }

    init(projectID: UUID, provider: ProviderKind, model: String?, effort: String?, runtimeMode: RuntimeMode, fastMode: Bool = false) {
        id = UUID()
        self.projectID = projectID
        title = Self.untitled
        createdAt = .now
        updatedAt = .now
        self.provider = provider
        self.model = model
        self.effort = effort
        self.fastMode = fastMode
        self.runtimeMode = runtimeMode
        interactionMode = .build
        isPinned = false
        isArchived = false
        hasUnread = false
        hasCustomTitle = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        title = container.value(.title, default: Self.untitled)
        createdAt = container.value(.createdAt, default: .now)
        updatedAt = container.value(.updatedAt, default: createdAt)
        provider = container.value(.provider, default: .codex)
        model = container.value(.model, default: nil)
        effort = container.value(.effort, default: nil)
        fastMode = container.value(.fastMode, default: false)
        runtimeMode = container.value(.runtimeMode, default: .fullAccess)
        interactionMode = container.value(.interactionMode, default: .build)
        worktreePath = container.value(.worktreePath, default: nil)
        branch = container.value(.branch, default: nil)
        providerSessionID = container.value(.providerSessionID, default: nil)
        isPinned = container.value(.isPinned, default: false)
        isArchived = container.value(.isArchived, default: false)
        isSettled = container.value(.isSettled, default: false)
        settledAt = container.value(.settledAt, default: nil)
        hasUnread = container.value(.hasUnread, default: false)
        hasCustomTitle = container.value(.hasCustomTitle, default: false)
        sortOrder = container.value(.sortOrder, default: nil)
        activityOrder = container.value(.activityOrder, default: nil)
        activityOrderDay = container.value(.activityOrderDay, default: nil)
        lastStatus = container.value(.lastStatus, default: nil)
        parentThreadID = container.value(.parentThreadID, default: nil)
        isInPanel = container.value(.isInPanel, default: false)
        foldsHelpers = container.value(.foldsHelpers, default: false)
        hydraEnabled = container.value(.hydraEnabled, default: false)
        hydraPairID = container.value(.hydraPairID, default: nil)
        hydraSpawnCount = container.value(.hydraSpawnCount, default: 0)
        hydra = container.value(.hydra, default: nil)
    }
}

struct Library: Codable, Sendable {
    var projects: [Project] = []
    var threads: [ChatThread] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = container.value(.projects, default: [Lenient<Project>]()).compactMap(\.value)
        threads = container.value(.threads, default: [Lenient<ChatThread>]()).compactMap(\.value)
    }
}
