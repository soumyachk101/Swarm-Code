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
            MCPLeadCard()
            if !connected.isEmpty {
                ChromeSection(title: "Connected") {
                    VStack(alignment: .leading, spacing: 8) {
                        ChromeCard {
                            ForEach(Array(connected.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { ChromeRowDivider() }
                                MCPConnectedRow(entry: entry)
                            }
                        }
                        // What the connected servers cost: every switched-on tool rides
                        // along in each turn's context, so the count is kept in view.
                        Text(verbatim: costLine)
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 4)
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
            Text("Connected servers reach every provider when a thread starts: the CLIs at launch, the API models through Droppy Code itself.")
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

    /// Tools across the switched-on servers, and a rough token figure for their
    /// definitions: about 80 tokens each for a name, a description and a schema.
    private var costLine: String {
        let enabled = connected.compactMap { model.mcp.connection(for: $0.id) }.filter(\.isEnabled)
        let tools = enabled.reduce(0) { $0 + $1.tools.count }
        guard !enabled.isEmpty, tools > 0 else { return "Switched-off servers add nothing to a turn." }
        let servers = enabled.count == 1 ? "1 server" : "\(enabled.count) servers"
        let rough = (tools * 80 + 50) / 100 * 100
        let tokens = rough >= 1000 ? String(format: "%.1fk", Double(rough) / 1000) : "\(rough)"
        return "\(tools) tools across \(servers) · roughly \(tokens) tokens on every turn. Switch a server off to leave its tools out."
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

private struct MCPLeadCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(Chrome.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Connected servers lead")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text("When you connect a server here, it is the only MCP server your threads use. Anything set up in a terminal or another app's config is left exactly as it is, and stays out of the way until you disconnect.")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                // Stacked: three facts in one line ran past the pane and truncated the last.
                VStack(alignment: .leading, spacing: 4) {
                    fact(symbol: "lock.fill", text: "Keys stay in your Keychain")
                    fact(symbol: "arrow.uturn.backward", text: "Disconnect to go back to your own setup")
                    fact(symbol: "sparkles", text: "Every provider, whatever the model")
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Chrome.primaryText.opacity(0.05))
        )
    }

    private func fact(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(Chrome.accent)
                .frame(width: 14)
            Text(verbatim: text)
        }
        .font(.system(size: 11))
        .foregroundStyle(Chrome.secondaryText)
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
                // Every card keeps the same shape: two lines held for the summary whether
                // it needs them or not, one line of tools, so the grid reads as a grid.
                Text(verbatim: entry.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: entry.sampleTools.isEmpty ? " " : entry.sampleTools.joined(separator: " · "))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Clear of the info button in the corner.
                    .padding(.trailing, 24)
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
        // The cell fills its row: a card whose fields are open makes its neighbour as tall.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Chrome.primaryText.opacity(0.05))
        )
        .overlay(alignment: .bottomTrailing) {
            if !celebrating {
                MCPInfoButton(entry: entry)
                    .padding(10)
            }
        }
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

/// The small `i` in a card's corner: hovering it opens the server's details, and so does a
/// click. The popover stays while the pointer is on it, so its docs link can be reached.
private struct MCPInfoButton: View {
    let entry: MCPCatalogEntry

    @State private var isPresented = false
    @State private var isOverButton = false
    @State private var isOverPopover = false
    @State private var settle: Task<Void, Never>?

    var body: some View {
        Button {
            settle?.cancel()
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Chrome.secondaryText.opacity(isOverButton || isPresented ? 1 : 0.55))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text("About \(entry.name)"))
        .onHover { over in
            isOverButton = over
            reconsider()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MCPInfoPopover(entry: entry)
                .onHover { over in
                    isOverPopover = over
                    reconsider()
                }
                .presentedChrome()
        }
    }

    /// Opens a beat after the pointer arrives, closes a beat after it has left both the
    /// button and the popover: the gap between the two is crossed without it closing.
    private func reconsider() {
        settle?.cancel()
        let wanted = isOverButton || isOverPopover
        guard wanted != isPresented else { return }
        settle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(wanted ? 220 : 320))
            guard !Task.isCancelled, (isOverButton || isOverPopover) == wanted else { return }
            isPresented = wanted
        }
    }
}

/// A server's details: what it is, how it connects, what it needs, the tools it brings,
/// and where its docs are.
private struct MCPInfoPopover: View {
    let entry: MCPCatalogEntry

    private static let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                MCPIcon(entry: entry, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Chrome.primaryText)
                    Text(verbatim: "\(entry.vendor) · \(entry.category.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
            Text(verbatim: entry.summary)
                .font(.system(size: 12))
                .foregroundStyle(Chrome.primaryText.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                detail("Connects", connection)
                detail("Needs", needs)
            }
            if !entry.sampleTools.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tools")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Chrome.secondaryText)
                    FlowChips(entry.sampleTools)
                }
            }
            if let url = URL(string: entry.docsURL) {
                Link(destination: url) {
                    HStack(spacing: 5) {
                        Text("Read the docs")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Chrome.accent)
                }
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 58, alignment: .leading)
            Text(verbatim: value)
                .font(.system(size: 11.5))
                .foregroundStyle(Chrome.primaryText.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connection: String {
        switch entry.transport {
        case .stdio(let command, let args):
            let package = args.first { !$0.hasPrefix("-") } ?? command
            return "Runs on this Mac through \(command) (\(package))."
        case .http(let url, _):
            return "Remote server at \(Self.host(of: url))."
        case .oauth(let url):
            return "Remote server at \(Self.host(of: url)); signs in through your browser the first time."
        }
    }

    private var needs: String {
        let required = entry.fields.filter(\.isRequired).map(\.label)
        let optional = entry.fields.filter { !$0.isRequired }.map(\.label)
        if required.isEmpty && optional.isEmpty { return entry.isOAuth ? "An account to sign in with." : "Nothing, it works right away." }
        var parts: [String] = []
        if !required.isEmpty { parts.append(required.joined(separator: ", ")) }
        if !optional.isEmpty { parts.append("optionally " + optional.joined(separator: ", ").lowercased()) }
        return parts.joined(separator: "; ") + "."
    }

    private static func host(of url: String) -> String {
        URL(string: url)?.host() ?? url
    }
}

/// Monospaced chips wrapping onto as many lines as they need.
private struct FlowChips: View {
    let items: [String]

    init(_ items: [String]) { self.items = items }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(verbatim: item)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Chrome.primaryText.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Chrome.overlay(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

/// Rows of subviews, each as wide as it needs, wrapping at the proposed width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
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
