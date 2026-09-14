import SwiftUI

enum TextGenerationChoice: String, CaseIterable, Identifiable {
    case automatic
    case claude
    case codex
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .claude: "Claude"
        case .codex: "Codex"
        case .off: "Off"
        }
    }
}

/// What the check on a thread row does once you are done with the thread.
enum ThreadFinishAction: String, CaseIterable, Identifiable {
    /// The thread stays in the sidebar, small and grey at the bottom of its list.
    case settle
    /// The thread leaves the sidebar for the Archive page.
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settle: "Settle"
        case .archive: "Archive"
        }
    }

    var detail: String {
        switch self {
        case .settle: "A settled thread drops to the bottom of the sidebar, small and grey, until you reopen it"
        case .archive: "An archived thread leaves the sidebar for the Archive page"
        }
    }
}

/// A model the composer's picker offers.
struct ModelPin: Codable, Hashable, Identifiable, Sendable {
    var provider: ProviderKind
    var modelID: String

    var id: String { "\(provider.rawValue)/\(modelID)" }
}

/// How a model starts in new chats.
struct ModelPreference: Codable, Hashable, Sendable {
    var effort: String?
    var fastMode = false
}

/// Preferences that belong to this Mac, stored in user defaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let defaultProvider = "defaultProvider"
        static let runtimeMode = "defaultRuntimeMode"
        static let workspaceMode = "defaultWorkspaceMode"
        static let notify = "notifyWhenFinished"
        static let chime = "chimeWhenFinished"
        static let confirmDelete = "confirmBeforeDeleting"
        static let threadFinishAction = "threadFinishAction"
        static let settleSound = "settleSound"
        static let showReasoning = "showReasoning"
        static let sidebarActivityView = "sidebarActivityView"
        static let appTheme = "appTheme"
        static let backdropOpacity = "backdropOpacity"
        static let appearance = "appearance"
        static let binaryPaths = "providerBinaryPaths"
        static let disabledProviders = "disabledProviders"
        static let models = "lastModels"
        static let efforts = "lastEfforts"
        static let textGeneration = "textGeneration"
        static let commitInstructions = "commitInstructions"
        static let terminalHeight = "terminalHeight"
        static let modelList = "modelList"
        static let modelPreferences = "modelPreferences"
        static let recentDownloadsPicker = "recentDownloadsPicker"
        static let lastProjectID = "lastProjectID"
        static let deepseekAPIKey = "deepseekAPIKey"
        static let metaAPIKey = "metaAPIKey"
        static let hydraEnabled = "hydraEnabled"
        static let hydraQueueHeads = "hydraQueueHeads"
        static let hydraIsolateHeads = "hydraIsolateHeads"
        static let hydraAutoMerge = "hydraAutoMerge"
        static let hydraAutoClearFinished = "hydraAutoClearFinished"
        static let hydraPairs = "hydraPairs"
    }

    static let modelListLimit = 15

    @ObservationIgnored private let defaults = WebsiteCaptures.defaults ?? .standard

    var defaultProvider: ProviderKind {
        didSet { defaults.set(defaultProvider.rawValue, forKey: Key.defaultProvider) }
    }

    var defaultRuntimeMode: RuntimeMode {
        didSet { defaults.set(defaultRuntimeMode.rawValue, forKey: Key.runtimeMode) }
    }

    var defaultWorkspaceMode: WorkspaceMode {
        didSet { defaults.set(defaultWorkspaceMode.rawValue, forKey: Key.workspaceMode) }
    }

    var notifyWhenFinished: Bool {
        didSet { defaults.set(notifyWhenFinished, forKey: Key.notify) }
    }

    /// A soft chime plays when a turn finishes, whether or not the thread is in view.
    var chimeWhenFinished: Bool {
        didSet { defaults.set(chimeWhenFinished, forKey: Key.chime) }
    }

    var confirmBeforeDeleting: Bool {
        didSet { defaults.set(confirmBeforeDeleting, forKey: Key.confirmDelete) }
    }

    /// What the check on a thread row, ⇧⌘⌫ and the palette's finish action do.
    var threadFinishAction: ThreadFinishAction {
        didSet { defaults.set(threadFinishAction.rawValue, forKey: Key.threadFinishAction) }
    }

    /// A soft note plays as a thread settles.
    var settleSound: Bool {
        didSet { defaults.set(settleSound, forKey: Key.settleSound) }
    }

    var showReasoning: Bool {
        didSet { defaults.set(showReasoning, forKey: Key.showReasoning) }
    }

    /// The sidebar lists every thread by when it was last active, instead of by project.
    var sidebarActivityView: Bool {
        didSet { defaults.set(sidebarActivityView, forKey: Key.sidebarActivityView) }
    }

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Key.appTheme)
            ThemeManager.current = theme
        }
    }

    /// How solid the window's backdrop is, 0 (clear glass, the desktop shows through) to
    /// 1 (a solid base colour). The midpoint is the stock look.
    var backdropOpacity: Double {
        didSet { defaults.set(backdropOpacity, forKey: Key.backdropOpacity) }
    }
    static let defaultBackdropOpacity = 0.5

    var textGeneration: TextGenerationChoice {
        didSet { defaults.set(textGeneration.rawValue, forKey: Key.textGeneration) }
    }

    var commitInstructions: String {
        didSet { defaults.set(commitInstructions, forKey: Key.commitInstructions) }
    }

    var terminalHeight: Double {
        didSet { defaults.set(terminalHeight, forKey: Key.terminalHeight) }
    }

    /// The attach button offers recent downloads first instead of opening Finder straight away.
    var recentDownloadsPicker: Bool {
        didSet { defaults.set(recentDownloadsPicker, forKey: Key.recentDownloadsPicker) }
    }

    /// The folder a new thread opens in when no thread is selected. Updated whenever a thread
    /// is selected or created, so ⌘N stays in the last folder you used.
    var lastProjectID: UUID? {
        didSet {
            if let lastProjectID {
                defaults.set(lastProjectID.uuidString, forKey: Key.lastProjectID)
            } else {
                defaults.removeObject(forKey: Key.lastProjectID)
            }
        }
    }

    /// DeepSeek talks to its cloud API directly, so it needs an API key instead of a CLI login.
    /// Stored in the Keychain when available, with a UserDefaults fallback for migration.
    /// Read once at launch and cached: a Keychain query on every render made Settings lag.
    var deepseekAPIKeyInput: String {
        didSet {
            guard deepseekAPIKeyInput != oldValue else { return }
            DeepSeekKeychain.setAPIKey(deepseekAPIKeyInput)
            storeAPIKeyFallback(deepseekAPIKeyInput, forKey: Key.deepseekAPIKey)
        }
    }

    /// Meta Model API (Muse Spark) talks to https://api.meta.ai/v1 directly,
    /// so it needs a MODEL_API_KEY instead of a CLI login.
    /// Stored in the Keychain when available, with a UserDefaults fallback for migration.
    var metaAPIKeyInput: String {
        didSet {
            guard metaAPIKeyInput != oldValue else { return }
            MetaKeychain.setAPIKey(metaAPIKeyInput)
            storeAPIKeyFallback(metaAPIKeyInput, forKey: Key.metaAPIKey)
        }
    }

    private func storeAPIKeyFallback(_ value: String, forKey key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }

    private(set) var binaryPaths: [String: String] {
        didSet { defaults.set(binaryPaths, forKey: Key.binaryPaths) }
    }

    private(set) var disabledProviders: [String] {
        didSet { defaults.set(disabledProviders, forKey: Key.disabledProviders) }
    }

    private(set) var lastModels: [String: String] {
        didSet { defaults.set(lastModels, forKey: Key.models) }
    }

    private(set) var lastEfforts: [String: String] {
        didSet { defaults.set(lastEfforts, forKey: Key.efforts) }
    }

    private(set) var modelList: [ModelPin] {
        didSet { store(modelList, forKey: Key.modelList) }
    }

    private(set) var modelPreferences: [String: ModelPreference] {
        didSet { store(modelPreferences, forKey: Key.modelPreferences) }
    }

    /// Hydra is on for the app: every chat's chrome row shows its mark while it is on.
    var hydraEnabled: Bool {
        didSet { defaults.set(hydraEnabled, forKey: Key.hydraEnabled) }
    }

    /// With Hydra on, a follow-up queued while a turn runs goes to a head at once
    /// instead of waiting for the turn.
    var hydraQueueHeads: Bool {
        didSet { defaults.set(hydraQueueHeads, forKey: Key.hydraQueueHeads) }
    }

    /// A head Droppy Code runs gets a copy of the checkout of its own, so no head ever
    /// sees another's half-done work; its changes land in the chat's checkout when it
    /// reports. Off, the heads work in the checkout itself.
    var hydraIsolateHeads: Bool {
        didSet { defaults.set(hydraIsolateHeads, forKey: Key.hydraIsolateHeads) }
    }

    /// Once the lead has finished and every head is back, the team's work goes out as a
    /// merge request and lands, and the checkout is brought up to date. Off unless asked.
    var hydraAutoMerge: Bool {
        didSet { defaults.set(hydraAutoMerge, forKey: Key.hydraAutoMerge) }
    }

    /// A head that finishes leaves the Hydra panel on its own, for the sidebar under its
    /// lead, instead of waiting for "Clear finished heads".
    var hydraAutoClearFinished: Bool {
        didSet { defaults.set(hydraAutoClearFinished, forKey: Key.hydraAutoClearFinished) }
    }

    /// The lead-and-heads pairings, in the order they were added.
    private(set) var hydraPairs: [HydraPair] {
        didSet { store(hydraPairs, forKey: Key.hydraPairs) }
    }

    init() {
        let defaults = WebsiteCaptures.defaults ?? .standard
        defaultProvider = ProviderKind(rawValue: defaults.string(forKey: Key.defaultProvider) ?? "") ?? .codex
        defaultRuntimeMode = RuntimeMode(rawValue: defaults.string(forKey: Key.runtimeMode) ?? "") ?? .fullAccess
        defaultWorkspaceMode = WorkspaceMode(rawValue: defaults.string(forKey: Key.workspaceMode) ?? "") ?? .local
        notifyWhenFinished = defaults.object(forKey: Key.notify) as? Bool ?? true
        chimeWhenFinished = defaults.object(forKey: Key.chime) as? Bool ?? true
        confirmBeforeDeleting = defaults.object(forKey: Key.confirmDelete) as? Bool ?? true
        threadFinishAction = ThreadFinishAction(rawValue: defaults.string(forKey: Key.threadFinishAction) ?? "") ?? .settle
        settleSound = defaults.object(forKey: Key.settleSound) as? Bool ?? true
        showReasoning = defaults.object(forKey: Key.showReasoning) as? Bool ?? false
        sidebarActivityView = defaults.bool(forKey: Key.sidebarActivityView)
        backdropOpacity = defaults.object(forKey: Key.backdropOpacity) as? Double ?? Self.defaultBackdropOpacity
        // The old System/Light/Dark choice maps straight onto the same themes.
        let initialTheme = AppTheme(rawValue: defaults.string(forKey: Key.appTheme) ?? "")
            ?? AppTheme(rawValue: defaults.string(forKey: Key.appearance) ?? "")
            ?? .system
        theme = initialTheme
        ThemeManager.current = initialTheme
        textGeneration = TextGenerationChoice(rawValue: defaults.string(forKey: Key.textGeneration) ?? "") ?? .automatic
        commitInstructions = defaults.string(forKey: Key.commitInstructions) ?? ""
        terminalHeight = defaults.object(forKey: Key.terminalHeight) as? Double ?? 260
        recentDownloadsPicker = defaults.object(forKey: Key.recentDownloadsPicker) as? Bool ?? true
        if let stored = defaults.string(forKey: Key.lastProjectID) {
            lastProjectID = UUID(uuidString: stored)
        } else {
            lastProjectID = nil
        }
        deepseekAPIKeyInput = DeepSeekKeychain.apiKey(fallback: defaults.string(forKey: Key.deepseekAPIKey) ?? "")
        metaAPIKeyInput = MetaKeychain.apiKey(fallback: defaults.string(forKey: Key.metaAPIKey) ?? "")
        binaryPaths = defaults.dictionary(forKey: Key.binaryPaths) as? [String: String] ?? [:]
        disabledProviders = defaults.stringArray(forKey: Key.disabledProviders) ?? []
        lastModels = defaults.dictionary(forKey: Key.models) as? [String: String] ?? [:]
        lastEfforts = defaults.dictionary(forKey: Key.efforts) as? [String: String] ?? [:]
        modelList = Self.load([ModelPin].self, forKey: Key.modelList) ?? []
        modelPreferences = Self.load([String: ModelPreference].self, forKey: Key.modelPreferences) ?? [:]
        hydraEnabled = defaults.object(forKey: Key.hydraEnabled) as? Bool ?? false
        hydraQueueHeads = defaults.object(forKey: Key.hydraQueueHeads) as? Bool ?? true
        hydraIsolateHeads = defaults.object(forKey: Key.hydraIsolateHeads) as? Bool ?? true
        hydraAutoMerge = defaults.object(forKey: Key.hydraAutoMerge) as? Bool ?? false
        hydraAutoClearFinished = defaults.object(forKey: Key.hydraAutoClearFinished) as? Bool ?? false
        hydraPairs = Self.load([Lenient<HydraPair>].self, forKey: Key.hydraPairs)?.compactMap(\.value) ?? []
    }

    // MARK: - Hydra pairs

    func addHydraPair(_ pair: HydraPair) {
        hydraPairs.append(pair)
    }

    func updateHydraPair(_ id: UUID, _ change: (inout HydraPair) -> Void) {
        guard let index = hydraPairs.firstIndex(where: { $0.id == id }) else { return }
        var pair = hydraPairs[index]
        change(&pair)
        pair.maxHeads = min(max(pair.maxHeads, HydraPair.maxHeadsRange.lowerBound), HydraPair.maxHeadsRange.upperBound)
        guard pair != hydraPairs[index] else { return }
        hydraPairs[index] = pair
    }

    func removeHydraPair(_ id: UUID) {
        hydraPairs.removeAll { $0.id == id }
    }

    func hydraPair(_ id: UUID?) -> HydraPair? {
        guard let id else { return nil }
        return hydraPairs.first { $0.id == id }
    }

    /// The pair a chat leads with: the one for its provider whose lead model is the chat's,
    /// else one for any model on the provider, else the provider's first pair.
    func hydraPair(for provider: ProviderKind, model: String?) -> HydraPair? {
        let candidates = hydraPairs.filter { $0.provider == provider }
        if let model, let exact = candidates.first(where: { $0.orchestratorModel == model }) { return exact }
        if let any = candidates.first(where: { $0.orchestratorModel == nil }) { return any }
        return candidates.first
    }

    // MARK: - Model picker

    func isInModelList(_ pin: ModelPin) -> Bool {
        modelList.contains(pin)
    }

    func addToModelList(_ pin: ModelPin) {
        guard !modelList.contains(pin), modelList.count < Self.modelListLimit else { return }
        modelList.append(pin)
    }

    func removeFromModelList(_ pin: ModelPin) {
        modelList.removeAll { $0 == pin }
    }

    /// Moves `pin` to sit right before or after `target`; returns whether the list changed.
    @discardableResult
    func moveModel(_ pin: ModelPin, to target: ModelPin, placeAfter: Bool) -> Bool {
        guard pin != target,
              let from = modelList.firstIndex(of: pin),
              let to = modelList.firstIndex(of: target) else { return false }
        var dest = to + (placeAfter ? 1 : 0)
        if from < dest { dest -= 1 }
        guard from != dest else { return false }
        let moved = modelList.remove(at: from)
        modelList.insert(moved, at: dest)
        return true
    }

    func preference(for provider: ProviderKind, model: String?) -> ModelPreference {
        guard let model else { return ModelPreference() }
        return modelPreferences[ModelPin(provider: provider, modelID: model).id] ?? ModelPreference()
    }

    func setPreference(_ preference: ModelPreference, for provider: ProviderKind, model: String) {
        let key = ModelPin(provider: provider, modelID: model).id
        modelPreferences[key] = preference == ModelPreference() ? nil : preference
    }

    private func store<Value: Encodable>(_ value: Value, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = (WebsiteCaptures.defaults ?? .standard).data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func binaryPath(for provider: ProviderKind) -> String {
        binaryPaths[provider.rawValue] ?? ""
    }

    func setBinaryPath(_ path: String, for provider: ProviderKind) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        binaryPaths[provider.rawValue] = trimmed.isEmpty ? nil : trimmed
    }

    func isEnabled(_ provider: ProviderKind) -> Bool {
        !disabledProviders.contains(provider.rawValue)
    }

    func setEnabled(_ enabled: Bool, for provider: ProviderKind) {
        disabledProviders.removeAll { $0 == provider.rawValue }
        if !enabled { disabledProviders.append(provider.rawValue) }
    }

    func lastModel(for provider: ProviderKind) -> String? {
        lastModels[provider.rawValue]
    }

    func lastEffort(for provider: ProviderKind) -> String? {
        lastEfforts[provider.rawValue]
    }

    func remember(model: String?, effort: String?, for provider: ProviderKind) {
        lastModels[provider.rawValue] = model
        lastEfforts[provider.rawValue] = effort
    }

    /// The API key Droppy Code sends to an API-key provider: the value from Settings,
    /// falling back to the provider's env var from the login environment
    /// (`DEEPSEEK_API_KEY` for DeepSeek, `MODEL_API_KEY` for Meta).
    func apiKey(for provider: ProviderKind) -> String {
        let stored: String = switch provider {
        case .deepseek: deepseekAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        case .meta: metaAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        default: ""
        }
        if !stored.isEmpty { return stored }
        guard provider.isAPIKeyBased, let envVar = provider.apiKeyEnvVar else { return "" }
        return (LoginEnvironment.current[envVar] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasAPIKey(for provider: ProviderKind) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    /// Settings-bound value for the Providers page, per API-key provider.
    func apiKeyInput(for provider: ProviderKind) -> String {
        switch provider {
        case .deepseek: deepseekAPIKeyInput
        case .meta: metaAPIKeyInput
        default: ""
        }
    }

    func setAPIKeyInput(_ value: String, for provider: ProviderKind) {
        switch provider {
        case .deepseek: deepseekAPIKeyInput = value
        case .meta: metaAPIKeyInput = value
        default: break
        }
    }
}
