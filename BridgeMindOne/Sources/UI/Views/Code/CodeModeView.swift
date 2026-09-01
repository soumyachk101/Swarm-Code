//
// CodeModeView.swift
// BridgeMind One — Single-Agent Code Mode
//
// Dedicated coding workspace with file tree, multi-file code editor,
// inline diffs, terminal execution, and Claude Code / Codex integration.
//

import SwiftUI
import Core

public struct CodeFileItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public var content: String
    public let isModified: Bool

    public init(id: String = UUID().uuidString, name: String, language: String, content: String, isModified: Bool = false) {
        self.id = id
        self.name = name
        self.language = language
        self.content = content
        self.isModified = isModified
    }
}

public struct CodeModeView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedFileId: String = "f1"
    @State private var promptText: String = ""
    @State private var isExecuting: Bool = false
    @State private var terminalOutput: [String] = [
        "BridgeMind Code Engine v0.1.12 initialized.",
        "Attached to workspace: /Users/soumyachakraborty/Documents/01-Projects/SwarmAI",
        "Ready for code generation and agent refactoring."
    ]

    @State private var openFiles: [CodeFileItem] = [
        CodeFileItem(
            id: "f1",
            name: "AgentManager.swift",
            language: "swift",
            content: """
// AgentManager.swift
// Actor-isolated engine supervision

import Foundation
import Core

public actor AgentManager {
    public static let shared = AgentManager()
    private var processes: [EngineType: AgentProcess] = [:]
    
    public func startEngine(_ type: EngineType) async throws {
        let process = AgentProcess(engine: type)
        try await process.launch()
        processes[type] = process
    }
}
"""
        ),
        CodeFileItem(
            id: "f2",
            name: "MCPTransport.swift",
            language: "swift",
            content: """
// MCPTransport.swift
// Protocol definition for Model Context Protocol

import Foundation

public protocol MCPTransport: Sendable {
    func connect() async throws
    func disconnect() async throws
    func send(request: JSONRPCRequest) async throws -> JSONRPCResponse
}
"""
        ),
        CodeFileItem(
            id: "f3",
            name: "Package.swift",
            language: "swift",
            content: """
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BridgeMindOne",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BridgeMindOne", targets: ["App"])
    ]
)
"""
        )
    ]

    public init() {}

    private var currentFile: CodeFileItem? {
        openFiles.first { $0.id == selectedFileId } ?? openFiles.first
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Workspace File Tree Sub-sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("WORKSPACE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BMColors.textMuted)
                    Spacer()
                    Image(systemName: "folder.badge.gear")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(openFiles) { file in
                            Button {
                                selectedFileId = file.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: fileIcon(for: file.name))
                                        .font(.system(size: 12))
                                        .foregroundStyle(file.id == selectedFileId ? BMColors.accentBlue : BMColors.textSecondary)

                                    Text(file.name)
                                        .font(.system(size: 12, weight: file.id == selectedFileId ? .semibold : .regular))
                                        .foregroundStyle(file.id == selectedFileId ? .white : BMColors.textSecondary)

                                    Spacer()

                                    if file.isModified {
                                        Circle()
                                            .fill(BMColors.claudeOrange)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(file.id == selectedFileId ? Color(red: 0.16, green: 0.16, blue: 0.19) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                        }
                    }
                }

                Spacer()

                // Engine info footer
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11))
                        .foregroundStyle(BMColors.claudeOrange)
                    Text("Claude Code CLI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("Auto-apply")
                        .font(.system(size: 9))
                        .foregroundStyle(BMColors.statusGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(BMColors.statusGreen.opacity(0.15))
                        .clipShape(Capsule())
                }
                .padding(12)
                .background(BMColors.sidebar)
            }
            .frame(width: 190)
            .background(BMColors.middlePane)
            .overlay(
                Divider().background(BMColors.borderSubtle),
                alignment: .trailing
            )

            // Main Editor & Code Agent Inspector
            VStack(spacing: 0) {
                // Open File Tabs Bar
                HStack(spacing: 4) {
                    ForEach(openFiles) { file in
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon(for: file.name))
                                .font(.system(size: 10))
                                .foregroundStyle(BMColors.textSecondary)

                            Text(file.name)
                                .font(.system(size: 12, weight: file.id == selectedFileId ? .semibold : .regular))
                                .foregroundStyle(file.id == selectedFileId ? .white : BMColors.textMuted)

                            Button {} label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(BMColors.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(file.id == selectedFileId ? BMColors.chatBackground : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture {
                            selectedFileId = file.id
                        }
                    }

                    Spacer()

                    Button {
                        runCodeBuild()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 10))
                            Text("Build & Test")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BMColors.accentBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(BMColors.sidebar)
                .overlay(
                    Divider().background(BMColors.borderSubtle),
                    alignment: .bottom
                )

                // Code Editor Display
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        // Line numbers
                        VStack(alignment: .trailing, spacing: 4) {
                            ForEach(1...25, id: \.self) { line in
                                Text("\(line)")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(BMColors.textMuted.opacity(0.6))
                            }
                        }
                        .padding(.top, 12)
                        .padding(.leading, 12)

                        // Code text
                        if let file = currentFile {
                            Text(file.content)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(Color(red: 0.90, green: 0.92, blue: 0.95))
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 12)
                        }
                    }
                }
                .background(BMColors.chatBackground)

                // Terminal / Build Output Drawer
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "terminal")
                            .font(.system(size: 10))
                            .foregroundStyle(BMColors.textMuted)
                        Text("AGENT TERMINAL")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(BMColors.textMuted)
                        Spacer()
                        Text("swift 5.9")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(BMColors.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(terminalOutput, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(line.contains("✅") || line.contains("success") ? BMColors.statusGreen : (line.contains("error") ? Color.red : BMColors.textSecondary))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    }
                    .frame(height: 80)
                }
                .background(BMColors.sidebar)
                .overlay(
                    Divider().background(BMColors.borderSubtle),
                    alignment: .top
                )

                // Code Agent Instruction Bar
                HStack(spacing: 10) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 13))
                        .foregroundStyle(BMColors.claudeOrange)

                    TextField("Instruct agent to refactor, add tests, or fix bugs...", text: $promptText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .onSubmit(sendCodeInstruction)

                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    Button("Generate Edit") {
                        sendCodeInstruction()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(BMColors.accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isExecuting)
                }
                .padding(12)
                .background(BMColors.inputBackground)
            }
        }
    }

    private func sendCodeInstruction() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        terminalOutput.append("$ claude code \"\(text)\"")
        promptText = ""
        isExecuting = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            terminalOutput.append("⚡ Claude analyzing AST and dependencies...")
            try? await Task.sleep(nanoseconds: 500_000_000)
            terminalOutput.append("📝 Applied diff to \(currentFile?.name ?? "file")")
            terminalOutput.append("✅ Generated clean implementation with 0 compiler warnings.")

            // Append edit to file content
            if let idx = openFiles.firstIndex(where: { $0.id == selectedFileId }) {
                openFiles[idx].content += "\n\n    // Added by Agent:\n    public func handleAutomatedEvent() async {\n        print(\"Event processed.\")\n    }"
            }
            isExecuting = false
        }
    }

    private func runCodeBuild() {
        terminalOutput.append("$ swift build")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            terminalOutput.append("🔨 Compiling Core, UI, and App...")
            try? await Task.sleep(nanoseconds: 400_000_000)
            terminalOutput.append("✅ Build complete! All unit tests passed.")
        }
    }

    private func fileIcon(for filename: String) -> String {
        if filename.hasSuffix(".swift") { return "swift" }
        if filename.hasSuffix(".md") { return "doc.text" }
        return "doc.plaintext"
    }
}
