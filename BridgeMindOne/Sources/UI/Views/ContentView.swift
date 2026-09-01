//
// ContentView.swift
// BridgeMind One — Complete 3-Column macOS Window Layout matching Screenshot
//

import SwiftUI
import Core

public struct ContentView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Top Navigation Header with [ Agent | Code | Chat ] and Bell
            TopNavHeaderView()

            // 3-Pane Main Body
            HStack(spacing: 0) {
                // Left Sidebar (Dashboard, Routines, Plugins, Skills, Agents, Notch, Credits, Profile)
                LeftSidebarView()

                Divider()
                    .background(BMColors.borderSubtle)

                // Middle Pane (Chats list / Plugins / Skills switch)
                if appState.selectedLeftSection == .plugins {
                    PluginsPanelView()
                } else if appState.selectedLeftSection == .skills {
                    SkillsView()
                } else {
                    MiddlePaneView()

                    // Right Main Timeline Pane
                    ExactChatView()
                }
            }
        }
        .background(BMColors.background)
        .sheet(isPresented: $state.isAboutSheetPresented) {
            AboutSheetView()
        }
        .sheet(isPresented: $state.isAgentSwitcherPresented) {
            AgentSwitcherView()
        }
    }
}
