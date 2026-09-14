import AppKit

/// The soft two-note chime that marks a turn finishing: a rising fifth with a celesta-like
/// tone, synthesized on first use so no sound file ships with the app and the tone is
/// tunable right here.
@MainActor
enum FinishChime {
    /// How loud the chime plays relative to the system volume. Well under a stock alert:
    /// it registers without cutting into whatever else is playing.
    private static let volume: Float = 0.35

    private static let sound: NSSound? = {
        let sound = NSSound(data: wave())
        sound?.volume = volume
        return sound
    }()

    static func play() {
        // NSSound declines a play while one is in flight, so several threads finishing in
        // the same moment make one chime, never a pile-up.
        sound?.play()
    }

    // MARK: - Synthesis

    /// A note of the chime: when it starts and how strongly it rings, relative to the other.
    private struct Note {
        var frequency: Double
        var onset: Double
        var level: Double
    }

    /// One sine in a note's tone: its frequency as a multiple of the fundamental, how loud it
    /// starts, and how quickly it fades (the seconds it takes to fall by about two thirds).
    private struct Partial {
        var multiple: Double
        var level: Double
        var decay: Double
    }

    /// D5 up to A5, the second note a beat later and a touch stronger, the way "done" lands.
    private static let notes = [
        Note(frequency: 587.33, onset: 0, level: 0.8),
        Note(frequency: 880, onset: 0.14, level: 1),
    ]

    /// The fundamental carries the tone; the octave and double octave add a brief glint at
    /// the strike and are gone within a tenth of a second, which keeps it soft rather than pingy.
    private static let partials = [
        Partial(multiple: 1, level: 1, decay: 0.14),
        Partial(multiple: 2, level: 0.22, decay: 0.06),
        Partial(multiple: 4, level: 0.08, decay: 0.04),
    ]

    private static let sampleRate = 44_100.0
    private static let duration = 0.7
    /// A raised-cosine onset: quick enough to feel struck, with no click.
    private static let attack = 0.006
    /// The tail is inaudible by the end; the fade makes sure it stops without a tick.
    private static let release = 0.08

    /// The chime rendered as 16-bit mono WAV data.
    private static func wave() -> Data {
        let count = Int(sampleRate * duration)
        var samples = [Double](repeating: 0, count: count)
        for note in notes {
            let start = Int(note.onset * sampleRate)
            for index in start..<count {
                let time = Double(index - start) / sampleRate
                let onset = time < attack ? 0.5 - 0.5 * cos(.pi * time / attack) : 1
                let tone = partials.reduce(0.0) { sum, partial in
                    sum + partial.level * exp(-time / partial.decay) * sin(2 * .pi * note.frequency * partial.multiple * time)
                }
                samples[index] += note.level * onset * tone
            }
        }
        let fade = Int(release * sampleRate)
        for index in (count - fade)..<count {
            samples[index] *= Double(count - index) / Double(fade)
        }
        let peak = samples.reduce(0) { max($0, abs($1)) }
        let scale = peak > 0 ? 0.9 / peak : 0

        var data = Data(capacity: 44 + count * 2)
        func append<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate) * 2) // bytes per second
        append(UInt16(2)) // bytes per frame
        append(UInt16(16)) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(count * 2))
        for sample in samples {
            append(Int16((sample * scale * Double(Int16.max)).rounded()))
        }
        return data
    }
}
