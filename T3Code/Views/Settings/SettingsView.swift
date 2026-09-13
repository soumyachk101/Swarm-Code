import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Providers", systemImage: "cpu") { ProviderSettings() }
            Tab("Source control", systemImage: "arrow.triangle.branch") { SourceControlSettings() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
            Tab("Archive", systemImage: "archivebox") { ArchiveSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 680, height: 540)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("New threads") {
                Picker("Provider", selection: $settings.defaultProvider) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                Picker("Permissions", selection: $settings.defaultRuntimeMode) {
                    ForEach(RuntimeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Workspace", selection: $settings.defaultWorkspaceMode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            Section("Conversation") {
                Toggle("Show reasoning", isOn: $settings.showReasoning)
                Toggle("Notify when a turn finishes", isOn: $settings.notifyWhenFinished)
                Toggle("Confirm before deleting threads", isOn: $settings.confirmBeforeDeleting)
            }
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppearancePreference.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            ForEach(ProviderKind.allCases) { provider in
                ProviderSettingsSection(provider: provider)
            }
        }
        .formStyle(.grouped)
        .task { await model.providers.refreshAll() }
    }
}

private struct ProviderSettingsSection: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    @State private var binaryPath = ""

    var body: some View {
        let status = model.providers.status(provider)
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.isEnabled(provider) },
                set: { model.settings.setEnabled($0, for: provider) }
            )) {
                HStack(spacing: 10) {
                    ProviderIcon(provider: provider, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                        Text(status.isChecking ? "Checking…" : status.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TextField("Binary path", text: $binaryPath, prompt: Text(status.executable?.path ?? provider.executableName))
                .font(.system(.body, design: .monospaced))
            HStack {
                if !status.isInstalled {
                    Link("Install \(provider.displayName)", destination: provider.installURL)
                } else if status.auth == .signedOut {
                    CopyCommandButton(command: provider.loginCommand)
                }
                Spacer()
                Button("Refresh") {
                    Task {
                        await model.providers.refresh(provider)
                        await model.providers.loadCatalog(provider, force: true)
                    }
                }
            }
        }
        .onAppear { binaryPath = model.settings.binaryPath(for: provider) }
        .onChange(of: binaryPath) { _, value in model.settings.setBinaryPath(value, for: provider) }
    }
}

private struct SourceControlSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Picker("Text generation", selection: $settings.textGeneration) {
                    ForEach(TextGenerationChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
            } footer: {
                Text("Writes thread titles and commit messages. Automatic prefers the thread's own provider. Claude uses Haiku, Codex uses your default Codex model.")
                    .foregroundStyle(.secondary)
            }
            Section("Commit message instructions") {
                TextEditor(text: $settings.commitInstructions)
                    .font(.body)
                    .frame(minHeight: 90)
            }
            Section {
                LabeledContent("Worktrees", value: Storage.worktreesDirectory.path)
                Button("Reveal worktrees in Finder") {
                    Workspace.revealInFinder(Storage.worktreesDirectory.path)
                }
            } footer: {
                Text("Pull requests use the GitHub CLI (gh) or GitLab CLI (glab) from your PATH.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    private let shortcuts: [(String, String)] = [
        ("New thread", "⌘N"),
        ("New thread in worktree", "⇧⌘N"),
        ("Add project", "⌘O"),
        ("Command palette", "⌘K"),
        ("Toggle terminal", "⌘J"),
        ("Toggle changes", "⌘D"),
        ("Plan mode", "⇧⌘P"),
        ("Stop the running turn", "⌘. or Esc"),
        ("Send", "Return"),
        ("New line", "⇧Return"),
        ("Recall an earlier prompt", "↑ in an empty composer"),
        ("Approve a request", "⌘Return"),
        ("Previous or next thread", "⌥⌘↑ / ⌥⌘↓"),
        ("Jump to a thread", "⌘1 to ⌘9"),
        ("Archive thread", "⇧⌘⌫"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(shortcuts, id: \.0) { name, keys in
                    LabeledContent(name) {
                        Text(keys)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ArchiveSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let archived = model.archivedThreads
        if archived.isEmpty {
            ContentUnavailableView("Nothing archived", systemImage: "archivebox", description: Text("Archived threads show up here."))
        } else {
            Form {
                Section {
                    ForEach(archived) { thread in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(thread.title)
                                Text(model.project(thread.projectID)?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { model.unarchive(thread.id) }
                            Button("Delete", role: .destructive) { model.delete(thread.id) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("T3 Code")
                .font(.title2.weight(.semibold))
            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .foregroundStyle(.secondary)
            Text("A native Swift fork of T3 Code by T3 Tools, rebuilt with Liquid Glass for macOS.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Text("T3 Code and SwiftTerm are MIT licensed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
