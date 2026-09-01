//
// ContentView.swift
// BridgeMind One — Master 3-Mode Functional Router
//
// Routes seamlessly between:
// 1. Agent Mode: Multi-agent orchestration with MCP tools & subagents
// 2. Code Mode: Single-agent coding workspace with editor & terminal
// 3. Chat Mode: Direct conversational AI with multi-model switcher
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

            // 3-Pane Body depending on top mode
            HStack(spacing: 0) {
                // Left Sidebar (Always accessible)
                LeftSidebarView()

                Divider()
                    .background(BMColors.borderSubtle)

                // Main Content Switching
                if appState.selectedLeftSection == .plugins {
                    PluginsPanelView()
                } else if appState.selectedLeftSection == .skills {
                    SkillsView()
                } else {
                    switch appState.topMode {
                    case .agent:
                        // Multi-Agent Orchestration Mode
                        MiddlePaneView()
                        ExactChatView()

                    case .code:
                        // Single-Agent Code Mode
                        CodeModeView()

                    case .chat:
                        // Direct AI Chat Mode
                        DirectChatModeView()
                    }
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
