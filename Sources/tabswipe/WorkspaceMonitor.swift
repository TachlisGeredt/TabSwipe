import AppKit
import Foundation
import TabSwipeCore

/// Represents the currently focused supported browser window.
struct ActiveBrowser: Equatable {
    let bundleIdentifier: String
    let localizedName: String
    let pid: pid_t
    let shortcuts: BrowserShortcuts
}

/// Event-driven observer that tracks when a supported browser becomes or stops being frontmost.
/// Uses `NSWorkspace.didActivateApplicationNotification` (zero polling, 0% idle CPU).
final class WorkspaceMonitor {
    private var observer: NSObjectProtocol?
    private let onChange: (ActiveBrowser?) -> Void

    init(onChange: @escaping (ActiveBrowser?) -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        // Emit initial frontmost app state immediately.
        notify(for: NSWorkspace.shared.frontmostApplication)

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.notify(for: app ?? NSWorkspace.shared.frontmostApplication)
        }
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func notify(for app: NSRunningApplication?) {
        guard let app = app,
              let bundleID = app.bundleIdentifier,
              let shortcuts = BrowserRegistry.shortcuts(for: bundleID)
        else {
            onChange(nil)
            return
        }

        let target = ActiveBrowser(
            bundleIdentifier: bundleID,
            localizedName: app.localizedName ?? bundleID,
            pid: app.processIdentifier,
            shortcuts: shortcuts
        )
        onChange(target)
    }
}
