import CoreGraphics
import Foundation
import TabSwipeCore

/// Synthesizes keyboard shortcuts to switch tabs in the currently active browser.
final class TabSwitcher {
    func perform(_ action: SwipeAction, shortcuts: BrowserShortcuts, targetPID: pid_t) {
        let shortcut: KeyShortcut = (action == .nextTab) ? shortcuts.nextTab : shortcuts.previousTab
        let flags = cgEventFlags(from: shortcut.modifiers)

        guard let source = CGEventSource(stateID: .privateState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        else {
            return
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.postToPid(targetPID)
        keyUp.postToPid(targetPID)
    }

    private func cgEventFlags(from modifiers: KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }
}
