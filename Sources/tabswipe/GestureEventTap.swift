import AppKit
import CoreGraphics
import Foundation
import TabSwipeCore

/// Low-level `CGEventTap` that intercepts 3-finger trackpad gestures while only `⌘ Command` is held,
/// suppresses macOS Desktop Space switching, and emits tab switch actions.
///
/// The tap is kept disabled whenever no supported browser is frontmost so there is zero overhead
/// in all other applications.
final class GestureEventTap {
    private static let gestureEventTypeRawValue: UInt32 = 29 // NSEvent.EventType.gesture
    private static let swipeEventTypeRawValue: UInt32 = 31   // NSEvent.EventType.swipe

    private let recognizer: SwipeRecognizer
    private let onSwipe: (SwipeAction) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = false
    private var isSuppressingGesture = false
    private var lastSuppressedTouchTime: TimeInterval = 0

    init(
        recognizer: SwipeRecognizer = SwipeRecognizer(),
        onSwipe: @escaping (SwipeAction) -> Void
    ) {
        self.recognizer = recognizer
        self.onSwipe = onSwipe
    }

    deinit {
        stop()
    }

    /// Installs the event tap in a disabled state. Returns `false` if Accessibility permission is missing.
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << Self.gestureEventTypeRawValue) |
            (1 << Self.swipeEventTypeRawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let instance = Unmanaged<GestureEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return instance.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        eventTap = tap
        runLoopSource = source
        setEnabled(false)
        return true
    }

    /// Enables or disables event interception dynamically as browser focus changes.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            recognizer.reset()
            isSuppressingGesture = false
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    func stop() {
        setEnabled(false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isEnabled, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        // Always read live HID keyboard modifier flags: macOS synthesized Dock/Spaces packets on
        // event type 29 often arrive with event.flags == 0 even while ⌘ is physically held down.
        let liveFlags = CGEventSource.flagsState(.hidSystemState)
        let commandOnly = isCommandOnly(liveFlags)

        if type == .flagsChanged {
            if !commandOnly {
                recognizer.reset()
                isSuppressingGesture = false
            }
            return Unmanaged.passUnretained(event)
        }

        // Legacy 3-finger swipe event: swallow while exact ⌘ is held.
        if type.rawValue == Self.swipeEventTypeRawValue {
            return commandOnly ? nil : Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.gestureEventTypeRawValue else {
            return Unmanaged.passUnretained(event)
        }

        let now = ProcessInfo.processInfo.systemUptime

        guard let nsEvent = NSEvent(cgEvent: event) else {
            return commandOnly ? nil : Unmanaged.passUnretained(event)
        }

        let allTouches = nsEvent.allTouches()

        // Synthesized Dock/Spaces fluid-gesture packets arrive on event type 29 with no NSTouch
        // payload. Swallow them immediately whenever ⌘ is held (and briefly after) so macOS never
        // starts sliding the desktop Space.
        if allTouches.isEmpty {
            if commandOnly || isSuppressingGesture || (now - lastSuppressedTouchTime) < 0.30 {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard commandOnly else {
            recognizer.reset()
            isSuppressingGesture = false
            return Unmanaged.passUnretained(event)
        }

        let touchingPoints = nsEvent.touches(matching: .touching, in: nil).map { touch in
            TouchPoint(x: Double(touch.normalizedPosition.x), y: Double(touch.normalizedPosition.y))
        }

        let result = recognizer.process(touches: touchingPoints, commandOnly: true)
        isSuppressingGesture = result.shouldSuppressSystemGesture
        if result.shouldSuppressSystemGesture {
            lastSuppressedTouchTime = now
        }

        if let action = result.action {
            onSwipe(action)
        }

        return result.shouldSuppressSystemGesture ? nil : Unmanaged.passUnretained(event)
    }

    /// True if either Left or Right ⌘ is held and Shift, Option, and Control are not held.
    private func isCommandOnly(_ flags: CGEventFlags) -> Bool {
        let disallowed: CGEventFlags = [.maskShift, .maskAlternate, .maskControl]
        return flags.contains(.maskCommand) && flags.isDisjoint(with: disallowed)
    }
}
