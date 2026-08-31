//
// AppState.swift
// BridgeMind One — UI-layer global state
//
// Wraps Core.AppState for SwiftUI @Environment usage.
// Provides UI-specific state alongside the core model state.
//

import SwiftUI
import Core

@Observable
public final class AppState {

 // MARK: - Core state (mirrors Core.AppState for @Environment use)

 public var databaseManager: DatabaseManager?
 public var currentSessionId: String?
 public var sessions: [ChatSessionRecord] = []
 public var currentMessages: [ChatMessageRecord] = []
 public var isStreaming: Bool = false
 public var activeAgent: String = "claude"
 public var statusMessage: String = "Ready"
 public var sidebarSelection: SidebarItem = .chat

 public enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
 case chat = "Chat"
 case autoPilot = "Auto-Pilot"
 case plugins = "Plugins"
 case skills = "Skills"
 case settings = "Settings"

 public var id: String { rawValue }
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

 // MARK: - UI-specific state

 public var isAboutSheetPresented: Bool = false
 public var isPluginsPanelPresented: Bool = false
 public var isAgentSwitcherPresented: Bool = false
 public var isSettingsPresented: Bool = false
 public var isAutoPilotEnabled: Bool = false
 public var selectedPluginId: String?
 public var selectedAgentId: String = "claude"
 public var searchText: String = ""
 public var sidebarWidth: CGFloat = 240
 public var isDictating: Bool = false

 // MARK: - Agent info cache

 public var availableAgents: [PluginDescriptor] = []
 public var engineStatuses: [String: EngineHealth] = [:]

 // MARK: - Streaming state

 public var streamingContent: String = ""
 public var isThinking: Bool = false

 // MARK: - Toast / notifications

 public var toastMessage: String?
 public var toastType: ToastType = .info

 public enum ToastType {
 case info, success, warning, error
 }

 // MARK: - Init

 public init() {
 self.availableAgents = PluginCollection.all
 Task { @MainActor in
 await initializeDatabase()
 }
 }

 // MARK: - Database

 public func initializeDatabase() async {
 do {
 let config = DatabaseConfiguration(path: AppConfig.databaseURL())
 let manager = try DatabaseManager(configuration: config)
 self.databaseManager = manager
 await loadSessions()
 } catch {
 self.statusMessage = "Database error: \(error.localizedDescription)"
 }
 }

 public func loadSessions() async {
 guard let db = databaseManager else { return }
 do {
 let records = try db.getAllSessions()
 self.sessions = records
 if currentSessionId == nil, let first = records.first {
 await selectSession(id: first.id)
 }
 } catch {
 print("Failed to load sessions: \(error)")
 }
 }

 public func createNewSession(title: String = "New Session", agentId: String = "claude") async {
 guard let db = databaseManager else { return }
 let newSession = ChatSessionRecord(
 id: UUID().uuidString,
 title: title,
 agentId: agentId,
 createdAt: ISO8601DateFormatter().string(from: Date()),
 updatedAt: ISO8601DateFormatter().string(from: Date())
 )
 do {
 try db.saveSession(newSession)
 await loadSessions()
 await selectSession(id: newSession.id)
 } catch {
 print("Failed to create session: \(error)")
 }
 }

 public func selectSession(id: String) async {
 self.currentSessionId = id
 guard let db = databaseManager else { return }
 do {
 self.currentMessages = try db.getMessages(forSession: id)
 } catch {
 print("Failed to load messages: \(error)")
 }
 }

 public func appendMessage(role: String, content: String) async {
 guard let sessionId = currentSessionId, let db = databaseManager else { return }
 let msg = ChatMessageRecord(
 id: UUID().uuidString,
 sessionId: sessionId,
 role: role,
 content: content,
 createdAt: ISO8601DateFormatter().string(from: Date())
 )
 do {
 try db.saveMessage(msg)
 self.currentMessages.append(msg)
 } catch {
 print("Failed to save message: \(error)")
 }
 }

 public func deleteSession(_ session: ChatSessionRecord) {
 guard let db = databaseManager else { return }
 do {
 try db.deleteSession(id: session.id)
 if currentSessionId == session.id {
 currentSessionId = nil
 currentMessages = []
 }
 loadSessions()
 } catch {
 print("Failed to delete session: \(error)")
 }
 }

 // MARK: - Computed

 public var currentSession: ChatSessionRecord? {
 sessions.first { $0.id == currentSessionId }
 }

 // MARK: - Actions

 public func createNewChat() {
 Task {
 await createNewSession(agentId: selectedAgentId)
 }
 }

 public func saveCurrentChat() {
 toastMessage = "Chat saved"
 toastType = .success
 }

 public func toggleAutoPilot() {
 isAutoPilotEnabled.toggle()
 toastMessage = isAutoPilotEnabled ? "Auto-Pilot enabled" : "Auto-Pilot disabled"
 toastType = isAutoPilotEnabled ? .success : .info
 }

 public func switchAgent(to agentId: String) {
 selectedAgentId = agentId
 activeAgent = agentId
 isAgentSwitcherPresented = false
 toastMessage = "Switched to \(agentId)"
 toastType = .success
 }

 public func openDocumentation() {
 if let url = URL(string: AppConfig.docsURL.absoluteString) {
 NSWorkspace.shared.open(url)
 }
 }

 public func openIssueReporter() {
 if let url = URL(string: "\(AppConfig.websiteURL)/issues") {
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
