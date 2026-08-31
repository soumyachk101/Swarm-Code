//
// AppConfig.swift
// Application configuration and constants
//

import Foundation

public struct AppConfig {
 // MARK: - App Identity
 public static let bundleIdentifier = "ai.bridgemind.one"
 public static let appName = "BridgeMind"
 public static let displayName = "BridgeMind One"

 // MARK: - Versions
 public static let version = "0.1.12"
 public static let build = "88ada94"
 public static let gitSHA = "88ada94ca0646bf9affd2c0dd192736b92dcc4a9"
 public static let buildConfig = "release"
 public static let flavor = "standard"

 // MARK: - URLs
 public static let websiteURL = URL(string: "https://www.bridgemind.ai")!
 public static let apiURL = URL(string: "https://api.bridgemind.ai")!
 public static let docsURL = URL(string: "https://docs.bridgemind.ai")!
 public static let updateFeedURL = URL(string: "https://downloads.bridgemind.ai/bridgemind-one/latest/appcast.xml")!

 // MARK: - MCP Protocol
 public static let mcpProtocolVersion = "2025-03-26"
 public static let mcpLocalPort = 8000
 public static let mcpSessionTokenEnv = "BRIDGEMIND_MCP_SESSION_TOKEN"

 // MARK: - Sparkle
 public static let sparklePublicKey = "qDys+F+w3LbYwVY20c0PCDFloXwhuuKQmCyZfbtYTKY="
 public static let sparkleFeedURL = "https://downloads.bridgemind.ai/bridgemind-one/latest/appcast.xml"

 // MARK: - Analytics
 public static let postHogAPIKey = "phc_xwHPCc9bhzdrsFSKZRvdZf2estjpbvTTghvDqzKKSPmS"
 public static let postHogHost = "https://us.i.posthog.com"

 // MARK: - Paths
 public static func applicationSupportURL() -> URL {
 FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
 .appendingPathComponent("BridgeMind", isDirectory: true)
 }

 public static func databaseURL() -> URL {
 applicationSupportURL().appendingPathComponent("bridgemind.db")
 }

 public static func skillsDirectoryURL() -> URL {
 applicationSupportURL().appendingPathComponent("skills", isDirectory: true)
 }

 public static func sessionsDirectoryURL() -> URL {
 applicationSupportURL().appendingPathComponent("sessions", isDirectory: true)
 }

 public static func logsDirectoryURL() -> URL {
 let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
 .appendingPathComponent("Logs/BridgeMind", isDirectory: true)

 try? FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
 return logsURL
 }
}
