//
// AppState.swift
// BridgeMind One — UI-layer global state & models
//

import SwiftUI
import Core

public typealias PluginState = PluginRuntimeState

// MARK: - Startup Behavior & App Theme

public enum StartupBehavior: String, CaseIterable, Identifiable, Codable, Sendable {
    case lastSession = "Resume Last Session"
    case newChat = "Open New Chat"
    case welcome = "Show Welcome Screen"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

// MARK: - Settings Data

public struct SettingsData: Codable, Sendable {
    public var autoSaveEnabled: Bool = true
    public var notificationsEnabled: Bool = true
    public var voiceDictationEnabled: Bool = false
    public var startupBehavior: StartupBehavior = .lastSession
    public var fontSize: Double = 14.0
    public var claudeCodePath: String = "claude"
    public var codexPath: String = "codex"
    public var cursorPath: String = "cursor"
    public var llmProvider: String = "anthropic"
    public var telemetryEnabled: Bool = false
    public var theme: AppTheme = .dark

    public init() {}
}

public enum TopNavMode: String, CaseIterable, Identifiable, Sendable {
    case agent = "Agent"
    case code = "Code"
    case chat = "Chat"

    public var id: String { rawValue }
}

public struct AgentProfile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let engineSubtitle: String
    public let isOnline: Bool
    public let iconColor: Color

    public init(id: String, name: String, engineSubtitle: String, isOnline: Bool = false, iconColor: Color = BMColors.claudeOrange) {
        self.id = id
        self.name = name
        self.engineSubtitle = engineSubtitle
        self.isOnline = isOnline
        self.iconColor = iconColor
    }
}

public struct ToolCallItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let type: String // "Search", "Run", "Draft"
    public let detail: String // "apollo: technographics · ai_coding_tools"
    public let isCompleted: Bool

    public init(id: String = UUID().uuidString, type: String, detail: String, isCompleted: Bool = true) {
        self.id = id
        self.type = type
        self.detail = detail
        self.isCompleted = isCompleted
    }
}

public struct RichChatMessage: Identifiable, Hashable, Sendable {
    public let id: String
    public let role: MessageRole
    public let content: String
    public let thoughtTime: String? // "Thought for 12s"
    public let previousToolCount: Int? // 2
    public let toolCalls: [ToolCallItem]
    public let footerNote: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        thoughtTime: String? = nil,
        previousToolCount: Int? = nil,
        toolCalls: [ToolCallItem] = [],
        footerNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thoughtTime = thoughtTime
        self.previousToolCount = previousToolCount
        self.toolCalls = toolCalls
        self.footerNote = footerNote
        self.createdAt = createdAt
    }
}

public struct ChatThreadItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let timeAgo: String
    public let previewSnippet: String
    public var messages: [RichChatMessage]

    public init(id: String = UUID().uuidString, title: String, timeAgo: String, previewSnippet: String, messages: [RichChatMessage] = []) {
        self.id = id
        self.title = title
        self.timeAgo = timeAgo
        self.previewSnippet = previewSnippet
        self.messages = messages
    }
}

@Observable
public final class AppState: ObservableObject, @unchecked Sendable {

    public static let shared = AppState()

    // MARK: - Navigation
    public var topMode: TopNavMode = .agent

    public enum LeftNavSection: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case routines = "Routines"
        case plugins = "Plugins"
        case skills = "Skills"

        public var id: String { rawValue }
    }

    public var selectedLeftSection: LeftNavSection? = nil
    public var selectedAgentId: String = "cold-outreach"

    public var agents: [AgentProfile] = [
        AgentProfile(id: "x-trend", name: "X trend scout", engineSubtitle: "Powered by Grok", isOnline: true),
        AgentProfile(id: "trend-video", name: "Trend video strategist", engineSubtitle: "Powered by Gemini"),
        AgentProfile(id: "charter-writer", name: "BridgeMind charter writer", engineSubtitle: "Powered by Codex"),
        AgentProfile(id: "cold-outreach", name: "Cold outreach operator", engineSubtitle: "Powered by Claude Code")
    ]

    public var selectedAgent: AgentProfile {
        agents.first { $0.id == selectedAgentId } ?? agents[3]
    }

    // MARK: - Middle Pane Sub Tabs
    public enum MiddleSubTab: String, CaseIterable, Identifiable {
        case chats = "Chats"
        case skills = "Skills 2"
        case settings = "Settings"

        public var id: String { rawValue }
    }

    public var middleSubTab: MiddleSubTab = .chats
    public var selectedThreadId: String = "t2"

    public var threads: [ChatThreadItem] = [
        ChatThreadItem(
            id: "t1",
            title: "bridgemind-one-swift",
            timeAgo: "17m",
            previewSnippet: "I want to connect with the ...",
            messages: [
                RichChatMessage(
                    role: .user,
                    content: "I want to connect with the Supabase MCP plugin and list all database schemas."
                ),
                RichChatMessage(
                    role: .assistant,
                    content: "Connected to Supabase MCP transport. Successfully read 4 schemas.",
                    thoughtTime: "Thought for 4s",
                    toolCalls: [
                        ToolCallItem(type: "Search", detail: "supabase: schemas · tables"),
                        ToolCallItem(type: "Run", detail: "supabase inspect db --local")
                    ]
                )
            ]
        ),
        ChatThreadItem(
            id: "t2",
            title: "bridgemind-one-swift",
            timeAgo: "20m",
            previewSnippet: "I need you to help me find lea...",
            messages: [
                RichChatMessage(
                    role: .user,
                    content: "I need you to help me find leads for the launch. Builders shipping with agents, not people talking about them."
                ),
                RichChatMessage(
                    role: .assistant,
                    content: "Filtered on evidence rather than vocabulary:\n\n• **412 accounts** mention agents in their bio.\n• **96** of those shipped a release in the last thirty days.\n• **41** did it with a coding agent in the commit trailer.\n\nThe 41 are the list. I put the other 371 in a second sheet so you can see what I threw away.",
                    thoughtTime: "Thought for 12s",
                    previousToolCount: 2,
                    toolCalls: [
                        ToolCallItem(type: "Search", detail: "apollo: technographics · ai_coding_tools"),
                        ToolCallItem(type: "Run", detail: "gh api search/commits --jq .items[].author")
                    ]
                ),
                RichChatMessage(
                    role: .user,
                    content: "Good. Queue the first ten."
                ),
                RichChatMessage(
                    role: .assistant,
                    content: "Ten drafts held at the gateway",
                    toolCalls: [
                        ToolCallItem(type: "Draft", detail: "10 messages · awaiting approval")
                    ]
                )
            ]
        )
    ]

    public var currentThread: ChatThreadItem? {
        get { threads.first { $0.id == selectedThreadId } ?? threads.first }
        set {
            if let newValue {
                if let idx = threads.firstIndex(where: { $0.id == newValue.id }) {
                    threads[idx] = newValue
                }
            }
        }
    }

    // MARK: - Input State
    public var promptText: String = ""
    public var selectedModel: String = "Automatic · Sonnet 5"
    public var effortLevel: String = "High"
    public var autoAcceptEdits: Bool = true
    public var tokenCountText: String = "31.6k tokens"
    public var isWorking: Bool = false
    public var workingCount: Int = 0

    // MARK: - Bottom Footer
    public var notchEnabled: Bool = false
    public var credits: String = "9,684"
    public var username: String = "Bridgemindapps"
    public var isPro: Bool = true

    // MARK: - Processing State
    public var isProcessing: Bool = false
    public var statusMessage: String = "Ready"

    // MARK: - Legacy Compatibility
    public var activeAgent: EngineType = .claude
    public var orbState: OrbState = .idle
    public var isAboutSheetPresented: Bool = false
    public var isAgentSwitcherPresented: Bool = false
    public var isPluginsPanelPresented: Bool = false
    public var showPlugins: Bool = false
    public var isAutoPilotEnabled: Bool = false
    public var sidebarSelection: SidebarItem = .chat
    public var settings: SettingsData = SettingsData()

    public enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
        case chat = "Chat"
        case autoPilot = "Auto-Pilot"
        case plugins = "Plugins"
        case skills = "Skills"
        case settings = "Settings"

        public var id: String { rawValue }
        public var title: String { rawValue }
        public var iconName: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .autoPilot: return "bolt.shield.fill"
            case .plugins: return "puzzlepiece.extension.fill"
            case .skills: return "brain.head.profile"
            case .settings: return "gearshape.fill"
            }
        }
    }

    public var allPlugins: [PluginIdentity] {
        PluginCollection.allIdentities
    }

    public var plugins: [PluginIdentity: PluginRuntimeState] = [:]
    public var sessions: [ChatSession] = []
    public var currentSessionId: String? = nil
    public var currentSession: ChatSession? = nil

    public init(core: Any? = nil) {
        for plugin in PluginCollection.allIdentities {
            self.plugins[plugin] = PluginRuntimeState(
                pluginId: plugin.id,
                enabled: true,
                connected: false
            )
        }
    }

    public func createNewChat() {
        let newThread = ChatThreadItem(
            title: "bridgemind-one-swift",
            timeAgo: "Just now",
            previewSnippet: "New conversation...",
            messages: []
        )
        threads.insert(newThread, at: 0)
        selectedThreadId = newThread.id
    }

    public func saveCurrentChat() {}
    public func toggleAutoPilot() { isAutoPilotEnabled.toggle() }
    public func switchAgent(to agent: EngineType) { activeAgent = agent }
    public func openDocumentation() {}
    public func openIssueReporter() {}
    public func deleteSession(_ session: ChatSession) {}
    public func selectSession(id: String) { selectedThreadId = id }
}
