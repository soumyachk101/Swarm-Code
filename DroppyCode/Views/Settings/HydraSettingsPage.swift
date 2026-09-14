import SwiftUI

/// Switches Hydra on for the app and sets up its pairs: which model leads and which runs
/// the heads, per provider, and how many heads go out at once.
struct HydraSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        ChromeSection(title: "Hydra") {
            ChromeCard {
                HStack(spacing: 14) {
                    HydraSettingsMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One chat, many heads")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Chrome.primaryText)
                        Text("With Hydra on, a chat's agent leads a team of helper agents on big jobs: a request with several parts, changes across the codebase, research over many files. Small requests it still does alone. The chrome row shows the Hydra mark; tap it to show the team's panel.")
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    SettingsSwitch(isOn: $settings.hydraEnabled)
                }
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 12)
                ChromeRowDivider()
                ChromeRow(title: "Queued follow-ups go to heads", detail: "With Hydra on, a prompt queued behind a running turn starts on a head right away, with a note on what the lead is doing") {
                    SettingsSwitch(isOn: $settings.hydraQueueHeads)
                }
                .disabled(!settings.hydraEnabled)
                .opacity(settings.hydraEnabled ? 1 : 0.5)
                ChromeRowDivider()
                ChromeRow(title: "Heads work in copies of their own", detail: "A head Droppy Code runs gets its own copy of the checkout, so no head sees another's half-done work; its changes land in the chat's checkout the moment it reports. Off, the heads work in the checkout itself.") {
                    SettingsSwitch(isOn: $settings.hydraIsolateHeads)
                }
                .disabled(!settings.hydraEnabled)
                .opacity(settings.hydraEnabled ? 1 : 0.5)
                ChromeRowDivider()
                ChromeRow(title: "Merge when the team is done", detail: "Once the lead has finished and every head is back, the files the team changed go out as a merge request on a branch of their own, land through glab, gh or tea, and the checkout is brought up to date, all without the checkout ever changing branch. Off, the work stays in the checkout for you.") {
                    SettingsSwitch(isOn: $settings.hydraAutoMerge)
                }
                .disabled(!settings.hydraEnabled)
                .opacity(settings.hydraEnabled ? 1 : 0.5)
                ChromeRowDivider()
                ChromeRow(title: "Clear finished heads automatically", detail: "A head that finishes leaves the panel on its own, for the sidebar under its lead, instead of waiting for “Clear finished heads”") {
                    SettingsSwitch(isOn: $settings.hydraAutoClearFinished)
                }
                .disabled(!settings.hydraEnabled)
                .opacity(settings.hydraEnabled ? 1 : 0.5)
            }
        }
        ChromeSection(title: "Pairs") {
            ChromeCard {
                if settings.hydraPairs.isEmpty {
                    ChromeRow(title: "No pairs yet", detail: "Heads run on the chat's own model and effort until a pair says otherwise.") {
                        HydraAddPairButton()
                    }
                } else {
                    ForEach(Array(settings.hydraPairs.enumerated()), id: \.element.id) { index, pair in
                        VStack(spacing: 0) {
                            if index > 0 { ChromeRowDivider() }
                            HydraPairRow(pair: pair)
                        }
                    }
                    ChromeRowDivider()
                    ChromeRow(title: "Another pair", detail: "One pair per provider is enough; more let different lead models run different teams.") {
                        HydraAddPairButton()
                    }
                }
            }
            Text("Each chat leads with the pair for its provider: the one whose lead model the chat runs, else one for any model.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
                .padding(.horizontal, 4)
        }
        ChromeSection(title: "Where heads run") {
            ChromeCard {
                ChromeRow(title: "Claude, Codex and Copilot", detail: "Inside the provider's own session: the heads are defined at launch on the pair's model and effort, and the lead sends them out with its own agent tools. Their transcripts show in the Hydra panel.") {
                    HStack(alignment: .center, spacing: 6) {
                        ProviderIcon(provider: .claude, size: 14)
                        ProviderIcon(provider: .codex, size: 14)
                        // Copilot's mark is wider than tall, so it fills less of a
                        // square frame; size it up to share the same optical height.
                        ProviderIcon(provider: .copilot, size: 16.75)
                    }
                    .foregroundStyle(Chrome.secondaryText)
                }
                ChromeRowDivider()
                ChromeRow(title: "Every other provider", detail: "The lead asks Droppy Code for heads with a delegation block at the end of its reply. Each head runs as a thread of its own on the pair's model, and their reports come back to the lead as the next message.") {
                    EmptyView()
                }
                ChromeRowDivider()
                ChromeRow(title: "Heads from the queue", detail: "A queued follow-up always runs as a thread of its own, whatever the provider, and reports back to the lead once it is idle.") {
                    EmptyView()
                }
            }
        }
    }
}

/// The lead-and-heads mark, large, for the page's opening card.
private struct HydraSettingsMark: View {
    var body: some View {
        HydraMarkImage()
            .foregroundStyle(Chrome.primaryText.opacity(0.85))
            .frame(width: 30, height: 30)
    }
}

private struct HydraAddPairButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            let installed = ProviderKind.allCases.filter { model.providers.status($0).isInstalled && model.settings.isEnabled($0) }
            let taken = Set(model.settings.hydraPairs.map(\.provider))
            let provider = installed.first { !taken.contains($0) } ?? installed.first ?? model.settings.defaultProvider
            withAnimation(Chrome.panelSlide) { model.settings.addHydraPair(HydraPair(provider: provider)) }
        } label: {
            Label("Add pair", systemImage: "plus")
        }
        .buttonStyle(.glass)
    }
}

/// One pair: who leads whom, on what effort, with the editor behind a click.
private struct HydraPairRow: View {
    @Environment(AppModel.self) private var model
    let pair: HydraPair

    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        let registry = model.providers
        HStack(spacing: 10) {
            Button {
                isEditing = true
            } label: {
                HStack(spacing: 12) {
                    ProviderIcon(provider: pair.provider, size: 16)
                        .foregroundStyle(Chrome.primaryText)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: HydraPairSummary.title(pair, registry: registry))
                            .font(.system(size: 13))
                            .foregroundStyle(Chrome.primaryText)
                        Text(verbatim: summary(registry: registry))
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
            .popover(isPresented: $isEditing, arrowEdge: .trailing) {
                HydraPairEditor(pairID: pair.id)
                    .frame(width: 360)
            }
            Button {
                withAnimation(Chrome.panelSlide) { model.settings.removeHydraPair(pair.id) }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Remove this pair")
            .accessibilityLabel(Text("Remove this pair"))
        }
        .padding(.leading, 16)
        .padding(.trailing, Chrome.rowControlTrailingPadding)
        .padding(.vertical, 9)
        .task { await registry.loadCatalog(pair.provider) }
    }

    private func summary(registry: ProviderRegistry) -> String {
        var parts = [pair.provider.displayName]
        if let effort = pair.orchestratorEffort { parts.append("Lead at \(ModelOption.effortTitle(effort).lowercased()) effort") }
        parts.append(HydraPairSummary.workers(pair, registry: registry))
        parts.append(pair.maxHeads == 1 ? "1 head at a time" : "Up to \(pair.maxHeads) heads at once")
        return parts.joined(separator: " · ")
    }
}

/// The pair's settings: provider, lead model and effort, heads' model and effort, and how
/// many heads go out at once. Every choice writes straight to the pair.
private struct HydraPairEditor: View {
    @Environment(AppModel.self) private var model
    let pairID: UUID

    var body: some View {
        if let pair = model.settings.hydraPair(pairID) {
            let registry = model.providers
            let providers = ProviderKind.allCases.filter { model.settings.isEnabled($0) && (registry.status($0).isInstalled || $0 == pair.provider) }
            let options = registry.models(for: pair.provider)
            let leadOption = registry.model(pair.orchestratorModel, for: pair.provider)
            let workerOption = registry.model(pair.workerModel, for: pair.provider)
            // A lead that may be any model offers every effort the provider's models know.
            let leadEfforts = leadOption?.efforts ?? Self.allEfforts(options)
            let workerEfforts = workerOption?.efforts ?? leadEfforts
            VStack(alignment: .leading, spacing: 0) {
                Text("Pair")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                editorRow("Provider") {
                    GlassPickerButton(
                        options: providers.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { pair.provider },
                            set: { provider in
                                model.settings.updateHydraPair(pairID) {
                                    guard $0.provider != provider else { return }
                                    $0.provider = provider
                                    $0.orchestratorModel = nil
                                    $0.orchestratorEffort = nil
                                    $0.workerModel = nil
                                    $0.workerEffort = nil
                                }
                                Task { await registry.loadCatalog(provider) }
                            }
                        ),
                        asset: { $0.iconName }
                    )
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                editorRow("Lead model", detail: "The chat's model while it leads") {
                    GlassPickerButton(
                        options: [(String?.none, "Any model")] + options.map { (Optional($0.id), $0.shortName) },
                        selection: Binding(
                            get: { pair.orchestratorModel },
                            set: { id in
                                model.settings.updateHydraPair(pairID) {
                                    $0.orchestratorModel = id
                                    if let effort = $0.orchestratorEffort, let option = registry.model(id, for: $0.provider), !option.efforts.contains(effort) {
                                        $0.orchestratorEffort = nil
                                    }
                                }
                            }
                        )
                    )
                }
                if !leadEfforts.isEmpty {
                    editorRow("Lead effort") {
                        effortPicker(
                            efforts: leadEfforts,
                            inherit: "Chat's effort",
                            selection: Binding(
                                get: { pair.orchestratorEffort },
                                set: { effort in model.settings.updateHydraPair(pairID) { $0.orchestratorEffort = effort } }
                            )
                        )
                    }
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                editorRow("Heads' model", detail: "What the heads run on") {
                    GlassPickerButton(
                        options: [(String?.none, "Same as the chat")] + options.map { (Optional($0.id), $0.shortName) },
                        selection: Binding(
                            get: { pair.workerModel },
                            set: { id in
                                model.settings.updateHydraPair(pairID) {
                                    $0.workerModel = id
                                    if let effort = $0.workerEffort, let option = registry.model(id, for: $0.provider), !option.efforts.contains(effort) {
                                        $0.workerEffort = nil
                                    }
                                }
                            }
                        )
                    )
                }
                if !workerEfforts.isEmpty {
                    editorRow("Heads' effort", detail: "Lower effort keeps heads quick and cheap") {
                        effortPicker(
                            efforts: workerEfforts,
                            inherit: "Same as the chat",
                            selection: Binding(
                                get: { pair.workerEffort },
                                set: { effort in model.settings.updateHydraPair(pairID) { $0.workerEffort = effort } }
                            )
                        )
                    }
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                editorRow("Heads at once", detail: "How many work in parallel") {
                    HStack(spacing: 8) {
                        Text(verbatim: "\(pair.maxHeads)")
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .frame(minWidth: 16)
                        Stepper(
                            "",
                            value: Binding(
                                get: { pair.maxHeads },
                                set: { count in model.settings.updateHydraPair(pairID) { $0.maxHeads = count } }
                            ),
                            in: HydraPair.maxHeadsRange
                        )
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
                if options.isEmpty {
                    Text(registry.loadingCatalogs.contains(pair.provider) ? "Loading models…" : "No models loaded for \(pair.provider.displayName) yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }
                Spacer(minLength: 12)
            }
            .padding(.bottom, 4)
            .task(id: pair.provider) { await registry.loadCatalog(pair.provider) }
        }
    }

    private func editorRow<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.primaryText)
                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func effortPicker(efforts: [String], inherit: String, selection: Binding<String?>) -> some View {
        GlassPickerButton(
            options: [(String?.none, inherit)] + efforts.map { (Optional($0), ModelOption.effortTitle($0)) },
            selection: selection
        )
    }

    /// Every effort any of the provider's models offers, in the order the first lists them.
    private static func allEfforts(_ options: [ModelOption]) -> [String] {
        var seen: [String] = []
        for option in options {
            for effort in option.efforts where !seen.contains(effort) { seen.append(effort) }
        }
        return seen
    }
}
