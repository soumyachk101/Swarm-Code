import Foundation

/// A pair worth having, written as a recipe: which provider leads, on what kind of model
/// and at what effort, and which runs the heads. A recipe is resolved against the
/// providers this Mac has set up and the models their catalogs list, so the cookbook
/// only offers pairs that will run.
struct HydraPairRecipe: Identifiable, Sendable {
    struct Side: Sendable {
        let provider: ProviderKind
        /// Names to look for in the provider's catalog, best first; none means the
        /// provider's default model (for the lead, whatever the chat is on).
        let models: [String]
        /// The effort asked for, kept only when the model found offers it.
        let effort: String?
    }

    let id: String
    let title: String
    let tagline: String
    let lead: Side
    let heads: Side
    let maxHeads: Int?
}

enum HydraCookbook {
    /// The best pairs, strongest first.
    static let recipes: [HydraPairRecipe] = [
        HydraPairRecipe(id: "claude-opus-sonnet", title: "Deep thinker, quick hands", tagline: "Opus plans and checks at full effort; Sonnet heads do the legwork.", lead: .init(provider: .claude, models: ["Opus"], effort: "max"), heads: .init(provider: .claude, models: ["Sonnet"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-opus-opus", title: "All Opus", tagline: "The strongest lead and the strongest heads, for the jobs that matter most.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .claude, models: ["Opus"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-gemini", title: "Claude leads, Gemini sprints", tagline: "A careful Claude lead over a fast Gemini Flash team: many quick heads at once.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .antigravity, models: ["Gemini 3.8 Flash", "Flash"], effort: "medium"), maxHeads: 6),
        HydraPairRecipe(id: "claude-commandcode", title: "Claude leads Command Code", tagline: "Opus writes the briefs; Muse Spark heads on Command Code run them side by side.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .commandcode, models: ["Muse Spark 1.3 Contributor", "Spark"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-deepseek", title: "Careful lead, thrifty heads", tagline: "Opus leads; DeepSeek Flash heads keep the bill small on the routine parts.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .deepseek, models: ["Flash"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "codex-codex", title: "Codex team", tagline: "A Codex lead on high sends Codex heads out at a working effort.", lead: .init(provider: .codex, models: [], effort: "high"), heads: .init(provider: .codex, models: [], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "codex-claude", title: "Codex leads Claude", tagline: "A Codex lead with Sonnet heads: two labs on one job.", lead: .init(provider: .codex, models: [], effort: "high"), heads: .init(provider: .claude, models: ["Sonnet"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "gemini-gemini", title: "Gemini all the way", tagline: "Gemini Pro leads; Gemini Flash heads sprint.", lead: .init(provider: .antigravity, models: ["Gemini 3.1 Pro", "Pro"], effort: "high"), heads: .init(provider: .antigravity, models: ["Gemini 3.8 Flash", "Flash"], effort: "medium"), maxHeads: 6),
        HydraPairRecipe(id: "commandcode-commandcode", title: "Command Code team", tagline: "Claude Opus 5 leads on Command Code; Muse Spark heads build alongside.", lead: .init(provider: .commandcode, models: ["Claude Opus 5", "Opus"], effort: "high"), heads: .init(provider: .commandcode, models: ["Muse Spark 1.3 Contributor", "Spark"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "copilot", title: "Copilot picks", tagline: "Copilot chooses the model for the lead and for every head.", lead: .init(provider: .copilot, models: [], effort: nil), heads: .init(provider: .copilot, models: [], effort: nil), maxHeads: nil),
        HydraPairRecipe(id: "deepseek", title: "DeepSeek team", tagline: "V4 Pro leads at high; V4.1 Flash heads at medium.", lead: .init(provider: .deepseek, models: ["Pro"], effort: "high"), heads: .init(provider: .deepseek, models: ["Flash"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "meta", title: "Spark team", tagline: "Spark 1.3 leads; Spark 1.3 Contributor heads build.", lead: .init(provider: .meta, models: ["Spark 1.3"], effort: "high"), heads: .init(provider: .meta, models: ["Contributor"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "pi", title: "pi team", tagline: "pi leads and runs its heads on whatever it is set to.", lead: .init(provider: .pi, models: [], effort: "high"), heads: .init(provider: .pi, models: [], effort: "medium"), maxHeads: nil),
    ]

    /// Whether a provider is set up and switched on here.
    @MainActor static func isReady(_ provider: ProviderKind, registry: ProviderRegistry, settings: AppSettings) -> Bool {
        settings.isEnabled(provider) && registry.status(provider).isInstalled
    }

    /// The provider a recipe still needs, if either of its two is not ready.
    @MainActor static func missingProvider(for recipe: HydraPairRecipe, registry: ProviderRegistry, settings: AppSettings) -> ProviderKind? {
        if !isReady(recipe.lead.provider, registry: registry, settings: settings) { return recipe.lead.provider }
        if !isReady(recipe.heads.provider, registry: registry, settings: settings) { return recipe.heads.provider }
        return nil
    }

    /// The pair a recipe makes on this Mac, or nil while a provider it needs is not ready.
    @MainActor static func resolve(_ recipe: HydraPairRecipe, registry: ProviderRegistry, settings: AppSettings) -> HydraPair? {
        guard missingProvider(for: recipe, registry: registry, settings: settings) == nil else { return nil }
        var pair = HydraPair(provider: recipe.lead.provider)
        let lead = model(named: recipe.lead.models, for: recipe.lead.provider, registry: registry)
        pair.orchestratorModel = lead?.id
        pair.orchestratorEffort = effort(recipe.lead.effort, for: lead ?? registry.defaultModel(for: recipe.lead.provider))
        if recipe.heads.provider != recipe.lead.provider { pair.workerProvider = recipe.heads.provider }
        let heads = model(named: recipe.heads.models, for: recipe.heads.provider, registry: registry)
        pair.workerModel = heads?.id
        pair.workerEffort = effort(recipe.heads.effort, for: heads ?? registry.defaultModel(for: recipe.heads.provider))
        pair.maxHeads = recipe.maxHeads
        return pair
    }

    /// The first catalog model whose name or id contains one of the names, best name first.
    @MainActor static func model(named names: [String], for provider: ProviderKind, registry: ProviderRegistry) -> ModelOption? {
        let options = registry.models(for: provider)
        for name in names {
            if let match = options.first(where: { $0.name.localizedCaseInsensitiveContains(name) || $0.id.localizedCaseInsensitiveContains(name) }) {
                return match
            }
        }
        return nil
    }

    /// The effort asked for when the model offers it; nil otherwise, which keeps the default.
    static func effort(_ wanted: String?, for option: ModelOption?) -> String? {
        guard let wanted, let option, option.efforts.contains(wanted) else { return nil }
        return wanted
    }

    /// Whether a pair like this one is already set up: the same providers and models.
    static func isAdded(_ pair: HydraPair, in pairs: [HydraPair]) -> Bool {
        pairs.contains { $0.provider == pair.provider && $0.headsProvider == pair.headsProvider && $0.orchestratorModel == pair.orchestratorModel && $0.workerModel == pair.workerModel }
    }
}
