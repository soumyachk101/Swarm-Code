// Working indicators, ported from Zeron (https://github.com/zeronsh/zeron), MIT License,
// Copyright (c) 2026 Wing. Source: apps/ios/Zeron/Views/Loaders.swift and apps/ios/Zeron/Theme/Motion.swift.
//
// gradient-spin-pulse: a 3×3 cell grid with per-row "sunrise" tints; each cell pulses once per
// 750ms with phase = distance from bottom-center, so the wave travels upward. The mini variant
// (2×3) snakes clockwise around the perimeter and marks working threads in the sidebar.

import SwiftUI

enum GradientSpin {
    /// Row tints: cool blue, amber, pink.
    static let rowTints: [Color] = [
        Color(red: 0xB6 / 255, green: 0xD3 / 255, blue: 0xEF / 255),
        Color(red: 0xED / 255, green: 0xB1 / 255, blue: 0x85 / 255),
        Color(red: 0xF8 / 255, green: 0x88 / 255, blue: 0xA0 / 255),
    ]
    static let dim = 0.1
    static let period: Double = 0.75

    /// Full at 0, eases down to dim by 45%, holds to 92%, rises to full by 100%.
    static func opacity(phase: Double) -> Double {
        var p = phase.truncatingRemainder(dividingBy: 1)
        if p < 0 { p += 1 }
        if p < 0.45 {
            let t = p / 0.45
            return 1 - (1 - dim) * (t * t * (3 - 2 * t))
        }
        if p < 0.92 { return dim }
        let t = (p - 0.92) / 0.08
        return dim + (1 - dim) * t
    }
}

/// The 3×3 working indicator shown while a reply is being written.
struct WorkingSpinner: View {
    var cellSize: CGFloat = 3.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            grid(time: timeline.date.timeIntervalSinceReferenceDate / GradientSpin.period)
        }
        .accessibilityHidden(true)
    }

    private func grid(time: Double) -> some View {
        VStack(spacing: cellSize * 0.8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: cellSize * 0.8) {
                    ForEach(0..<3, id: \.self) { column in
                        let dx = Double(column - 1)
                        let dy = Double(2 - row)
                        let distance = (dx * dx + dy * dy).squareRoot() / 2.5
                        Rectangle()
                            .fill(GradientSpin.rowTints[row])
                            .frame(width: cellSize, height: cellSize)
                            .opacity(GradientSpin.opacity(phase: time - distance))
                    }
                }
            }
        }
    }
}

/// The 2×3 mini indicator whose cells snake clockwise, for working threads in lists.
struct MiniSpinner: View {
    var cellSize: CGFloat = 2.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ring: [(row: Int, column: Int)] = [
        (0, 0), (0, 1), (1, 1), (2, 1), (2, 0), (1, 0),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            grid(time: timeline.date.timeIntervalSinceReferenceDate / GradientSpin.period)
        }
        .accessibilityLabel(Text("Working"))
    }

    private func grid(time: Double) -> some View {
        VStack(spacing: cellSize * 0.8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: cellSize * 0.8) {
                    ForEach(0..<2, id: \.self) { column in
                        let index = Self.ring.firstIndex { $0.row == row && $0.column == column } ?? 0
                        Rectangle()
                            .fill(GradientSpin.rowTints[row])
                            .frame(width: cellSize, height: cellSize)
                            .opacity(GradientSpin.opacity(phase: time - Double(index) / Double(Self.ring.count)))
                    }
                }
            }
        }
    }
}

/// The word beside the working indicator, rotated every few seconds and seeded per thread,
/// so two threads working at once do not say the same thing.
enum WorkingWords {
    static let words = [
        "Thinking", "Pondering", "Scheming", "Brewing", "Weaving", "Tinkering",
        "Musing", "Composing", "Sifting", "Untangling", "Distilling", "Sketching",
        "Plotting", "Riffing", "Combobulating", "Percolating", "Marinating",
        "Noodling", "Puzzling", "Conjuring", "Creating", "Dancing",
    ]
    static let rotateSeconds: Int64 = 7

    /// FNV-1a over the thread identifier.
    static func seed(_ identifier: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identifier.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    static func word(seed: UInt64, elapsedSeconds: Int64) -> String {
        let step = UInt64(max(0, elapsedSeconds) / rotateSeconds)
        return words[Int((seed &+ step) % UInt64(words.count))]
    }
}
