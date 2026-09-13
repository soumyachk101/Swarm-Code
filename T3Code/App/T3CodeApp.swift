import SwiftUI

@main
struct T3CodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        // Provider processes can exit while we write to them; report EPIPE instead of crashing.
        signal(SIGPIPE, SIG_IGN)
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("T3 Code", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .frame(minWidth: 860, minHeight: 560)
                .containerBackground(Color.clear, for: .window)
                .task {
                    delegate.model = model
                    await model.bootstrap()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .containerBackground(Color.clear, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
