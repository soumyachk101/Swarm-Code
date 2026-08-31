//
// AppState.swift
// BridgeMind One — UI-layer global state
//
// Bridges Core.AppState for UI consumption. Uses @Observable for modern
// SwiftUI observation. All state mutations flow through Core.AppState.
//

import SwiftUI
import Core

@Observable
public final class AppState {

 // MARK: - Core bridge

 public let core: Core.AppState

 // MARK: - UI state

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

 // MARK: - Agent cache

 public var availableAgents: [PluginDescriptor] = []
 public var engineStatuses: [String: EngineHealth] = [:]

 // MARK: - Streaming

 public var streamingContent: String = ""
 public var isThinking: Bool = false

 // MARK: - Toast

 public var toastMessage: String?
 public var toastType: ToastType = .info

 public enum ToastType {
 case info, success, warning, error
 }

 // MARK: - Init

 public init(core: Core.AppState = .shared) {
 self.core = core
 self.availableAgents = PluginCollection.agents.map { $0.descriptor }

 Task { @MainActor in
 for await _ in core.$sessions {
 break
 }
 }
 }

 // MARK: - Computed

 public var currentSession: ChatSessionRecord? {
 core.sessions.first { $0.id == core.currentSessionId }
 }

 public var isStreaming: Bool {
 core.isStreaming
 }

 public var sessions: [ChatSessionRecord] {
 core.sessions
 }

 public var currentMessages: [ChatMessageRecord] {
 core.currentMessages
 }

 // MARK: - Actions

 public func createNewChat() {
 Task {
 await core.createNewSession(agentId: selectedAgentId)
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
 core.activeAgent = agentId
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
