import SwiftUI

enum Tour {
    static let pages: [TourPage] = [
        TourPage(imageName: "tour-welcome", title: "Welcome to Droppy Code", description: "One native macOS window for every coding agent you use. Claude, Codex, Gemini, Copilot and more, each in its own thread, on the same Liquid Glass."),
        TourPage(imageName: "tour-hydra", title: "Meet Hydra", description: "One chat, many heads. The lead writes the briefs, sends helper agents out in parallel, each in a copy of your project, and their work lands back in your checkout."),
        TourPage(imageName: "tour-pairs", title: "Pair a strong lead with quick heads", description: "Put a Claude lead over Gemini or OpenCode heads. Pick the pair from the model picker, cap how many heads run at once, and give each side its own effort."),
        TourPage(imageName: "tour-slider", title: "Effort, on a slider", description: "Drag from low to max on any model. In a pair the track blends the lead's colour into the heads', fast mode streaks toward the knob, and the title opens the model picker."),
        TourPage(imageName: "tour-panels", title: "Panels that float", description: "Changes, the terminal and the team's panel dock to any corner and can pop out on their own. The conversation makes room, and everything stays in one window."),
        TourPage(imageName: "tour-themes", title: "Make it yours", description: "\(themeCount) themes, from Catppuccin to Kanagawa, in real Liquid Glass. Built in Swift, so it scrolls at 120 frames a second and starts in a blink."),
    ]

    /// The number of themes spelled out ("Twenty-six"), read from the catalogue so the
    /// page cannot drift from it again: the copy said twenty-five after the twenty-sixth
    /// was added.
    private static var themeCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US")
        let spelled = formatter.string(from: NSNumber(value: AppTheme.allCases.count)) ?? "\(AppTheme.allCases.count)"
        return spelled.prefix(1).uppercased() + spelled.dropFirst()
    }

    @MainActor static func present(model: AppModel) {
        TourWindowController.shared.present(pages: pages, onFinish: { model.settings.hasSeenTour = true }, onClose: { model.settings.hasSeenTour = true })
    }
}
