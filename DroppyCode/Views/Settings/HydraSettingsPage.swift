import SwiftUI

/// Switches Hydra on for the app and sets up its pairs: which model leads and which runs
/// the heads, per provider, and how many heads go out at once.
struct HydraSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        // A row that is off says why it is off: dimming alone leaves the user guessing.
        let hydraOff: String? = settings.hydraEnabled ? nil : "Switch Hydra on above first"
        let queuedOff: String? = if !settings.hydraEnabled {
            "Switch Hydra on above first"
        } else if settings.hydraAlwaysHeads {
            "Every message already goes to a head"
        } else {
            nil
        }
        ChromeSection(title: "Hydra") {
            ChromeCard {
                HStack(spacing: 14) {
                    HydraSettingsMark()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One chat, many heads")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Chrome.primaryText)
                        Text("With Hydra on, a chat's agent leads a team of helper agents on big jobs and still does small ones alone. The Hydra mark in the chrome row opens the team's panel.")
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
            }
        }
        ChromeSection(title: "Heads") {
            ChromeCard {
                toggleRow("Queued follow-ups go to heads", detail: "A prompt queued behind a running turn starts on a head right away.", isOn: $settings.hydraQueueHeads, blockedBy: queuedOff)
                ChromeRowDivider()
                toggleRow("Every message goes to a head", detail: "Each message starts on a head of its own; the lead only hears the reports. When a pair's heads are all busy, the message goes to the lead.", isOn: $settings.hydraAlwaysHeads, blockedBy: hydraOff)
                ChromeRowDivider()
                toggleRow("Heads work in copies of their own", detail: "Each head gets its own copy of the checkout, and its changes land in the chat's checkout when it reports. Off, heads work in the checkout itself.", isOn: $settings.hydraIsolateHeads, blockedBy: hydraOff)
                ChromeRowDivider()
                toggleRow("Clear finished heads automatically", detail: "A finished head leaves the panel for the sidebar under its lead.", isOn: $settings.hydraAutoClearFinished, blockedBy: hydraOff)
            }
        }
        ChromeSection(title: "When the team is done") {
            ChromeCard {
                toggleRow("Lead audits the heads' work", detail: "Before it finishes, the lead reads every file the heads changed, checks it does what was asked, and corrects it where needed. Slower, but catches what quick heads miss.", isOn: $settings.hydraReviewHeads, blockedBy: hydraOff)
                ChromeRowDivider()
                toggleRow("Merge when the team is done", detail: "Once the lead has finished and every head is back, the team's changes go out as a merge request on their own branch, are merged, and the checkout is brought up to date. Off, the work stays in the checkout.", isOn: $settings.hydraAutoMerge, blockedBy: hydraOff)
            }
        }
        ChromeSection(title: "Pairs") {
            ChromeCard {
                if settings.hydraPairs.isEmpty {
                    ChromeRow(title: "No pairs yet", detail: "Heads run on the chat's own model and effort until a chat is put in a pair.") {
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
            Text("With Hydra on, every pair sits at the top of the composer's model picker: a tap puts the chat in it, and a chat made from that one carries the pair along. A model picked there takes the chat back out, its heads on its own model and effort. The effort slider sets the lead's effort while the chat leads a pair.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
                .padding(.horizontal, 4)
        }
        ChromeSection(title: "Where heads run") {
            ChromeCard {
                ChromeRow(title: "Claude, Codex and Copilot", detail: "In the provider's own session, on the pair's model and effort, sent out by the lead's own agent tools. Their transcripts show in the Hydra panel.") {
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
                ChromeRow(title: "Every other provider", detail: "The lead asks for heads with a delegation block at the end of its reply. Each runs as a thread of its own on the pair's model and reports back as the lead's next message.") {
                    EmptyView()
                }
                ChromeRowDivider()
                ChromeRow(title: "Heads on another provider", detail: "A pair can lead on one provider and run its heads on another: a strong lead over quick heads. Those heads always run as threads of their own, and their work lands in the lead's checkout as they report.") {
                    HStack(alignment: .center, spacing: 5) {
                        ProviderIcon(provider: .claude, size: 14)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                        ProviderIcon(provider: .antigravity, size: 14)
                    }
                    .foregroundStyle(Chrome.secondaryText)
                }
                ChromeRowDivider()
                ChromeRow(title: "Heads from the queue", detail: "A queued follow-up runs as a thread of its own, whatever the provider, and reports to the lead once it is idle.") {
                    EmptyView()
                }
            }
        }
    }

    /// A toggle row: the reason it is switched off follows its detail, and the row is dimmed
    /// and inert while there is one.
    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>, blockedBy reason: String?) -> some View {
        ChromeRow(title: title, detail: self.detail(detail, blockedBy: reason)) {
            SettingsSwitch(isOn: isOn)
        }
        .disabled(reason != nil)
        .opacity(reason == nil ? 1 : 0.5)
    }

    /// A row's detail, with the reason it is switched off after it. Nothing is added while
    /// the row works.
    private func detail(_ text: String, blockedBy reason: String?) -> String {
        guard let reason else { return text }
        return text.hasSuffix(".") ? "\(text) \(reason)." : "\(text). \(reason)."
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
                    HydraPairIcons(pair: pair)
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
        .task(id: pair.headsProvider) {
            await registry.loadCatalog(pair.provider)
            await registry.loadCatalog(pair.headsProvider)
        }
    }

    /// The row's second line: only what the title and the icons do not already say. The
    /// title names the models, the icons the providers, so this reads the efforts, a head
    /// cap when one is set, and a warning when the heads' provider is not set up. Defaults
    /// say nothing: a pair with no effort chosen and no cap has one short line.
    private func summary(registry: ProviderRegistry) -> String {
        var parts = [HydraPairSummary.providers(pair)]
        if let efforts = HydraPairSummary.efforts(pair) { parts.append(efforts) }
        if let cap = pair.maxHeads {
            parts.append(cap == 1 ? "One head at a time" : "Up to \(cap) heads")
        }
        // Heads on a provider this Mac cannot run stay on the lead's, on the chat's own
        // model (see `AppModel.hydraHeadsProvider`); the row says so rather than promising
        // a team that would fail.
        if pair.sendsHeadsElsewhere, model.hydraHeadsProvider(of: pair) == pair.provider {
            parts.append("\(pair.headsProvider.displayName) is not set up, heads stay on \(pair.provider.displayName)")
        }
        return parts.joined(separator: " · ")
    }
}

/// A pair's provider mark: the lead's icon, and after it the heads' when they run
/// elsewhere, so a row says at a glance that this pair crosses providers.
private struct HydraPairIcons: View {
    let pair: HydraPair

    var body: some View {
        HStack(spacing: 4) {
            ProviderIcon(provider: pair.provider, size: 16)
                .foregroundStyle(Chrome.primaryText)
            if pair.sendsHeadsElsewhere {
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Chrome.secondaryText)
                ProviderIcon(provider: pair.headsProvider, size: 13)
                    .foregroundStyle(Chrome.primaryText.opacity(0.8))
            }
        }
        .frame(minWidth: 22, alignment: .leading)
        .accessibilityLabel(Text(pair.sendsHeadsElsewhere ? "\(pair.provider.displayName) lead, \(pair.headsProvider.displayName) heads" : pair.provider.displayName))
    }
}

/// The pair's settings: provider, lead model and effort, the heads' provider, model and
/// effort, and how many heads go out at once. Every choice writes straight to the pair.
private struct HydraPairEditor: View {
    @Environment(AppModel.self) private var model
    let pairID: UUID

    var body: some View {
        if let pair = model.settings.hydraPair(pairID) {
            let registry = model.providers
            let providers = ProviderKind.allCases.filter { model.settings.isEnabled($0) && (registry.status($0).isInstalled || $0 == pair.provider) }
            let headsProviders = ProviderKind.allCases.filter { model.settings.isEnabled($0) && (registry.status($0).isInstalled || $0 == pair.headsProvider) }
            let options = registry.models(for: pair.provider)
            let headsOptions = registry.models(for: pair.headsProvider)
            let leadOption = registry.model(pair.orchestratorModel, for: pair.provider)
            let workerOption = registry.model(pair.workerModel, for: pair.headsProvider)
            // A lead that may be any model offers every effort the provider's models know.
            let leadEfforts = leadOption?.efforts ?? Self.allEfforts(options)
            // Heads with no model chosen inherit the chat's, and its efforts; on another
            // provider they run its default model, so its efforts are the ones on offer.
            let workerEfforts = workerOption?.efforts ?? (pair.sendsHeadsElsewhere ? (registry.defaultModel(for: pair.headsProvider)?.efforts ?? Self.allEfforts(headsOptions)) : leadEfforts)
            VStack(alignment: .leading, spacing: 0) {
                Text("Pair")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                editorRow("Lead provider") {
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
                                    // Heads on the old lead provider go with it; heads on a
                                    // provider of their own keep their model and effort, and
                                    // when that provider is the new lead's, they are simply
                                    // on the lead's provider again.
                                    if $0.workerProvider == nil {
                                        $0.workerModel = nil
                                        $0.workerEffort = nil
                                    } else if $0.workerProvider == provider {
                                        $0.workerProvider = nil
                                    }
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
                        ),
                        maxWidth: 190
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
                editorRow("Heads' provider", detail: "Another provider puts quick heads under a strong lead") {
                    GlassPickerButton(
                        options: [(ProviderKind?.none, "Same as the lead")] + headsProviders.filter { $0 != pair.provider }.map { (Optional($0), $0.displayName) },
                        selection: Binding(
                            get: { pair.sendsHeadsElsewhere ? pair.workerProvider : nil },
                            set: { provider in
                                model.settings.updateHydraPair(pairID) {
                                    let chosen = provider == $0.provider ? nil : provider
                                    guard $0.workerProvider != chosen else { return }
                                    // The heads' model and effort were the old provider's.
                                    $0.workerProvider = chosen
                                    $0.workerModel = nil
                                    $0.workerEffort = nil
                                }
                                if let provider { Task { await registry.loadCatalog(provider) } }
                            }
                        ),
                        asset: { ($0 ?? pair.provider).iconName }
                    )
                }
                editorRow("Heads' model", detail: pair.sendsHeadsElsewhere ? "What the heads run on, from \(pair.headsProvider.displayName)'s models" : "What the heads run on") {
                    GlassPickerButton(
                        options: [(String?.none, pair.sendsHeadsElsewhere ? "\(pair.headsProvider.displayName)'s default" : "Same as the chat")] + headsOptions.map { (Optional($0.id), $0.shortName) },
                        selection: Binding(
                            get: { pair.workerModel },
                            set: { id in
                                model.settings.updateHydraPair(pairID) {
                                    $0.workerModel = id
                                    if let effort = $0.workerEffort, let option = registry.model(id, for: $0.headsProvider), !option.efforts.contains(effort) {
                                        $0.workerEffort = nil
                                    }
                                }
                            }
                        ),
                        maxWidth: 190
                    )
                }
                if !workerEfforts.isEmpty {
                    editorRow("Heads' effort", detail: "Lower effort keeps heads quick and cheap") {
                        effortPicker(
                            efforts: workerEfforts,
                            inherit: pair.sendsHeadsElsewhere ? "\(pair.headsProvider.displayName)'s default" : "Same as the chat",
                            selection: Binding(
                                get: { pair.workerEffort },
                                set: { effort in model.settings.updateHydraPair(pairID) { $0.workerEffort = effort } }
                            )
                        )
                    }
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                editorRow("Heads at once", detail: "How many work in parallel; with no cap, as many as the work takes") {
                    GlassPickerButton(
                        options: [(Int?.none, "No cap")] + HydraPair.maxHeadsRange.map { (Optional($0), String($0)) },
                        selection: Binding(
                            get: { pair.maxHeads },
                            set: { count in model.settings.updateHydraPair(pairID) { $0.maxHeads = count } }
                        )
                    )
                }
                ForEach(pair.sendsHeadsElsewhere ? [pair.provider, pair.headsProvider] : [pair.provider], id: \.self) { provider in
                    if registry.models(for: provider).isEmpty {
                        Text(registry.loadingCatalogs.contains(provider) ? "Loading \(provider.displayName)'s models…" : "No models loaded for \(provider.displayName) yet.")
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                    }
                }
                Spacer(minLength: 12)
            }
            .padding(.bottom, 4)
            .task(id: [pair.provider, pair.headsProvider]) {
                await registry.loadCatalog(pair.provider)
                await registry.loadCatalog(pair.headsProvider)
            }
        }
    }

    private func editorRow<Control: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail {
                    Text(verbatim: detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
                .layoutPriority(1)
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
