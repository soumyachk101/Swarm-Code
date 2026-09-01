//
// AppState.swift
// BridgeMind One — UI-layer global state
//
// Wraps Core models and state for SwiftUI Observation and environment usage.
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

// MARK: - AppState

@Observable
public final class AppState: ObservableObject, @unchecked Sendable {

    public static let shared = AppState()

    // MARK: - Navigation

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

    public var sidebarSelection: SidebarItem = .chat
    public var selectedThreadId: String?

    // MARK: - Chat & Sessions

    public var databaseManager: DatabaseManager?
    public var currentSessionId: String?
    public var sessions: [ChatSession] = []
    public var currentMessages: [ChatMessage] = []

    public var currentSession: ChatSession? {
        get {
            if let id = currentSessionId {
                return sessions.first { $0.id == id }
            }
            return sessions.first
        }
        set {
            if let newValue {
                if let idx = sessions.firstIndex(where: { $0.id == newValue.id }) {
                    sessions[idx] = newValue
                } else {
                    sessions.append(newValue)
                }
                currentSessionId = newValue.id
            }
        }
    }

    // MARK: - Agent State

    public var activeAgent: EngineType = .claude
    public var selectedAgentId: String = "claude"
    public var availableEngines: [EngineType] { EngineType.allCases }
    public var engineStatuses: [EngineType: EngineHealth] = [:]

    // MARK: - Plugins State

    public var plugins: [PluginIdentity: PluginRuntimeState] = [:]
    public var activePlugins: [PluginIdentity] {
        allPlugins.filter { plugins[$0]?.connected ?? false }
    }
    public var allPlugins: [PluginIdentity] {
        PluginCollection.allIdentities
    }

    // MARK: - Processing & Orb

    public var isStreaming: Bool = false
    public var isProcessing: Bool = false
    public var orbState: OrbState = .idle
    public var statusMessage: String = "Ready"
    public var streamingContent: String = ""
    public var isThinking: Bool = false
    public var isDictating: Bool = false

    // MARK: - Sheets & Panels

    public var isAboutSheetPresented: Bool = false
    public var isPluginsPanelPresented: Bool = false
    public var showPlugins: Bool {
        get { isPluginsPanelPresented }
        set { isPluginsPanelPresented = newValue }
    }
    public var isAgentSwitcherPresented: Bool = false
    public var isSettingsPresented: Bool = false
    public var isAutoPilotEnabled: Bool = false
    public var selectedPluginId: String?

    // MARK: - Settings & UI

    public var settings: SettingsData = SettingsData()
    public var searchText: String = ""
    public var sidebarWidth: CGFloat = 240
    public var toastMessage: String?
    public var toastType: ToastType = .info

    public enum ToastType {
        case info, success, warning, error
    }

    // MARK: - Init

    public init(core: Any? = nil) {
        // Initialize default sample session
        let initial = ChatSession(
            title: "Welcome to BridgeMind One",
            agentId: "claude",
            messages: [
                ChatMessage(
                    role: .assistant,
                    content: "Welcome to BridgeMind One! I am your AI-powered multi-agent orchestration workspace. You can switch engines, enable plugins, or connect MCP servers to get started."
                )
            ]
        )
        self.sessions = [initial]
        self.currentSessionId = initial.id
        self.currentMessages = initial.messages

        // Initialize plugin states
        for plugin in PluginCollection.allIdentities {
            self.plugins[plugin] = PluginRuntimeState(
                pluginId: plugin.id,
                enabled: true,
                connected: false
            )
        }
    }

    // MARK: - Session Management

    public func createNewChat() {
        let newSession = ChatSession(
            title: "New Chat",
            agentId: selectedAgentId,
            messages: []
        )
        sessions.insert(newSession, at: 0)
        currentSessionId = newSession.id
        selectedThreadId = newSession.id
        currentMessages = []
    }

    public func createNewSession(agentId: String = "claude") async {
        createNewChat()
    }

    public func selectSession(id: String) {
        currentSessionId = id
        selectedThreadId = id
        if let session = sessions.first(where: { $0.id == id }) {
            currentMessages = session.messages
        }
    }

    public func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSessionId == session.id {
            currentSessionId = sessions.first?.id
            selectedThreadId = currentSessionId
            currentMessages = sessions.first?.messages ?? []
        }
    }

    public func saveCurrentChat() {
        showToast("Chat saved", type: .success)
    }

    public func toggleAutoPilot() {
        isAutoPilotEnabled.toggle()
        showToast(
            isAutoPilotEnabled ? "Auto-Pilot: Enabled" : "Auto-Pilot: Disabled",
            type: isAutoPilotEnabled ? .success : .info
        )
    }

    public func switchAgent(to agent: EngineType) {
        activeAgent = agent
        selectedAgentId = agent.rawValue
        isAgentSwitcherPresented = false
        showToast("Switched engine to \(agent.displayName)", type: .success)
    }

    public func switchAgent(to agentId: String) {
        if let engine = EngineType(rawValue: agentId) {
            switchAgent(to: engine)
        } else {
            selectedAgentId = agentId
            isAgentSwitcherPresented = false
            showToast("Switched agent to \(agentId)", type: .success)
        }
    }

    public func openDocumentation() {
        if let url = URL(string: "https://docs.bridgemind.ai") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openIssueReporter() {
        if let url = URL(string: "https://github.com/bridgemind/bridgemind/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openSettings() {
        isSettingsPresented = true
    }

    public func showToast(_ message: String, type: ToastType = .info) {
        toastMessage = message
        toastType = type
    }
}
