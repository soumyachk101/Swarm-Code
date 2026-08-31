//
// SettingsView.swift
// Application settings
//

import SwiftUI

public struct SettingsView: View {
 @EnvironmentObject private var appState: AppState
 @EnvironmentObject private var analytics: AnalyticsEngine
 @State private var selectedTab: SettingsTab = .general

 public var body: some View {
 TabView(selection: $selectedTab) {
 GeneralSettingsView()
 .tabItem { Label("General", systemImage: "gear") }
 .tag(SettingsTab.general)

 EnginesSettingsView()
 .tabItem { Label("Engines", systemImage: "cpu") }
 .tag(SettingsTab.engines)

 PrivacySettingsView()
 .tabItem { Label("Privacy", systemImage: "lock.shield") }
 .tag(SettingsTab.privacy)

 AppearanceSettingsView()
 .tabItem { Label("Appearance", systemImage: "paintbrush") }
 .tag(SettingsTab.appearance)
 }
 .padding(20)
 .frame(width: 500, height: 400)
 }

 private enum SettingsTab: String, CaseIterable {
 case general
 case engines
 case privacy
 case appearance
 }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("General") {
 Toggle("Auto-save chats", isOn: $appState.settings.autoSaveEnabled)
 Toggle("Enable notifications", isOn: $appState.settings.notificationsEnabled)
 Toggle("Voice dictation (fn key)", isOn: $appState.settings.voiceDictationEnabled)
 }

 Section("Behavior") {
 Picker("Startup", selection: $appState.settings.startupBehavior) {
 ForEach(StartupBehavior.allCases, id: \.self) { behavior in
 Text(behavior.displayName).tag(behavior)
 }
 }
 }

 Section("Font Size") {
 Slider(value: $appState.settings.fontSize, in: 11...20, step: 1)
 Text("\(Int(appState.settings.fontSize))pt")
 .foregroundStyle(.secondary)
 }
 }
 }
}

private extension StartupBehavior {
 var displayName: String {
 switch self {
 case .restoreLastSession: return "Restore last session"
 case .showWelcome: return "Show welcome screen"
 case .createNewChat: return "Create new chat"
 }
 }
}

// MARK: - Engines Settings

private struct EnginesSettingsView: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("Agent Engine Paths") {
 HStack {
 Text("Claude Code")
 TextField("Path", text: $appState.settings.claudeCodePath)
 }
 HStack {
 Text("Codex")
 TextField("Path", text: $appState.settings.codexPath)
 }
 HStack {
 Text("Cursor")
 TextField("Path", text: $appState.settings.cursorPath)
 }
 }

 Section("Default Provider") {
 Picker("LLM Provider", selection: $appState.settings.llmProvider) {
 Text("Anthropic").tag("anthropic")
 Text("OpenAI").tag("openai")
 Text("Google").tag("google")
 Text("Custom").tag("custom")
 }
 }
 }
 }
}

// MARK: - Privacy Settings

private struct PrivacySettingsView: View {
 @EnvironmentObject private var appState: AppState
 @EnvironmentObject private var analytics: AnalyticsEngine

 public var body: some View {
 Form {
 Section("Analytics") {
 Toggle("Usage analytics", isOn: Binding(
 get: { appState.settings.telemetryEnabled },
 set: { enabled in
 appState.settings.telemetryEnabled = enabled
 if !enabled { analytics.reset() }
 }
 ))
 Text("Anonymous usage data helps improve BridgeMind One. No prompts or messages are sent.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 Section("Security") {
 Text("Credentials are stored securely in the macOS Keychain using CryptoKit encryption.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 Section("Data") {
 Button("Clear all chat history") {
 appState.sessions.removeAll()
 appState.currentSession = nil
 }
 .foregroundStyle(.red)
 }
 }
 }
}

// MARK: - Appearance Settings

private struct AppearanceSettingsView: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("Theme") {
 Picker("Appearance", selection: $appState.settings.theme) {
 ForEach(AppTheme.allCases, id: \.self) { theme in
 Text(theme.displayName).tag(theme)
 }
 }
 }
 }
 }
}

private extension AppTheme {
 var displayName: String {
 switch self {
 case .system: return "System"
 case .light: return "Light"
 case .dark: return "Dark"
 }
 }
}
