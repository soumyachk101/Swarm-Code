//
// DatabaseManager.swift
// Shared database manager instance
//

import Foundation
import Core

public enum DatabaseManager {
 public static let shared = DatabaseManager()

 private var configuration: DatabaseConfiguration?

 public mutating func configure() {
 // Default database path in Application Support
 let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
 let dbURL = appSupport.appendingPathComponent("BridgeMind/bridgemind.db", isDirectory: false)

 // Ensure directory exists
 try? FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)

 configuration = DatabaseConfiguration(path: dbURL)

 // Initialize on background
 Task {
 try? DatabaseManager.configure(config: configuration!)
 }
 }

 public static func configure(config: DatabaseConfiguration) throws {
 // Will be used by the actor instance
 }

 public func saveSession(_ session: ChatSession?) async throws {
 guard let session else { return }

 // Implementation will use GRDB
 }

 public func loadSessions() async throws -> [ChatSession] {
 []
 }

 public func saveMessage(_ message: ChatMessage, to sessionId: String) async throws {
 // Implementation
 }

 public func loadMessages(for sessionId: String) async throws -> [ChatMessage] {
 []
 }
}
