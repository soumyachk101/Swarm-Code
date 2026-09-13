import AppKit
import SwiftUI
import UserNotifications

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// The app's library of projects and threads, plus everything that spans threads.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let providers: ProviderRegistry
    let terminals: TerminalStore
    let sidebar: SidebarLayout

    private(set) var projects: [Project] = []
    private(set) var threads: [ChatThread] = []
    var selectedThreadID: UUID? {
        didSet {
            if let selectedThreadID { markRead(selectedThreadID) }
        }
    }
    var isCommandPalettePresented = false
    var alert: AppAlert?

    @ObservationIgnored private var runtimes: [UUID: ThreadRuntime] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var didRequestNotifications = false

    init() {
        settings = AppSettings()
        providers = ProviderRegistry(settings: settings)
        terminals = TerminalStore()
        sidebar = SidebarLayout()
        let library = Storage.loadLibrary()
        projects = library.projects
        threads = library.threads
        for index in threads.indices where threads[index].lastStatus == .running {
            threads[index].lastStatus = .interrupted
        }
    }

    func bootstrap() async {
        await LoginEnvironment.load()
        await providers.refreshAll()
        if providers.status(.codex).isInstalled {
            await providers.loadCatalog(.codex)
        }
    }

    // MARK: - Lookup

    func project(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    func thread(_ id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    var selectedThread: ChatThread? {
        selectedThreadID.flatMap(thread)
    }

    var currentProject: Project? {
        selectedThread.flatMap { project($0.projectID) } ?? projects.first
    }

    func threads(in project: Project) -> [ChatThread] {
        threads
            .filter { $0.projectID == project.id && !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                switch (lhs.sortOrder, rhs.sortOrder) {
                case let (left?, right?) where left != right: return left < right
                // Threads created after a reorder have no place yet and stay on top.
                case (nil, .some): return true
                case (.some, nil): return false
                default: return lhs.createdAt > rhs.createdAt
                }
            }
    }

    /// Places a thread directly above or below another thread in the same project.
    func moveThread(_ id: UUID, to targetID: UUID, placeAfter: Bool) {
        guard id != targetID, let moving = thread(id), let target = thread(targetID),
              moving.projectID == target.projectID, let project = project(moving.projectID) else { return }
        var order = threads(in: project).map(\.id)
        order.removeAll { $0 == id }
        guard let index = order.firstIndex(of: targetID) else { return }
        order.insert(id, at: placeAfter ? index + 1 : index)
        if moving.isPinned != target.isPinned {
            updateThread(id) { $0.isPinned = target.isPinned }
        }
        for (position, threadID) in order.enumerated() {
            updateThread(threadID) { $0.sortOrder = Double(position) }
        }
    }

    var archivedThreads: [ChatThread] {
        threads.filter(\.isArchived).sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Threads in the order the sidebar shows them, for keyboard navigation.
    var sidebarThreads: [ChatThread] {
        projects.filter(\.isExpanded).flatMap { threads(in: $0) }
    }

    func runtime(for id: UUID) -> ThreadRuntime {
        if let runtime = runtimes[id] { return runtime }
        let runtime = ThreadRuntime(threadID: id, app: self)
        runtimes[id] = runtime
        return runtime
    }

    func existingRuntime(for id: UUID) -> ThreadRuntime? {
        runtimes[id]
    }

    var workingDirectory: String? {
        guard let thread = selectedThread, let project = project(thread.projectID) else { return nil }
        return thread.worktreePath ?? project.path
    }

    // MARK: - Projects

    @discardableResult
    func addProject(at url: URL) -> Project {
        let path = url.standardizedFileURL.path
        if let existing = projects.first(where: { $0.path == path }) { return existing }
        var project = Project(name: url.lastPathComponent, path: path)
        project.scripts = ProjectFile.scripts(at: url)
        projects.append(project)
        scheduleSave()
        return project
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add project"
        panel.message = "Choose a folder for your agents to work in."
        guard panel.runModal() == .OK else { return }
        var added: Project?
        for url in panel.urls { added = addProject(at: url) }
        if let added { newThread(in: added) }
    }

    func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var project = projects[index]
        change(&project)
        guard project != projects[index] else { return }
        projects[index] = project
        scheduleSave()
    }

    func removeProject(_ project: Project) {
        for thread in threads where thread.projectID == project.id {
            discardThreadState(thread)
        }
        threads.removeAll { $0.projectID == project.id }
        projects.removeAll { $0.id == project.id }
        if selectedThread == nil { selectedThreadID = nil }
        scheduleSave()
    }

    // MARK: - Threads

    @discardableResult
    func newThread(in project: Project? = nil, workspace: WorkspaceMode? = nil) -> ChatThread? {
        guard let project = project ?? currentProject else {
            chooseProjectFolder()
            return nil
        }
        let current = selectedThread
        let installed = ProviderKind.allCases.filter { providers.status($0).isInstalled && settings.isEnabled($0) }
        var provider = current?.provider ?? settings.defaultProvider
        if !installed.isEmpty, !installed.contains(provider) { provider = installed[0] }
        let carriesModel = current?.provider == provider
        let model = carriesModel ? current?.model : providers.defaultModel(for: provider)?.id
        let preference = settings.preference(for: provider, model: model)
        let effort = carriesModel ? current?.effort : (preference.effort ?? settings.lastEffort(for: provider))
        let fastMode = carriesModel ? (current?.fastMode ?? false) : preference.fastMode
        let thread = ChatThread(
            projectID: project.id,
            provider: provider,
            model: model,
            effort: effort,
            runtimeMode: settings.defaultRuntimeMode,
            fastMode: fastMode
        )
        threads.append(thread)
        updateProject(project.id) { $0.isExpanded = true }
        selectedThreadID = thread.id
        scheduleSave()
        if (workspace ?? settings.defaultWorkspaceMode) == .worktree {
            Task { await createWorktree(for: thread.id) }
        }
        return thread
    }

    func updateThread(_ id: UUID, _ change: (inout ChatThread) -> Void) {
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        change(&thread)
        guard thread != threads[index] else { return }
        threads[index] = thread
        scheduleSave()
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateThread(id) {
            $0.title = trimmed
            $0.hasCustomTitle = true
        }
    }

    func archive(_ id: UUID) {
        if selectedThreadID == id { selectNeighbor(of: id) }
        existingRuntime(for: id)?.stopSession()
        updateThread(id) {
            $0.isArchived = true
            $0.isPinned = false
        }
    }

    func unarchive(_ id: UUID) {
        updateThread(id) { $0.isArchived = false }
    }

    func delete(_ id: UUID, removeWorktree: Bool = false) {
        guard let thread = thread(id) else { return }
        if selectedThreadID == id { selectNeighbor(of: id) }
        discardThreadState(thread)
        threads.removeAll { $0.id == id }
        if let project = project(thread.projectID) {
            let git = Git(project.path)
            let worktree = removeWorktree ? thread.worktreePath : nil
            Task {
                await git.deleteCheckpoints(thread: id)
                if let worktree { try? await git.removeWorktree(at: worktree) }
            }
        }
        scheduleSave()
    }

    private func discardThreadState(_ thread: ChatThread) {
        runtimes[thread.id]?.stopSession()
        runtimes[thread.id] = nil
        terminals.closeAll(for: thread.id)
        Storage.deleteDocument(thread.id)
    }

    private func selectNeighbor(of id: UUID) {
        let order = sidebarThreads
        guard let index = order.firstIndex(where: { $0.id == id }) else {
            selectedThreadID = nil
            return
        }
        let neighbor = order.indices.contains(index + 1) ? order[index + 1] : (index > 0 ? order[index - 1] : nil)
        selectedThreadID = neighbor?.id
    }

    func selectThread(offset: Int) {
        let order = sidebarThreads
        guard !order.isEmpty else { return }
        guard let current = selectedThreadID, let index = order.firstIndex(where: { $0.id == current }) else {
            selectedThreadID = order.first?.id
            return
        }
        selectedThreadID = order[(index + offset + order.count) % order.count].id
    }

    func selectThread(number: Int) {
        let order = sidebarThreads
        guard order.indices.contains(number - 1) else { return }
        selectedThreadID = order[number - 1].id
    }

    func createWorktree(for threadID: UUID) async {
        guard let thread = thread(threadID), thread.worktreePath == nil, let project = project(thread.projectID) else { return }
        let git = Git(project.path)
        guard await git.isRepository(), await git.hasCommits() else {
            alert = AppAlert(title: "Worktree unavailable", message: "New worktrees need a git repository with at least one commit.")
            return
        }
        let suffix = String(threadID.uuidString.lowercased().prefix(8))
        let folder = project.name.replacingOccurrences(of: " ", with: "-").lowercased()
        let path = Storage.worktreesDirectory.appendingPathComponent("\(folder)-\(suffix)").path
        let branch = "droppy-code/\(suffix)"
        let base = await git.status()?.branch
        do {
            try await git.addWorktree(at: path, branch: branch, base: base)
            updateThread(threadID) {
                $0.worktreePath = path
                $0.branch = branch
            }
            for script in project.scripts where script.runOnWorktreeCreate {
                terminals.run(script, threadID: threadID, directory: path)
                runtime(for: threadID).isTerminalVisible = true
            }
        } catch {
            alert = AppAlert(title: "Could not create a worktree", message: error.localizedDescription)
        }
    }

    // MARK: - Attention

    func threadNeedsAttention(_ id: UUID) {
        guard !(NSApp.isActive && selectedThreadID == id), let thread = thread(id) else { return }
        notify(threadID: id, title: thread.title, body: "Waiting for your decision.")
        NSApp.requestUserAttention(.informationalRequest)
    }

    func turnFinished(_ id: UUID, status: TurnStatus) {
        let isVisible = NSApp.isActive && selectedThreadID == id
        updateThread(id) {
            $0.lastStatus = status
            $0.updatedAt = .now
            if !isVisible { $0.hasUnread = true }
        }
        updateDockBadge()
        guard !isVisible, settings.notifyWhenFinished, let thread = thread(id) else { return }
        let body = switch status {
        case .completed: "Finished."
        case .interrupted: "Stopped."
        case .failed: "Stopped with an error."
        case .running: ""
        }
        notify(threadID: id, title: thread.title, body: body)
    }

    func markRead(_ id: UUID) {
        guard thread(id)?.hasUnread == true else { return }
        updateThread(id) { $0.hasUnread = false }
        updateDockBadge()
    }

    func requestNotificationPermission() {
        guard !didRequestNotifications else { return }
        didRequestNotifications = true
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    private func notify(threadID: UUID, title: String, body: String) {
        requestNotificationPermission()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["threadID": threadID.uuidString]
        let request = UNNotificationRequest(identifier: threadID.uuidString, content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    private func updateDockBadge() {
        let unread = threads.count { $0.hasUnread && !$0.isArchived }
        NSApp.dockTile.badgeLabel = unread > 0 ? String(unread) : nil
    }

    // MARK: - Text generation

    func textEngine(preferring provider: ProviderKind?) -> TextGeneration.Engine? {
        func claude() -> TextGeneration.Engine? {
            guard providers.status(.claude).auth != .signedOut, let executable = providers.executable(for: .claude) else { return nil }
            return .claude(executable: executable, environment: providers.environment(for: .claude))
        }
        func codex() -> TextGeneration.Engine? {
            guard providers.status(.codex).auth != .signedOut,
                  let executable = providers.executable(for: .codex),
                  let model = providers.defaultModel(for: .codex)?.id else { return nil }
            return .codex(executable: executable, environment: providers.environment(for: .codex), model: model)
        }
        switch settings.textGeneration {
        case .off: return nil
        case .claude: return claude()
        case .codex: return codex()
        case .automatic: return provider == .codex ? (codex() ?? claude()) : (claude() ?? codex())
        }
    }

    // MARK: - Persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveLibrary()
        }
    }

    private func saveLibrary() {
        var library = Library()
        library.projects = projects
        library.threads = threads
        guard let data = try? JSONEncoder.storage.encode(library) else { return }
        Task { await DiskWriter.shared.write(data, to: Storage.libraryURL) }
    }

    /// Writes everything synchronously, for use while the app terminates.
    func saveBeforeQuit() {
        var library = Library()
        library.projects = projects
        library.threads = threads
        if let data = try? JSONEncoder.storage.encode(library) {
            try? data.write(to: Storage.libraryURL, options: .atomic)
        }
        for runtime in runtimes.values {
            runtime.stopSession()
            var document = ThreadDocument(threadID: runtime.threadID)
            document.items = runtime.entries.map(\.item)
            document.turns = runtime.turns
            document.usage = runtime.usage
            if let data = try? JSONEncoder.storage.encode(document) {
                try? data.write(to: Storage.threadURL(runtime.threadID), options: .atomic)
            }
        }
        terminals.terminateAll()
    }
}

/// Reads project scripts from `droppy-code.json` at the project root.
enum ProjectFile {
    static func scripts(at url: URL) -> [ProjectScript] {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("droppy-code.json")),
              let json = JSONValue.parse(data) else { return [] }
        return (json["scripts"]?.array ?? []).compactMap { script in
            guard let name = script["name"]?.string, let command = script["command"]?.string else { return nil }
            return ProjectScript(
                name: name,
                command: command,
                symbol: symbol(for: script["icon"]?.string),
                runOnWorktreeCreate: script["runOnWorktreeCreate"]?.bool ?? false
            )
        }
    }

    static func symbol(for icon: String?) -> String {
        switch icon {
        case "test": "checkmark.seal"
        case "lint": "wand.and.stars"
        case "configure": "gearshape"
        case "build": "hammer"
        case "debug": "ant"
        default: "play"
        }
    }
}
