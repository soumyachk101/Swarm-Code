//
// BridgeMindOneApp.swift
// BridgeMind One — Application Entry Point
//

import SwiftUI
import Core
import UI

@main
public struct BridgeMindOneApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BridgeMind One") {
                    appState.isAboutSheetPresented = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    appState.createNewChat()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Chat") {
                    appState.saveCurrentChat()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            SidebarCommands()

            CommandMenu("Agent") {
                Button("Switch Agent…") {
                    appState.isAgentSwitcherPresented = true
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Button("Toggle Auto-Pilot") {
                    appState.toggleAutoPilot()
                }
                .keyboardShortcut("p", modifiers: [.command, .control])
            }

            CommandMenu("Plugins") {
                Button("Show Plugins Panel") {
                    appState.isPluginsPanelPresented = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("BridgeMind Documentation") {
                    appState.openDocumentation()
                }
                Button("Report an Issue") {
                    appState.openIssueReporter()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }

        Window("Plugins", id: "plugins-panel") {
            PluginsPanelView()
                .environment(appState)
        }
        .defaultPosition(.trailing)
    }
}
