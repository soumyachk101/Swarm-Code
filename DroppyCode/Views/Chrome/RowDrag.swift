import Foundation

/// One live grip-drag reorder of a row in a stack. The grabbed row follows the
/// pointer exactly; whenever its centre passes a neighbour's centre the item
/// moves one slot and the neighbour slides across, with the row's own slot
/// shift folded into `settled` so it never jumps under the pointer.
struct RowDrag<ID: Hashable> {
    var id: ID?
    /// The pointer's travel since the grab.
    var translation: CGFloat = 0
    /// How far the row's slot has already moved toward the pointer through
    /// reorders; subtracting it keeps the row pinned under the pointer.
    var settled: CGFloat = 0

    var visualOffset: CGFloat { translation - settled }

    /// Walks the grabbed row across every neighbour whose centre it has passed,
    /// so a fast flick crosses several rows in one step. `move` swaps the item
    /// with the neighbour (before it for `placeAfter: false`, after it otherwise)
    /// and runs inside the caller's slide animation together with the slot
    /// compensation. Returns whether anything moved.
    mutating func settle(
        order: [ID],
        heights: [ID: CGFloat],
        fallbackHeight: CGFloat,
        move: (_ neighbour: ID, _ placeAfter: Bool, _ slot: CGFloat) -> Void
    ) -> Bool {
        guard let id, let index = order.firstIndex(of: id) else { return false }
        let own = heights[id] ?? fallbackHeight
        var current = index
        var moved = false
        while true {
            let offset = visualOffset
            if offset > 0, current + 1 < order.count {
                let next = order[current + 1]
                let slot = heights[next] ?? fallbackHeight
                guard offset > (own + slot) / 2 else { break }
                move(next, true, slot)
                current += 1
                moved = true
            } else if offset < 0, current > 0 {
                let previous = order[current - 1]
                let slot = heights[previous] ?? fallbackHeight
                guard -offset > (own + slot) / 2 else { break }
                move(previous, false, slot)
                current -= 1
                moved = true
            } else {
                break
            }
        }
        return moved
    }
}
