import AppKit
import SwiftUI

/// Builds Cody's windows the way Droppy builds its settings window: a plain titled AppKit window
/// with a clear background and a SwiftUI glass pane, so no scene background draws a second corner.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    let model = AppModel()

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private enum Size {
        static let main = NSSize(width: 1320, height: 860)
        static let mainMinimum = NSSize(width: 860, height: 560)
        static let settings = NSSize(width: 780, height: 580)
    }

    private static let mainFrameName = "CodyMainWindow"

    func showMain() {
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        present(window)
    }

    func showSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeMainWindow() -> NSWindow {
        let window = makeWindow(title: "Cody", size: Size.main, resizable: true) { RootView() }
        window.contentMinSize = Size.mainMinimum
        if !window.setFrameUsingName(Self.mainFrameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.mainFrameName)
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = makeWindow(title: "Settings", size: Size.settings, resizable: false) { SettingsView() }
        window.center()
        return window
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        resizable: Bool,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.tabbingMode = .disallowed
        WindowChrome.configure(window)

        let hosting = WindowHostingView(rootView: AnyView(HostedRoot(model: model, content: content())))
        hosting.frame = frame
        let container = NSView(frame: frame)
        container.addSubview(hosting)
        window.contentView = container
        return window
    }
}

/// Shared environment for every hosted window, plus the app-wide appearance choice.
private struct HostedRoot<Content: View>: View {
    let model: AppModel
    let content: Content

    var body: some View {
        content
            .environment(model)
            .buttonBorderShape(.capsule)
            .preferredColorScheme(model.settings.appearance.colorScheme)
            .onChange(of: model.settings.appearance, initial: true) { _, appearance in
                NSApp.appearance = switch appearance {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
            }
    }
}

/// Lets the window frame define the hosting view's size instead of the content hugging it.
private final class WindowHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        sizingOptions = []
        safeAreaRegions = []
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
