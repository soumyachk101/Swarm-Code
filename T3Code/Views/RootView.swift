import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 380)
        } detail: {
            DetailView()
        }
        .overlay {
            if model.isCommandPalettePresented {
                CommandPalette()
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @discardableResult
    private func handleDrop(_ urls: [URL]) -> Bool {
        var folders: [URL] = []
        var files: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue { folders.append(url) } else { files.append(url) }
        }
        var lastProject: Project?
        for folder in folders { lastProject = model.addProject(at: folder) }
        if let lastProject { model.newThread(in: lastProject) }
        if !files.isEmpty, let threadID = model.selectedThreadID {
            let runtime = model.runtime(for: threadID)
            for file in files where runtime.draft.attachments.count < 8 {
                if let attachment = try? Storage.importAttachment(from: file) {
                    runtime.draft.attachments.append(attachment)
                }
            }
        }
        return !folders.isEmpty || !files.isEmpty
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let threadID = model.selectedThreadID, model.thread(threadID) != nil {
            ChatView(runtime: model.runtime(for: threadID))
                .id(threadID)
        } else if model.projects.isEmpty {
            WelcomeView()
        } else {
            NoThreadView()
        }
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                VStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 104, height: 104)
                    Text("T3 Code")
                        .font(.system(size: 34, weight: .semibold))
                    Text("A calm, native home for your coding agents.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 10) {
                    Button {
                        model.chooseProjectFolder()
                    } label: {
                        Label("Add a project", systemImage: "folder.badge.plus")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    Text("Or drop a folder anywhere in this window.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                ProviderChecklist()
                    .frame(maxWidth: 480)
            }
            .padding(48)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct ProviderChecklist: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ProviderKind.allCases) { provider in
                let status = model.providers.status(provider)
                HStack(spacing: 12) {
                    ProviderIcon(provider: provider, size: 18)
                        .foregroundStyle(.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                        Text(status.isChecking ? "Checking…" : status.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if status.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else if !status.isInstalled {
                        Link("Install", destination: provider.installURL)
                            .buttonStyle(.glass)
                    } else if status.auth == .signedOut {
                        CopyCommandButton(command: provider.loginCommand)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

struct CopyCommandButton: View {
    let command: String
    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            didCopy = true
        } label: {
            Label(didCopy ? "Copied" : command, systemImage: didCopy ? "checkmark" : "terminal")
                .font(.system(.caption, design: .monospaced))
        }
        .buttonStyle(.glass)
        .help("Copy the sign-in command, then run it in Terminal")
    }
}

struct NoThreadView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Pick a thread or start a new one")
                .font(.title3)
            Button {
                model.newThread()
            } label: {
                Label("New thread", systemImage: "square.and.pencil")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Text("⌘N")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
