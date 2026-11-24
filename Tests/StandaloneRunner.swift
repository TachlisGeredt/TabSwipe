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

// 1. Swipe right -> nextTab once (single-step)
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: true)
    expect(f1.action == nil && f1.shouldSuppressSystemGesture, "Anchor frame suppresses without firing")
    let f2 = r.process(touches: threeFingers(x: 0.44), commandOnly: true)
    expect(f2.action == nil && f2.shouldSuppressSystemGesture, "Sub-threshold frame does not fire")
    let f3 = r.process(touches: threeFingers(x: 0.49), commandOnly: true)
    expect(f3.action == .nextTab && f3.shouldSuppressSystemGesture, "Swipe right triggers nextTab")
    let f4 = r.process(touches: threeFingers(x: 0.70), commandOnly: true)
    expect(f4.action == nil && f4.shouldSuppressSystemGesture, "Continued slide stays single-step")
}

// 2. Swipe left -> previousTab once
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true)
    let f2 = r.process(touches: threeFingers(x: 0.50), commandOnly: true)
    expect(f2.action == .previousTab && f2.shouldSuppressSystemGesture, "Swipe left triggers previousTab")
    let f3 = r.process(touches: threeFingers(x: 0.30), commandOnly: true)
    expect(f3.action == nil && f3.shouldSuppressSystemGesture, "Continued left slide stays single-step")
}

// 3. Lift fingers while holding Command allows repeat swipe
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    _ = r.process(touches: threeFingers(x: 0.40), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.50), commandOnly: true).action == .nextTab, "First swipe fires")
    let lift = r.process(touches: [], commandOnly: true)
    expect(lift.action == nil && !lift.shouldSuppressSystemGesture, "Finger lift resets")
    _ = r.process(touches: threeFingers(x: 0.40), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.50), commandOnly: true).action == .nextTab, "Second swipe fires without releasing Command")
}

// 4. Ignored when Command is not held alone
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: false)
    let f2 = r.process(touches: threeFingers(x: 0.60), commandOnly: false)
    expect(f1.action == nil && !f1.shouldSuppressSystemGesture, "No Command -> passthrough")
    expect(f2.action == nil && !f2.shouldSuppressSystemGesture, "No Command swipe -> passthrough")
}

// 5. Ignored for 2 or 4 fingers
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    let two = [TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5)]
    let four = [TouchPoint(x: 0.3, y: 0.5), TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5), TouchPoint(x: 0.6, y: 0.5)]
    expect(!r.process(touches: two, commandOnly: true).shouldSuppressSystemGesture, "2 fingers ignored")
    expect(!r.process(touches: four, commandOnly: true).shouldSuppressSystemGesture, "4 fingers ignored")
}

// 6. Vertical swipe rejected and stays ignored until lift
do {
    let r = SwipeRecognizer(horizontalThreshold: 0.075)
    _ = r.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true)
    expect(r.process(touches: threeFingers(x: 0.51, y: 0.65), commandOnly: true).action == nil, "Vertical movement ignored")
    expect(r.process(touches: threeFingers(x: 0.70, y: 0.65), commandOnly: true).action == nil, "Subsequent drift ignored")
}

// 7. BrowserRegistry matching & shortcuts
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
