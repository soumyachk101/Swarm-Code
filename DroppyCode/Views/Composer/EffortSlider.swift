import AppKit
import SwiftUI

/// The models the composer offers: the list chosen in Settings, or every ready provider's models until one is set up.
@MainActor
enum ModelCatalog {
    struct Entry: Identifiable, Hashable {
        let provider: ProviderKind
        let option: ModelOption

        var id: String { "\(provider.rawValue)/\(option.id)" }
    }

    static func entries(_ model: AppModel, including thread: ChatThread?) -> [Entry] {
        let registry = model.providers
        var result: [Entry] = if model.settings.modelList.isEmpty {
            registry.availableProviders.flatMap { provider in
                registry.models(for: provider).map { Entry(provider: provider, option: $0) }
            }
        } else {
            model.settings.modelList.compactMap { pin in
                registry.model(pin.modelID, for: pin.provider).map { Entry(provider: pin.provider, option: $0) }
            }
        }
        if let thread, let current = registry.model(thread.model, for: thread.provider),
           !result.contains(where: { $0.provider == thread.provider && $0.option.id == current.id }) {
            result.insert(Entry(provider: thread.provider, option: current), at: 0)
        }
        return result
    }
}

// MARK: - Composer chip

/// The composer's model chip. It opens the effort slider, and the slider's title opens the model list.
struct ModelEffortButton: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let hasHistory: Bool
    /// Floating panels are narrow: the chip collapses to the provider's icon so the
    /// text field keeps its room. The full name stays in the tooltip and VoiceOver.
    var compact: Bool = false

    @State private var isPresented = false

    var body: some View {
        let registry = model.providers
        let current = registry.model(thread.model, for: thread.provider)
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                ProviderIcon(provider: thread.provider, size: 14)
                if thread.fastMode, current?.supportsFast == true {
                    Image(systemName: "bolt.fill")
                        .font(Chrome.inlineIconFont)
                        .foregroundStyle(.yellow)
                }
                if !compact {
                    if isPresented {
                        Text("Select effort")
                            .lineLimit(1)
                    } else {
                        Text(verbatim: current?.chipName ?? thread.model ?? thread.provider.displayName)
                            .foregroundStyle(Chrome.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let current, !current.efforts.isEmpty {
                            Text(verbatim: ModelOption.effortTitle(thread.effort ?? current.defaultEffort ?? ""))
                                .foregroundStyle(Chrome.primaryText.opacity(0.72))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(Chrome.chevronFont)
                        .foregroundStyle(Chrome.secondaryText)
                }
            }
        }
        .buttonStyle(.chip)
        .help(helpText(current: current))
        .accessibilityLabel(Text(helpText(current: current)))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ModelEffortPanel(threadID: thread.id, hasHistory: hasHistory)
        }
        .background {
            // The website captures hang the slider and the switcher from the real chip.
            if WebsiteCaptures.isEnabled {
                AttachmentAnchorCapture { WebsiteCaptures.modelChipAnchor = WeakView($0) }
            }
        }
        .task(id: thread.provider) { await registry.loadCatalog(thread.provider) }
    }

    /// The full model and effort, for the tooltip and VoiceOver when the chip shows only the icon.
    private func helpText(current: ModelOption?) -> String {
        let name = current?.shortName ?? thread.model ?? thread.provider.displayName
        guard let current, !current.efforts.isEmpty else { return name }
        let effort = ModelOption.effortTitle(thread.effort ?? current.defaultEffort ?? "")
        return "\(name) · \(effort)"
    }
}

/// The popover behind the chip: the slider, or the model list when its title is tapped.
private struct ModelEffortPanel: View {
    @Environment(AppModel.self) private var model
    let threadID: UUID
    let hasHistory: Bool

    @State private var showsModels = false

    var body: some View {
        if let thread = model.thread(threadID) {
            Group {
                if showsModels {
                    ModelList(thread: thread, hasHistory: hasHistory) { entry in
                        choose(entry, for: thread)
                        showsModels = false
                    } onBack: {
                        showsModels = false
                    }
                    .transition(.opacity)
                } else {
                    slider(for: thread)
                        .transition(.opacity)
                }
            }
            .frame(width: 330)
            .animation(.easeOut(duration: 0.12), value: showsModels)
        }
    }

    private func slider(for thread: ChatThread) -> some View {
        let option = model.providers.model(thread.model, for: thread.provider)
        return EffortSliderCard(
            modelName: option?.shortName ?? thread.model ?? thread.provider.displayName,
            provider: thread.provider,
            efforts: option?.efforts ?? [],
            defaultEffort: option?.defaultEffort,
            supportsFast: option?.supportsFast ?? false,
            effort: Binding(
                get: { thread.effort },
                set: { effort in
                    model.updateThread(thread.id) { $0.effort = effort }
                    remember(thread.id)
                }
            ),
            fastMode: Binding(
                get: { thread.fastMode },
                set: { isOn in
                    model.updateThread(thread.id) { $0.fastMode = isOn }
                    remember(thread.id)
                }
            ),
            onTitleTap: { showsModels = true },
            onReset: {
                model.updateThread(thread.id) {
                    $0.effort = nil
                    $0.fastMode = false
                }
                remember(thread.id)
            }
        )
    }

    /// A choice made in a chat becomes that model's setting for every future chat.
    private func remember(_ id: UUID) {
        guard let thread = model.thread(id), let modelID = thread.model else { return }
        model.settings.setPreference(ModelPreference(effort: thread.effort, fastMode: thread.fastMode), for: thread.provider, model: modelID)
        model.settings.remember(model: modelID, effort: thread.effort, for: thread.provider)
    }

    private func choose(_ entry: ModelCatalog.Entry, for thread: ChatThread) {
        let provider = entry.provider
        let option = entry.option
        let switchesProvider = provider != thread.provider
        let preference = model.settings.preference(for: provider, model: option.id)
        let effort = preference.effort.flatMap { option.efforts.contains($0) ? $0 : nil }
        model.updateThread(thread.id) { thread in
            if switchesProvider {
                thread.provider = provider
                thread.providerSessionID = nil
            }
            thread.model = option.id
            thread.effort = effort
            thread.fastMode = option.supportsFast && preference.fastMode
        }
        if switchesProvider { model.existingRuntime(for: thread.id)?.stopSession() }
        model.settings.remember(model: option.id, effort: effort, for: provider)
        model.settings.defaultProvider = provider
    }
}

struct ModelList: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let hasHistory: Bool
    let onChoose: (ModelCatalog.Entry) -> Void
    let onBack: () -> Void

    var body: some View {
        let entries = ModelCatalog.entries(model, including: thread)
        let showsProviders = Set(entries.map(\.provider)).count > 1
        // Fixed row heights let the popover size itself in one pass instead of measuring and resizing.
        let rowHeight: CGFloat = showsProviders || (hasHistory && entries.contains { $0.provider != thread.provider }) ? 46 : 34
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Chrome.secondaryText)
                .help("Back")
                Text("Select model")
                    .font(.system(size: 13))
                    .foregroundStyle(Chrome.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        let locked = hasHistory && entry.provider != thread.provider
                        ModelListRow(
                            entry: entry,
                            detail: locked ? "New chats only" : (showsProviders ? entry.provider.displayName : nil),
                            showsIcon: showsProviders,
                            rowHeight: rowHeight,
                            isSelected: entry.provider == thread.provider && entry.option.id == thread.model,
                            isEnabled: !locked
                        ) {
                            onChoose(entry)
                        }
                    }
                    if entries.isEmpty {
                        Text("Loading models…")
                            .font(.system(size: 13))
                            .foregroundStyle(Chrome.secondaryText)
                            .padding(10)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(CGFloat(max(entries.count, 1)) * (rowHeight + 1), 440))
        }
        .padding(6)
    }
}

private struct ModelListRow: View {
    let entry: ModelCatalog.Entry
    let detail: String?
    let showsIcon: Bool
    let rowHeight: CGFloat
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if showsIcon {
                    ProviderIcon(provider: entry.provider, size: 14)
                        .foregroundStyle(Chrome.secondaryText)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: entry.option.shortName)
                        .font(.system(size: 14))
                        .foregroundStyle(Chrome.primaryText)
                    if let detail {
                        Text(verbatim: detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Chrome.secondaryText)
                    }
                }
                Spacer(minLength: 12)
                if entry.option.supportsFast {
                    Image(systemName: "bolt")
                        .font(.system(size: 10))
                        .foregroundStyle(Chrome.secondaryText)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Chrome.primaryText)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: rowHeight)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovering && isEnabled ? Chrome.overlay(0.1) : Color.clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
    }
}

// MARK: - Slider card

/// Fast mode, the effort title and model name, reset, and the effort slider.
struct EffortSliderCard: View {
    let modelName: String
    let provider: ProviderKind?
    let efforts: [String]
    let defaultEffort: String?
    let supportsFast: Bool
    @Binding var effort: String?
    @Binding var fastMode: Bool
    var onTitleTap: (() -> Void)?
    let onReset: () -> Void

    @State private var isTitleHovering = false

    private var resolvedIndex: Int {
        if let effort, let index = efforts.firstIndex(of: effort) { return index }
        if let defaultEffort, let index = efforts.firstIndex(of: defaultEffort) { return index }
        return efforts.firstIndex(of: "medium") ?? 0
    }

    private var isMaxEffort: Bool {
        efforts.count > 1 && resolvedIndex == efforts.count - 1
    }

    private var title: String {
        guard !efforts.isEmpty else { return "Standard" }
        return ModelOption.effortTitle(efforts[resolvedIndex])
    }

    private var isFast: Bool { supportsFast && fastMode }

    private var brand: EffortBrand { EffortBrand(provider: provider) }

    /// The title takes the slider's colour: the provider's brand at maximum, gold in
    /// fast mode, and both blended when the two are on together.
    private var titleStyle: AnyShapeStyle {
        switch (isMaxEffort, isFast) {
        case (true, true): AnyShapeStyle(LinearGradient(colors: [brand.titleColor, EffortPalette.fast], startPoint: .leading, endPoint: .trailing))
        case (true, false): brand.title
        case (false, true): AnyShapeStyle(EffortPalette.fast)
        case (false, false): AnyShapeStyle(EffortPalette.title)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                HStack {
                    if supportsFast {
                        FastModeButton(isOn: $fastMode)
                    }
                    Spacer()
                    RoundIconButton(symbol: "arrow.counterclockwise", help: "Reset to default", action: onReset)
                }
                VStack(spacing: 2) {
                    Button {
                        onTitleTap?()
                    } label: {
                        HStack(spacing: 4) {
                            Text(verbatim: title)
                                .font(.system(size: 17, weight: .medium))
                                .contentTransition(.numericText())
                            if onTitleTap != nil {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Chrome.secondaryText)
                            }
                        }
                        .foregroundStyle(titleStyle)
                        .animation(.smooth(duration: 0.3), value: isMaxEffort)
                        .animation(.smooth(duration: 0.3), value: isFast)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isTitleHovering && onTitleTap != nil ? Chrome.overlay(0.08) : Color.clear)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(onTitleTap == nil)
                    .onHover { hovering in
                        withAnimation(Chrome.hover) { isTitleHovering = hovering }
                    }
                    .help(onTitleTap == nil ? "" : "Choose a model")

                    HStack(spacing: 5) {
                        if let provider {
                            ProviderIcon(provider: provider, size: 12)
                        }
                        Text(verbatim: modelName)
                            .font(.system(size: 13))
                            .foregroundStyle(Chrome.primaryText.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 44)
            }

            if efforts.isEmpty {
                Text("This model has one reasoning level.")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.secondaryText)
                    .frame(height: EffortSlider.thumbSize)
            } else {
                EffortSlider(
                    count: efforts.count,
                    index: Binding(
                        get: { resolvedIndex },
                        set: { index in
                            withAnimation(.snappy(duration: 0.2)) { effort = efforts[index] }
                        }
                    ),
                    fastMode: isFast,
                    brand: brand,
                    accessibilityTitle: title
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
}

private struct FastModeButton: View {
    @Binding var isOn: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            Image(systemName: isOn ? "bolt.fill" : "bolt")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.yellow : Chrome.secondaryText)
                .symbolEffect(.bounce, value: isOn)
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(isOn ? Color.yellow.opacity(0.18) : Chrome.overlay(isHovering ? 0.1 : 0.06))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isOn ? "Fast mode is on" : "Fast mode")
        .accessibilityLabel(Text("Fast mode"))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

private struct RoundIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Chrome.secondaryText)
                .frame(width: 30, height: 30)
                .background { Circle().fill(isHovering ? Chrome.overlay(0.1) : Color.clear) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Chrome.hover) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// A thick capsule track with a dot per level, filled up to a large glass knob that snaps to each level.
struct EffortSlider: View {
    static let trackHeight: CGFloat = 34
    static let thumbSize: CGFloat = 42

    let count: Int
    @Binding var index: Int
    /// Fast mode on, for a model that has it. Colours the fill gold with
    /// speed streaks; at maximum effort it fuses with the brand's particles.
    var fastMode = false
    /// The colours maximum effort wears: the provider's brand.
    var brand: EffortBrand = .purple
    let accessibilityTitle: String

    @State private var dragX: CGFloat?

    private var look: TrackLook {
        let isMax = count > 1 && index == count - 1
        let kind: TrackLook.Kind = switch (isMax, fastMode) {
        case (true, true): .fusion
        case (true, false): .supercharged
        case (false, true): .fast
        case (false, false): .plain
        }
        return TrackLook(kind: kind, brand: brand)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let inset = Self.trackHeight / 2
            let step = count > 1 ? (width - inset * 2) / CGFloat(count - 1) : 0
            let restingX = inset + CGFloat(index) * step
            let x = min(max(dragX ?? restingX, inset), width - inset)
            let look = look

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Chrome.overlay(0.1))
                Capsule(style: .continuous)
                    .fill(look.fill)
                    .frame(width: x + inset)
                    .overlay(alignment: .leading) {
                        if look.kind != .plain {
                            TrackEffect(look: look)
                                .frame(width: x + inset, height: Self.trackHeight)
                                .clipShape(Capsule(style: .continuous))
                                .transition(.opacity)
                                .id(look)
                        }
                    }
                ForEach(0..<count, id: \.self) { stop in
                    let stopX = inset + CGFloat(stop) * step
                    Circle()
                        .fill(stopX <= x ? look.stopColor : Chrome.overlay(0.32))
                        .frame(width: 5, height: 5)
                        .position(x: stopX, y: Self.trackHeight / 2)
                }
                // The knob is a Liquid Glass lens: it refracts the fill's edge, the stops and
                // the particles as it slides over them, lit white just enough to read as the
                // knob on the dark track. The charged fills keep their glow under it: a blurred
                // disc beneath the lens rather than a shadow on it, because a shadow that
                // changes colour and radius on glass makes the lens flash as the look changes.
                ZStack {
                    Circle()
                        .fill(look.glow)
                        .blur(radius: look.kind == .plain ? 4 : 8)
                        .offset(y: 1)
                    Circle()
                        .fill(.clear)
                        .glassEffect(.regular.tint(Color.white.opacity(look.isLightFill ? 0.55 : 0.32)).interactive(), in: Circle())
                        // On a white fill the lens needs an edge to read against it.
                        .overlay {
                            Circle().strokeBorder(Color.black.opacity(look.isLightFill ? 0.14 : 0), lineWidth: 1)
                        }
                }
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .scaleEffect(dragX == nil ? 1 : 1.06)
                .position(x: x, y: Self.trackHeight / 2)
            }
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
            .animation(.smooth(duration: 0.3), value: look)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragX == nil {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { dragX = value.location.x }
                        } else {
                            dragX = value.location.x
                        }
                        let nearest = nearestStop(to: value.location.x, inset: inset, step: step)
                        if nearest != index {
                            index = nearest
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { dragX = nil }
                    }
            )
        }
        .frame(height: Self.thumbSize)
        .accessibilityElement()
        .accessibilityLabel(Text("Reasoning effort"))
        .accessibilityValue(Text(verbatim: accessibilityTitle))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(count - 1, index + 1)
            case .decrement: index = max(0, index - 1)
            @unknown default: break
            }
        }
    }

    private func nearestStop(to x: CGFloat, inset: CGFloat, step: CGFloat) -> Int {
        guard count > 1, step > 0 else { return 0 }
        return min(count - 1, max(0, Int(((x - inset) / step).rounded())))
    }
}

enum EffortPalette {
    /// The accent lifted a little, so the effort name reads clearly on glass.
    static var title: Color { Chrome.accent.mix(with: .white, by: 0.22) }
    static let supercharged = Color(red: 0.74, green: 0.55, blue: 1.0)
    static let superchargedFill = Color(red: 0.55, green: 0.34, blue: 0.97)
    /// Fast mode's gold: the bolt's yellow, deepened for a fill.
    static let fast = Color(red: 1.0, green: 0.84, blue: 0.36)
    static let fastFill = Color(red: 0.93, green: 0.66, blue: 0.13)
}

/// The colours a provider's maximum effort wears: its brand. Claude's terracotta,
/// DeepSeek's blue, Meta's blue gradient, Google's Gemini gradient for Antigravity.
/// Brands whose marks are black and white (Codex, Cursor, Grok, OpenCode, Devin, Copilot) get
/// a white fill with dark sparks, and everything in the track flips dark to read on it.
enum EffortBrand: Hashable {
    case claude
    case deepseek
    case meta
    case antigravity
    case silver
    /// The stock purple, for a slider with no provider behind it.
    case purple

    init(provider: ProviderKind?) {
        self = switch provider {
        case .claude: .claude
        case .deepseek: .deepseek
        case .meta: .meta
        case .antigravity: .antigravity
        case .codex, .cursor, .grok, .opencode, .devin, .copilot: .silver
        case nil: .purple
        }
    }

    /// The colour the effort name takes at maximum, also the near end of the fast blend.
    var titleColor: Color {
        switch self {
        case .claude: Color(red: 0.93, green: 0.58, blue: 0.44)
        case .deepseek: Color(red: 0.49, green: 0.58, blue: 1.0)
        case .meta: Color(red: 0.31, green: 0.64, blue: 1.0)
        case .antigravity: Color(red: 0.61, green: 0.45, blue: 0.80)
        case .silver: Chrome.primaryText
        case .purple: EffortPalette.supercharged
        }
    }

    var title: AnyShapeStyle {
        switch self {
        case .antigravity: AnyShapeStyle(LinearGradient(colors: Self.gemini, startPoint: .leading, endPoint: .trailing))
        default: AnyShapeStyle(titleColor)
        }
    }

    /// The fill behind the particles.
    var fill: AnyShapeStyle {
        switch self {
        case .claude: AnyShapeStyle(Color(red: 0.80, green: 0.42, blue: 0.28))
        case .deepseek: AnyShapeStyle(Color(red: 0.24, green: 0.36, blue: 0.98))
        case .meta: AnyShapeStyle(LinearGradient(
            colors: [Color(red: 0.0, green: 0.39, blue: 0.88), Color(red: 0.0, green: 0.51, blue: 0.98)],
            startPoint: .leading, endPoint: .trailing
        ))
        case .antigravity: AnyShapeStyle(LinearGradient(colors: Self.gemini, startPoint: .leading, endPoint: .trailing))
        case .silver: AnyShapeStyle(LinearGradient(
            colors: [Color.white, Color(red: 0.88, green: 0.88, blue: 0.91)],
            startPoint: .leading, endPoint: .trailing
        ))
        case .purple: AnyShapeStyle(EffortPalette.superchargedFill)
        }
    }

    /// The fill's darkest colour, for the fusion blend's near end and the knob's glow.
    var fillColor: Color {
        switch self {
        case .claude: Color(red: 0.80, green: 0.42, blue: 0.28)
        case .deepseek: Color(red: 0.24, green: 0.36, blue: 0.98)
        case .meta: Color(red: 0.0, green: 0.45, blue: 0.93)
        case .antigravity: Color(red: 0.56, green: 0.45, blue: 0.80)
        case .silver: Color(red: 0.92, green: 0.92, blue: 0.94)
        case .purple: EffortPalette.superchargedFill
        }
    }

    /// The particles and sheen: white on colour, dark on white.
    var spark: Color { self == .silver ? .black : .white }

    /// Whether the fill is light enough that the knob and stops must read dark against it.
    var isLight: Bool { self == .silver }

    var glow: Color { self == .silver ? .black.opacity(0.35) : fillColor.opacity(0.6) }

    /// Google's Gemini sweep: blue into violet into coral.
    static let gemini = [
        Color(red: 0.26, green: 0.52, blue: 0.96),
        Color(red: 0.61, green: 0.45, blue: 0.80),
        Color(red: 0.85, green: 0.40, blue: 0.44),
    ]
}

/// How the filled part of the effort track looks.
struct TrackLook: Hashable {
    enum Kind: Hashable {
        case plain
        /// Maximum effort: the brand's fill with particles drifting toward the knob.
        case supercharged
        /// Fast mode: gold with speed streaks and lightning.
        case fast
        /// Both: the brand running into gold, particles, streaks, lightning and a sweeping sheen.
        case fusion
    }

    var kind: Kind
    var brand: EffortBrand

    var fill: AnyShapeStyle {
        switch kind {
        case .plain: AnyShapeStyle(Chrome.accent)
        case .supercharged: brand.fill
        case .fast: AnyShapeStyle(EffortPalette.fastFill)
        case .fusion: AnyShapeStyle(LinearGradient(
            colors: [brand.fillColor, brand.fillColor, EffortPalette.fastFill],
            startPoint: .leading, endPoint: .trailing
        ))
        }
    }

    var glow: Color {
        switch kind {
        case .plain: .black.opacity(0.28)
        case .supercharged: brand.glow
        case .fast: EffortPalette.fastFill.opacity(0.7)
        case .fusion: EffortPalette.fast.opacity(0.75)
        }
    }

    /// Whether the fill under the knob is light (a white brand at maximum, not in fusion,
    /// whose far end is gold).
    var isLightFill: Bool { kind == .supercharged && brand.isLight }

    /// The passed stops: white on colour, dark on a white fill.
    var stopColor: Color { isLightFill ? .black.opacity(0.35) : .white.opacity(0.6) }

    /// The particles' and sheen's colour.
    var spark: Color { kind == .supercharged || kind == .fusion ? brand.spark : .white }
}

/// The track's animation, one small Canvas drawn only while the slider needs it.
///
/// Maximum effort: particles drifting through the fill toward the knob, each with its own height,
/// size, speed and shimmer, fading at the ends. Fast mode: speed streaks zipping toward the knob
/// and a lightning bolt flashing now and then. Both together layer the two, over a fill that runs
/// from purple into gold, with a glossy sheen sweeping across. 30fps, 60 when streaks move.
private struct TrackEffect: View {
    let look: TrackLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    var body: some View {
        let kind = look.kind
        let spark = look.spark
        TimelineView(.animation(minimumInterval: 1.0 / (kind == .supercharged ? 30 : 60), paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSince(startedAt)
            Canvas { context, size in
                guard size.width > 8 else { return }
                if kind == .supercharged || kind == .fusion {
                    Self.drawParticles(context, size: size, time: time, color: spark)
                }
                if kind == .fast || kind == .fusion {
                    Self.drawStreaks(context, size: size, time: time)
                    Self.drawBolts(context, size: size, time: time)
                }
                if kind == .fusion {
                    Self.drawSheen(context, size: size, time: time, color: spark)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func drawParticles(_ context: GraphicsContext, size: CGSize, time: TimeInterval, color: Color) {
        let span = Double(size.width) + 8
        let count = max(10, Int(size.width / 5))
        for index in 0..<count {
            let seed = Double(index)
            let height = random(seed, 1)
            let speed = 12 + 28 * random(seed, 2)
            let radius = 0.7 + 1.1 * random(seed, 3)
            let start = random(seed, 4) * span
            let brightness = 0.22 + 0.5 * random(seed, 5)

            let x = (start + time * speed).truncatingRemainder(dividingBy: span) - 4
            let y = Double(size.height) * (0.16 + 0.68 * height)
            let shimmer = 0.6 + 0.4 * sin(time * (2 + 3 * random(seed, 6)) + seed)
            let opacity = brightness * shimmer * edgeFade(x, width: Double(size.width))
            guard opacity > 0.01 else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color.opacity(opacity))
            )
        }
    }

    /// Thin streaks racing toward the knob, bright at the head and fading down the tail.
    private static func drawStreaks(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = Double(size.width)
        let count = max(5, Int(width / 14))
        for index in 0..<count {
            let seed = Double(index) + 100
            let length = 10 + 20 * random(seed, 1)
            let speed = 110 + 190 * random(seed, 2)
            let thickness = 1.1 + 1.1 * random(seed, 3)
            let span = width + length + 12
            let x = (random(seed, 4) * span + time * speed).truncatingRemainder(dividingBy: span) - length - 6
            let y = Double(size.height) * (0.2 + 0.6 * random(seed, 5))
            let brightness = (0.35 + 0.55 * random(seed, 6)) * edgeFade(x + length, width: width)
            guard brightness > 0.02 else { continue }
            let rect = CGRect(x: x, y: y - thickness / 2, width: length, height: thickness)
            context.fill(
                Path(roundedRect: rect, cornerRadius: thickness / 2),
                with: .linearGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(brightness)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
        }
    }

    /// Two lightning bolts on their own beats: each flashes for a quarter second every second
    /// or two, somewhere new along the fill, as a glowing zigzag.
    private static func drawBolts(_ context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = Double(size.width)
        let height = Double(size.height)
        for slot in 0..<2 {
            let seed = Double(slot) + 200
            let period = 1.4 + 0.9 * random(seed, 1)
            let offset = random(seed, 2) * period
            let cycle = ((time + offset) / period).rounded(.down)
            let phase = (time + offset) - cycle * period
            let flash = 0.26
            guard phase < flash else { continue }
            let intensity = sin(phase / flash * .pi)
            let cycleSeed = seed + cycle * 7.31
            let x = 12 + (width - 24) * random(cycleSeed, 3)
            guard x > 6, x < width - 6 else { continue }
            let lean = 3.0 + 3.0 * random(cycleSeed, 4)
            var bolt = Path()
            bolt.move(to: CGPoint(x: x + lean, y: 3))
            bolt.addLine(to: CGPoint(x: x - lean * 0.4, y: height * 0.42))
            bolt.addLine(to: CGPoint(x: x + lean * 0.5, y: height * 0.5))
            bolt.addLine(to: CGPoint(x: x - lean, y: height - 3))
            var glow = context
            glow.addFilter(.blur(radius: 3))
            glow.stroke(bolt, with: .color(EffortPalette.fast.opacity(0.9 * intensity)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            context.stroke(bolt, with: .color(.white.opacity(intensity)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    /// A slanted band of light sweeping the whole fill every few seconds.
    private static func drawSheen(_ context: GraphicsContext, size: CGSize, time: TimeInterval, color: Color) {
        let width = Double(size.width)
        let height = Double(size.height)
        let band = 46.0
        let period = 2.8
        let progress = (time / period).truncatingRemainder(dividingBy: 1)
        let x = -band + (width + band * 2) * progress
        var path = Path()
        path.move(to: CGPoint(x: x + 10, y: 0))
        path.addLine(to: CGPoint(x: x + band + 10, y: 0))
        path.addLine(to: CGPoint(x: x + band, y: height))
        path.addLine(to: CGPoint(x: x, y: height))
        path.closeSubpath()
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0), color.opacity(0.22), color.opacity(0)]),
                startPoint: CGPoint(x: x, y: 0),
                endPoint: CGPoint(x: x + band + 10, y: 0)
            )
        )
    }

    /// Fades a point out over the last 14 points at either end of the fill.
    private static func edgeFade(_ x: Double, width: Double) -> Double {
        min(1, max(0, x / 14), max(0, (width - x) / 14))
    }

    /// A stable pseudo-random value in 0..<1 for an element and one of its traits.
    private static func random(_ index: Double, _ trait: Double) -> Double {
        let value = sin(index * 12.9898 + trait * 78.233) * 43758.5453
        return value - value.rounded(.down)
    }
}
