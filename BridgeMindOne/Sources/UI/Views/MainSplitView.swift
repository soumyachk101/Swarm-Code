//
// MainSplitView.swift
// Root SwiftUI macOS multi-pane layout
//

import SwiftUI
import Core

public struct MainSplitView: View {
    @State private var selectedTab: String = "Chat"

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Section("Navigation") {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .tag("Chat")
                    Label("Auto-Pilot", systemImage: "bolt.shield.fill")
                        .tag("Auto-Pilot")
                    Label("Plugins", systemImage: "puzzlepiece.extension.fill")
                        .tag("Plugins")
                    Label("Skills", systemImage: "brain.head.profile")
                        .tag("Skills")
                    Label("Settings", systemImage: "gearshape.fill")
                        .tag("Settings")
                }
            }
            .navigationTitle("BridgeMind")
            .frame(minWidth: 200)
        } detail: {
            VStack {
                Text("BridgeMind One")
                    .font(.largeTitle.bold())
                Text("Universal AI Development Orchestrator")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
