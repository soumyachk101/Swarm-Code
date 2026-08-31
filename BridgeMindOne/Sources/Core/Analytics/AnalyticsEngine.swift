//
// AnalyticsEngine.swift
// PostHog analytics integration
//

import Foundation
import Combine

public protocol AnalyticsBackend: Sendable {
 func initialize()
 func track(event: String, properties: [String: Any]?)
 func identify(userId: String?, properties: [String: Any]?)
 func reset()
 func flush()
}

public actor AnalyticsEngine: AnalyticsBackend {
 public static let shared = AnalyticsEngine()
 public static let apiKey = "phc_xwHPCc9bhzdrsFSKZRvdZf2estjpbvTTghvDqzKKSPmS"

 private var client: Any?
 private var isInitialized = false
 private var isEnabled: Bool {
 UserDefaults.standard.object(forKey: "analytics_enabled") as? Bool ?? true
 }

 public func initialize() {
 guard isEnabled, !isInitialized else { return }

 // PostHog SDK initialization
 // In production: PostHogSDK.shared.setup(apiKey: Self.apiKey)
 isInitialized = true
 }

 public func track(event: String, properties: [String: Any]? = nil) {
 guard isEnabled else { return }

 // Delegate to PostHog SDK
 Task.detached(priority: .background) {
 // PostHogSDK.shared.capture(event, properties: properties)
 }
 }

 public func identify(userId: String?, properties: [String: Any]? = nil) {
 guard isEnabled else { return }

 Task.detached(priority: .background) {
 // if let userId {
 // PostHogSDK.shared.identify(userId, userProperties: properties)
 // }
 }
 }

 public func reset() {
 Task.detached(priority: .background) {
 // PostHogSDK.shared.reset()
 }
 }

 public func flush() {
 Task.detached(priority: .background) {
 // PostHogSDK.shared.flush()
 }
 }

 // MARK: - Convenience Methods

 public func trackAppLaunch() {
 track(event: "app_launched", properties: [
 "version": Bundle.main.version ?? "unknown",
 "build": Bundle.main.build ?? "unknown",
 "platform": "macos",
 "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
 ])
 }

 public func trackPluginConnected(pluginId: String) {
 track(event: "plugin_connected", properties: ["plugin_id": pluginId])
 }

 public func trackPluginDisconnected(pluginId: String) {
 track(event: "plugin_disconnected", properties: ["plugin_id": pluginId])
 }

 public func trackToolCalled(pluginId: String, toolName: String) {
 track(event: "tool_called", properties: [
 "plugin_id": pluginId,
 "tool_name": toolName,
 ])
 }

 public func trackAgentSwitched(engine: String) {
 track(event: "agent_switched", properties: ["engine": engine])
 }

 public func trackChatCreated(sessionId: String) {
 track(event: "chat_created", properties: ["session_id": sessionId])
 }

 public func trackMessageSent(sessionId: String, role: String, hasTools: Bool) {
 track(event: "message_sent", properties: [
 "session_id": sessionId,
 "role": role,
 "has_tools": hasTools,
 ])
 }
}

// MARK: - Bundle Extensions

private extension Bundle {
 var version: String? {
 infoDictionary?["CFBundleShortVersionString"] as? String
 }

 var build: String? {
 infoDictionary?["CFBundleVersion"] as? String
 }
}
