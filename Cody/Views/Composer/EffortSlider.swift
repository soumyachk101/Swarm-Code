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

    @State private var isPresented = false

    var body: some View {
        let registry = model.providers
        let current = registry.model(thread.model, for: thread.provider)
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                if thread.fastMode, current?.supportsFast == true {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
                if isPresented {
                    Text("Select effort")
                } else {
                    Text(verbatim: current?.shortName ?? thread.model ?? thread.provider.displayName)
                        .foregroundStyle(Chrome.primaryText)
                    if let current, !current.efforts.isEmpty {
                        Text(verbatim: ModelOption.effortTitle(thread.effort ?? current.defaultEffort ?? ""))
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .buttonStyle(.chip)
        .fixedSize()
        .help("Model and reasoning effort")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ModelEffortPanel(threadID: thread.id, hasHistory: hasHistory)
        }
        .task(id: thread.provider) { await registry.loadCatalog(thread.provider) }
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
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    slider(for: thread)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(width: 330)
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: showsModels)
        }
    }

    private func slider(for thread: ChatThread) -> some View {
        let option = model.providers.model(thread.model, for: thread.provider)
        return EffortSliderCard(
            modelName: option?.shortName ?? thread.model ?? thread.provider.displayName,
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

private struct ModelList: View {
    @Environment(AppModel.self) private var model
    let thread: ChatThread
    let hasHistory: Bool
    let onChoose: (ModelCatalog.Entry) -> Void
    let onBack: () -> Void

    var body: some View {
        let entries = ModelCatalog.entries(model, including: thread)
        let showsProviders = Set(entries.map(\.provider)).count > 1
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
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        let locked = hasHistory && entry.provider != thread.provider
                        ModelListRow(
                            entry: entry,
                            detail: locked ? "New chats only" : (showsProviders ? entry.provider.displayName : nil),
                            showsIcon: showsProviders,
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
            .frame(maxHeight: 420)
        }
        .padding(6)
    }
}

private struct ModelListRow: View {
    let entry: ModelCatalog.Entry
    let detail: String?
    let showsIcon: Bool
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
            .padding(.vertical, detail == nil ? 8 : 6)
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

    private var title: String {
        guard !efforts.isEmpty else { return "Standard" }
        return ModelOption.effortTitle(efforts[resolvedIndex])
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
                        .foregroundStyle(Chrome.accent)
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

                    Text(verbatim: modelName)
                        .font(.system(size: 13))
                        .foregroundStyle(Chrome.secondaryText)
                        .lineLimit(1)
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

/// A thick capsule track with a dot per level, filled up to a large white knob that snaps to each level.
struct EffortSlider: View {
    static let trackHeight: CGFloat = 34
    static let thumbSize: CGFloat = 42

    let count: Int
    @Binding var index: Int
    let accessibilityTitle: String

    @State private var dragX: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let inset = Self.trackHeight / 2
            let step = count > 1 ? (width - inset * 2) / CGFloat(count - 1) : 0
            let restingX = inset + CGFloat(index) * step
            let x = min(max(dragX ?? restingX, inset), width - inset)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Chrome.overlay(0.1))
                Capsule(style: .continuous)
                    .fill(Chrome.accent)
                    .frame(width: x + inset)
                ForEach(0..<count, id: \.self) { stop in
                    let stopX = inset + CGFloat(stop) * step
                    Circle()
                        .fill(stopX <= x ? Color.white.opacity(0.6) : Chrome.overlay(0.32))
                        .frame(width: 5, height: 5)
                        .position(x: stopX, y: Self.trackHeight / 2)
                }
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 1)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .scaleEffect(dragX == nil ? 1 : 1.06)
                    .position(x: x, y: Self.trackHeight / 2)
            }
            .frame(height: Self.trackHeight)
            .frame(maxHeight: .infinity)
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
