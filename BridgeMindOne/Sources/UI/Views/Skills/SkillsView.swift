//
// SkillsView.swift
// BridgeMind One — Bundled Skills Browser and Manager
//

import SwiftUI
import Core

public struct SkillItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let filename: String
    public let iconName: String

    public init(id: String, name: String, summary: String, filename: String, iconName: String) {
        self.id = id
        self.name = name
        self.summary = summary
        self.filename = filename
        self.iconName = iconName
    }
}

public struct SkillsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSkill: SkillItem?
    @State private var skillContent: String = ""

    public static let bundledSkills: [SkillItem] = [
        SkillItem(
            id: "draft-for-reader",
            name: "Draft for a Reader",
            summary: "Structure clarity, tone calibration, and executive summary formulation.",
            filename: "skill-draft-for-a-reader.md",
            iconName: "doc.text.fill"
        ),
        SkillItem(
            id: "keep-memory",
            name: "Keep a Memory",
            summary: "Extracts persistent facts and preferences into long-term context memory.",
            filename: "skill-keep-a-memory.md",
            iconName: "brain.head.profile"
        ),
        SkillItem(
            id: "lean-code",
            name: "Lean Code Optimizer",
            summary: "Refactors complex code into clean, modular, and performant implementations.",
            filename: "skill-lean-code.md",
            iconName: "curlybraces"
        ),
        SkillItem(
            id: "research-question",
            name: "Research a Question",
            summary: "Performs systematic multi-hop investigation with citation and synthesis.",
            filename: "skill-research-a-question.md",
            iconName: "magnifyingglass"
        ),
        SkillItem(
            id: "root-cause",
            name: "Root Cause Analysis",
            summary: "Deep-dives stack traces and logs to isolate the exact defect and regression.",
            filename: "skill-root-cause.md",
            iconName: "stethoscope"
        ),
        SkillItem(
            id: "save-tokens",
            name: "Save Tokens",
            summary: "Compresses prompt context without loss of critical technical semantics.",
            filename: "skill-save-tokens.md",
            iconName: "leaf.fill"
        ),
        SkillItem(
            id: "write-a-skill",
            name: "Write a Skill",
            summary: "Meta-skill to author structured agent skills with YAML frontmatter.",
            filename: "skill-write-a-skill.md",
            iconName: "pencil.and.outline"
        )
    ]

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(Self.bundledSkills, selection: $selectedSkill) { skill in
                HStack(spacing: 12) {
                    Image(systemName: skill.iconName)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name)
                            .font(.system(size: 13, weight: .semibold))

                        Text(skill.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
                .tag(skill)
            }
            .listStyle(.sidebar)
            .navigationTitle("Bundled Skills")
            .frame(minWidth: 260)
        } detail: {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: skill.iconName)
                                .font(.largeTitle)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading) {
                                Text(skill.name)
                                    .font(.title2.bold())
                                Text(skill.filename)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Use in Chat") {
                                appState.sidebarSelection = .chat
                                appState.createNewChat()
                                appState.currentSession?.messages.append(
                                    ChatMessage(
                                        role: .user,
                                        content: "Apply skill: \(skill.name)\n\n\(skill.summary)"
                                    )
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.bottom, 8)

                        Divider()

                        Text("Skill Definition")
                            .font(.headline)

                        Text(skillContent)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Spacer()
                    }
                    .padding(24)
                }
                .onChange(of: selectedSkill) { _, newSkill in
                    loadSkillContent(for: newSkill)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Select a skill to inspect its prompt rules and capabilities")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedSkill == nil {
                selectedSkill = Self.bundledSkills.first
                loadSkillContent(for: selectedSkill)
            }
        }
    }

    private func loadSkillContent(for skill: SkillItem?) {
        guard let skill else { return }
        if let url = Bundle.main.url(forResource: skill.filename.replacingOccurrences(of: ".md", with: ""), withExtension: "md", subdirectory: "Skills") ??
                     Bundle.main.url(forResource: skill.filename, withExtension: nil) {
            skillContent = (try? String(contentsOf: url, encoding: .utf8)) ?? skill.summary
        } else {
            skillContent = "### \(skill.name)\n\n\(skill.summary)\n\n*Bundled in BridgeMind One Resources.*"
        }
    }
}
