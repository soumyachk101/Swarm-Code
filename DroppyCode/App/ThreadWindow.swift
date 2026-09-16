import AppKit

final class ThreadWindow: NSWindow {
    var selectThread: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48, attachedSheet == nil {
            let chord = KeyChord(keyCode: Int(event.keyCode), modifiers: event.modifierFlags)
            if chord == ShortcutStore.shared.chord(for: .nextThread) {
                selectThread?(1)
                return true
            }
            if chord == ShortcutStore.shared.chord(for: .previousThread) {
                selectThread?(-1)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
