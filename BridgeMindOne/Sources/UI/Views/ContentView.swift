//
// ContentView.swift
// Main content view with multi-pane layout
//
// Integrates ThreadSidebarView with ChatView in a NavigationSplitView.
// Uses @Environment for the new AppState type.
//

import SwiftUI
import Core

public struct ContentView: View {

 // MARK: - Environment

 @Environment(AppState.self) private var appState

 // MARK: - State

 @State private var showSidebar: Bool = true

 // MARK: - Body

 public var body: some View {
 NavigationSplitView(columnVisibility: .constant(.all)) {
 threadSidebar
 } detail: {
 chatDetail
 }
 .navigationSplitViewStyle(.balanced)
 .sheet(isPresented: $appState.isAboutSheetPresented) {
 AboutSheetView()
 }
 .sheet(isPresented: $appState.isAgentSwitcherPresented) {
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
 if appState.sidebarSelection == .chat {
 ChatView()
 } else if appState.sidebarSelection == .plugins {
 PluginsPanelView()
 } else if appState.sidebarSelection == .autoPilot {
 AgentsView()
 } else if appState.sidebarSelection == .settings {
 SettingsView()
 } else {
 // Skills view placeholder
 Text("Skills")
 .foregroundStyle(.secondary)
 }
 }
 }
}

// MARK: - Preview

#Preview {
 ContentView()
 .environment(AppState())
 .frame(width: 1000, height: 700)
}
