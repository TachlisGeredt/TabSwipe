import Foundation
import TabSwipeCore

// Lightweight zero-dependency test runner so `make test` works with Apple Command Line Tools alone
// (no full Xcode / XCTest.framework required). Full XCTest suites also live in Tests/TabSwipeTests/.

private var passed = 0
private var failed = 0

private func expect(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        fputs("FAIL (\(file):\(line)): \(message)\n", stderr)
    }
}

private func threeFingers(x: Double, y: Double = 0.5) -> [TouchPoint] {
    [
        TouchPoint(x: x - 0.05, y: y),
        TouchPoint(x: x, y: y),
        TouchPoint(x: x + 0.05, y: y),
    ]
}

// 1. Quick short swipe right -> previousTab (natural macOS direction)
do {
    let r = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: true)
    expect(f1.actions.isEmpty && f1.shouldSuppressSystemGesture, "Anchor frame suppresses without firing")
    let f2 = r.process(touches: threeFingers(x: 0.42), commandOnly: true)
    expect(f2.actions.isEmpty && f2.shouldSuppressSystemGesture, "Sub-threshold frame does not fire")
    let f3 = r.process(touches: threeFingers(x: 0.44), commandOnly: true)
    expect(f3.actions == [.previousTab] && f3.shouldSuppressSystemGesture, "Quick swipe right triggers previousTab")
}

// 2. Continuous swipe left emits a step at every stepDistance
do {
    let r = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true).actions == [.nextTab], "1st step fires at initialThreshold")
    expect(r.process(touches: threeFingers(x: 0.54), commandOnly: true).actions.isEmpty, "Between detents emits nothing")
    expect(r.process(touches: threeFingers(x: 0.515), commandOnly: true).actions == [.nextTab], "2nd step fires at stepDistance")
    expect(r.process(touches: threeFingers(x: 0.47), commandOnly: true).actions == [.nextTab], "3rd step fires at stepDistance")
}

// 3. Reversing direction mid-swipe steps back without lifting
do {
    let r = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true).actions == [.nextTab], "Step left fires nextTab")
    expect(r.process(touches: threeFingers(x: 0.615), commandOnly: true).actions == [.previousTab], "Reversing right fires previousTab")
}

// 4. Lift fingers while holding Command allows repeat swipe
do {
    let r = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true).actions == [.nextTab], "First swipe fires")
    let lift = r.process(touches: [], commandOnly: true)
    expect(lift.actions.isEmpty && !lift.shouldSuppressSystemGesture, "Finger lift resets")
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true).actions == [.nextTab], "Second swipe fires without releasing Command")
}

// 5. Ignored when Command is not held alone
do {
    let r = SwipeRecognizer()
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: false)
    let f2 = r.process(touches: threeFingers(x: 0.60), commandOnly: false)
    expect(f1.actions.isEmpty && !f1.shouldSuppressSystemGesture, "No Command -> passthrough")
    expect(f2.actions.isEmpty && !f2.shouldSuppressSystemGesture, "No Command swipe -> passthrough")
}

// 6. Ignored for 2 or 4 fingers
do {
    let r = SwipeRecognizer()
    let two = [TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5)]
    let four = [TouchPoint(x: 0.3, y: 0.5), TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5), TouchPoint(x: 0.6, y: 0.5)]
    expect(!r.process(touches: two, commandOnly: true).shouldSuppressSystemGesture, "2 fingers ignored")
    expect(!r.process(touches: four, commandOnly: true).shouldSuppressSystemGesture, "4 fingers ignored")
}

// 7. Vertical swipe rejected and stays ignored until lift
do {
    let r = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)
    _ = r.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.505, y: 0.60), commandOnly: true).actions.isEmpty, "Vertical movement ignored")
    expect(r.process(touches: threeFingers(x: 0.70, y: 0.60), commandOnly: true).actions.isEmpty, "Subsequent drift ignored")
}

// 8. BrowserRegistry matching & shortcuts
do {
    expect(BrowserRegistry.isSupportedBrowser("com.apple.Safari"), "Safari supported")
    expect(BrowserRegistry.isSupportedBrowser("com.google.Chrome"), "Chrome supported")
    expect(BrowserRegistry.isSupportedBrowser("org.mozilla.firefox"), "Firefox supported")
    expect(BrowserRegistry.shortcuts(for: "COM.APPLE.SAFARI") == .standard, "Case-insensitive lookup")
    expect(BrowserRegistry.shortcuts(for: "company.thebrowser.Browser") == .arc, "Arc uses sidebar shortcuts")
    expect(!BrowserRegistry.isSupportedBrowser("com.apple.finder"), "Finder rejected")
    expect(!BrowserRegistry.isSupportedBrowser("com.apple.Terminal"), "Terminal rejected")
    expect(!BrowserRegistry.isSupportedBrowser(nil), "nil rejected")
}

print("TabSwipe tests: \(passed) passed, \(failed) failed.")
exit(failed == 0 ? 0 : 1)
