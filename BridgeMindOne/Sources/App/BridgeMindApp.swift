//
// BridgeMindApp.swift
// Main entry point for BridgeMind One macOS Application
//

import SwiftUI
import Core
import UI

@main
public struct BridgeMindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    public init() {}

    public var body: some Scene {
        WindowGroup {
            MainSplitView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Chat Session") {
                    Task {
                        await appState.createNewSession()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            VStack {
                Text("Settings")
                    .font(.title2)
            }
            .padding()
            .frame(width: 400, height: 300)
        }
    }
}
