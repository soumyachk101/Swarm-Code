//
// ContentView.swift
// Main content view with multi-pane layout
//

import SwiftUI

public struct ContentView: View {
 @EnvironmentObject private var appState: AppState

 public var body: some View {
 NavigationSplitView {
 // Sidebar: Chat threads
 ThreadSidebarView()
 .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
 } detail: {
 // Main: Chat view
 ChatView()
 }
 .navigationSplitViewStyle(.balanced)
 .sheet(isPresented: $appState.showAboutSheet) {
 AboutSheetView()
 }
 .sheet(isPresented: $appState.showAgentSwitcher) {
 AgentSwitcherView()
 }
 .toolbar {
 ToolbarItemGroup(placement: .primaryAction) {
 Button(action: { appState.showPlugins.toggle() }) {
 Label("Plugins", systemImage: "puzzlepiece.extension")
 }
 .keyboardShortcut(",", modifiers: .command)

 Button(action: { appState.toggleAutoPilot() }) {
 Label(appState.isAutoPilotEnabled ? "Auto-Pilot: ON" : "Auto-Pilot: OFF",
 systemImage: appState.isAutoPilotEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
 }
 .tint(appState.isAutoPilotEnabled ? .green : .secondary)

 Button(action: { appState.showAgentSwitcher = true }) {
 Label("Switch Agent", systemImage: "person.2.fill")
 }
 }
 }
 }
}

#Preview {
 ContentView()
 .environmentObject(AppState.shared)
}
