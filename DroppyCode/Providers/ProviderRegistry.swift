import Foundation

struct ProviderStatus: Equatable, Sendable {
    enum Auth: Equatable, Sendable {
        case unknown
        case signedIn(String?)
        case signedOut
    }

    var executable: URL?
    var version: String?
    var auth: Auth = .unknown
    var isChecking = false
    /// Native API providers (DeepSeek, Meta) have no CLI; they are installed once an API key exists.
    var apiKeyConfigured = false

    var isInstalled: Bool { executable != nil || apiKeyConfigured }

    var summary: String {
        guard isInstalled else { return "Not installed" }
        switch auth {
        case .signedIn(let account): return account.map { "Signed in as \($0)" } ?? "Signed in"
        case .signedOut: return "Not signed in"
        case .unknown: return version.map { "Installed · \($0)" } ?? "Installed"
        }
    }
}

/// Finds provider CLIs, checks their sign-in state and caches their model catalogs.
@MainActor
@Observable
final class ProviderRegistry {
    private(set) var statuses: [ProviderKind: ProviderStatus] = [:]
    private(set) var catalogs: [ProviderKind: [ModelOption]] = [:]
    private(set) var commands: [ProviderKind: [SlashCommand]] = [:]
    private(set) var loadingCatalogs: Set<ProviderKind> = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let cacheKey = "providerModelCatalogs"
    private(set) var planLimits: [ProviderKind: PlanLimits] = [:]
    private(set) var loadingLimits: Set<ProviderKind> = []
    @ObservationIgnored private var limitsFetchedAt: [ProviderKind: Date] = [:]

    private static let claudeEfforts = ["low", "medium", "high", "xhigh", "max"]
    private static let claudeSeed = [
        ModelOption(id: "default", name: "Default", detail: "Claude Code's recommended model", efforts: claudeEfforts, isDefault: true, fastTier: "fast"),
        ModelOption(id: "opus", name: "Opus", efforts: claudeEfforts, fastTier: "fast"),
        ModelOption(id: "sonnet", name: "Sonnet", efforts: claudeEfforts),
        ModelOption(id: "haiku", name: "Haiku"),
    ]

    static let deepseekEfforts = ["low", "high", "max"]
    static let deepseekSeed = [
        ModelOption(id: "deepseek-v4-pro", name: "V4 Pro", detail: "Best reasoning and coding quality", efforts: deepseekEfforts, defaultEffort: "high", isDefault: true),
        ModelOption(id: "deepseek-flash", name: "V4 Flash", detail: "Fast everyday chat and edits", efforts: deepseekEfforts, defaultEffort: "high"),
    ]

    static let metaEfforts = ["minimal", "low", "medium", "high", "xhigh", "max"]
    static let metaSeed = [
        ModelOption(id: "muse-spark-1.3", name: "Spark 1.3", detail: "Latest Muse Spark · best agentic coding · 1M context", efforts: metaEfforts, defaultEffort: "high", isDefault: true),
        ModelOption(id: "muse-spark-1.3-contributor", name: "Spark 1.3 Contributor", detail: "Same 1.3 checkpoint · discounted contributor tier", efforts: metaEfforts, defaultEffort: "high"),
        ModelOption(id: "muse-spark-1.2", name: "Spark 1.2", detail: "Previous checkpoint · Standard tier · 1M context", efforts: metaEfforts, defaultEffort: "high"),
        ModelOption(id: "muse-spark-1.2-contributor", name: "Spark 1.2 Contributor", detail: "1.2 checkpoint · discounted contributor tier", efforts: metaEfforts, defaultEffort: "high"),
        ModelOption(id: "muse-spark-1.1", name: "Spark 1.1", detail: "Original checkpoint · Standard tier · 1M context", efforts: metaEfforts, defaultEffort: "high"),
    ]

    init(settings: AppSettings) {
        self.settings = settings
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([String: [ModelOption]].self, from: data) {
            for (key, list) in cached {
                if let provider = ProviderKind(rawValue: key) { catalogs[provider] = list }
            }
        }
        if catalogs[.claude]?.isEmpty ?? true { catalogs[.claude] = Self.claudeSeed }
        if catalogs[.deepseek]?.isEmpty ?? true { catalogs[.deepseek] = Self.deepseekSeed }
        if catalogs[.meta]?.isEmpty ?? true { catalogs[.meta] = Self.metaSeed }
    }

    var availableProviders: [ProviderKind] {
        ProviderKind.allCases.filter { settings.isEnabled($0) && (statuses[$0]?.isInstalled ?? true) }
    }

    func status(_ provider: ProviderKind) -> ProviderStatus {
        statuses[provider] ?? ProviderStatus()
    }

    func executable(for provider: ProviderKind) -> URL? {
        guard !provider.isAPIKeyBased else { return nil }
        let custom = settings.binaryPath(for: provider)
        guard !custom.isEmpty || !provider.executableName.isEmpty else { return nil }
        return LoginEnvironment.which(custom.isEmpty ? provider.executableName : custom)
    }

    func environment(for provider: ProviderKind) -> [String: String] {
        var environment = LoginEnvironment.current
        if let directory = executable(for: provider)?.deletingLastPathComponent().path,
           let path = environment["PATH"],
           !path.split(separator: ":").contains(Substring(directory)) {
            environment["PATH"] = directory + ":" + path
        }
        return environment
    }

    @ObservationIgnored private var lastFullRefresh: Date?

    /// Refreshes every provider unless that already happened within the last minute.
    func refreshAllIfStale() async {
        if let lastFullRefresh, Date.now.timeIntervalSince(lastFullRefresh) < 60 { return }
        await refreshAll()
    }

    func refreshAll() async {
        lastFullRefresh = .now
        await withTaskGroup(of: Void.self) { group in
            for provider in ProviderKind.allCases {
                group.addTask { await self.refresh(provider) }
            }
        }
    }

    func refresh(_ provider: ProviderKind) async {
        var status = statuses[provider] ?? ProviderStatus()
        status.isChecking = true
        statuses[provider] = status
        if provider.isAPIKeyBased {
            await refreshAPIProvider(provider)
            return
        }
        guard let executable = executable(for: provider) else {
            statuses[provider] = ProviderStatus()
            return
        }
        let environment = environment(for: provider)
        async let version = Self.version(executable, environment)
        async let auth = Self.auth(provider, executable, environment)
        statuses[provider] = ProviderStatus(executable: executable, version: await version, auth: await auth)
    }

    /// API-key providers have no binary: presence (and validity) of the key is the install state.
    private func refreshAPIProvider(_ provider: ProviderKind) async {
        let apiKey = settings.apiKey(for: provider)
        guard !apiKey.isEmpty else {
            statuses[provider] = ProviderStatus(auth: .signedOut)
            return
        }
        if provider == .deepseek {
            let valid = await DeepSeekAPI.validate(apiKey: apiKey)
            statuses[provider] = ProviderStatus(
                version: "API",
                auth: valid ? .signedIn(nil) : .signedOut,
                apiKeyConfigured: true
            )
        } else if provider == .meta {
            let valid = await MetaAPI.validate(apiKey: apiKey)
            statuses[provider] = ProviderStatus(
                version: "API",
                auth: valid ? .signedIn(nil) : .signedOut,
                apiKeyConfigured: true
            )
        } else {
            statuses[provider] = ProviderStatus(auth: .signedIn(nil), apiKeyConfigured: true)
        }
    }

    // MARK: - Models

    func models(for provider: ProviderKind) -> [ModelOption] {
        catalogs[provider] ?? []
    }

    func model(_ id: String?, for provider: ProviderKind) -> ModelOption? {
        guard let id else { return nil }
        return models(for: provider).first { $0.id == id }
    }

    func defaultModel(for provider: ProviderKind) -> ModelOption? {
        let list = models(for: provider)
        if let last = settings.lastModel(for: provider), let match = list.first(where: { $0.id == last }) {
            return match
        }
        return list.first(where: \.isDefault) ?? list.first
    }

    func loadCatalog(_ provider: ProviderKind, force: Bool = false) async {
        guard provider != .claude else { return }
        guard force || models(for: provider).isEmpty, !loadingCatalogs.contains(provider) else { return }
        if provider.isAPIKeyBased {
            await loadAPICatalog(provider, force: force)
            return
        }
        guard let executable = executable(for: provider) else { return }
        loadingCatalogs.insert(provider)
        defer { loadingCatalogs.remove(provider) }
        let environment = environment(for: provider)
        let list: [ModelOption]? = switch provider {
        case .codex: try? await CodexSession.listModels(executable: executable, environment: environment)
        case .cursor, .opencode, .grok: try? await ACPSession.probeModels(provider: provider, executable: executable, environment: environment)
        case .claude, .deepseek, .meta: nil
        }
        if let list, !list.isEmpty { updateCatalog(list, for: provider) }
    }

    private func loadAPICatalog(_ provider: ProviderKind, force: Bool) async {
        // The seed keeps API providers usable offline; a live fetch only refines it.
        let seed: [ModelOption]? = switch provider {
        case .deepseek: Self.deepseekSeed
        case .meta: Self.metaSeed
        default: nil
        }
        guard let seed else { return }
        if models(for: provider).isEmpty { updateCatalog(seed, for: provider) }
        loadingCatalogs.insert(provider)
        defer { loadingCatalogs.remove(provider) }
        let apiKey = settings.apiKey(for: provider)
        guard !apiKey.isEmpty else { return }
        let list: [ModelOption]? = switch provider {
        case .deepseek: try? await DeepSeekAPI.listModels(apiKey: apiKey)
        case .meta: try? await MetaAPI.listModels(apiKey: apiKey)
        default: nil
        }
        if let list, !list.isEmpty {
            updateCatalog(list, for: provider)
        }
    }

    /// Reads the provider's plan limits, at most once a minute after a successful read unless forced.
    /// The read runs on its own task, so closing the popover that asked for it cannot cancel it.
    func refreshPlanLimits(_ provider: ProviderKind, force: Bool = false) {
        guard PlanLimitsReader.exposesLimits(provider), !loadingLimits.contains(provider),
              let executable = executable(for: provider) else { return }
        if !force, let fetched = limitsFetchedAt[provider], Date.now.timeIntervalSince(fetched) < 60 { return }
        loadingLimits.insert(provider)
        let environment = environment(for: provider)
        Task {
            let limits = await PlanLimitsReader.read(provider, executable: executable, environment: environment)
            loadingLimits.remove(provider)
            guard let limits else { return }
            planLimits[provider] = limits
            limitsFetchedAt[provider] = .now
        }
    }

    func updateCatalog(_ list: [ModelOption], for provider: ProviderKind) {
        guard !list.isEmpty, list != catalogs[provider] else { return }
        catalogs[provider] = list
        let encoded = Dictionary(uniqueKeysWithValues: catalogs.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    func updateCommands(_ list: [SlashCommand], for provider: ProviderKind) {
        commands[provider] = list
    }

    // MARK: - Probes

    private static func version(_ executable: URL, _ environment: [String: String]) async -> String? {
        guard let result = try? await Shell.run(executable, ["--version"], environment: environment, timeout: 20),
              result.succeeded else { return nil }
        let text = TextCleanup.stripANSI(result.output + result.errorOutput)
        if let match = text.firstMatch(of: #/\d+\.\d+(?:\.\d+)?(?:[-.][0-9A-Za-z]+)?/#) {
            return String(match.output)
        }
        return nil
    }

    private static func auth(_ provider: ProviderKind, _ executable: URL, _ environment: [String: String]) async -> ProviderStatus.Auth {
        switch provider {
        case .codex:
            guard let result = try? await Shell.run(executable, ["login", "status"], environment: environment, timeout: 20) else {
                return .unknown
            }
            let text = result.output + result.errorOutput
            return result.succeeded && text.localizedCaseInsensitiveContains("logged in") ? .signedIn(nil) : .signedOut
        case .claude:
            guard let result = try? await Shell.run(executable, ["auth", "status"], environment: environment, timeout: 20),
                  let json = JSONValue.parse(result.stdout) else { return .unknown }
            return json["loggedIn"]?.bool == true ? .signedIn(json["email"]?.string) : .signedOut
        case .cursor:
            guard let result = try? await Shell.run(executable, ["status"], environment: environment, timeout: 20) else {
                return .unknown
            }
            let text = TextCleanup.stripANSI(result.output + result.errorOutput)
            if let match = text.firstMatch(of: #/Logged in as (\S+)/#) { return .signedIn(String(match.output.1)) }
            return text.localizedCaseInsensitiveContains("not logged in") ? .signedOut : .unknown
        case .opencode, .grok, .deepseek, .meta:
            return .unknown
        }
    }
}
