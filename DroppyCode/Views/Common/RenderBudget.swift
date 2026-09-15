import SwiftUI

// MARK: - Scroll activity

/// Whether the reader is scrolling a timeline right now: the drag, the flick and the coast
/// after it, and wheel ticks, until the content has been still for a beat. Each timeline
/// reports its own; this is the union. It flips at most twice per scroll, so a view that
/// reads it re-renders at the start and at the end, never per frame. Motion that has no
/// business running under a moving finger (a progress sweep, a shimmer, a breathing ring)
/// pauses on it and gives the frame back to the scroll.
@MainActor
@Observable
final class ScrollActivity {
    static let shared = ScrollActivity()

    private(set) var isScrolling = false
    @ObservationIgnored private var scrolling: Set<UUID> = []

    /// Called by a timeline when its reader starts or stops scrolling it.
    func setScrolling(_ active: Bool, timeline: UUID) {
        if active { scrolling.insert(timeline) } else { scrolling.remove(timeline) }
        let now = !scrolling.isEmpty
        if now != isScrolling { isScrolling = now }
    }
}

// MARK: - Glass budget

extension EnvironmentValues {
    /// True for everything inside a floating glass panel: a helper's, the team's, the
    /// usage panel. Liquid Glass samples what lies behind it on every frame that content
    /// moves, and a panel already does that for its whole surface; a capsule or a circle
    /// drawn as glass on top of it is a second sampling pass for the same pixels, and with
    /// a few panels open those added up to twenty-odd passes over a scrolling timeline.
    /// Controls read this and draw as a flat tinted fill on a panel instead.
    @Entry var isOnGlassPanel = false
}

extension Chrome {
    /// The fill of a control drawn flat on a glass panel (see `isOnGlassPanel`): the
    /// theme's tint over the panel's scrim, lifted a touch, and brighter under the
    /// pointer the way interactive glass brightens.
    static func panelControlFill(isDark: Bool, hovered: Bool = false) -> Color {
        let lift = hovered ? (isDark ? 0.24 : 0.12) : (isDark ? 0.12 : 0.04)
        return Chrome.glassTint
            .mix(with: isDark ? .white : .black, by: lift)
            .opacity(isDark ? 0.55 : 0.42)
    }
}
