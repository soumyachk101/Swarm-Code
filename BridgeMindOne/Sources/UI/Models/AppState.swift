//
// AppState.swift
// Global application state management
//

import Foundation
import SwiftUI
import Core

@MainActor
@Observable
public final class AppState {
 public static let shared = AppState()

 // Current session
 public var currentSession: ChatSession?
 public var sessions: [ChatSession] = []

 // Agents
 public var activeAgent: AgentIdentity?
 public var availableEngines: [AgentEngine] = []
 public var isAutoPilotEnabled = false

 // Plugins
 public var plugins: [PluginIdentity: PluginState] = [:]
 public var showPlugins = false
 public var activePlugins: [PluginIdentity] { plugins.filter { $0.value.enabled }.map { $0.key } }

 // UI State
 public var showAboutSheet = false
 public var showAgentSwitcher = false
 public var showSettings = false
 public var selectedThreadId: String?

 // Status
 public var isProcessing = false
 public var statusMessage: String?
 public var orbState: OrbState = .idle

 // Settings
 public var settings = AppSettings()
 public var workingDirectory: URL?
 public var apiKeys: [String: String] = [:]

 // Presence
 public var isPresent: Bool = true
 public var connectedAgents: [AgentIdentity] = []

 private init() {
 loadState()
 }

 public func createNewChat() {
 let session = ChatSession(
 title: "New Chat",
 agentId: activeAgent?.id
 )
 currentSession = session
 sessions.append(session)
 saveState()
 }

 public func deleteSession(_ session: ChatSession) {
 sessions.removeAll { $0.id == session.id }
 if currentSession?.id == session.id {
 currentSession = sessions.first
 }
 saveState()
 }

 public func toggleAutoPilot() {
 isAutoPilotEnabled.toggle()
 if isAutoPilotEnabled {
 statusMessage = "Auto-Pilot active"
 orbState = .listening
 }
 }

 public func saveCurrentChat() {
 // Trigger save to SQLite
 Task {
 try? await DatabaseManager.shared.saveSession(currentSession)
 }
 }

 public func openDocumentation() {
 if let url = URL(string: "https://docs.bridgemind.ai") {
 NSWorkspace.shared.open(url)
 }
 }

 public func openIssueReporter() {
 if let url = URL(string: "https://github.com/bridgemind/bridgemind-one/issues") {
 NSWorkspace.shared.open(url)
 }

 public func switchAgent(to agent: AgentIdentity) {
 activeAgent = agent
 showAgentSwitcher = false
 }

 // MARK: - Private

 private func loadState() {
 // Load from UserDefaults + SQLite
 settings = AppSettings.load()
 }

 private func saveState() {
 settings.save()
 }
}

// MARK: - Models

public struct AppSettings: Codable, Equatable {
 public var llmProvider: String = "anthropic"
 public var claudeCodePath: String = "claude"
 public var codexPath: String = "codex"
 public var cursorPath: String = "cursor"
 public var autoSaveEnabled: Bool = true
 public var telemetryEnabled: Bool = true
 public var notificationsEnabled: Bool = true
 public var voiceDictationEnabled: Bool = true
 public var fnKeyTriggersDictation: Bool = true
 public var fontSize: Double = 14
 public var theme: AppTheme = .system
 public var startupBehavior: StartupBehavior = .restoreLastSession

 public static func load() -> AppSettings {
 let defaults = UserDefaults.standard
 guard let data = defaults.data(forKey: "AppSettings"),
 let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
 return AppSettings()
 }
 return settings
 }

 public mutating func save() {
 let data = try? JSONEncoder().encode(self)
 UserDefaults.standard.set(data, forKey: "AppSettings")
 }
}

public enum AppTheme: String, Codable, CaseIterable {
 case system
 case light
 case dark
}

public enum StartupBehavior: String, Codable, CaseIterable {
 case restoreLastSession
 case showWelcome
 case createNewChat
}

public struct AgentIdentity: Codable, Equatable, Identifiable {
 public let id: String
 public var name: String
 public var engine: AgentEngineType
 public var workingDirectory: URL?
 public var capabilities: [String] = []

 public init(id: String, name: String, engine: AgentEngineType, workingDirectory: URL? = nil) {
 self.id = id
 self.name = name
 self.engine = engine
 self.workingDirectory = workingDirectory
 }
}

public enum AgentEngineType: String, Codable, CaseIterable {
 case claude = "claude"
 case codex = "codex"
 case copilot = "copilot"
 case cursor = "cursor"
 case aider = "aider"
 case deepseek = "deepseek"
 case gemini = "gemini"
 case grok = "grok"
 case opencode = "opencode"
 case antigravity = "antigravity"
 case droid = "droid"
}

public enum OrbState: String, CaseIterable {
 case idle
 case listening
 case thinking
 case speaking
 case error
 case disconnected
}
