import AppKit

struct Hotkey: Equatable {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    init(shortcutKey: ShortcutKey) {
        self.keyCode = shortcutKey.keyCode
        self.modifiers = shortcutKey.modifierFlag
    }
}
