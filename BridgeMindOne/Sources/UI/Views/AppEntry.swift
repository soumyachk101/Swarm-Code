//
// AppEntry.swift
// BridgeMind One — Application Scene definition
//
// Defines the primary window structure, scene phases, commands,
// and multi-window support. The actual @main entry point lives
// in the App target (BridgeMindOneApp.swift).
//
// Uses NavigationSplitView via MainSplitView for the primary layout.
//

import SwiftUI
import Core
import UI

public struct BridgeMindOneAppEntry: App {

 // MARK: - App lifecycle

 @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

 // MARK: - State

 @State private var appState: AppState

 // MARK: - Init

 public init() {
 let coreState = Core.AppState.shared
 _appState = State(initialValue: AppState(core: coreState))
 }

 // MARK: - Body

 public var body: some Scene {
 WindowGroup {
 MainSplitView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
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
 Task {
 await appState.createNewChat()
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

 SidebarCommands()

 CommandMenu("Agent") {
 Button("Switch Agent...") {
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

 // Settings panel
 Settings {
 SettingsView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)

 // Plugins standalone window
 Window("Plugins", id: "plugins-panel") {
 PluginsPanelView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .defaultPosition(.trailing)
 }
}
