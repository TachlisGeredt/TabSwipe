import ApplicationServices
import Foundation

/// Checks macOS Accessibility permission and quietly waits until granted when running headless.
final class PermissionsManager {
    private var pollTimer: DispatchSourceTimer?

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the macOS Accessibility prompt if not yet trusted.
    @discardableResult
    static func requestPermissionPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to Privacy & Security -> Accessibility.
    static func openAccessibilitySettings() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? process.run()
    }

    /// If Accessibility is already trusted, invokes `onTrusted` immediately.
    /// Otherwise checks quietly every `intervalSeconds` until granted, then stops the timer.
    func waitUntilTrusted(intervalSeconds: TimeInterval = 5.0, onTrusted: @escaping () -> Void) {
        if Self.isTrusted() {
            onTrusted()
            return
        }

        stopWaiting()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            if Self.isTrusted() {
                self?.stopWaiting()
                onTrusted()
            }
        }
        pollTimer = timer
        timer.resume()
    }

    func stopWaiting() {
        pollTimer?.cancel()
        pollTimer = nil
    }
}
