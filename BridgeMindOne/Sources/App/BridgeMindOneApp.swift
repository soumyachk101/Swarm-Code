//
// BridgeMindOneApp.swift
// BridgeMind One — Application Entry Point
//
// @main entry point with window management, scene phase handling,
// and global environment setup.
//
// Wires the UI layer AppState, Core AppState, and all scenes together.
//

import SwiftUI
import Core
import UI

// MARK: - BridgeMindOneApp

@main
public struct BridgeMindOneApp: App {

 // MARK: - App lifecycle

 @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

 // MARK: - State

 @State private var appState: AppState
 @State private var scenePhase: ScenePhase = .active
 @State private var analyticsInitialized: Bool = false

 // MARK: - Init

 public init() {
 // Bridge core state to UI layer before body runs
 let core = Core.AppState.shared
 _appState = State(initialValue: AppState(core: core))

 // Configure application-wide settings
 NSApp.setActivationPolicy(.regular)

 // Register for notification center observers
 NotificationCenter.default.addObserver(
 forName: NSApplication.didBecomeActiveNotification,
 object: nil,
 queue: .main
 ) { _ in
 // Refresh state when app becomes active
 Task { @MainActor in
 core.loadSessions()
 }
 }
 }

 // MARK: - Body

 public var body: some Scene {

 // MARK: - Main Window Group

 WindowGroup {
 MainContentView()
 .environment(appState)
 .onAppear {
 if !analyticsInitialized {
 // AnalyticsEngine.shared.initialize()
 analyticsInitialized = true
 }
 }
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .windowToolbarStyle(.unified)
 .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
 Button("Switch Agent…") {
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

 // MARK: - Settings Window

 Settings {
 SettingsView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)

 // MARK: - Plugins Panel

 Window("Plugins", id: "plugins-panel") {
 PluginsPanelView()
 .environment(appState)
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .defaultPosition(.trailing)
 .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
 }
}
