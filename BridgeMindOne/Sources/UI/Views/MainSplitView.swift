//
// MainSplitView.swift
// Root SwiftUI macOS multi-pane layout
//
// Routes between Chat, Auto-Pilot, Plugins, Skills, and Settings
// based on sidebar selection.
//

import SwiftUI
import Core

public struct MainSplitView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var selectedTab: AppState.SidebarItem = .chat

 // MARK: - Body

 public var body: some View {
 NavigationSplitView {
 sidebar
 } detail: {
 detailContent
 }
 .navigationSplitViewStyle(.balanced)
 }
}

// MARK: - Sidebar

private extension MainSplitView {
 var sidebar: some View {
 List(selection: $selectedTab) {
 Section("Workspace") {
 ForEach(AppState.SidebarItem.allCases) { item in
 Label(item.title, systemImage: item.iconName)
 .tag(item)
 .accessibilityLabel("\(item.title) sidebar item")
 }
 }
 }
 .navigationTitle("BridgeMind")
 .frame(minWidth: 200)
 .onChange(of: selectedTab) { _, newValue in
 appState.sidebarSelection = newValue
 }
 }
}

// MARK: - Detail Content

private extension MainSplitView {
 @ViewBuilder
 var detailContent: some View {
 switch appState.sidebarSelection {
 case .chat:
 ChatView()
 case .autoPilot:
 AgentsView()
 case .plugins:
 PluginsPanelView()
 case .skills:
 Text("Skills view")
 .foregroundStyle(.secondary)
 case .settings:
 SettingsView()
 }
 }
}
