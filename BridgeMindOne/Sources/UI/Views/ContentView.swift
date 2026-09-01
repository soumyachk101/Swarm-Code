//
// ContentView.swift
// Main content view with multi-pane layout
//

import SwiftUI
import Core

public struct ContentView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: .constant(.all)) {
            ThreadSidebarView()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
        } detail: {
            detailPane
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

    @ViewBuilder
    private var detailPane: some View {
        switch appState.sidebarSelection {
        case .chat:
            ChatView()
        case .plugins:
            PluginsPanelView()
        case .autoPilot:
            AgentsView()
        case .skills:
            SkillsView()
        case .settings:
            SettingsView()
        }
    }
}
