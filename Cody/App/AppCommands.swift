import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    private let shortcuts = ShortcutStore.shared

    private var runtime: ThreadRuntime? {
        model.selectedThreadID.map(model.runtime(for:))
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { WindowManager.shared.showSettings() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .openSettings))
        }

        CommandGroup(before: .windowArrangement) {
            Button("Cody") { WindowManager.shared.showMain() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .showMainWindow))
            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button("New thread") { model.newThread() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .newThread))
            Button("New thread in worktree") { model.newThread(workspace: .worktree) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .newWorktreeThread))
            Divider()
            Button("Add project…") { model.chooseProjectFolder() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .addProject))
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle sidebar") { model.sidebar.toggle() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleSidebar))
            Button("Command palette") { model.isCommandPalettePresented.toggle() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .commandPalette))
            Button("Toggle terminal") { runtime?.isTerminalVisible.toggle() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleTerminal))
                .disabled(model.selectedThreadID == nil)
            Button("Toggle changes") { runtime?.isDiffVisible.toggle() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleChanges))
                .disabled(model.selectedThreadID == nil)
            Divider()
        }

        CommandMenu("Thread") {
            Button("Stop") { runtime?.interrupt() }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .stopTurn))
                .disabled(!(runtime?.isRunning ?? false))
            Button("Toggle plan mode") {
                guard let id = model.selectedThreadID else { return }
                model.updateThread(id) { $0.interactionMode = $0.interactionMode == .plan ? .build : .plan }
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .togglePlanMode))
            .disabled(model.selectedThreadID == nil)
            Divider()
            Button("Previous thread") { model.selectThread(offset: -1) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .previousThread))
            Button("Next thread") { model.selectThread(offset: 1) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .nextThread))
            ForEach(1...9, id: \.self) { number in
                Button("Thread \(number)") { model.selectThread(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Divider()
            Button("Archive thread") {
                if let id = model.selectedThreadID { model.archive(id) }
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .archiveThread))
            .disabled(model.selectedThreadID == nil)
        }
    }
}
