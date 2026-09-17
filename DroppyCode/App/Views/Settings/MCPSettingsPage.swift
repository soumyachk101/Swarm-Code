import AppKit
import SwiftUI

/// The MCP servers: a grid of cards where one tap connects, with the connected
/// ones gathered in a section on top.
struct MCPSettingsPage: View {
    let query: String
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Servers flashing their success before they leave the grid for Connected.
    @State private var celebrating: Set<String> = []

    private static let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var connected: [MCPCatalogEntry] {
        MCPCatalog.entries
            .filter { !celebrating.contains($0.id) && model.mcp.state(for: $0.id).isConnected }
            .sorted { $0.name < $1.name }
    }

    private var visibleSections: [(category: MCPCategory, entries: [MCPCatalogEntry])] {
        MCPCatalog.byCategory.compactMap { group in
            let entries = group.entries.filter { entry in
                (!model.mcp.state(for: entry.id).isConnected || celebrating.contains(entry.id))
                    && Self.matches(entry, query: query)
            }
            return entries.isEmpty ? nil : (category: group.category, entries: entries)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
            if !connected.isEmpty {
                ChromeSection(title: "Connected") {
                    ChromeCard {
                        ForEach(Array(connected.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { ChromeRowDivider() }
                            MCPConnectedRow(entry: entry)
                        }
                    }
                }
            }
            ForEach(visibleSections, id: \.category) { section in
                ChromeSection(title: section.category.title) {
                    LazyVGrid(columns: Self.columns, spacing: 10) {
                        ForEach(section.entries) { entry in
                            MCPServerCard(entry: entry, celebrating: celebrating.contains(entry.id))
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                }
                .animation(.spring(duration: 0.35), value: celebrating)
            }
            Text("Connected servers are handed to Claude, Codex, Copilot, Cursor, OpenCode and Gemini when a thread starts. Keys stay in your Keychain.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
        }
        .onChange(of: model.mcp.states) { previous, current in
            guard !reduceMotion else { return }
            for (id, state) in current where state.isConnected && !(previous[id]?.isConnected ?? false) {
                celebrating.insert(id)
                SettleChime.play()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    celebrating.remove(id)
                }
            }
        }
    }

    private static func matches(_ entry: MCPCatalogEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return entry.name.localizedCaseInsensitiveContains(trimmed)
            || entry.vendor.localizedCaseInsensitiveContains(trimmed)
            || entry.summary.localizedCaseInsensitiveContains(trimmed)
            || entry.id.localizedCaseInsensitiveContains(trimmed)
            || entry.sampleTools.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// A connected server: its icon, name, tool count and version, a switch for
/// handing it to providers, and a menu for refreshing, peeking at tools and leaving.
private struct MCPConnectedRow: View {
    @Environment(AppModel.self) private var model
    let entry: MCPCatalogEntry

    @State private var showMenu = false
    @State private var showTools = false

    private var connection: MCPConnection? { model.mcp.connection(for: entry.id) }

    private var toolCount: Int {
        if case .connected(let count) = model.mcp.state(for: entry.id) { return count }
        return connection?.tools.count ?? 0
    }

    var body: some View {
        HStack(spacing: 12) {
            MCPIcon(entry: entry, size: 22)
                .frame(width: 26, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text(verbatim: "\(toolCount) tools · \(connection?.serverVersion ?? entry.vendor)")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
            Spacer(minLength: 12)
            SettingsSwitch(isOn: Binding(
                get: { model.mcp.connection(for: entry.id)?.isEnabled ?? true },
                set: { model.mcp.setEnabled($0, for: entry) }
            ))
            Button {
                showMenu.toggle()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Server options")
            .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                PopoverMenu {
                    PopoverItem("Refresh", symbol: "arrow.clockwise") {
                        model.mcp.refresh(entry)
                    }
                    PopoverItem("Show tools", symbol: "wrench") {
                        showMenu = false
                        showTools = true
                    }
                    PopoverDivider()
                    PopoverItem("Disconnect", symbol: "xmark.circle", isDestructive: true) {
                        model.mcp.disconnect(entry)
                    }
                }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, Chrome.rowControlTrailingPadding)
        .padding(.vertical, 11)
        .popover(isPresented: $showTools, arrowEdge: .bottom) {
            PopoverMenu {
                PopoverSectionHeader("\(entry.name) tools")
                let tools = connection?.tools ?? []
                if tools.isEmpty {
                    PopoverNote("No tools listed yet.")
                }
                ForEach(tools) { tool in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: tool.name)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Chrome.primaryText)
                        if let summary = tool.summary, !summary.isEmpty {
                            Text(verbatim: summary)
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// One server in the grid: its icon, name, summary and sample tools, with a
/// Connect button that either connects at once or opens its fields inline.
private struct MCPServerCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: MCPCatalogEntry
    var celebrating = false

    @State private var isExpanded = false
    @State private var successPopped = false

    private var state: MCPConnectionState { model.mcp.state(for: entry.id) }

    private var toolCount: Int {
        if case .connected(let count) = state { return count }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if celebrating {
                successView
            } else {
                headerRow
                Text(verbatim: entry.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.isOAuth {
                    Text("Opens your browser to sign in.")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
                if !entry.sampleTools.isEmpty {
                    Text(verbatim: entry.sampleTools.joined(separator: " · "))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if case .failed(let message) = state {
                    Text(verbatim: message)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.danger)
                        .lineLimit(2)
                }
                if isExpanded, entry.needsInput, !state.isConnected, !state.isConnecting {
                    fieldList
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Chrome.primaryText.opacity(0.05))
        )
        .animation(.spring(duration: 0.35), value: isExpanded)
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            MCPIcon(entry: entry, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text(verbatim: entry.vendor)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
            Spacer(minLength: 8)
            action
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .notConnected:
            if entry.isOAuth {
                Button("Sign in") { model.mcp.connect(entry) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            } else if entry.needsInput {
                // Once the fields are open, the prominent button under them is the one to
                // press; a second "Connect" up here read as two ways to do one thing.
                if !isExpanded {
                    Button("Connect") { isExpanded = true }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            } else {
                Button("Connect") { model.mcp.connect(entry) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        case .connecting:
            HStack(spacing: 6) {
                WorkingSpinner(cellSize: 3)
                Text(entry.isOAuth ? "Waiting for sign-in…" : "Connecting…")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
            }
        case .connected:
            EmptyView()
        case .failed:
            Button("Try again") {
                if entry.needsInput, !entry.isOAuth {
                    isExpanded = true
                }
                model.mcp.connect(entry)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var fieldList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.fields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        fieldInput(field)
                        if field.kind == .path {
                            Button {
                                pickPath(for: field)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Chrome.secondaryText)
                                    .frame(width: 22, height: 22)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help("Choose a folder or file")
                        }
                    }
                    if let help = field.help, !help.isEmpty {
                        Text(verbatim: help)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                }
            }
            Button("Connect") { model.mcp.connect(entry) }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(!model.mcp.canConnect(entry))
            if let docsURL = URL(string: entry.docsURL) {
                Link("Where do I get this?", destination: docsURL)
                    .font(.system(size: 11))
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func fieldInput(_ field: MCPField) -> some View {
        let binding = Binding(
            get: { model.mcp.value(for: field, of: entry) },
            set: { model.mcp.setDraft($0, for: field, of: entry) }
        )
        Group {
            if field.kind == .secret {
                SecureField(field.placeholder, text: binding, prompt: Text(verbatim: field.placeholder))
            } else {
                TextField(field.placeholder, text: binding, prompt: Text(verbatim: field.placeholder))
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity)
    }

    private func pickPath(for field: MCPField) {
        let panel = NSOpenPanel()
        let isDirectory = entry.id == "filesystem" && field.key == "root"
        panel.canChooseDirectories = isDirectory
        panel.canChooseFiles = !isDirectory
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        let current = model.mcp.value(for: field, of: entry)
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            model.mcp.setDraft(url.path(percentEncoded: false), for: field, of: entry)
        }
    }

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Chrome.success)
                .scaleEffect(successPopped ? 1 : 0.5)
            Text(verbatim: "Connected · \(toolCount) tools")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Chrome.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { successPopped = true }
        }
    }
}

struct MCPIcon: View {
    let entry: MCPCatalogEntry
    var size: CGFloat = 20

    var body: some View {
        Image(entry.asset)
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(entry.isMonochrome ? Chrome.primaryText : entry.color)
            .frame(width: size, height: size)
    }
}
