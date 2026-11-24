import Foundation

/// Modifier flags represented independently of CoreGraphics so TabSwipeCore stays pure Swift.
public struct KeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift   = KeyModifiers(rawValue: 1 << 1)
    public static let option  = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// A macOS virtual key code paired with modifier flags.
public struct KeyShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// Tab navigation shortcuts for a browser.
public struct BrowserShortcuts: Equatable, Sendable {
    public let nextTab: KeyShortcut
    public let previousTab: KeyShortcut

    public init(nextTab: KeyShortcut, previousTab: KeyShortcut) {
        self.nextTab = nextTab
        self.previousTab = previousTab
    }

    /// Standard macOS browser tab shortcuts: ⌘⇧] (next) and ⌘⇧[ (previous).
    /// Key codes: 30 = ']', 33 = '[' (US ANSI layout).
    public static let standard = BrowserShortcuts(
        nextTab: KeyShortcut(keyCode: 30, modifiers: [.command, .shift]),
        previousTab: KeyShortcut(keyCode: 33, modifiers: [.command, .shift])
    )

    /// Arc browser sidebar tab navigation: ⌘⌥↓ (next) and ⌘⌥↑ (previous).
    /// Key codes: 125 = Down Arrow, 126 = Up Arrow.
    public static let arc = BrowserShortcuts(
        nextTab: KeyShortcut(keyCode: 125, modifiers: [.command, .option]),
        previousTab: KeyShortcut(keyCode: 126, modifiers: [.command, .option])
    )
}

/// Built-in registry of supported macOS browsers and their tab-switching shortcuts.
/// To add a browser, append its macOS bundle identifier to `browsers` below and rebuild.
public enum BrowserRegistry {
    public static let browsers: [String: BrowserShortcuts] = [
        // Safari
        "com.apple.Safari": .standard,
        "com.apple.SafariTechnologyPreview": .standard,

        // Google Chrome
        "com.google.Chrome": .standard,
        "com.google.Chrome.beta": .standard,
        "com.google.Chrome.dev": .standard,
        "com.google.Chrome.canary": .standard,

        // Brave
        "com.brave.Browser": .standard,
        "com.brave.Browser.beta": .standard,
        "com.brave.Browser.nightly": .standard,

        // Firefox
        "org.mozilla.firefox": .standard,
        "org.mozilla.firefoxdeveloperedition": .standard,
        "org.mozilla.nightly": .standard,

        // Microsoft Edge
        "com.microsoft.edgemac": .standard,
        "com.microsoft.edgemac.Beta": .standard,
        "com.microsoft.edgemac.Dev": .standard,
        "com.microsoft.edgemac.Canary": .standard,

        // Arc
        "company.thebrowser.Browser": .arc,

        // Vivaldi
        "com.vivaldi.Vivaldi": .standard,

        // Opera
        "com.operasoftware.Opera": .standard,
        "com.operasoftware.OperaGX": .standard,

        // Orion
        "com.kagi.kagimacOS": .standard,

        // Zen Browser
        "app.zen-browser.zen": .standard,
        "io.github.zen-browser.zen": .standard,

        // Chromium
        "org.chromium.Chromium": .standard,
    ]

    private static let lowercasedLookup: [String: BrowserShortcuts] = {
        var map: [String: BrowserShortcuts] = [:]
        map.reserveCapacity(browsers.count)
        for (bundleID, shortcuts) in browsers {
            map[bundleID.lowercased()] = shortcuts
        }
        return map
    }()

    /// Returns the tab-switching shortcuts if `bundleIdentifier` belongs to a supported browser.
    public static func shortcuts(for bundleIdentifier: String?) -> BrowserShortcuts? {
        guard let bundleID = bundleIdentifier?.lowercased() else { return nil }
        return lowercasedLookup[bundleID]
    }

    /// Returns `true` if `bundleIdentifier` belongs to a supported browser.
    public static func isSupportedBrowser(_ bundleIdentifier: String?) -> Bool {
        shortcuts(for: bundleIdentifier) != nil
    }
}
