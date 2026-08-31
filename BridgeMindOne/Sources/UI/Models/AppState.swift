//
// AppState.swift
// BridgeMind One — UI-layer global state
//
// Wraps and extends the Core AppState for UI consumption.
// Uses @Observable (iOS 17+/macOS 14+ macro) for modern SwiftUI observation.
//

import SwiftUI
import Core
import Combine

@Observable
public final class AppState {
 // MARK: - Core state (bridged from Core.AppState)

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

 // MARK: - Agent info cache

 public var availableAgents: [PluginDescriptor] = []
 public var engineStatuses: [String: Bool] = [:]

 // MARK: - Streaming state

 public var streamingContent: String = ""
 public var streamingToolCall: ToolCall?
 public var isThinking: Bool = false

 // MARK: - Toast / notifications

 public var toastMessage: String?
 public var toastType: ToastType = .info

 public enum ToastType {
 case info, success, warning, error
 }

 // MARK: - Init

 public init(core: Core.AppState = .shared) {
 self.core = core
 self.availableAgents = PluginCollection.agents

 Task { @MainActor in
 for await _ in core.$currentMessages {
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
 await core.createNewSession()
 }
 }

 public func saveCurrentChat() {
 // Persist current chat context — handled by DatabaseManager on every append
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
 if let url = URL(string: "https://docs.bridgemind.ai") {
 NSWorkspace.shared.open(url)
 }
 }

 public func openIssueReporter() {
 if let url = URL(string: "https://github.com/bridgemind/bridgemind-one/issues") {
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
