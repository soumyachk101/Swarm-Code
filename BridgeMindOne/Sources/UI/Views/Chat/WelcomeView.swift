//
// WelcomeView.swift
// Welcome / landing screen
//

import SwiftUI
import Core

public struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("BridgeMind One")
                .font(.largeTitle.bold())

            Text("Your AI-powered development orchestrator")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            // Quick actions
            VStack(spacing: 12) {
                Button("Start New Chat") {
                    appState.createNewChat()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Open Plugins") {
                    appState.showPlugins = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
