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
    var hasUnread: Bool
    var hasCustomTitle: Bool
    var lastStatus: TurnStatus?

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
        hasUnread = container.value(.hasUnread, default: false)
        hasCustomTitle = container.value(.hasCustomTitle, default: false)
        lastStatus = container.value(.lastStatus, default: nil)
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
