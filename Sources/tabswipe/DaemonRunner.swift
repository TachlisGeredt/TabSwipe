import AppKit
import Foundation
import TabSwipeCore

/// Coordinates permissions, event-driven browser monitoring, gesture tapping, and tab switching.
final class DaemonRunner {
    private let permissions = PermissionsManager()
    private let tabSwitcher = TabSwitcher()
    private var workspaceMonitor: WorkspaceMonitor?
    private var gestureTap: GestureEventTap?
    private var activeBrowser: ActiveBrowser?
    private var signalSources: [DispatchSourceSignal] = []

    func run() {
        // Run as a completely invisible background agent (no Dock icon, no menu bar, no windows).
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        installSignalHandlers()
        log("TabSwipe daemon starting.")

        if !PermissionsManager.isTrusted() {
            log("Waiting for Accessibility permission (checking every 5s)...")
        }

        permissions.waitUntilTrusted(intervalSeconds: 5.0) { [weak self] in
            self?.activate()
        }

        app.run()
    }

    private func activate() {
        let tap = GestureEventTap { [weak self] action in
            guard let self = self, let browser = self.activeBrowser else { return }
            self.tabSwitcher.perform(action, shortcuts: browser.shortcuts, targetPID: browser.pid)
        }

        guard tap.start() else {
            log("Failed to create CGEventTap even though Accessibility reported trusted; retrying in 5s.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.activate()
            }
            return
        }

        gestureTap = tap

        let monitor = WorkspaceMonitor { [weak self] browser in
            guard let self = self else { return }
            self.activeBrowser = browser
            self.gestureTap?.setEnabled(browser != nil)
        }
        workspaceMonitor = monitor
        monitor.start()

        log("TabSwipe active (event tap enabled only when a supported browser is focused).")
    }

    private func shutdown() {
        log("TabSwipe daemon stopping.")
        permissions.stopWaiting()
        workspaceMonitor?.stop()
        gestureTap?.stop()
        NSApplication.shared.terminate(nil)
    }

    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutdown()
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}
