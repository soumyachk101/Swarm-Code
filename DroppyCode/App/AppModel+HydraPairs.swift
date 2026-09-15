import Foundation

// A pair set up in Settings is somewhere a chat can go, not only a rule it falls under:
// the composer's model picker lists every pair that is ready to run, and one tap puts the
// chat in it. Entering a pair is the same move as choosing a model, with the pair's lead
// model and effort instead of a single model, the pair pinned to the chat, and Hydra on.

extension AppModel {
    /// The pairs the model picker offers: the ones whose provider is installed and
    /// switched on, in the order they were set up.
    var hydraPickerPairs: [HydraPair] {
        settings.hydraPairs.filter { providers.status($0.provider).isInstalled && settings.isEnabled($0.provider) }
    }

    /// Whether a chat leads with this pair right now: Hydra on, the chat on the pair's
    /// provider, and the pair's lead model the chat's own or any model at all.
    func leadsWithHydraPair(_ pair: HydraPair, thread: ChatThread) -> Bool {
        guard hydraIsOn(thread), thread.provider == pair.provider else { return false }
        guard let lead = pair.orchestratorModel else { return true }
        return lead == thread.model
    }

    /// Puts a chat in a pair from the model picker: it switches to the pair's provider and
    /// lead model and effort, pins the pair so it keeps leading with this one, and Hydra
    /// goes on for the app. The session is left to restart itself: the runtime launches the
    /// next turn with the pair's head definitions on its own.
    func enterHydraPair(_ pair: HydraPair, for threadID: UUID) {
        guard let thread = thread(threadID) else { return }
        let provider = pair.provider
        let switchesProvider = provider != thread.provider
        // A pair with no lead model runs on any model, so the chat keeps the one it is on;
        // arriving from another provider there is nothing to keep and it takes that
        // provider's default.
        let option: ModelOption? = if let lead = pair.orchestratorModel {
            providers.model(lead, for: provider)
        } else if switchesProvider {
            providers.defaultModel(for: provider)
        } else {
            providers.model(thread.model, for: provider)
        }
        let modelID = option?.id ?? (switchesProvider ? nil : thread.model)
        let preference = settings.preference(for: provider, model: modelID)
        // The pair's own effort wins. Without one the chat picks up what this model was
        // last left on, the way choosing the model by hand does.
        let effort: String? = if let chosen = pair.orchestratorEffort, option?.efforts.contains(chosen) ?? true {
            chosen
        } else {
            preference.effort.flatMap { (option?.efforts.contains($0) ?? false) ? $0 : nil }
        }
        updateThread(threadID) { thread in
            if switchesProvider {
                thread.provider = provider
                thread.providerSessionID = nil
            }
            thread.model = modelID
            thread.effort = effort
            thread.fastMode = (option?.supportsFast ?? false) && preference.fastMode
            thread.hydraPairID = pair.id
        }
        // A chat that changes provider leaves its old session behind, as a model choice does.
        if switchesProvider { existingRuntime(for: threadID)?.stopSession() }
        settings.remember(model: modelID, effort: effort, for: provider)
        settings.defaultProvider = provider
        settings.hydraEnabled = true
    }
}
