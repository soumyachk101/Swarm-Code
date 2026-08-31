//
// AppState.swift
// Root application state management
//

import SwiftUI
import Combine
import Core

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var databaseManager: DatabaseManager?
    @Published public var currentSessionId: String?
    @Published public var sessions: [ChatSessionRecord] = []
    @Published public var currentMessages: [ChatMessageRecord] = []
    @Published public var isStreaming: Bool = false
    @Published public var activeAgent: String = "claude"
    @Published public var isDictating: Bool = false
    @Published public var statusMessage: String = "Ready"
    @Published public var sidebarSelection: SidebarItem = .chat

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

    public init() {
        Task {
            await initializeDatabase()
        }
    }

    public func initializeDatabase() async {
        do {
            let manager = try DatabaseManager()
            self.databaseManager = manager
            await loadSessions()
        } catch {
            self.statusMessage = "Database error: \(error.localizedDescription)"
        }
    }

    public func loadSessions() async {
        guard let db = databaseManager else { return }
        do {
            let records = try await db.getAllSessions()
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
            try await db.saveSession(newSession)
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
            self.currentMessages = try await db.getMessages(forSession: id)
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
            try await db.saveMessage(msg)
            self.currentMessages.append(msg)
        } catch {
            print("Failed to save message: \(error)")
        }
    }
}
