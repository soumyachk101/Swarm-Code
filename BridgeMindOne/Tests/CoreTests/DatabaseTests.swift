//
// DatabaseTests.swift
// Unit tests for SQLite database persistence
//

import XCTest
@testable import Core

final class DatabaseTests: XCTestCase {
    var db: DatabaseManager!

    override func setUp() async throws {
        db = try DatabaseManager(configuration: .inMemory)
    }

    override func tearDown() async throws {
        await db.close()
        db = nil
    }

    func testCreateAndRetrieveSession() async throws {
        let session = ChatSessionRecord(
            id: "test-session-1",
            title: "Test Chat",
            agentId: "claude"
        )
        try await db.saveSession(session)

        let retrieved = try await db.getSession(id: "test-session-1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "test-session-1")
        XCTAssertEqual(retrieved?.title, "Test Chat")
        XCTAssertEqual(retrieved?.agentId, "claude")
    }

    func testSaveAndRetrieveMessages() async throws {
        let session = ChatSessionRecord(id: "test-session-2", title: "Message Test", agentId: "codex")
        try await db.saveSession(session)

        let msg1 = ChatMessageRecord(id: "m1", sessionId: "test-session-2", role: "user", content: "Hello world")
        let msg2 = ChatMessageRecord(id: "m2", sessionId: "test-session-2", role: "assistant", content: "Hi there!")
        try await db.saveMessage(msg1)
        try await db.saveMessage(msg2)

        let messages = try await db.getMessages(forSession: "test-session-2")
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].content, "Hello world")
        XCTAssertEqual(messages[1].content, "Hi there!")
    }

    func testOAuthTokenStorage() async throws {
        try await db.saveOAuthToken(pluginId: "linear", tokenData: "{\"token\": \"lin_123\"}")
        let token = try await db.getOAuthToken(pluginId: "linear")
        XCTAssertEqual(token, "{\"token\": \"lin_123\"}")

        try await db.deleteOAuthToken(pluginId: "linear")
        let deleted = try await db.getOAuthToken(pluginId: "linear")
        XCTAssertNil(deleted)
    }

    func testPluginStatePersistence() async throws {
        try await db.savePluginState(pluginId: "github", enabled: true, connected: true, lastError: nil)
        let state = try await db.getPluginState(pluginId: "github")
        XCTAssertNotNil(state)
        XCTAssertTrue(state?.enabled ?? false)
        XCTAssertTrue(state?.connected ?? false)

        let allStates = try await db.getAllPluginStates()
        XCTAssertEqual(allStates.count, 1)
    }

    func testAppSettingsStorage() async throws {
        try await db.setSetting(key: "theme", value: "dark")
        let theme = try await db.getSetting(key: "theme")
        XCTAssertEqual(theme, "dark")
    }
}
