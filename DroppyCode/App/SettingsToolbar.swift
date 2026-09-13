import AppKit
import Observation

/// The settings window's search: the current page's prompt, or nil when the page has nothing to
/// search, and what has been typed into the toolbar field.
@MainActor
@Observable
final class SettingsSearch {
    static let shared = SettingsSearch()

    var query = "" {
        didSet { if query != oldValue { toolbar?.sync() } }
    }

    var prompt: String? {
        didSet { if prompt != oldValue { toolbar?.sync() } }
    }

    @ObservationIgnored weak var toolbar: SettingsToolbar?
}

/// The settings window's toolbar. It holds only AppKit's own search item, so the field is the system
/// search field with its Liquid Glass capsule, and the toolbar shows only on pages that can be searched.
@MainActor
final class SettingsToolbar: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    private static let searchIdentifier = NSToolbarItem.Identifier("droppycode.settings.search")

    private let toolbar = NSToolbar(identifier: "DroppyCodeSettings")
    private let search: SettingsSearch
    private weak var window: NSWindow?
    private var searchItem: NSSearchToolbarItem?

    init(window: NSWindow) {
        search = SettingsSearch.shared
        self.window = window
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.isVisible = search.prompt != nil
        window.toolbarStyle = .unified
        window.toolbar = toolbar
        search.toolbar = self
        sync()
    }

    func sync() {
        let isVisible = search.prompt != nil
        if toolbar.isVisible != isVisible {
            toolbar.isVisible = isVisible
            // Showing or hiding the toolbar lays the title bar out again; keep the window buttons pinned.
            if let window {
                WindowChrome.placeTrafficLights(on: window, sidebarVisible: true, animated: false)
            }
        }
        guard let field = searchItem?.searchField else { return }
        if let prompt = search.prompt, field.placeholderString != prompt {
            field.placeholderString = prompt
            field.setAccessibilityLabel(prompt)
        }
        if field.stringValue != search.query {
            field.stringValue = search.query
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.searchIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.searchIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.searchIdentifier else { return nil }
        let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
        // The search item stretches to fill the toolbar, so without a cap it
        // balloons across the title bar. Pin the field to the preferred width.
        let width: CGFloat = 240
        item.preferredWidthForSearchField = width
        item.resignsFirstResponderWithCancel = true
        let field = item.searchField
        field.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.placeholderString = search.prompt
        field.stringValue = search.query
        field.delegate = self
        searchItem = item
        return item
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField, field.stringValue != search.query else { return }
        search.query = field.stringValue
    }

    /// The clear button and Escape end searching without typing, so they report here.
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        if !search.query.isEmpty {
            search.query = ""
        }
    }
}
