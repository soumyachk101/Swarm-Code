import AppKit
import SwiftUI

/// Builds Swarm Code's windows the way Swarm Code builds its settings window: a plain titled AppKit window
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

    private static let mainFrameName = "SwarmCodeMainWindow"

    func showMain() {
        let window = mainWindow ?? makeMainWindow()
        mainWindow = window
        present(window)
    }

    func showSettings(page: SettingsPage? = nil) {
        if let page { SettingsNavigation.shared.requestedPage = page }
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        centerOverMainWindow(window)
        present(window)
    }

    /// Opens a window centered over the main window, kept on the screen the main window is on.
    private func centerOverMainWindow(_ window: NSWindow) {
        guard let main = mainWindow, main.isVisible, !main.isMiniaturized else {
            window.center()
            return
        }
        let parent = main.frame
        var frame = window.frame
        frame.origin.x = (parent.midX - frame.width / 2).rounded()
        frame.origin.y = (parent.midY - frame.height / 2).rounded()
        if let visible = (main.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: false)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeMainWindow() -> NSWindow {
        let window = makeWindow(title: "Swarm Code", size: Size.main, resizable: true) { RootView() }
        window.contentMinSize = Size.mainMinimum
        if !window.setFrameUsingName(Self.mainFrameName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.mainFrameName)
        return window
    }

    /// The main window for the website captures: the same window, at a fixed size, with
    /// no frame autosave, so the run never reads or writes where the real window sits.
    func makeCaptureWindow(size: NSSize) -> NSWindow {
        makeWindow(title: "Swarm Code", size: size, resizable: true) { RootView() }
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
        windowClass: NSWindow.Type = NSWindow.self,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        let frame = NSRect(origin: .zero, size: size)
        let window = windowClass.init(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
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
            .preferredColorScheme(model.settings.theme.spec.scheme)
            .modifier(ThemeTint(theme: model.settings.theme))
            .onChange(of: model.settings.theme, initial: true) { _, theme in
                NSApp.appearance = switch theme.spec.scheme {
                case nil: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                @unknown default: nil
                }
            }
    }
}

/// Tints prominent glass buttons, toggles and progress views with the
/// theme's accent. System/Light/Dark keep the system control accent.
private struct ThemeTint: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        if let accent = theme.spec.accent {
            content.tint(accent)
        } else {
            content
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

    /// Every window here holds focusable text (the composer, a search field), so the
    /// answer is always yes. SwiftUI's own answer searches the whole view tree for a
    /// navigable item, and AppKit asks on every display cycle while content scrolls
    /// under the title bar to work out the window's drag region.
    override var acceptsFirstResponder: Bool { true }
}
