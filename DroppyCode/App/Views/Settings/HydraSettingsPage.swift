import SwiftUI

/// Switches Hydra on for the app and sets up its heads: how they work, which messages go
/// to them, what happens when the team is done, and which model leads which, per provider.
struct HydraSettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: Chrome.sectionHeaderSpacing) {
            ChromeCard {
                HStack(spacing: 14) {
                    HStack(spacing: -9) {
                        ForEach(0..<5, id: \.self) { index in
                            HydraGlyph(persona: HydraRoster.persona(at: index), size: 26)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Hydra")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Chrome.primaryText)
                            InfoHoverButton(help: "How Hydra works") { HydraInfoPopover(topic: .hydra) }
                        }
                        Text("One chat leads a team of heads on big jobs.")
                            .font(.system(size: 11))
                            .foregroundStyle(Chrome.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    SettingsSwitch(isOn: $settings.hydraEnabled)
                }
                .padding(.leading, 16)
                .padding(.trailing, Chrome.rowControlTrailingPadding)
                .padding(.vertical, 14)
            }
            // One note for the whole page: the sections below dim together rather than
            // each row repeating why it is off.
            if !settings.hydraEnabled {
                Text("Switch Hydra on to set up its heads.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
        Group {
            ChromeSection(title: "Heads", accessory: AnyView(InfoHoverButton(help: "How heads work") { HydraInfoPopover(topic: .heads) })) {
                ChromeCard {
                    ChromeRow(
                        title: "Checkout",
                        detail: settings.hydraIsolateHeads
                            ? "Each head works in a copy of its own; its changes land in the chat's checkout when it reports."
                            : "Heads work in the chat's checkout itself."
                    ) {
                        ChromeVisualPicker(options: [(true, "Own copy"), (false, "Shared")], selection: $settings.hydraIsolateHeads) { isolated in
                            HeadCheckoutPreview(isolated: isolated)
                        }
                    }
                    ChromeRowDivider()
                    ChromeRow(
                        title: "Heads at once",
                        detail: settings.hydraMaxHeads.map { "At most \($0) heads in parallel." } ?? "As many heads as the job needs."
                    ) {
                        ChromeSegmentedPicker(
                            options: [ChromeSegmentedOption(value: Int?.none, title: "No cap", symbol: "infinity")]
                                + HydraPair.maxHeadsRange.map { ChromeSegmentedOption(value: Optional($0), title: String($0)) },
                            selection: $settings.hydraMaxHeads
                        )
                    }
                    ChromeRowDivider()
                    toggleRow("Clear finished heads", detail: "A finished head moves from the panel to the sidebar.", isOn: $settings.hydraAutoClearFinished)
                    ChromeRowDivider()
                    ChromeRow(title: "Head panel", detail: "The head's progress bar, or each of its steps as it goes.") {
                        ChromeVisualPicker(options: [(false, "Progress"), (true, "Every step")], selection: $settings.hydraShowsHeadDetails) { showsSteps in
                            HeadPanelPreview(showsSteps: showsSteps)
                        }
                    }
                    ChromeRowDivider()
                    ChromeRow(
                        title: "Heads' panels",
                        detail: settings.hydraAutoPopsHeads ? "Each head after the first gets a panel of its own beside the chat while there is room, left and right until each side is full; the usage panel keeps its spot." : "One panel over the chat lists every head."
                    ) {
                        ChromeVisualPicker(options: [(false, "One panel"), (true, "A panel each")], selection: $settings.hydraAutoPopsHeads) { popped in
                            HeadsPlacementPreview(popped: popped)
                        }
                    }
                    ChromeRowDivider()
                    toggleRow("Heads work at a working effort", detail: "A lead thinking above medium sends its heads out at medium on the same model — on a scale without a medium (Z.ai), at the scale's own middle rung; a pair that names the heads' effort keeps it.", isOn: $settings.hydraTempersHeadEffort)
                }
            }
            ChromeSection(title: "Messages") {
                ChromeCard {
                    toggleRow("Queued follow-ups start on heads", detail: "A prompt queued behind a running turn goes out at once.", isOn: $settings.hydraQueueHeads, blockedBy: settings.hydraAlwaysHeads ? "Every message already goes to a head." : nil)
                    ChromeRowDivider()
                    toggleRow("Every message goes to a head", detail: "The lead only hears the reports.", isOn: $settings.hydraAlwaysHeads)
                }
            }
            ChromeSection(title: "When the team is done") {
                ChromeCard {
                    toggleRow("Lead checks the heads' work", detail: "Reads every changed file and corrects it. Slower, more careful.", isOn: $settings.hydraReviewHeads)
                    ChromeRowDivider()
                    toggleRow("Merge automatically", detail: "The team's changes go out as a merge request and are merged.", isOn: $settings.hydraAutoMerge)
                }
            }
            ChromeSection(title: "Pairs") {
                ChromeCard {
                    HStack(alignment: .center, spacing: 14) {
                        // A lead and the heads it sends out: the pair, drawn with the roster.
                        HStack(spacing: 6) {
                            HydraGlyph(persona: HydraRoster.persona(at: 0), size: 30)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Chrome.secondaryText)
                            HStack(spacing: -8) {
                                ForEach(1..<4, id: \.self) { index in
                                    HydraGlyph(persona: HydraRoster.persona(at: index), size: 22)
                                }
                            }
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("One leads, the others build")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Chrome.primaryText)
                            Text("A pair says which model leads and which runs the heads. Put a deep thinker over quick hands on one provider, or lead on one provider and send the heads out on another: the strongest lead with the fastest team, every time.")
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        HydraCookbookButton()
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, Chrome.rowControlTrailingPadding)
                    .padding(.vertical, 14)
                }
                ChromeCard {
                    if settings.hydraPairs.isEmpty {
                        ChromeRow(title: "No pairs yet", detail: "Heads run on the chat's own model until a chat joins a pair.") {
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
                        ChromeRow(title: "Another pair", detail: "One per provider is enough.") {
                            HydraAddPairButton()
                        }
                    }
                }
                Text("Pairs sit at the top of the model picker: a tap puts the chat in one. Right-click a project in the sidebar to start each of its new chats on one pair.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.secondaryText)
                    .padding(.horizontal, 4)
            }
        }
        .disabled(!settings.hydraEnabled)
        .opacity(settings.hydraEnabled ? 1 : 0.5)
        .animation(.smooth(duration: 0.2), value: settings.hydraEnabled)
        ChromeSection(title: "Where heads run") {
            ChromeCard {
                ChromeRow(title: "Claude, Codex and Copilot", detail: "In the provider's own session, through the lead's own agent tools.") {
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
                ChromeRow(title: "Other providers", detail: "As threads of their own, asked for at the end of the lead's reply.") {
                    EmptyView()
                }
                ChromeRowDivider()
                ChromeRow(title: "Across providers", detail: "A pair can lead on one provider and run its heads on another.") {
                    HydraPairMark(lead: .claude, heads: .antigravity, leadSize: 14)
                    .foregroundStyle(Chrome.secondaryText)
                }
            }
        }
    }

    /// A toggle row. A reason it is blocked stands in for its detail, and the row is dimmed
    /// and inert while there is one.
    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>, blockedBy reason: String? = nil) -> some View {
        ChromeRow(title: title, detail: reason ?? detail) {
            SettingsSwitch(isOn: isOn)
        }
        .disabled(reason != nil)
        .opacity(reason == nil ? 1 : 0.5)
    }
}

/// Opens the cookbook: the best pairs for the providers set up here, added with a click.
private struct HydraCookbookButton: View {
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Label("Open cookbook", systemImage: "book")
        }
        .buttonStyle(.glass)
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            HydraCookbookPanel()
                .presentedChrome()
        }
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
                    .presentedChrome()
            }
            Button {
                withAnimation(Chrome.panelSlide) { model.removeHydraPair(pair.id) }
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
        if pair.customName != nil { parts.insert(HydraPairSummary.modelsTitle(pair, registry: registry), at: 0) }
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

/// A pair's provider marks: the lead's larger and the heads' smaller after an arrow,
/// the same mark wherever a pair is drawn, so a same-provider pair shows
/// provider → provider too and a row reads the same everywhere.
private struct HydraPairIcons: View {
    let pair: HydraPair

    var body: some View {
        HydraPairMark(lead: pair.provider, heads: pair.headsProvider)
        .frame(minWidth: 22, alignment: .leading)
    }
}

/// The pair's settings: provider, lead model and effort, the heads' provider, model and
/// effort, and how many heads go out at once. Every choice writes straight to the pair.
/// The head profiles at the end are the pair's advanced mode: purpose-named overrides
/// of the shared heads' choices, so an empty list leaves the pair as it always was.
private struct HydraPairEditor: View {
    @Environment(AppModel.self) private var model
    let pairID: UUID

    /// The profile rows the user has opened; keyed by profile id so a redraw from a
    /// write (a renamed profile, say) never collapses the row being edited.
    @State private var expandedProfiles: Set<UUID> = []

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
                editorRow("Name", detail: "Stands in for the models in the picker and the composer") {
                    TextField("", text: Binding(
                        get: { pair.name ?? "" },
                        set: { text in model.updateHydraPair(pairID) { $0.name = text.isEmpty ? nil : text } }
                    ), prompt: Text(HydraPairSummary.modelsTitle(pair, registry: registry)))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 150)
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                editorRow("Lead provider") {
                    GlassPickerButton(
                        options: providers.map { ($0, $0.displayName) },
                        selection: Binding(
                            get: { pair.provider },
                            set: { provider in
                                model.updateHydraPair(pairID) {
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
                                model.updateHydraPair(pairID) {
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
                                set: { effort in model.updateHydraPair(pairID) { $0.orchestratorEffort = effort } }
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
                                model.updateHydraPair(pairID) {
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
                                model.updateHydraPair(pairID) {
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
                                set: { effort in model.updateHydraPair(pairID) { $0.workerEffort = effort } }
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
                            set: { count in model.updateHydraPair(pairID) { $0.maxHeads = count } }
                        )
                    )
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 6)
                headProfilesSection(pair: pair, registry: registry)
                ForEach(Self.catalogProviders(pair), id: \.self) { provider in
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
            .task(id: Self.catalogProviders(pair)) {
                for provider in Self.catalogProviders(pair) {
                    await registry.loadCatalog(provider)
                }
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

    /// The providers whose catalogs the editor shows: the lead's, the heads', and any a
    /// profile names, each once and in that order, so the pickers and the loading notes
    /// cover a head routed to another provider.
    private static func catalogProviders(_ pair: HydraPair) -> [ProviderKind] {
        var providers = pair.sendsHeadsElsewhere ? [pair.provider, pair.headsProvider] : [pair.provider]
        for provider in pair.headProfiles.compactMap(\.provider) where !providers.contains(provider) {
            providers.append(provider)
        }
        return providers
    }

    /// The pair's advanced mode, below its shared heads' choices: purpose-named profiles
    /// the lead routes a head to ("quick", "deep"). With none, the pair behaves as it
    /// always did, so the section reads as optional rather than as a missing step.
    private func headProfilesSection(pair: HydraPair, registry: ProviderRegistry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Head profiles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Chrome.primaryText)
                .padding(.horizontal, 14)
            Text("Advanced: the lead can send a head out for a purpose by name; that head runs on the profile's own provider, model and effort, inheriting the pair's where a field is unset.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.top, 1)
                .padding(.bottom, 2)
            ForEach(Array(pair.headProfiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { Divider().padding(.horizontal, 14).padding(.vertical, 6) }
                headProfileRow(profile, pair: pair, registry: registry)
            }
            editorRow(pair.headProfiles.isEmpty ? "No profiles yet" : "Another profile",
                      detail: pair.headProfiles.isEmpty ? "Every head runs on the pair's choices above." : nil) {
                Button {
                    let profile = HydraHeadProfile(name: Self.suggestedProfileName(in: pair))
                    withAnimation(Chrome.panelSlide) {
                        model.updateHydraPair(pairID) { $0.headProfiles.append(profile) }
                        // A profile exists to be tuned, so its row opens as it lands.
                        expandedProfiles.insert(profile.id)
                    }
                } label: {
                    Label("Add profile", systemImage: "plus")
                }
                .buttonStyle(.glass)
            }
        }
    }

    /// One profile: its name and what it overrides, opening to its editor on a click, the
    /// same shape as the pair's own row in the list.
    private func headProfileRow(_ profile: HydraHeadProfile, pair: HydraPair, registry: ProviderRegistry) -> some View {
        let isExpanded = expandedProfiles.contains(profile.id)
        // The provider every picker below filters by: the profile's, or the pair's heads
        // provider when the profile inherits.
        let provider = profile.provider ?? pair.headsProvider
        let options = registry.models(for: provider)
        let efforts = registry.model(profile.model, for: provider)?.efforts ?? Self.allEfforts(options)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(Chrome.panelSlide) {
                        if isExpanded { expandedProfiles.remove(profile.id) } else { expandedProfiles.insert(profile.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Chrome.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: profile.name.isEmpty ? "Unnamed" : profile.name)
                                .font(.system(size: 13))
                                .foregroundStyle(profile.name.isEmpty ? Chrome.secondaryText : Chrome.primaryText)
                            Text(verbatim: profileSummary(profile, pair: pair, registry: registry))
                                .font(.system(size: 11))
                                .foregroundStyle(Chrome.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(Chrome.panelSlide) {
                        model.updateHydraPair(pairID) { $0.headProfiles.removeAll { $0.id == profile.id } }
                        expandedProfiles.remove(profile.id)
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Remove this profile")
                .accessibilityLabel(Text("Remove this profile"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            if isExpanded {
                headProfileEditor(profile, provider: provider, options: options, efforts: efforts, registry: registry)
                    .padding(.bottom, 4)
            }
        }
    }

    /// A profile's fields, each nil reading as "inherit the pair". Provider and model
    /// changes clear what depended on them, as the pair's own pickers do: a model id or
    /// effort of the old provider's would name nothing on the new one.
    private func headProfileEditor(_ profile: HydraHeadProfile, provider: ProviderKind, options: [ModelOption], efforts: [String], registry: ProviderRegistry) -> some View {
        let providers = ProviderKind.allCases.filter { model.settings.isEnabled($0) && (registry.status($0).isInstalled || $0 == profile.provider) }
        return VStack(spacing: 0) {
            editorRow("Name", detail: "The word the lead routes to this profile") {
                TextField("", text: Binding(
                    get: { profile.name },
                    set: { name in updateProfile(profile.id) { $0.name = name } }
                ), prompt: Text("quick"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 150)
            }
            editorRow("Provider", detail: "Runs this profile's heads on another provider") {
                GlassPickerButton(
                    options: [(ProviderKind?.none, "Same as the pair")] + providers.map { (Optional($0), $0.displayName) },
                    selection: Binding(
                        get: { profile.provider },
                        set: { chosen in
                            updateProfile(profile.id) {
                                guard $0.provider != chosen else { return }
                                $0.provider = chosen
                                $0.model = nil
                                $0.effort = nil
                            }
                            Task { await registry.loadCatalog(chosen ?? provider) }
                        }
                    ),
                    asset: { ($0 ?? provider).iconName }
                )
            }
            editorRow("Model") {
                GlassPickerButton(
                    options: [(String?.none, "Pair's model")] + options.map { (Optional($0.id), $0.shortName) },
                    selection: Binding(
                        get: { profile.model },
                        set: { id in
                            updateProfile(profile.id) {
                                $0.model = id
                                if let effort = $0.effort, let option = registry.model(id, for: provider), !option.efforts.contains(effort) {
                                    $0.effort = nil
                                }
                            }
                        }
                    ),
                    maxWidth: 190
                )
            }
            if !efforts.isEmpty {
                editorRow("Effort") {
                    effortPicker(
                        efforts: efforts,
                        inherit: "Pair's effort",
                        selection: Binding(
                            get: { profile.effort },
                            set: { effort in updateProfile(profile.id) { $0.effort = effort } }
                        )
                    )
                }
            }
        }
    }

    /// The row's second line: only the fields the profile sets ("Opus 5 · High effort ·
    /// on Antigravity"), since unset ones inherit; a profile that sets nothing says so.
    private func profileSummary(_ profile: HydraHeadProfile, pair: HydraPair, registry: ProviderRegistry) -> String {
        var parts: [String] = []
        if let model = profile.model {
            parts.append(registry.model(model, for: profile.provider ?? pair.headsProvider)?.shortName ?? model)
        }
        if let effort = profile.effort { parts.append(ModelOption.effortTitle(effort) + " effort") }
        if let provider = profile.provider { parts.append("on " + provider.displayName) }
        return parts.isEmpty ? "Same as the pair" : parts.joined(separator: " · ")
    }

    /// Writes one profile's fields through the pair's update, looked up by id: the editor
    /// redraws from the stored pair on every write, so the value a row was built with
    /// would go stale mid-edit.
    private func updateProfile(_ id: UUID, _ change: (inout HydraHeadProfile) -> Void) {
        model.updateHydraPair(pairID) { pair in
            guard let index = pair.headProfiles.firstIndex(where: { $0.id == id }) else { return }
            change(&pair.headProfiles[index])
        }
    }

    /// The name a new profile starts with: the first unused of the purpose words, then
    /// "Profile 1", "Profile 2" and so on.
    private static func suggestedProfileName(in pair: HydraPair) -> String {
        let taken = Set(pair.headProfiles.map { $0.name.lowercased() })
        for name in ["quick", "deep", "visual"] where !taken.contains(name) { return name }
        var number = 1
        while taken.contains("profile \(number)") { number += 1 }
        return "Profile \(number)"
    }
}
