import SwiftUI

/// The pairs cookbook: the best pairs for the providers set up on this Mac, each added
/// with one click. Recipes that need a provider not set up here wait, dimmed, below.
struct HydraCookbookPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let registry = model.providers
        let settings = model.settings
        let ready = HydraCookbook.recipes.compactMap { recipe -> (recipe: HydraPairRecipe, pair: HydraPair)? in
            HydraCookbook.resolve(recipe, registry: registry, settings: settings).map { (recipe, $0) }
        }
        let waiting = HydraCookbook.recipes.compactMap { recipe -> (recipe: HydraPairRecipe, provider: ProviderKind)? in
            HydraCookbook.missingProvider(for: recipe, registry: registry, settings: settings).map { (recipe, $0) }
        }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cookbook")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text("The best pairs for the providers set up on this Mac. Add one and it is in the model picker.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if ready.isEmpty {
                        Text("Set up a provider in Settings › Providers to see its pairs.")
                            .font(.system(size: 12))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(16)
                    }
                    ForEach(ready, id: \.recipe.id) { entry in
                        HydraCookbookRow(recipe: entry.recipe, pair: entry.pair, missing: nil)
                        Divider().opacity(0.35).padding(.leading, 16)
                    }
                    if !waiting.isEmpty {
                        Text("Needs a provider")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                        ForEach(waiting, id: \.recipe.id) { entry in
                            HydraCookbookRow(recipe: entry.recipe, pair: nil, missing: entry.provider)
                                .opacity(0.55)
                            Divider().opacity(0.35).padding(.leading, 16)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 460, height: 540)
        .task {
            // The recipes pick their models from the catalogs, so every ready provider's is loaded.
            for provider in ProviderKind.allCases where HydraCookbook.isReady(provider, registry: registry, settings: settings) {
                await registry.loadCatalog(provider)
            }
        }
    }
}

/// One recipe: the provider marks, the name and the pitch, the models it resolved to,
/// and the button that adds it. A recipe still missing a provider says which.
private struct HydraCookbookRow: View {
    @Environment(AppModel.self) private var model
    let recipe: HydraPairRecipe
    let pair: HydraPair?
    let missing: ProviderKind?

    var body: some View {
        let registry = model.providers
        let isAdded = pair.map { HydraCookbook.isAdded($0, in: model.settings.hydraPairs) } ?? false
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 4) {
                ProviderIcon(provider: recipe.lead.provider, size: 16)
                    .foregroundStyle(Chrome.primaryText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Chrome.secondaryText)
                ProviderIcon(provider: recipe.heads.provider, size: 13)
                    .foregroundStyle(Chrome.primaryText.opacity(0.8))
            }
            .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: recipe.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                Text(verbatim: recipe.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let pair {
                    Text(verbatim: [HydraPairSummary.title(pair, registry: registry), HydraPairSummary.efforts(pair)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                        .lineLimit(2)
                } else if let missing {
                    Text(verbatim: "Set up \(missing.displayName) to add this pair.")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText.opacity(0.8))
                }
            }
            Spacer(minLength: 8)
            if let pair {
                if isAdded {
                    Label("Added", systemImage: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 10)
                } else {
                    Button {
                        withAnimation(Chrome.panelSlide) { model.settings.addHydraPair(pair) }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
