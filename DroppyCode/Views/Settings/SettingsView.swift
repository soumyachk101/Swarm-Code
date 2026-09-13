import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case providers
    case models
    case sourceControl
    case shortcuts
    case archive
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .models: "Models"
        case .sourceControl: "Source control"
        case .shortcuts: "Shortcuts"
        case .archive: "Archive"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .providers: "cpu"
        case .models: "slider.horizontal.3"
        case .sourceControl: "arrow.triangle.branch"
        case .shortcuts: "command"
        case .archive: "archivebox"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: Chrome.gray
        case .providers: Chrome.blue
        case .models: Color(red: 0.686, green: 0.322, blue: 0.871)
        case .sourceControl: Color(red: 0.345, green: 0.337, blue: 0.839)
        case .shortcuts: Color(red: 0.32, green: 0.48, blue: 0.93)
        case .archive: Chrome.orange
        case .about: Color(red: 0.204, green: 0.780, blue: 0.349)
        }
    }

    var keywords: [String] {
        switch self {
        case .general: ["permissions", "worktree", "reasoning", "notifications", "theme", "appearance", "dark", "light", "token", "tokens", "activity", "usage", "heatmap", "daily", "weekly", "cumulative"]
        case .models: ["model", "effort", "reasoning", "fast", "slider", "picker"]
        case .providers: ["codex", "claude", "cursor", "opencode", "grok", "deepseek", "meta", "muse", "spark", "binary", "path", "sign in", "login", "api key"]
        case .sourceControl: ["git", "commit", "pull request", "titles", "text generation"]
        case .shortcuts: ["keyboard", "keys"]
        case .archive: ["archived", "restore"]
        case .about: ["version", "license"]
        }
    }
}

struct SettingsView: View {
    @State private var page: SettingsPage = .general
    @State private var search = ""
    @State private var modelSearch = ""
    @State private var scrollChrome = ChromeScrollModel()

    private var visiblePages: [SettingsPage] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsPage.allCases }
        return SettingsPage.allCases.filter { page in
            page.title.localizedCaseInsensitiveContains(query)
                || page.keywords.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
            detail
                .padding(.trailing, Chrome.sheetInset)
                .padding(.vertical, Chrome.sheetInset)
        }
        .background { WindowBackdrop() }
        .background { WindowChromeConfigurator() }
        .clipShape(RoundedRectangle(cornerRadius: Chrome.windowCornerRadius, style: .continuous))
        .ignoresSafeArea()
        .frame(width: 780, height: 580)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: Chrome.trafficLightDiameter)
                .padding(.top, Chrome.trafficLightTop)
            SidebarSearchField(text: $search) {
                if let first = visiblePages.first { page = first }
            }
            .padding(.horizontal, Chrome.listInset)
            .padding(.top, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(visiblePages) { item in
                        SidebarRow(title: item.title, isSelected: page == item, action: { page = item }) {
                            SidebarIconBadge {
                                SidebarSymbol(item.symbol, scale: item == .general ? 1.15 : 1)
                            }
                        }
                    }
                    if visiblePages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No results")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Chrome.primaryText.opacity(0.92))
                            Text("Try a setting or a provider name.")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, Chrome.listInset)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { WindowDragArea() }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
                pageContent
            }
            .padding(.horizontal, Chrome.contentHorizontalPadding + 8)
            // Pages without chrome controls start just below the sheet edge; the others clear their capsules.
            .padding(.top, pageHasChromeControls ? Chrome.chromeTopPadding + Chrome.capsuleHeight + 16 : 22)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .id(page)
        .onScrollGeometryChange(for: CGFloat.self, of: Self.travel) { _, travel in
            scrollChrome.update(travel: travel)
        }
        .overlay(alignment: .top) {
            PaneTopVeil(model: scrollChrome)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 10) {
                ChromeCompactTitle(title: page.title, model: scrollChrome)
                if page == .models {
                    ChromeSearchField(query: $modelSearch, prompt: "Search models")
                }
                if page == .providers {
                    ProvidersRefreshButton()
                }
            }
            .frame(minHeight: Chrome.capsuleHeight)
            .padding(.horizontal, Chrome.chromeHorizontalPadding)
            .padding(.top, Chrome.chromeTopPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .detailSheet()
        .onChange(of: page, initial: true) {
            scrollChrome.update(travel: 0)
            modelSearch = ""
        }
    }

    private var pageHasChromeControls: Bool {
        page == .providers || page == .models
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .general: GeneralSettingsPage()
        case .providers: ProvidersSettingsPage()
        case .models:
            ModelsSettingsPage(query: modelSearch)
        case .sourceControl: SourceControlSettingsPage()
        case .shortcuts: ShortcutsSettingsPage()
        case .archive: ArchiveSettingsPage()
        case .about: AboutSettingsPage()
        }
    }

    private nonisolated static func travel(_ geometry: ScrollGeometry) -> CGFloat {
        geometry.contentOffset.y + geometry.contentInsets.top
    }
}

private struct SettingsSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

private struct GeneralSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        // The Token activity heatmap leads the page: it summarizes what the
        // settings below configure, rather than configuring anything itself.
        TokenActivitySection()
        ChromeSection(title: "New threads") {
            ChromeCard {
                ChromeRow(title: "Provider") {
                    GlassPickerButton(options: ProviderKind.allCases.map { ($0, $0.displayName) }, selection: $settings.defaultProvider, asset: { $0.iconName })
                }
                ChromeRowDivider()
                ChromeRow(title: "Permissions", detail: settings.defaultRuntimeMode.summary) {
                    GlassPickerButton(options: RuntimeMode.allCases.map { ($0, $0.title) }, selection: $settings.defaultRuntimeMode)
                }
                ChromeRowDivider()
                ChromeRow(title: "Workspace", detail: "Where a new thread makes its changes") {
                    GlassPickerButton(options: WorkspaceMode.allCases.map { ($0, $0.title) }, selection: $settings.defaultWorkspaceMode)
                }
            }
        }
            ChromeSection(title: "Conversation") {
                ChromeCard {
                    ChromeRow(title: "Show reasoning") {
                        SettingsSwitch(isOn: $settings.showReasoning)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Recent downloads", detail: "The attach button offers recent downloads first") {
                        SettingsSwitch(isOn: $settings.recentDownloadsPicker)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Notify when a turn finishes") {
                    SettingsSwitch(isOn: $settings.notifyWhenFinished)
                }
                ChromeRowDivider()
                ChromeRow(title: "Confirm before deleting threads") {
                    SettingsSwitch(isOn: $settings.confirmBeforeDeleting)
                }
            }
        }
        ChromeSection(title: "Appearance") {
            ChromeCard {
                ChromeRow(title: "Theme") {
                    GlassPickerButton(options: AppearancePreference.allCases.map { ($0, $0.title) }, selection: $settings.appearance)
                }
            }
        }
    }
}

private struct ProvidersRefreshButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ChromeCapsule {
            ChromeIconButton(
                symbol: "arrow.clockwise",
                isEnabled: !model.providers.isRefreshing,
                help: model.providers.isRefreshing ? "Checking providers…" : "Check providers again"
            ) {
                Task { await model.providers.refreshEverything() }
            }
        }
    }
}

/// Shows what launch (or the refresh button) last found. Opening or scrolling the page checks nothing.
private struct ProvidersSettingsPage: View {
    var body: some View {
        // Eager on purpose: a handful of sections, and lazy ones were rebuilt while scrolling,
        // which reset their fields and re-ran every check they started on appear.
        VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
            ForEach(ProviderKind.allCases) { provider in
                ProviderSettingsSection(provider: provider)
            }
        }
    }
}

private struct ProviderSettingsSection: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    @State private var binaryPath = ""
    @State private var apiKey = ""
    @State private var showsAPIKey = false
    @State private var keyCheck: Task<Void, Never>?

    var body: some View {
        let status = model.providers.status(provider)
        ChromeSection(title: provider.displayName) {
            ChromeCard {
                HStack(spacing: 12) {
                    ProviderIcon(provider: provider, size: 18)
                        .foregroundStyle(Chrome.primaryText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: status.isChecking ? "Checking…" : status.summary)
                            .font(.system(size: 13))
                        if let version = status.version, !provider.isAPIKeyBased {
                            Text(verbatim: "Version \(version)")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                        } else if provider.isAPIKeyBased, status.apiKeyConfigured, let host = provider.apiHost {
                            Text(verbatim: "Native API · \(host)")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                        }
                    }
                    Spacer()
                    SettingsSwitch(isOn: Binding(
                        get: { model.settings.isEnabled(provider) },
                        set: { model.settings.setEnabled($0, for: provider) }
                    ))
                }
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 11)
                if provider.isAPIKeyBased {
                    ChromeRowDivider()
                    ChromeRow(title: "API key", detail: "Stored in your Keychain. Get one at \(provider.apiKeySource ?? "the provider dashboard").") {
                        HStack(spacing: 8) {
                            Group {
                                if showsAPIKey {
                                    TextField("", text: $apiKey, prompt: Text("sk-…"))
                                } else {
                                    SecureField("", text: $apiKey, prompt: Text("sk-…"))
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 200)
                            Button {
                                showsAPIKey.toggle()
                            } label: {
                                Image(systemName: showsAPIKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Chrome.secondaryText)
                            .help(showsAPIKey ? "Hide the API key" : "Show the API key")
                        }
                    }
                    if !status.isInstalled {
                        ChromeRowDivider()
                        ChromeRow(title: "Get a key", detail: "\(provider.displayName) needs an API key — no install required.") {
                            Link("Get a \(provider.displayName) key", destination: provider.installURL)
                                .buttonStyle(.glass)
                        }
                    }
                } else {
                    ChromeRowDivider()
                    ChromeRow(title: "Binary path", detail: status.executable?.path) {
                        TextField("", text: $binaryPath, prompt: Text(provider.executableName))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 200)
                    }
                    if !status.isInstalled {
                        ChromeRowDivider()
                        ChromeRow(title: "Install", detail: "\(provider.displayName) was not found on your PATH.") {
                            Link("Get \(provider.displayName)", destination: provider.installURL)
                                .buttonStyle(.glass)
                        }
                    } else if status.auth == .signedOut {
                        ChromeRowDivider()
                        ChromeRow(title: "Sign in", detail: "Run this command in Terminal.") {
                            CopyCommandButton(command: provider.loginCommand)
                        }
                    }
                }
            }
        }
        .onAppear {
            binaryPath = model.settings.binaryPath(for: provider)
            if provider.isAPIKeyBased { apiKey = model.settings.apiKeyInput(for: provider) }
        }
        .onChange(of: binaryPath) { _, value in
            guard value != model.settings.binaryPath(for: provider) else { return }
            model.settings.setBinaryPath(value, for: provider)
        }
        .onChange(of: apiKey) { _, value in
            // Only an edit counts: loading the stored key into the field must not save or check it.
            guard provider.isAPIKeyBased, value != model.settings.apiKeyInput(for: provider) else { return }
            model.settings.setAPIKeyInput(value, for: provider)
            keyCheck?.cancel()
            keyCheck = Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                await model.providers.refresh(provider)
                await model.providers.loadCatalog(provider, force: true)
            }
        }
        .onChange(of: model.settings.apiKeyInput(for: provider)) { _, value in
            guard provider.isAPIKeyBased, value != apiKey else { return }
            apiKey = value
        }
    }
}

private struct SourceControlSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ChromeSection(title: "Text generation") {
            ChromeCard {
                ChromeRow(
                    title: "Thread titles and commit messages",
                    detail: "Automatic uses the thread's own provider. Claude uses Haiku, Codex your default model."
                ) {
                    GlassPickerButton(options: TextGenerationChoice.allCases.map { ($0, $0.title) }, selection: $settings.textGeneration, asset: { ProviderKind(rawValue: $0.rawValue)?.iconName })
                }
            }
        }
        ChromeSection(title: "Commit message instructions") {
            ChromeCard {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $settings.commitInstructions)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 90)
                    if settings.commitInstructions.isEmpty {
                        Text("For example: use conventional commit prefixes")
                            .font(.system(size: 13))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(12)
            }
        }
        ChromeSection(title: "Worktrees and pull requests") {
            ChromeCard {
                ChromeRow(title: "Worktrees", detail: Storage.worktreesDirectory.path) {
                    Button("Reveal") { Workspace.revealInFinder(Storage.worktreesDirectory.path) }
                        .buttonStyle(.glass)
                }
                ChromeRowDivider()
                ChromeRow(title: "Pull requests", detail: "Opened with the GitHub CLI (gh) or GitLab CLI (glab) from your PATH.") {
                    EmptyView()
                }
            }
        }
    }
}

private struct ArchiveSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let archived = model.archivedThreads
        if archived.isEmpty {
            Text("Archived threads show up here.")
                .font(.system(size: 13))
                .foregroundStyle(Chrome.secondaryText)
        } else {
            ChromeCard {
                ForEach(Array(archived.enumerated()), id: \.element.id) { index, thread in
                    if index > 0 { ChromeRowDivider() }
                    ChromeRow(title: thread.title, detail: model.project(thread.projectID)?.name) {
                        HStack(spacing: 8) {
                            Button("Restore") { model.unarchive(thread.id) }
                                .buttonStyle(.glass)
                            Button("Delete", role: .destructive) { model.delete(thread.id) }
                                .buttonStyle(.glass)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

private struct AboutSettingsPage: View {
    private static let droppyURL = URL(string: "https://getdroppy.app")!

    var body: some View {
        VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
            appCard
            ChromeSection(title: "Credits") {
                ChromeCard {
                    MadeByDroppyRow(url: Self.droppyURL)
                    ChromeRowDivider()
                    ChromeRow(title: "Working indicators", detail: "Ported from Zeron by Wing, MIT License.") {
                        CreditLink(title: "zeronsh/zeron", url: URL(string: "https://github.com/zeronsh/zeron")!)
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Terminal", detail: "SwiftTerm by Miguel de Icaza, MIT License.") {
                        CreditLink(title: "SwiftTerm", url: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
                    }
                }
            }
        }
    }

    private var appCard: some View {
        ChromeCard {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Droppy Code")
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: "Version \(AppInfo.version) (\(AppInfo.build))")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            ChromeRowDivider()
            Text("The coding app by Droppy: a native home for your coding agents, built in Swift with Liquid Glass.")
                .font(.system(size: 13))
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 11)
            ChromeRowDivider()
            Text("Droppy Code and SwiftTerm are MIT licensed.")
                .font(.system(size: 12))
                .foregroundStyle(Chrome.secondaryText)
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 11)
        }
    }
}

/// Droppy's logo and name, linking to getdroppy.app, so it is clear the app is made by Droppy.
private struct MadeByDroppyRow: View {
    let url: URL
    @State private var isHovering = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image("droppy-logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Made by Droppy")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Chrome.primaryText)
                    Text("Droppy Code is a coding app by Droppy for Mac.")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    Text(verbatim: "getdroppy.app")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Chrome.accent)
                .opacity(isHovering ? 1 : 0.9)
            }
            .padding(.leading, 16)
            .padding(.trailing, Chrome.rowControlTrailingPadding + 4)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help("Open getdroppy.app")
        .accessibilityLabel(Text("Made by Droppy. Open getdroppy.app"))
    }
}

private struct CreditLink: View {
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Chrome.accent)
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}
