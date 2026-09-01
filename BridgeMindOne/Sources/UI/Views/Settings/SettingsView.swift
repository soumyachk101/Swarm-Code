//
// SettingsView.swift
// Application settings with tabbed interface
//

import SwiftUI
import Core

public struct SettingsView: View {
    @Environment(AppState.self) private var appState
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
        .frame(width: 520, height: 420)
        .padding()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Behavior") {
                Toggle("Auto-save chats", isOn: $state.settings.autoSaveEnabled)
                Toggle("Notifications", isOn: $state.settings.notificationsEnabled)
                Toggle("Voice dictation (fn key)", isOn: $state.settings.voiceDictationEnabled)
            }

            Section("Startup") {
                Picker("On launch:", selection: $state.settings.startupBehavior) {
                    ForEach(StartupBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
            }

            Section("Font Size") {
                Slider(value: $state.settings.fontSize, in: 11...20, step: 1)
                HStack {
                    Text("Small")
                    Spacer()
                    Text("\(Int(state.settings.fontSize))pt")
                    Spacer()
                    Text("Large")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Engines

private struct EnginesSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Engine Paths") {
                HStack {
                    Text("Claude Code")
                    TextField("Path", text: $state.settings.claudeCodePath)
                }
                HStack {
                    Text("Codex")
                    TextField("Path", text: $state.settings.codexPath)
                }
                HStack {
                    Text("Cursor")
                    TextField("Path", text: $state.settings.cursorPath)
                }
            }

            Section("Default Provider") {
                Picker("LLM Provider", selection: $state.settings.llmProvider) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI").tag("openai")
                    Text("Google").tag("google")
                }
            }
        }
        .padding()
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Analytics") {
                Toggle("Usage analytics", isOn: $state.settings.telemetryEnabled)
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
                    appState.currentSessionId = nil
                }
                .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        Form {
            Section("Theme") {
                Picker("Appearance", selection: $state.settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }
        .padding()
    }
}
