import SwiftUI

struct CommandPalette: View {
    @Environment(AppModel.self) private var model

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private struct Item: Identifiable {
        let id: String
        let title: String
        var subtitle: String?
        let symbol: String
        var shortcut: String?
        let perform: () -> Void
    }

    var body: some View {
        let items = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.06)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search threads, projects and actions", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($isFocused)
                        .onSubmit { run(items) }
                        .onKeyPress(.upArrow) {
                            selection = max(0, selection - 1)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            selection = min(max(0, items.count - 1), selection + 1)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                if !items.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == selection)
                                .onTapGesture {
                                    selection = index
                                    run(items)
                                }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }
            .frame(width: 600)
            .glassEffect(.regular, in: .rect(cornerRadius: 24, style: .continuous))
            .padding(.top, 72)
        }
        .onAppear { isFocused = true }
        .onChange(of: query) { selection = 0 }
    }

    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .frame(width: 18)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(Color.clear), in: .rect(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
    }

    private var results: [Item] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        var actions = [
            Item(id: "new-thread", title: "New thread", symbol: "square.and.pencil", shortcut: "⌘N") { model.newThread() },
            Item(id: "new-worktree", title: "New thread in worktree", symbol: "arrow.triangle.branch", shortcut: "⇧⌘N") {
                model.newThread(workspace: .worktree)
            },
            Item(id: "add-project", title: "Add project", symbol: "folder.badge.plus", shortcut: "⌘O") { model.chooseProjectFolder() },
        ]
        if let threadID = model.selectedThreadID {
            let runtime = model.runtime(for: threadID)
            actions.append(Item(id: "terminal", title: "Toggle terminal", symbol: "terminal", shortcut: "⌘J") {
                runtime.isTerminalVisible.toggle()
            })
            actions.append(Item(id: "changes", title: "Toggle changes", symbol: "plusminus", shortcut: "⌘D") {
                runtime.toggleDiff()
            })
            actions.append(Item(id: "archive", title: "Archive thread", symbol: "archivebox", shortcut: "⇧⌘⌫") {
                model.archive(threadID)
            })
            if model.settings.hydraEnabled, let thread = model.thread(threadID), !thread.isHelper {
                let isOn = thread.hydraEnabled
                actions.append(Item(id: "hydra", title: isOn ? "Turn off Hydra" : "Turn on Hydra", symbol: "point.3.connected.trianglepath.dotted") {
                    model.setHydra(!isOn, for: threadID)
                })
            }
        }
        actions.append(Item(id: "settings", title: "Settings", symbol: "gearshape", shortcut: "⌘,") { WindowManager.shared.showSettings() })

        let matchingActions = needle.isEmpty ? actions : actions.filter { $0.title.lowercased().contains(needle) }
        let threads = model.threads
            .filter { !$0.isArchived && !$0.isInPanel && (needle.isEmpty || $0.title.lowercased().contains(needle)) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(needle.isEmpty ? 6 : 10)
            .map { thread in
                Item(id: thread.id.uuidString, title: thread.title, subtitle: model.project(thread.projectID)?.name, symbol: "bubble.left") {
                    model.selectedThreadID = thread.id
                }
            }
        let projects = needle.isEmpty ? [] : model.projects
            .filter { $0.name.lowercased().contains(needle) }
            .map { project in
                Item(id: project.id.uuidString, title: "New thread in \(project.name)", subtitle: project.path, symbol: "folder") {
                    model.newThread(in: project)
                }
            }
        let ordered = needle.isEmpty ? Array(threads) + matchingActions : matchingActions + Array(threads) + projects
        return Array(ordered.prefix(12))
    }

    private func run(_ items: [Item]) {
        guard items.indices.contains(selection) else { return }
        let item = items[selection]
        close()
        item.perform()
    }

    private func close() {
        model.isCommandPalettePresented = false
    }
}
