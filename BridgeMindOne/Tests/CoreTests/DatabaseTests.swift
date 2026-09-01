//
// DatabaseTests.swift
// Unit tests for SQLite database persistence
//

import Testing
@testable import Core

@Suite("Database Manager Tests")
struct DatabaseTests {

    @Test("Create and retrieve chat session")
    func testCreateAndRetrieveSession() async throws {
        let db = try DatabaseManager(configuration: .inMemory)
        let session = ChatSessionRecord(
            id: "test-session-1",
            title: "Test Chat",
            agentId: "claude"
        )
        try await db.saveSession(session)

        let retrieved = try await db.getSession(id: "test-session-1")
        #expect(retrieved != nil)
        #expect(retrieved?.id == "test-session-1")
        #expect(retrieved?.title == "Test Chat")
        #expect(retrieved?.agentId == "claude")
    }

    @Test("Save and retrieve chat messages")
    func testSaveAndRetrieveMessages() async throws {
        let db = try DatabaseManager(configuration: .inMemory)
        let session = ChatSessionRecord(id: "test-session-2", title: "Message Test", agentId: "codex")
        try await db.saveSession(session)

        let msg1 = ChatMessageRecord(id: "m1", sessionId: "test-session-2", role: "user", content: "Hello world")
        let msg2 = ChatMessageRecord(id: "m2", sessionId: "test-session-2", role: "assistant", content: "Hi there!")
        try await db.saveMessage(msg1)
        try await db.saveMessage(msg2)

        let messages = try await db.getMessages(forSession: "test-session-2")
        #expect(messages.count == 2)
        #expect(messages[0].content == "Hello world")
        #expect(messages[1].content == "Hi there!")
    }

    @Test("OAuth token storage and deletion")
    func testOAuthTokenStorage() async throws {
        let db = try DatabaseManager(configuration: .inMemory)
        try await db.saveOAuthToken(pluginId: "linear", tokenData: "{\"token\": \"lin_123\"}")
        let token = try await db.getOAuthToken(pluginId: "linear")
        #expect(token == "{\"token\": \"lin_123\"}")

        try await db.deleteOAuthToken(pluginId: "linear")
        let deleted = try await db.getOAuthToken(pluginId: "linear")
        #expect(deleted == nil)
    }

    @Test("Plugin state persistence")
    func testPluginStatePersistence() async throws {
        let db = try DatabaseManager(configuration: .inMemory)
        try await db.savePluginState(pluginId: "github", enabled: true, connected: true, lastError: nil)
        let state = try await db.getPluginState(pluginId: "github")
        #expect(state != nil)
        #expect(state?.enabled == true)
        #expect(state?.connected == true)

        let allStates = try await db.getAllPluginStates()
        #expect(allStates.count == 1)
    }

    @Test("App settings key-value storage")
    func testAppSettingsStorage() async throws {
        let db = try DatabaseManager(configuration: .inMemory)
        try await db.setSetting(key: "theme", value: "dark")
        let theme = try await db.getSetting(key: "theme")
        #expect(theme == "dark")
    }
}
