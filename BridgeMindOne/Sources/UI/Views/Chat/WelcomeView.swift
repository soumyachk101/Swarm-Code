//
// WelcomeView.swift
// BridgeMind One — Welcome & Prompt Starter Screen
//

import SwiftUI
import Core

public struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header Hero
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 54))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("BridgeMind One")
                    .font(.system(size: 28, weight: .bold))

                Text("Multi-Agent AI Orchestration & MCP Workspace")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Quick Skill Cards Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                SkillCard(
                    icon: "magnifyingglass",
                    title: "Research a Question",
                    description: "Multi-hop investigation with deep source synthesis."
                ) {
                    insertPrompt("Research a question: ")
                }

                SkillCard(
                    icon: "stethoscope",
                    title: "Root Cause Analysis",
                    description: "Trace stack errors, regressions, and root issues."
                ) {
                    insertPrompt("Analyze the root cause of this error: ")
                }

                SkillCard(
                    icon: "curlybraces",
                    title: "Lean Code Optimizer",
                    description: "Refactor for high performance and clean architecture."
                ) {
                    insertPrompt("Optimize and refactor this code cleanly: ")
                }

                SkillCard(
                    icon: "doc.text.fill",
                    title: "Draft for a Reader",
                    description: "Calibrate clarity, tone, and executive summary."
                ) {
                    insertPrompt("Help me draft a clear technical explanation: ")
                }
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: 640)

            Spacer()

            // Quick Stats Footer
            HStack(spacing: 24) {
                Label("\(appState.activeAgent.displayName) Active", systemImage: "cpu")
                Label("24 MCP Plugins", systemImage: "puzzlepiece.extension")
                Label("7 Bundled Skills", systemImage: "brain.head.profile")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func insertPrompt(_ prompt: String) {
        if appState.currentSession == nil {
            appState.createNewChat()
        }
        appState.currentSession?.messages.append(
            ChatMessage(role: .user, content: prompt)
        )
    }
}

private struct SkillCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
