//
// Database.swift
// Native SQLite3 persistence layer for BridgeMind One
//

import Foundation
import SQLite3

// MARK: - Database Configuration

public struct DatabaseConfiguration: Sendable {
    public let path: URL
    public let isInMemory: Bool

    public init(path: URL) {
        self.path = path
        self.isInMemory = false
    }

    public static var inMemory: DatabaseConfiguration {
        DatabaseConfiguration(inMemory: true)
    }

    private init(inMemory: Bool) {
        self.path = URL(fileURLWithPath: ":memory:")
        self.isInMemory = inMemory
    }

    public static func defaultPath() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ai.bridgemind.one", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bridgemind.sqlite")
    }
}

// MARK: - Database Errors

public enum DatabaseError: Error, Equatable, CustomStringConvertible {
    case notConfigured
    case connectionFailed(String)
    case queryFailed(String)
    case migrationFailed(String)
    case recordNotFound(String)
    case serializationError(String)

    public var description: String {
        switch self {
        case .notConfigured: return "Database not configured"
        case .connectionFailed(let msg): return "Database connection failed: \(msg)"
        case .queryFailed(let msg): return "Query execution failed: \(msg)"
        case .migrationFailed(let msg): return "Migration failed: \(msg)"
        case .recordNotFound(let id): return "Record not found: \(id)"
        case .serializationError(let msg): return "Serialization error: \(msg)"
        }
    }
}

// MARK: - Database Records

public struct ChatSessionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    public var agentId: String?
    public var createdAt: String
    public var updatedAt: String
    public var metadata: String?

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        agentId: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        metadata: String? = nil
    ) {
        self.id = id
        self.title = title
        self.agentId = agentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

public struct ChatMessageRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var sessionId: String
    public var role: String
    public var content: String
    public var toolCallId: String?
    public var createdAt: String
    public var metadata: String?

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        role: String,
        content: String,
        toolCallId: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        metadata: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.toolCallId = toolCallId
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

public struct OAuthTokenRecord: Codable, Equatable, Sendable {
    public var pluginId: String
    public var tokenData: String
    public var updatedAt: String

    public init(pluginId: String, tokenData: String, updatedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.pluginId = pluginId
        self.tokenData = tokenData
        self.updatedAt = updatedAt
    }
}

public struct PluginStateRecord: Codable, Equatable, Sendable {
    public var pluginId: String
    public var enabled: Bool
    public var connected: Bool
    public var lastError: String?
    public var updatedAt: String

    public init(pluginId: String, enabled: Bool, connected: Bool, lastError: String? = nil, updatedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.pluginId = pluginId
        self.enabled = enabled
        self.connected = connected
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

public struct SkillMetaRecord: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String?
    public var contentHash: String?
    public var installedAt: String

    public init(id: String, name: String, version: String? = nil, contentHash: String? = nil, installedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id
        self.name = name
        self.version = version
        self.contentHash = contentHash
        self.installedAt = installedAt
    }
}

public struct AppSettingRecord: Codable, Equatable, Sendable {
    public var key: String
    public var value: String
    public var updatedAt: String

    public init(key: String, value: String, updatedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

// MARK: - Database Manager

public actor DatabaseManager {
    private var db: OpaquePointer?
    public let configuration: DatabaseConfiguration

    public init(configuration: DatabaseConfiguration = DatabaseConfiguration(path: DatabaseConfiguration.defaultPath())) throws {
        self.configuration = configuration
        try self.openDatabase()
        try self.createTables()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func openDatabase() throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let pathString = configuration.isInMemory ? ":memory:" : configuration.path.path

        if sqlite3_open_v2(pathString, &db, flags, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.connectionFailed(errmsg)
        }

        // Enable WAL mode & foreign keys
        _ = execute(sql: "PRAGMA journal_mode = WAL;")
        _ = execute(sql: "PRAGMA foreign_keys = ON;")
    }

    private func execute(sql: String) -> Bool {
        guard let db = db else { return false }
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        if result != SQLITE_OK {
            if let errorMsg = errorMsg {
                sqlite3_free(errorMsg)
            }
            return false
        }
        return true
    }

    public func createTables() throws {
        guard let db = db else { throw DatabaseError.notConfigured }

        let schema = """
        CREATE TABLE IF NOT EXISTS chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT,
            agent_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            metadata TEXT
        );

        CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            tool_call_id TEXT,
            created_at TEXT NOT NULL,
            metadata TEXT,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS oauth_tokens (
            plugin_id TEXT PRIMARY KEY,
            token_data TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS plugin_state (
            plugin_id TEXT PRIMARY KEY,
            enabled INTEGER NOT NULL,
            connected INTEGER NOT NULL,
            last_error TEXT,
            updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS skills_meta (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            version TEXT,
            content_hash TEXT,
            installed_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS app_settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_messages_session ON chat_messages(session_id, created_at);
        CREATE INDEX IF NOT EXISTS idx_sessions_updated ON chat_sessions(updated_at);
        """

        var errorMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, schema, nil, nil, &errorMsg) != SQLITE_OK {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Unknown schema creation error"
            sqlite3_free(errorMsg)
            throw DatabaseError.migrationFailed(msg)
        }
    }

    // MARK: - Chat Session CRUD

    public func saveSession(_ session: ChatSessionRecord) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "INSERT OR REPLACE INTO chat_sessions (id, title, agent_id, created_at, updated_at, metadata) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (session.id as NSString).utf8String, -1, nil)
        if let title = session.title { sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 2) }
        if let agentId = session.agentId { sqlite3_bind_text(stmt, 3, (agentId as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, (session.createdAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (session.updatedAt as NSString).utf8String, -1, nil)
        if let meta = session.metadata { sqlite3_bind_text(stmt, 6, (meta as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 6) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getSession(id: String) throws -> ChatSessionRecord? {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT id, title, agent_id, created_at, updated_at, metadata FROM chat_sessions WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let sId = String(cString: sqlite3_column_text(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let agentId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let createdAt = String(cString: sqlite3_column_text(stmt, 3))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 4))
            let meta = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            return ChatSessionRecord(id: sId, title: title, agentId: agentId, createdAt: createdAt, updatedAt: updatedAt, metadata: meta)
        }
        return nil
    }

    public func getAllSessions() throws -> [ChatSessionRecord] {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT id, title, agent_id, created_at, updated_at, metadata FROM chat_sessions ORDER BY updated_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var sessions: [ChatSessionRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sId = String(cString: sqlite3_column_text(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let agentId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let createdAt = String(cString: sqlite3_column_text(stmt, 3))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 4))
            let meta = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
            sessions.append(ChatSessionRecord(id: sId, title: title, agentId: agentId, createdAt: createdAt, updatedAt: updatedAt, metadata: meta))
        }
        return sessions
    }

    public func deleteSession(id: String) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "DELETE FROM chat_sessions WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Message CRUD

    public func saveMessage(_ message: ChatMessageRecord) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "INSERT OR REPLACE INTO chat_messages (id, session_id, role, content, tool_call_id, created_at, metadata) VALUES (?, ?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (message.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (message.sessionId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (message.role as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (message.content as NSString).utf8String, -1, nil)
        if let toolCallId = message.toolCallId { sqlite3_bind_text(stmt, 5, (toolCallId as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_bind_text(stmt, 6, (message.createdAt as NSString).utf8String, -1, nil)
        if let meta = message.metadata { sqlite3_bind_text(stmt, 7, (meta as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 7) }

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getMessages(forSession sessionId: String) throws -> [ChatMessageRecord] {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT id, session_id, role, content, tool_call_id, created_at, metadata FROM chat_messages WHERE session_id = ? ORDER BY created_at ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        var messages: [ChatMessageRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mId = String(cString: sqlite3_column_text(stmt, 0))
            let sId = String(cString: sqlite3_column_text(stmt, 1))
            let role = String(cString: sqlite3_column_text(stmt, 2))
            let content = String(cString: sqlite3_column_text(stmt, 3))
            let toolCallId = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let createdAt = String(cString: sqlite3_column_text(stmt, 5))
            let meta = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            messages.append(ChatMessageRecord(id: mId, sessionId: sId, role: role, content: content, toolCallId: toolCallId, createdAt: createdAt, metadata: meta))
        }
        return messages
    }

    // MARK: - OAuth Token Storage

    public func saveOAuthToken(pluginId: String, tokenData: String) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "INSERT OR REPLACE INTO oauth_tokens (plugin_id, token_data, updated_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (pluginId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (tokenData as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getOAuthToken(pluginId: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT token_data FROM oauth_tokens WHERE plugin_id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (pluginId as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }

    public func deleteOAuthToken(pluginId: String) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "DELETE FROM oauth_tokens WHERE plugin_id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (pluginId as NSString).utf8String, -1, nil)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Plugin State

    public func savePluginState(pluginId: String, enabled: Bool, connected: Bool, lastError: String? = nil) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "INSERT OR REPLACE INTO plugin_state (plugin_id, enabled, connected, last_error, updated_at) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (pluginId as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, enabled ? 1 : 0)
        sqlite3_bind_int(stmt, 3, connected ? 1 : 0)
        if let err = lastError { sqlite3_bind_text(stmt, 4, (err as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_text(stmt, 5, (now as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getPluginState(pluginId: String) throws -> PluginStateRecord? {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT plugin_id, enabled, connected, last_error, updated_at FROM plugin_state WHERE plugin_id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (pluginId as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            let pid = String(cString: sqlite3_column_text(stmt, 0))
            let enabled = sqlite3_column_int(stmt, 1) != 0
            let conn = sqlite3_column_int(stmt, 2) != 0
            let lastErr = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let updated = String(cString: sqlite3_column_text(stmt, 4))
            return PluginStateRecord(pluginId: pid, enabled: enabled, connected: conn, lastError: lastErr, updatedAt: updated)
        }
        return nil
    }

    public func getAllPluginStates() throws -> [PluginStateRecord] {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT plugin_id, enabled, connected, last_error, updated_at FROM plugin_state;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var list: [PluginStateRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let pid = String(cString: sqlite3_column_text(stmt, 0))
            let enabled = sqlite3_column_int(stmt, 1) != 0
            let conn = sqlite3_column_int(stmt, 2) != 0
            let lastErr = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let updated = String(cString: sqlite3_column_text(stmt, 4))
            list.append(PluginStateRecord(pluginId: pid, enabled: enabled, connected: conn, lastError: lastErr, updatedAt: updated))
        }
        return list
    }

    // MARK: - App Settings

    public func setSetting(key: String, value: String) throws {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "INSERT OR REPLACE INTO app_settings (key, value, updated_at) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let now = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (now as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func getSetting(key: String) throws -> String? {
        guard let db = db else { throw DatabaseError.notConfigured }
        let sql = "SELECT value FROM app_settings WHERE key = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }

    public func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
}
