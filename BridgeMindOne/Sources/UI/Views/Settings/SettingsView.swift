//
// SettingsView.swift
// Application settings with tabbed interface
//

import SwiftUI

public struct SettingsView: View {
 @EnvironmentObject private var appState: AppState
 @State private var selectedTab = 0

 public init() {}

 public var body: some View {
 TabView(selection: $selectedTab) {
 GeneralSettings()
 .tabItem { Label("General", systemImage: "gear") }
 .tag(0)

 EnginesSettings()
 .tabItem { Label("Engines", systemImage: "cpu") }
 .tag(1)

 PrivacySettings()
 .tabItem { Label("Privacy", systemImage: "lock.shield") }
 .tag(2)

 AppearanceSettings()
 .tabItem { Label("Appearance", systemImage: "paintbrush") }
 .tag(3)
 }
 .frame(width: 500, height: 400)
 }
}

// MARK: - General

private struct GeneralSettings: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("Behavior") {
 Toggle("Auto-save chats", isOn: $appState.settings.autoSaveEnabled)
 Toggle("Notifications", isOn: $appState.settings.notificationsEnabled)
 Toggle("Voice dictation (fn key)", isOn: $appState.settings.voiceDictationEnabled)
 }

 Section("Startup") {
 Picker("On launch:", selection: $appState.settings.startupBehavior) {
 ForEach(StartupBehavior.allCases, id: \.self) { behavior in
 Text(behavior.displayName).tag(behavior)
 }
 }
 }

 Section("Font Size") {
 Slider(value: $appState.settings.fontSize, in: 11...20, step: 1)
 HStack {
 Text("Small")
 Spacer()
 Text("\(Int(appState.settings.fontSize))pt")
 Spacer()
 Text("Large")
 }
 }
 }
 }
}

// MARK: - Engines

private struct EnginesSettings: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("Engine Paths") {
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
 }
 }
 }
 }
}

// MARK: - Privacy

private struct PrivacySettings: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 Form {
 Section("Analytics") {
 Toggle("Usage analytics", isOn: $appState.settings.telemetryEnabled)
 Text("Anonymous usage data helps improve BridgeMind One. No prompts or messages are sent.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }

 Section("Security") {
 Text("Credentials stored in macOS Keychain with CryptoKit encryption.")
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

// MARK: - Appearance

private struct AppearanceSettings: View {
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

private extension StartupBehavior {
 var displayName: String {
 switch self {
 case .restoreLastSession: return "Restore last session"
 case .showWelcome: return "Show welcome screen"
 case .createNewChat: return "Create new chat"
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
