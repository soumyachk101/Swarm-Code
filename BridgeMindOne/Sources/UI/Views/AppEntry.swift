//
// AppEntry.swift
// BridgeMind One — Main Application Entry
//

import SwiftUI
import Core

@main
public struct BridgeMindOneApp: App {
 @StateObject private var appState = AppState.shared
 @StateObject private var analytics = AnalyticsEngine.shared

 public init() {
 // Configure database
 DatabaseManager.shared.configure()

 // Load built-in skills
 Task {
 await SkillEngine.shared.loadBuiltInSkills()
 }

 // Initialize analytics
 AnalyticsEngine.shared.initialize()
 }

 public var body: some Scene {
 WindowGroup {
 ContentView()
 .environmentObject(appState)
 .environmentObject(analytics)
 .onAppear {
 analytics.trackAppLaunch()
 }
 }
 .windowResizability(.contentSize)
 .windowStyle(.titleBar)
 .commands {
 CommandGroup(replacing: .appInfo) {
 Button("About BridgeMind One") {
 appState.showAboutSheet = true
 }
 Divider()
 }
 CommandGroup(replacing: .newItem) {
 Button("New Chat") {
 appState.createNewChat()
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
 }

 // Settings window
 Settings {
 SettingsView()
 .environmentObject(appState)
 .environmentObject(analytics)
 }

 // Plugin panel
 Window("Plugins", id: "plugins") {
 PluginsPanelView()
 .environmentObject(appState)
 .environmentObject(analytics)
 }
 .windowResizability(.contentSize)
 .defaultPosition(.trailing)
 .keyboardShortcut(",", modifiers: .command)
}