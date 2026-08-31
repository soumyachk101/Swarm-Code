//
// AppConfig.swift
// Application constants, metadata and global configuration
//

import Foundation

public struct AppConfig: Sendable {
    public static let appName = "BridgeMind One"
    public static let appIdentifier = "ai.bridgemind.one"
    public static let version = "0.1.12"
    public static let buildNumber = "1"
    public static let gitSHA = "88ada94ca0646bf9affd2c0dd192736b92dcc4a9"
    public static let updateFeedURL = URL(string: "https://downloads.bridgemind.ai/bridgemind-one/latest/appcast.xml")!
    public static let postHogApiKey = "phc_xwHPCc9bhzdrsFSKZRvdZf2estjpbvTTghvDqzKKSPmS"
    public static let postHogHost = "https://app.posthog.com"
    public static let sessionTokenEnvVar = "BRIDGEMIND_MCP_SESSION_TOKEN"

    public static var appSupportDirectory: URL {
        let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = path.appendingPathComponent(appIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }

    public static var skillsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("skills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var logsDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
