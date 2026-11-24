# AGENTS.md — Contributor & AI Agent Guide for TabSwipe

This file gives human contributors and AI coding agents a fast, accurate map of **TabSwipe** so modifications stay lightweight, clean, and reliable.

## Project Goals & Constraints

- **Ultra-lightweight**: Invisible macOS LaunchAgent daemon (`NSApplication.setActivationPolicy(.prohibited)`), zero UI, zero third-party dependencies, zero config files.
- **Browser-only interception**: Never keep the `CGEventTap` enabled outside supported browsers. `WorkspaceMonitor` must remain event-driven (`NSWorkspace.didActivateApplicationNotification`), with zero polling.
- **Exact `⌘`-only single-step gesture**: Left or Right `⌘` without `⇧`/`⌥`/`⌃`; 3-finger swipe right → next tab, swipe left → previous tab; 1 swipe = 1 tab; lift fingers while holding `⌘` to swipe again.

## Repository Layout

```
Package.swift                           # Swift 5.8+ SPM manifest (macOS 13+, zero deps)
Sources/
├── TabSwipeCore/                       # Pure-Swift, unit-testable core (no AppKit/CGEvent)
│   ├── BrowserRegistry.swift           # Built-in browser bundle IDs & tab key shortcuts
│   └── SwipeRecognizer.swift           # Single-step 3-finger horizontal swipe state machine
└── tabswipe/                           # macOS daemon & CLI executable
    ├── main.swift                      # Subcommands: install, uninstall, status, run
    ├── DaemonRunner.swift              # Main lifecycle coordinator & signal handling
    ├── WorkspaceMonitor.swift          # Event-driven frontmost-app browser detector
    ├── GestureEventTap.swift           # CGEventTap (type 29 & 31 + flagsChanged)
    ├── TabSwitcher.swift               # Synthesizes CGEvent keystrokes to browser PID
    ├── PermissionsManager.swift        # AXIsProcessTrusted() check & 5s quiet wait loop
    └── LaunchAgentManager.swift        # Installs/uninstalls ~/.local/bin/tabswipe & plist
Tests/
└── TabSwipeTests/
    ├── SwipeRecognizerTests.swift      # State machine tests
    └── BrowserRegistryTests.swift      # Browser lookup & shortcut tests
```

## Build & Test Commands

```bash
make build                 # Build standalone release binary (.build/release/tabswipe) with CLT
make test                  # Run unit tests (uses swift test with Xcode, or StandaloneRunner with CLT)
```

No full Xcode installation is required — Apple Command Line Tools (`swiftc`) is sufficient. If full Xcode is installed, `swift test` and `swift build -c release` also work directly.

## Common Modifications

### Adding a Browser
1. Find the app's bundle ID: `osascript -e 'id of app "BrowserName"'`
2. Add it to `BrowserRegistry.browsers` in `Sources/TabSwipeCore/BrowserRegistry.swift` with `.standard` (`⌘⇧]` / `⌘⇧[`) or a custom `BrowserShortcuts`.
3. Add a test case in `Tests/TabSwipeTests/BrowserRegistryTests.swift`.

### Adjusting Gesture Sensitivity or Direction
- Edit `horizontalThreshold` (default `0.075` of normalized trackpad width) or `horizontalDominanceRatio` (default `1.5`) in `Sources/TabSwipeCore/SwipeRecognizer.swift`.
- Keep `TabSwipeCore` free of `AppKit`/`CoreGraphics` imports so `SwipeRecognizer` stays fast and unit-testable.

## macOS Implementation Gotchas

- **Memory safety in `CGEventTapCallBack`**: Always return `Unmanaged.passUnretained(event)` when passing an event through (returning `passRetained` leaks every event).
- **Space-switch suppression**: macOS emits both raw touch frames (`!nsEvent.allTouches().isEmpty`) and synthesized Dock/Spaces fluid-gesture packets (`nsEvent.allTouches().isEmpty`) on `CGEventType(rawValue: 29)`. Both must return `nil` while suppressing an active `⌘` + 3-finger gesture.
- **Event tap timeout recovery**: Always handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` by re-enabling the tap only when `isEnabled == true`.
- **Accessibility after rebuild**: `tabswipe install` ad-hoc signs `~/.local/bin/tabswipe`. On some macOS versions, replacing the binary may require toggling Accessibility off/on in System Settings.
