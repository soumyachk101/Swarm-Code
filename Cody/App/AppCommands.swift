import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    private var runtime: ThreadRuntime? {
        model.selectedThreadID.map(model.runtime(for:))
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { WindowManager.shared.showSettings() }
                .keyboardShortcut(",")
        }

        CommandGroup(before: .windowArrangement) {
            Button("Cody") { WindowManager.shared.showMain() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button("New thread") { model.newThread() }
                .keyboardShortcut("n")
            Button("New thread in worktree") { model.newThread(workspace: .worktree) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Add project…") { model.chooseProjectFolder() }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle sidebar") { model.sidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button("Command palette") { model.isCommandPalettePresented.toggle() }
                .keyboardShortcut("k")
            Button("Toggle terminal") { runtime?.isTerminalVisible.toggle() }
                .keyboardShortcut("j")
                .disabled(model.selectedThreadID == nil)
            Button("Toggle changes") { runtime?.isDiffVisible.toggle() }
                .keyboardShortcut("d")
                .disabled(model.selectedThreadID == nil)
            Divider()
        }

        CommandMenu("Thread") {
            Button("Stop") { runtime?.interrupt() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!(runtime?.isRunning ?? false))
            Button("Toggle plan mode") {
                guard let id = model.selectedThreadID else { return }
                model.updateThread(id) { $0.interactionMode = $0.interactionMode == .plan ? .build : .plan }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(model.selectedThreadID == nil)
            Divider()
            Button("Previous thread") { model.selectThread(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Next thread") { model.selectThread(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            ForEach(1...9, id: \.self) { number in
                Button("Thread \(number)") { model.selectThread(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
            }
            Divider()
            Button("Archive thread") {
                if let id = model.selectedThreadID { model.archive(id) }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
            .disabled(model.selectedThreadID == nil)
        }
    }
}
