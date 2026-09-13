import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case cursor
    case opencode
    case grok
    case deepseek
    case meta

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .grok: "Grok"
        case .deepseek: "DeepSeek"
        case .meta: "Meta"
        }
    }

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .cursor: "cursor-agent"
        case .opencode: "opencode"
        case .grok: "grok"
        case .deepseek: ""
        case .meta: ""
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
        case .deepseek: "DEEPSEEK_API_KEY=sk-..."
        case .meta: "MODEL_API_KEY=..."
        }
    }

    var installURL: URL {
        switch self {
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        case .claude: URL(string: "https://claude.com/product/claude-code")!
        case .cursor: URL(string: "https://cursor.com/cli")!
        case .opencode: URL(string: "https://opencode.ai")!
        case .grok: URL(string: "https://x.ai/cli")!
        case .deepseek: URL(string: "https://platform.deepseek.com/api_keys")!
        case .meta: URL(string: "https://dev.meta.ai/")!
        }
    }

    /// API-key providers talk to their cloud API directly instead of a local CLI.
    var isAPIKeyBased: Bool { self == .deepseek || self == .meta }

    /// Host shown in Settings for API-key providers, e.g. "api.meta.ai/v1".
    var apiHost: String? {
        switch self {
        case .deepseek: "api.deepseek.com"
        case .meta: "api.meta.ai/v1"
        default: nil
        }
    }

    /// Where the dashboard key lives, for the Settings detail line.
    var apiKeySource: String? {
        switch self {
        case .deepseek: "platform.deepseek.com"
        case .meta: "dev.meta.ai"
        default: nil
        }
    }

    /// Env var fallback read when no key is stored in Settings.
    var apiKeyEnvVar: String? {
        switch self {
        case .deepseek: "DEEPSEEK_API_KEY"
        case .meta: "MODEL_API_KEY"
        default: nil
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
    /// The service tier that makes this model fast, when its provider offers one.
    var fastTier: String?

    init(
        id: String,
        name: String,
        detail: String? = nil,
        efforts: [String] = [],
        defaultEffort: String? = nil,
        isDefault: Bool = false,
        fastTier: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.isDefault = isDefault
        self.fastTier = fastTier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        efforts = try container.decodeIfPresent([String].self, forKey: .efforts) ?? []
        defaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultEffort)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        fastTier = try container.decodeIfPresent(String.self, forKey: .fastTier)
    }

    var supportsFast: Bool { fastTier != nil }

    /// The name as the picker shows it, such as "5.6 Terra" for "GPT-5.6-Terra".
    var shortName: String {
        var trimmed = name
        if trimmed.lowercased().hasPrefix("gpt-") { trimmed = String(trimmed.dropFirst(4)) }
        return trimmed.replacingOccurrences(of: "-", with: " ")
    }

    static func effortTitle(_ effort: String) -> String {
        switch effort {
        case "xhigh", "extra-high": "Extra High"
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
