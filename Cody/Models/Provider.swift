import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case cursor
    case opencode
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .grok: "Grok"
        }
    }

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .cursor: "cursor-agent"
        case .opencode: "opencode"
        case .grok: "grok"
        }
    }

    var iconName: String { "provider-\(rawValue)" }

    var loginCommand: String {
        switch self {
        case .codex: "codex login"
        case .claude: "claude auth login"
        case .cursor: "cursor-agent login"
        case .opencode: "opencode auth login"
        case .grok: "grok login"
        }
    }

    var installURL: URL {
        switch self {
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: URL(string: "https://claude.com/product/claude-code")!
        case .cursor: URL(string: "https://cursor.com/cli")!
        case .opencode: URL(string: "https://opencode.ai")!
        case .grok: URL(string: "https://x.ai/cli")!
        }
    }

    /// Whether the provider can drop later turns from its own conversation.
    var supportsRewind: Bool { self == .codex || self == .claude }

    var supportsImages: Bool { self != .grok }

    var usesACP: Bool { self == .cursor || self == .opencode || self == .grok }
}

enum RuntimeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case supervised
    case autoAcceptEdits
    case auto
    case fullAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supervised: "Supervised"
        case .autoAcceptEdits: "Auto-accept edits"
        case .auto: "Auto"
        case .fullAccess: "Full access"
        }
    }

    var summary: String {
        switch self {
        case .supervised: "Asks before commands and file changes"
        case .autoAcceptEdits: "Edits files freely, asks before other actions"
        case .auto: "The provider's reviewer approves routine actions"
        case .fullAccess: "Runs commands and edits without asking"
        }
    }

    var symbol: String {
        switch self {
        case .supervised: "hand.raised"
        case .autoAcceptEdits: "pencil.line"
        case .auto: "wand.and.sparkles"
        case .fullAccess: "lock.open"
        }
    }
}

enum InteractionMode: String, Codable, Sendable {
    case build
    case plan
}

enum WorkspaceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case local
    case worktree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: "Local"
        case .worktree: "New worktree"
        }
    }
}

struct ModelOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var detail: String?
    var efforts: [String]
    var defaultEffort: String?
    var isDefault: Bool

    init(
        id: String,
        name: String,
        detail: String? = nil,
        efforts: [String] = [],
        defaultEffort: String? = nil,
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.isDefault = isDefault
    }

    static func effortTitle(_ effort: String) -> String {
        switch effort {
        case "xhigh", "extra-high": "Extra high"
        case "": "Default"
        default: effort.prefix(1).uppercased() + effort.dropFirst()
        }
    }
}

struct SlashCommand: Hashable, Identifiable, Sendable {
    var name: String
    var detail: String
    var isBuiltIn: Bool = false

    var id: String { name }
}
