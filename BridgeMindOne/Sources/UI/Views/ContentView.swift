//
// ContentView.swift
// Main content view with multi-pane layout
//

import SwiftUI
import Core

public struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var showSidebar: Bool = true

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: .constant(.all)) {
            threadSidebar
        } detail: {
            chatDetail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $state.isAboutSheetPresented) {
            AboutSheetView()
        }
        .sheet(isPresented: $state.isAgentSwitcherPresented) {
            AgentSwitcherView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.isPluginsPanelPresented.toggle()
                } label: {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                }
                .keyboardShortcut(",", modifiers: .command)

                Button {
                    appState.toggleAutoPilot()
                } label: {
                    Label(
                        appState.isAutoPilotEnabled ? "Auto-Pilot: ON" : "Auto-Pilot: OFF",
                        systemImage: "wand.and.stars"
                    )
                }
                .tint(appState.isAutoPilotEnabled ? .green : .secondary)

                Button {
                    appState.isAgentSwitcherPresented = true
                } label: {
                    Label("Switch Agent", systemImage: "person.2.fill")
                }
            }
        }
    }
}

// MARK: - Thread Sidebar

private extension ContentView {
    var threadSidebar: some View {
        ThreadSidebarView()
    }
}

// MARK: - Chat Detail

private extension ContentView {
    var chatDetail: some View {
        ZStack {
            switch appState.sidebarSelection {
            case .chat:
                ChatView()
            case .plugins:
                PluginsPanelView()
            case .autoPilot:
                AgentsView()
            case .settings:
                SettingsView()
            case .skills:
                Text("Skills")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
