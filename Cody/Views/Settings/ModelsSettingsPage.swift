import SwiftUI

/// Chooses the models the composer's picker offers, and each one's effort and fast mode for new chats.
struct ModelsSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.settings
        let registry = model.providers
        let pins = settings.modelList
        VStack(alignment: .leading, spacing: Chrome.sectionSpacing) {
            ChromeSection(title: "Your models") {
                ChromeCard {
                    if pins.isEmpty {
                        ChromeRow(
                            title: "No models chosen yet",
                            detail: "Until you add some below, the picker shows every model from your providers."
                        ) {
                            EmptyView()
                        }
                    } else {
                        ForEach(Array(pins.enumerated()), id: \.element) { index, pin in
                            if index > 0 { ChromeRowDivider() }
                            PinnedModelRow(pin: pin, index: index, count: pins.count)
                        }
                    }
                }
                Text("\(pins.count) of \(AppSettings.modelListLimit). Click a model to set its reasoning effort and fast mode for every new chat.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.horizontal, 4)
            }

            ForEach(registry.availableProviders) { provider in
                ProviderModelsSection(provider: provider)
            }
        }
    }
}

private struct PinnedModelRow: View {
    @Environment(AppModel.self) private var model
    let pin: ModelPin
    let index: Int
    let count: Int

    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        let settings = model.settings
        let option = model.providers.model(pin.modelID, for: pin.provider)
        let preference = settings.preference(for: pin.provider, model: pin.modelID)
        HStack(spacing: 10) {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    ProviderIcon(provider: pin.provider, size: 16)
                        .foregroundStyle(Chrome.primaryText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option?.shortName ?? pin.modelID)
                            .font(.system(size: 13))
                            .foregroundStyle(Chrome.primaryText)
                        Text(verbatim: summary(option: option, preference: preference))
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundStyle(Chrome.secondaryText)
                        .opacity(isHovering ? 1 : 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                EffortSliderCard(
                    modelName: option?.shortName ?? pin.modelID,
                    efforts: option?.efforts ?? [],
                    defaultEffort: option?.defaultEffort,
                    supportsFast: option?.supportsFast ?? false,
                    effort: Binding(
                        get: { settings.preference(for: pin.provider, model: pin.modelID).effort },
                        set: { effort in
                            var updated = settings.preference(for: pin.provider, model: pin.modelID)
                            updated.effort = effort
                            settings.setPreference(updated, for: pin.provider, model: pin.modelID)
                        }
                    ),
                    fastMode: Binding(
                        get: { settings.preference(for: pin.provider, model: pin.modelID).fastMode },
                        set: { isOn in
                            var updated = settings.preference(for: pin.provider, model: pin.modelID)
                            updated.fastMode = isOn
                            settings.setPreference(updated, for: pin.provider, model: pin.modelID)
                        }
                    ),
                    onReset: { settings.setPreference(ModelPreference(), for: pin.provider, model: pin.modelID) }
                )
                .frame(width: 330)
            }

            HStack(spacing: 2) {
                RowControl(symbol: "chevron.up", help: "Move up", isEnabled: index > 0) {
                    withAnimation(Chrome.panelSlide) { settings.moveModel(pin, by: -1) }
                }
                RowControl(symbol: "chevron.down", help: "Move down", isEnabled: index < count - 1) {
                    withAnimation(Chrome.panelSlide) { settings.moveModel(pin, by: 1) }
                }
                RowControl(symbol: "minus.circle", help: "Remove from the picker", isEnabled: true) {
                    withAnimation(Chrome.panelSlide) { settings.removeFromModelList(pin) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .task { await model.providers.loadCatalog(pin.provider) }
    }

    private func summary(option: ModelOption?, preference: ModelPreference) -> String {
        var parts = [pin.provider.displayName]
        if let option, !option.efforts.isEmpty {
            parts.append(ModelOption.effortTitle(preference.effort ?? option.defaultEffort ?? "") + " effort")
        }
        if preference.fastMode, option?.supportsFast == true { parts.append("Fast") }
        return parts.joined(separator: " · ")
    }
}

private struct RowControl: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

private struct ProviderModelsSection: View {
    @Environment(AppModel.self) private var model
    let provider: ProviderKind

    var body: some View {
        let settings = model.settings
        let registry = model.providers
        let options = registry.models(for: provider)
        let isFull = settings.modelList.count >= AppSettings.modelListLimit
        VStack(alignment: .leading, spacing: Chrome.sectionHeaderSpacing) {
            HStack(spacing: 8) {
                ProviderIcon(provider: provider, size: 16)
                    .foregroundStyle(Chrome.primaryText)
                Text(verbatim: provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 22)
            ChromeCard {
                if options.isEmpty {
                    ChromeRow(title: registry.loadingCatalogs.contains(provider) ? "Loading models…" : "No models loaded") {
                        Button("Load models") {
                            Task { await registry.loadCatalog(provider, force: true) }
                        }
                        .buttonStyle(.glass)
                        .disabled(registry.loadingCatalogs.contains(provider))
                    }
                } else {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 { ChromeRowDivider() }
                        let pin = ModelPin(provider: provider, modelID: option.id)
                        let isAdded = settings.isInModelList(pin)
                        ChromeRow(title: option.shortName, detail: option.detail) {
                            HStack(spacing: 10) {
                                if option.supportsFast {
                                    Image(systemName: "bolt")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Chrome.secondaryText)
                                        .help("Supports fast mode")
                                }
                                Button {
                                    withAnimation(Chrome.panelSlide) {
                                        if isAdded { settings.removeFromModelList(pin) } else { settings.addToModelList(pin) }
                                    }
                                } label: {
                                    Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.system(size: 17))
                                        .foregroundStyle(isAdded ? Chrome.accent : Chrome.secondaryText)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(.plain)
                                .disabled(!isAdded && isFull)
                                .help(isAdded ? "Remove from the picker" : (isFull ? "The picker holds up to \(AppSettings.modelListLimit) models" : "Add to the picker"))
                            }
                        }
                    }
                }
            }
        }
        .task { await registry.loadCatalog(provider) }
    }
}
