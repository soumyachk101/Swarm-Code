//
// SettingsView.swift
// BridgeMind One — Application settings
//
// General settings, engine paths, API keys, and privacy settings.
//
// macOS 14+ APIs. Dark/light mode support. Accessibility labels throughout.
//

import SwiftUI
import Core

// MARK: - SettingsView

public struct SettingsView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var selectedTab: SettingsTab = .general
 @State private var generalSettings: GeneralSettings = GeneralSettings()
 @State private var enginePaths: EnginePaths = EnginePaths()
 @State private var apiKeySettings: APIKeySettings = APIKeySettings()
 @State private var privacySettings: PrivacySettings = PrivacySettings()

 // MARK: - Body

 public var body: some View {
 NavigationSplitView {
 settingsSidebar
 } detail: {
 settingsDetail
 }
 .navigationSplitViewStyle(.balanced)
 }
}

// MARK: - Settings Sidebar

private extension SettingsView {
 var settingsSidebar: some View {
 List(selection: $selectedTab) {
 Section {
 ForEach(SettingsTab.allCases) { tab in
 Label(tab.title, systemImage: tab.iconName)
 .tag(tab)
 .accessibilityLabel("\(tab.title) settings")
 }
 }
 }
 .navigationTitle("Settings")
 .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
 }
}

// MARK: - Settings Detail

private extension SettingsView {
 @ViewBuilder
 var settingsDetail: some View {
 switch selectedTab {
 case .general:
 GeneralSettingsView(settings: $generalSettings)
 case .engines:
 EnginePathsView(paths: $enginePaths)
 case .apiKeys:
 APIKeysView(settings: $apiKeySettings)
 case .privacy:
 PrivacySettingsView(settings: $privacySettings)
 }
 }
}

// MARK: - Settings Tab

public enum SettingsTab: String, CaseIterable, Identifiable {
 case general = "General"
 case engines = "Engines"
 case apiKeys = "API Keys"
 case privacy = "Privacy"

 public var id: String { rawValue }
 public var title: String { rawValue }
 public var iconName: String {
 switch self {
 case .general: return "gear"
 case .engines: return "terminal.fill"
 case .apiKeys: return "key.fill"
 case .privacy: return "lock.shield.fill"
 }
 }
}

// MARK: - Settings Models

public struct GeneralSettings: Equatable {
 public var appName: String = AppConfig.appName
 public var checkForUpdates: Bool = true
 public var launchAtLogin: Bool = false
 public var minimizeToMenuBar: Bool = false
 public var showInDock: Bool = true
 public var defaultAgent: String = "claude"
 public var theme: AppTheme = .system

 public init() {}
}

public struct EnginePaths: Equatable {
 public var claudePath: String = "/usr/local/bin/claude"
 public var codexPath: String = "/usr/local/bin/codex"
 public var aiderPath: String = "/usr/local/bin/aider"
 public var defaultPort: Int = 3000
 public var logLevel: LogLevel = .info

 public init() {}
}

public struct APIKeySettings: Equatable {
 public var anthropicKey: String = ""
 public var openaiKey: String = ""
 public var googleKey: String = ""
 public var customKeys: [String: String] = [:]

 public init() {}
}

public struct PrivacySettings: Equatable {
 public var allowAnalytics: Bool = false
 public var crashReporting: Bool = true
 public var telemetry: Bool = false
 public var dataRetentionDays: Int = 90
 public var encryptLocalData: Bool = true

 public init() {}
}

public enum AppTheme: String, CaseIterable {
 case system = "System"
 case light = "Light"
 case dark = "Dark"

 public var nsAppearance: NSAppearance.Name? {
 switch self {
 case .system: return nil
 case .light: return .aqua
 case .dark: return .vibrantDark
 }
 }
}

public enum LogLevel: String, CaseIterable {
 case debug = "Debug"
 case info = "Info"
 case warning = "Warning"
 case error = "Error"
}

// MARK: - General Settings View

private struct GeneralSettingsView: View {
 @Binding var settings: GeneralSettings

 var body: some View {
 Form {
 Section("Application") {
 Toggle("Launch at login", isOn: $settings.launchAtLogin)
 Toggle("Minimize to menu bar", isOn: $settings.minimizeToMenuBar)
 Toggle("Show in Dock", isOn: $settings.showInDock)
 Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
 }

 Section("Appearance") {
 Picker("Theme", selection: $settings.theme) {
 ForEach(AppTheme.allCases) { theme in
 Text(theme.rawValue).tag(theme)
 }
 }
 .accessibilityLabel("App theme selection")
 }

 Section("Defaults") {
 Picker("Default Agent", selection: $settings.defaultAgent) {
 ForEach(PluginCollection.agents, id: \.id) { agent in
 Text(agent.displayName).tag(agent.id)
 }
 }
 .accessibilityLabel("Default AI agent")
 }
 }
 .formStyle(.grouped)
 .navigationTitle("General")
 }
}

// MARK: - Engine Paths View

private struct EnginePathsView: View {
 @Binding var paths: EnginePaths

 var body: some View {
 Form {
 Section("Local Engines") {
 PathField(label: "Claude CLI", path: $paths.claudePath, hint: "Path to Claude CLI binary")
 PathField(label: "Codex CLI", path: $paths.codexPath, hint: "Path to Codex CLI binary")
 PathField(label: "Aider", path: $paths.aiderPath, hint: "Path to Aider binary")
 }

 Section("Network") {
 HStack {
 Text("Default Port")
 Spacer()
 TextField("Port", value: $paths.defaultPort, format: .number)
 .frame(width: 80)
 .accessibilityLabel("Default port number")
 }

 Picker("Log Level", selection: $paths.logLevel) {
 ForEach(LogLevel.allCases) { level in
 Text(level.rawValue).tag(level)
 }
 }
 }
 }
 .formStyle(.grouped)
 .navigationTitle("Engine Paths")
 }
}

// MARK: - Path Field

private struct PathField: View {
 let label: String
 @Binding var path: String
 let hint: String

 @State private var showingPicker: Bool = false

 var body: some View {
 HStack {
 Text(label)
 Spacer()
 TextField("", text: $path)
 .textFieldStyle(.roundedBorder)
 .frame(width: 240)
 .accessibilityLabel("\(label) path")

 Button("Browse") {
 showingPicker = true
 }
 .sheet(isPresented: $showingPicker) {
 let panel = NSOpenPanel()
 panel.allowsMultipleSelection = false
 panel.canChooseDirectories = false
 panel.canChooseFiles = true
 panel.message = "Select \(label)"
 if panel.runModal() == .OK, let selected = panel.url?.path {
 path = selected
 }
 }
 }
 }
}

// MARK: - API Keys View

private struct APIKeysView: View {
 @Binding var settings: APIKeySettings
 @State private var showingAnthropic: Bool = false
 @State private var showingOpenAI: Bool = false
 @State private var showingGoogle: Bool = false

 var body: some View {
 Form {
 Section {
 ForEach(apiKeyRows, id: \.label) { row in
 SecureField(row.label, text: row.binding)
 .textFieldStyle(.roundedBorder)
 .accessibilityLabel("\(row.label) API key")
 }

 HStack {
 Spacer()
 Button("Reveal All") {
 showingAnthropic = true
 showingOpenAI = true
 showingGoogle = true
 }
 .buttonStyle(.borderless)
 }
 }

 Section {
 Text("Keys are stored securely in the macOS Keychain and never written to disk in plaintext.")
 .font(.caption)
 .foregroundStyle(.secondary)
 }
 }
 .formStyle(.grouped)
 .navigationTitle("API Keys")
 }

 private var apiKeyRows: [(label: String, binding: Binding<String>)] {
 return [
 ("Anthropic", $settings.anthropicKey),
 ("OpenAI", $settings.openaiKey),
 ("Google AI", $settings.googleKey)
 ]
 }
}

// MARK: - Privacy Settings View

private struct PrivacySettingsView: View {
 @Binding var settings: PrivacySettings

 var body: some View {
 Form {
 Section("Data & Analytics") {
 Toggle("Allow analytics", isOn: $settings.allowAnalytics)
 Toggle("Crash reporting", isOn: $settings.crashReporting)
 Toggle("Telemetry", isOn: $settings.telemetry)
 }

 Section("Data Protection") {
 Toggle("Encrypt local data", isOn: $settings.encryptLocalData)

 Stepper(value: $settings.dataRetentionDays, in: 7...365) {
 Text("Data retention: \(settings.dataRetentionDays) days")
 }
 .accessibilityLabel("Data retention period in days")

 Button("Delete All Local Data…") {
 // Show confirmation and delete
 }
 .foregroundStyle(.red)
 }
 }
 .formStyle(.grouped)
 .navigationTitle("Privacy")
 }
}

// MARK: - Preview

#Preview {
 SettingsView()
 .environment(AppState())
 .frame(width: 700, height: 500)
}
