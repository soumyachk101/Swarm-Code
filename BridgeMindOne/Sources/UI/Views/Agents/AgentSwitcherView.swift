//
// AgentSwitcherView.swift
// Agent selection and switching UI
//

import SwiftUI
import Core

public struct AgentSwitcherView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEngine: EngineType = .claude

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Text("Select Agent Engine")
                .font(.title.bold())

            // Engine grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 16)], spacing: 16) {
                ForEach(EngineType.allCases, id: \.self) { engine in
                    EngineCard(engine: engine, isSelected: selectedEngine == engine)
                        .onTapGesture {
                            selectedEngine = engine
                        }
                }
            }

            Divider()

            // Selected engine details
            VStack(alignment: .leading, spacing: 8) {
                Text(selectedEngine.displayName)
                    .font(.headline)

                Text(engineDescription(for: selectedEngine))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Switch Agent") {
                    appState.switchAgent(to: selectedEngine)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedEngine == appState.activeAgent)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 480, height: 520)
        .onAppear {
            selectedEngine = appState.activeAgent
        }
    }

    private func engineDescription(for engine: EngineType) -> String {
        switch engine {
        case .claude: return "Anthropic's Claude via Claude Code CLI"
        case .codex: return "OpenAI's Codex CLI"
        case .cursor: return "Cursor IDE integration"
        case .aider: return "Aider coding assistant"
        case .deepseek: return "DeepSeek AI models"
        case .gemini: return "Google Gemini"
        case .grok: return "xAI's Grok"
        case .opencode: return "OpenCode terminal agent"
        default: return "AI Agent Engine"
        }
    }
}

private struct EngineCard: View {
    let engine: EngineType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: engineIcon)
                .font(.system(size: 36))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Text(engine.displayName)
                .font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var engineIcon: String {
        switch engine {
        case .claude: return "brain.head.profile"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursor.rays"
        case .aider: return "hammer"
        case .deepseek: return "dot.radiowaves.left.and.right"
        case .gemini: return "sparkles"
        case .grok: return "bolt"
        case .opencode: return "terminal"
        default: return "cpu"
        }
    }
}
