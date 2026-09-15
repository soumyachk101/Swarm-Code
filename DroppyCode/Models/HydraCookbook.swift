import Foundation

/// A pair worth having, written as a recipe: which model leads at what effort and
/// which model builds at what effort. A recipe is resolved against the models this
/// Mac's providers list, so the cookbook only offers pairs whose models are here.
struct HydraPairRecipe: Identifiable, Sendable {
    struct Side: Sendable {
        let provider: ProviderKind
        /// Names to look for in the provider's catalog, best first; a recipe whose
        /// names find nothing is not offered.
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
        HydraPairRecipe(id: "claude-fable-opus", title: "Fable leads Opus", tagline: "The deepest lead over the strongest builders: Fable plans and checks at high, Opus heads build at medium.", lead: .init(provider: .claude, models: ["Fable"], effort: "high"), heads: .init(provider: .claude, models: ["Opus"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-opus-opus", title: "Opus max, Opus heads", tagline: "Opus thinks as hard as it can about the plan and the review; Opus heads build at a working effort.", lead: .init(provider: .claude, models: ["Opus"], effort: "max"), heads: .init(provider: .claude, models: ["Opus"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-opus-sonnet", title: "Opus leads Sonnet", tagline: "A careful plan and quick hands: the everyday pair, cheaper than all-Opus and nearly as good.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .claude, models: ["Sonnet"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-fable-fable", title: "All Fable", tagline: "For the hardest, longest jobs: every seat on the most capable model, a few heads at a time.", lead: .init(provider: .claude, models: ["Fable"], effort: "max"), heads: .init(provider: .claude, models: ["Fable"], effort: "high"), maxHeads: 4),
        HydraPairRecipe(id: "claude-fable-gemini-flash", title: "Fable leads Gemini Flash", tagline: "A slow, careful lead and a wide, fast team: many Gemini Flash heads on the mechanical parts.", lead: .init(provider: .claude, models: ["Fable"], effort: "high"), heads: .init(provider: .antigravity, models: ["Flash"], effort: "medium"), maxHeads: 6),
        HydraPairRecipe(id: "claude-opus-spark", title: "Opus leads Spark Contributor", tagline: "Opus writes the briefs; Muse Spark Contributor heads on Command Code run them fast and cheap.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .commandcode, models: ["Contributor"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "claude-opus-deepseek-flash", title: "Opus leads DeepSeek Flash", tagline: "Opus keeps the plan tight; DeepSeek Flash heads keep the bill small on the routine parts.", lead: .init(provider: .claude, models: ["Opus"], effort: "high"), heads: .init(provider: .deepseek, models: ["Flash"], effort: "high"), maxHeads: nil),
        HydraPairRecipe(id: "commandcode-astra-spark", title: "GPT leads Spark Contributor", tagline: "The newest GPT orchestrates at high; Muse Spark Contributor heads build at medium, all on one Command Code account.", lead: .init(provider: .commandcode, models: ["GPT-6"], effort: "high"), heads: .init(provider: .commandcode, models: ["Contributor"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "commandcode-astra-gpt", title: "GPT leads GPT", tagline: "OpenAI top to bottom: the newest GPT plans and reviews, its lighter sibling does the work.", lead: .init(provider: .commandcode, models: ["GPT-6"], effort: "high"), heads: .init(provider: .commandcode, models: ["Luna", "GPT-5"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "commandcode-fable-flash", title: "Fable leads Gemini Flash on Command Code", tagline: "Claude Fable leads; Gemini Flash heads sprint, without a second account.", lead: .init(provider: .commandcode, models: ["Claude Fable"], effort: "high"), heads: .init(provider: .commandcode, models: ["Gemini"], effort: "medium"), maxHeads: 6),
        HydraPairRecipe(id: "commandcode-astra-kimi", title: "GPT leads Kimi", tagline: "A frontier lead over open-weight heads with a million tokens of context each.", lead: .init(provider: .commandcode, models: ["GPT-6"], effort: "high"), heads: .init(provider: .commandcode, models: ["Kimi K"], effort: "high"), maxHeads: nil),
        HydraPairRecipe(id: "codex-gpt-family", title: "Codex GPT team", tagline: "A Codex lead on the newest GPT sends its lightest sibling out at medium: quick, cheap legwork.", lead: .init(provider: .codex, models: ["Sol", "Terra", "GPT-5"], effort: "high"), heads: .init(provider: .codex, models: ["Luna", "GPT-5"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "codex-claude-sonnet", title: "Codex GPT leads Sonnet", tagline: "Two labs on one job: a Codex lead with Claude Sonnet heads.", lead: .init(provider: .codex, models: ["Sol", "Terra", "GPT-5"], effort: "high"), heads: .init(provider: .claude, models: ["Sonnet"], effort: "medium"), maxHeads: nil),
        HydraPairRecipe(id: "antigravity-pro-flash", title: "Gemini Pro leads Gemini Flash", tagline: "Gemini Pro plans at high; six Gemini Flash heads sprint at medium.", lead: .init(provider: .antigravity, models: ["Pro"], effort: "high"), heads: .init(provider: .antigravity, models: ["Flash"], effort: "medium"), maxHeads: 6),
        HydraPairRecipe(id: "deepseek-pro-flash", title: "DeepSeek Pro leads DeepSeek Flash", tagline: "DeepSeek end to end: Pro reasons at high, Flash heads build at high for very little.", lead: .init(provider: .deepseek, models: ["Pro"], effort: "high"), heads: .init(provider: .deepseek, models: ["Flash"], effort: "high"), maxHeads: nil),
        HydraPairRecipe(id: "meta-spark-contributor", title: "Spark leads Spark Contributor", tagline: "Muse Spark leads at high; the cheaper Contributor heads build at medium.", lead: .init(provider: .meta, models: ["Spark"], effort: "high"), heads: .init(provider: .meta, models: ["Contributor"], effort: "medium"), maxHeads: nil),
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

    /// Whether both providers are ready but a named model is not in its catalog.
    @MainActor static func missingModel(for recipe: HydraPairRecipe, registry: ProviderRegistry, settings: AppSettings) -> Bool {
        guard missingProvider(for: recipe, registry: registry, settings: settings) == nil else { return false }
        if !recipe.lead.models.isEmpty && model(named: recipe.lead.models, for: recipe.lead.provider, registry: registry) == nil { return true }
        if !recipe.heads.models.isEmpty && model(named: recipe.heads.models, for: recipe.heads.provider, registry: registry) == nil { return true }
        return false
    }

    /// The pair a recipe makes on this Mac, or nil while a provider it needs is not
    /// ready or a named model is not in its catalog.
    @MainActor static func resolve(_ recipe: HydraPairRecipe, registry: ProviderRegistry, settings: AppSettings) -> HydraPair? {
        guard missingProvider(for: recipe, registry: registry, settings: settings) == nil else { return nil }
        guard !missingModel(for: recipe, registry: registry, settings: settings) else { return nil }
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

    /// A fragment names a family; the newest member the catalog lists wins, so a new
    /// release moves a recipe up on its own.
    @MainActor static func model(named names: [String], for provider: ProviderKind, registry: ProviderRegistry) -> ModelOption? {
        let options = registry.models(for: provider)
        for name in names {
            let matches = options.filter { $0.name.localizedCaseInsensitiveContains(name) || $0.id.localizedCaseInsensitiveContains(name) }
            guard !matches.isEmpty else { continue }
            return matches.max { lhs, rhs in
                let lhsVersion = version(of: lhs.name) ?? -1
                let rhsVersion = version(of: rhs.name) ?? -1
                if lhsVersion != rhsVersion { return lhsVersion < rhsVersion }
                return options.firstIndex(where: { $0.id == lhs.id })! > options.firstIndex(where: { $0.id == rhs.id })!
            }
        }
        return nil
    }

    /// The first version number in a catalog name ('Gemini 3.8 Flash' → 3.8), if any.
    private static func version(of name: String) -> Double? {
        guard let match = name.firstMatch(of: #/[0-9]+(?:\.[0-9]+)?/#) else { return nil }
        return Double(match.output)
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
