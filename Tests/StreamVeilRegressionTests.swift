import Foundation
import SwiftUI
import Testing

@testable import DroppyCode

/// 1.5.1 crashed rendering a Hydra reply whose mention split the prose at a combining
/// mark: "e" + U+0301 is two characters of the runs but one of the join, and slicing the
/// joined string by the runs' own counts trapped past `endIndex` (EXC_BREAKPOINT).
@Test func proseOffsetsAreMeasuredOnTheJoinedString() {
    let view = VeiledText(segments: [
        .prose(AttributedString("cafe")),
        .fixed(Text(verbatim: "Hank")),
        .prose(AttributedString("\u{0301} y limón")),
    ])
    #expect(view.proseEnds == [4, "cafe\u{0301} y limón".count])
}
