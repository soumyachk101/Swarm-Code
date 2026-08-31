//
// AppEntry.swift
// BridgeMind One — Main App Scene
//
// @main entry point with window management, scene phase handling,
// multi-window support, and menu commands.
//
// Uses NavigationSplitView for the primary layout.
//

import SwiftUI
import Core
import UI

@main
public struct BridgeMindOneApp: App {

 // MARK: - App lifecycle

 @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
 @State private var scenePhase: ScenePhase = .active

 // MARK: - Environment state

 @State private var appState: AppState

 // MARK: - Init

 public init() {
 // Force-load Core.AppState early
 let coreState = Core.AppState.shared
 // Bridge to UI layer
 _appState = State(initialValue: AppState(core: coreState))
 }

 // MARK: - Body

 public var body: some Scene {
 WindowGroup {
 NavigationSplitView {
 SidebarView()
 } detail: {
 MainContentView()
 }
 .environment(appState)
 .onChange(of: scenePhase) { _, newPhase in
 handleScenePhase(newPhase)
 }
 .onAppear {
 appState.core.loadSessions()
 }
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .windowToolbarStyle(.unified)
 .commands {
 AppCommands(appState: appState)
 }
 .handlesExternalEvents(preferring: ["*"], allowing: ["*"])

 Settings {
 SettingsView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 }

 // Plugin panel — standalone window
 Window("Plugins", id: "plugins-panel") {
 PluginsPanelView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .defaultPosition(.trailing)
 .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
 }

 // MARK: - Scene phase

 private func handleScenePhase(_ phase: ScenePhase) {
 switch phase {
 case .active:
 if let db = appState.core.databaseManager {
 // Refresh state on activate
 Task {
 await appState.core.loadSessions()
 }
 }
 case .inactive:
 break
 case .background:
 break
 @unknown default:
 break
 }
 }
}

// MARK: - App Commands

private struct AppCommands: Commands {
 let appState: AppState

 var body: some Commands {
 CommandGroup(replacing: .appInfo) {
 Button("About BridgeMind One") {
 appState.isAboutSheetPresented = true
 }
 }

 CommandGroup(replacing: .newItem) {
 Button("New Chat") {
 Task {
 await appState.core.createNewSession()
 }
 }
 .keyboardShortcut("n", modifiers: .command)
 }

 CommandGroup(replacing: .saveItem) {
 Button("Save Chat") {
 appState.saveCurrentChat()
 }
 .keyboardShortcut("s", modifiers: [.command, .shift])
 }

 CommandGroup(replacing: .help) {
 Button("BridgeMind Documentation") {
 appState.openDocumentation()
 }
 Button("Report an Issue") {
 appState.openIssueReporter()
 }
 }

 SidebarCommands()

 CommandMenu("Plugins") {
 Button("Show Plugins Panel") {
 appState.isPluginsPanelPresented = true
 }
 .keyboardShortcut(",", modifiers: .command)
 }

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
 }
}
