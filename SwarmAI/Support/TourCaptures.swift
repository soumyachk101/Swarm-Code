import AppKit
import SwiftUI

/// The onboarding tour's captures: six scenes (plus four theme variants) photographed
/// over curated gradient backdrops as 16:10 images:
///
///     open -n -W "SwarmAI.app" --args --tour-captures <folder>
///
/// Same isolation contract as WebsiteCaptures: own storage folder, own defaults suite,
/// quits when the last file is written. The Hydra scene itself lives in
/// `TourCaptures+Hydra.swift`, written by another head.
@MainActor
enum TourCaptures {
    enum Backdrop: CaseIterable {
        case welcome, hydra, pairs, slider, panels, themes
    }

    static func backdropView(_ backdrop: Backdrop) -> some View {
        let colors: [Color]
        switch backdrop {
        case .welcome:
            colors = hexes(["#12153F", "#4B36C4", "#2E7CF6", "#0B0D2A", "#3A2A9E", "#1C4FB8", "#07081A", "#1B1650", "#0D2A6B"])
        case .hydra:
            colors = hexes(["#07201F", "#0E5A4A", "#12836B", "#041412", "#0B3D34", "#E39A2E", "#020A09", "#062421", "#0A4A3C"])
        case .pairs:
            colors = hexes(["#2B1548", "#6A2C9E", "#F0655E", "#1B0D30", "#4A1F7A", "#B8407A", "#0E0619", "#2A1240", "#5A2260"])
        case .slider:
            colors = hexes(["#2A0F3A", "#8E2E6C", "#F5A54A", "#1B0A28", "#C2416B", "#E3743F", "#0F0518", "#5C1F48", "#8A3A2E"])
        case .panels:
            colors = hexes(["#0D1B2A", "#1F4E79", "#6FB1E8", "#08121C", "#173B5E", "#2F6FA8", "#04090F", "#0F2942", "#1A4C78"])
        case .themes:
            colors = hexes(["#1A1033", "#7B2FF7", "#F72F8B", "#120A26", "#4E1FA6", "#FFB347", "#0A0518", "#2B1160", "#B0286A"])
        }
        let corners: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.52), SIMD2(0.48, 0.46), SIMD2(1, 0.55),
            SIMD2(0, 1), SIMD2(0.54, 1), SIMD2(1, 1),
        ]
        return ZStack {
            MeshGradient(width: 3, height: 3, points: corners, colors: colors)
            RadialGradient(colors: [.white.opacity(0.1), .clear], center: .topLeading, startRadius: 0, endRadius: 900)
            RadialGradient(colors: [.white.opacity(0.1), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }

    private static func hexes(_ values: [String]) -> [Color] {
        values.map { Color(hex: $0) }
    }

    static func run(model: AppModel) async {
        guard let output = WebsiteCaptures.outputDirectory else { return }
        Task {
            try? await Task.sleep(for: .seconds(110))
            WebsiteCaptures.log("out of time, quitting")
            exit(0)
        }
        let stage = Stage(model: model)
        stage.show(size: NSSize(width: 1200, height: 660))
        await stage.ensureActive()
        let recorder = Recorder(output: output, stage: stage)
        try? await Task.sleep(for: .milliseconds(1_400))

        // 1. tour-welcome
        await capture(model, stage, recorder, name: "tour-welcome", backdrop: .welcome, size: NSSize(width: 1200, height: 660)) {
            if !model.sidebar.isVisible { model.sidebar.toggle() }
            model.settings.theme = .dark
            model.selectedThreadID = WebsiteCaptures.composerThreadID
            await WebsiteCaptures.editingScene(model, stage, recorder, film: false)
            return nil
        }
        // 2. tour-hydra (the other head's).
        await TourCaptures.hydraScene(model, stage, recorder)
        // 3. tour-pairs
        await capture(model, stage, recorder, name: "tour-pairs", backdrop: .pairs, size: NSSize(width: 900, height: 600)) {
            if model.sidebar.isVisible { model.sidebar.toggle() }
            model.selectedThreadID = WebsiteCaptures.freshThreadID
            // The chip reports where it sits once the thread has laid out; the popover
            // hangs from that.
            try? await Task.sleep(for: .milliseconds(900))
            await model.providers.loadCatalog(.claude)
            await model.providers.loadCatalog(.antigravity)
            await model.providers.loadCatalog(.opencode)
            model.settings.hydraEnabled = true
            let fableID = model.providers.model("claude-fable-5-1[1m]", for: .claude)?.id ?? "claude-fable-5-1[1m]"
            var first = HydraPair(provider: .claude)
            first.orchestratorModel = fableID
            first.workerProvider = .antigravity
            first.workerModel = "gemini-3.8-flash"
            let opencodeID = model.providers.catalogs[.opencode]?.first(where: {
                $0.name.localizedCaseInsensitiveContains("Muse Spark") && $0.name.localizedCaseInsensitiveContains("Contributor")
            })?.id ?? model.providers.defaultModel(for: .opencode)?.id
            var second = HydraPair(provider: .claude)
            second.orchestratorModel = fableID
            second.workerProvider = .opencode
            second.workerModel = opencodeID
            model.settings.addHydraPair(first)
            model.settings.addHydraPair(second)
            guard let thread = model.thread(WebsiteCaptures.freshThreadID) else { return nil }
            let list = ModelList(thread: thread, hasHistory: false, onChoose: { _ in }, onBack: {})
            let popover = stage.presentPopover(list.environment(model), width: 330, chipOf: WebsiteCaptures.freshThreadID)
            await stage.holdPopover(popover, seconds: 1.6)
            WebsiteCaptures.log("pairs popover shown=\(popover.isShown) size=\(popover.contentSize)")
            return popover
        }
        // 4. tour-slider
        await capture(model, stage, recorder, name: "tour-slider", backdrop: .slider, size: NSSize(width: 900, height: 600)) {
            if let pair = model.settings.hydraPairs.first {
                model.enterHydraPair(pair, for: WebsiteCaptures.freshThreadID)
            }
            model.updateThread(WebsiteCaptures.freshThreadID) { $0.effort = "max" }
            guard let thread = model.thread(WebsiteCaptures.freshThreadID) else { return nil }
            let option = model.providers.model(thread.model, for: thread.provider)
            let pair = model.settings.hydraPair(thread.hydraPairID).map { EffortPairLook($0, registry: model.providers) }
            let card = EffortSliderCard(
                modelName: option?.shortName ?? thread.model ?? thread.provider.displayName,
                provider: thread.provider,
                pair: pair,
                efforts: option?.efforts ?? [],
                defaultEffort: option?.defaultEffort,
                supportsFast: option?.supportsFast ?? false,
                effort: Binding(get: { model.thread(WebsiteCaptures.freshThreadID)?.effort }, set: { effort in model.updateThread(WebsiteCaptures.freshThreadID) { $0.effort = effort } }),
                fastMode: Binding(get: { model.thread(WebsiteCaptures.freshThreadID)?.fastMode ?? false }, set: { on in model.updateThread(WebsiteCaptures.freshThreadID) { $0.fastMode = on } }),
                onTitleTap: {},
                onReset: {}
            )
            let popover = stage.presentPopover(card.environment(model), width: 330, chipOf: WebsiteCaptures.freshThreadID)
            await stage.holdPopover(popover, seconds: 1.6)
            return popover
        }
        // 5. tour-panels: the team's panel and a popped-out head over the lead's chat.
        await TourCaptures.panelsScene(model, stage, recorder)
        // 6. tour-theme-<rawValue>: four themes far apart, one of them light.
        for theme in [AppTheme.tokyoNight, .gruvbox, .catppuccinLatte, .rosePine] {
            await capture(model, stage, recorder, name: "tour-theme-\(theme.rawValue)", backdrop: .themes, size: NSSize(width: 900, height: 560)) {
                if !model.sidebar.isVisible { model.sidebar.toggle() }
                model.selectedThreadID = WebsiteCaptures.composerThreadID
                model.settings.theme = theme
                try? await Task.sleep(for: .milliseconds(700))
                return nil
            }
        }
        model.settings.theme = .dark

        // 7. tour-window: the tour itself, over the backdrop alone, for the website.
        WebsiteCaptures.log("scene tour-window")
        stage.setBackdrop(backdropView(.welcome))
        stage.setWindowHidden(true)
        let tourWindow = TourWindowController.shared.present(pages: Tour.pages)
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(1_400))
        await recorder.still("tour-window", Stage.tourRect(around: tourWindow.frame))
        TourWindowController.shared.close()
        stage.setWindowHidden(false)

        await recorder.finish()
        WebsiteCaptures.log("tour done")
        exit(0)
    }

    /// Sets the gradient backdrop, resizes, settles, runs the body (which stages the
    /// scene and returns any popover to keep open for the shot), photographs the
    /// 16:10 tour rect, then closes the popover and runs `after`.
    private static func capture(
        _ model: AppModel, _ stage: Stage, _ recorder: Recorder,
        name: String, backdrop: Backdrop, size: NSSize,
        body: () async -> NSPopover?,
        after: () -> Void = {}
    ) async {
        WebsiteCaptures.log("scene \(name)")
        stage.setBackdrop(backdropView(backdrop))
        stage.resize(to: size)
        await stage.ensureActive()
        try? await Task.sleep(for: .milliseconds(900))
        _ = model
        let popover = await body()
        await recorder.still(name, stage.tourCaptureRect)
        popover?.close()
        after()
    }
}
