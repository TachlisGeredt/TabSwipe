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

// 1. Continuous velocity gradient clamps and interpolates smoothly
do {
    let r = SwipeRecognizer(
        initialThreshold: 0.035,
        maxStepDistance: 0.045,
        minStepDistance: 0.028,
        slowSpeed: 0.25,
        fastSpeed: 2.20
    )
    expect(abs(r.stepDistance(forSpeed: 0.0) - 0.045) < 1e-6, "Slow floor clamps at 0.045")
    expect(abs(r.stepDistance(forSpeed: 0.25) - 0.045) < 1e-6, "Slow boundary equals 0.045")
    expect(abs(r.stepDistance(forSpeed: 1.225) - 0.0365) < 1e-6, "Midpoint speed interpolates to 0.0365")
    expect(abs(r.stepDistance(forSpeed: 2.20) - 0.028) < 1e-6, "Fast boundary equals 0.028")
    expect(abs(r.stepDistance(forSpeed: 5.0) - 0.028) < 1e-6, "Fast ceiling clamps at 0.028")
}

// 2. Quick short swipe right -> previousTab (natural macOS direction)
do {
    let r = SwipeRecognizer()
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: true, timestamp: 1.0)
    expect(f1.actions.isEmpty && f1.shouldSuppressSystemGesture, "Anchor frame suppresses without firing")
    let f2 = r.process(touches: threeFingers(x: 0.42), commandOnly: true, timestamp: 1.2)
    expect(f2.actions.isEmpty && f2.shouldSuppressSystemGesture, "Sub-threshold frame does not fire")
    let f3 = r.process(touches: threeFingers(x: 0.44), commandOnly: true, timestamp: 1.4)
    expect(f3.actions == [.previousTab] && f3.shouldSuppressSystemGesture, "Quick swipe right triggers previousTab")
}

// 3. Fast swipe triggers more tabs than slow swipe while respecting the readable 55ms rate cap
do {
    let slowR = SwipeRecognizer()
    let fastR = SwipeRecognizer()
    var slowTabs = 0
    var fastTabs = 0

    for i in 0...30 {
        let x = 0.90 - Double(i) * 0.01
        slowTabs += slowR.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.10).actions.count
        fastTabs += fastR.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.012).actions.count
    }

    expect(fastTabs > slowTabs, "Fast swipe (\(fastTabs)) switches more tabs than slow swipe (\(slowTabs))")
    expect(fastTabs <= 9, "Rate cap keeps fast sweep readable (got \(fastTabs) tabs in 0.36s)")
}

// 4. Reversing direction mid-swipe steps back without lifting
do {
    let r = SwipeRecognizer()
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 1.0)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 1.5).actions == [.nextTab], "Step left fires nextTab")
    expect(r.process(touches: threeFingers(x: 0.615), commandOnly: true, timestamp: 2.0).actions == [.previousTab], "Reversing right fires previousTab")
}

// 5. Lift fingers while holding Command allows repeat swipe
do {
    let r = SwipeRecognizer()
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 1.0)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 1.5).actions == [.nextTab], "First swipe fires")
    let lift = r.process(touches: [], commandOnly: true, timestamp: 1.6)
    expect(lift.actions.isEmpty && !lift.shouldSuppressSystemGesture, "Finger lift resets")
    _ = r.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 2.0)
    expect(r.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 2.5).actions == [.nextTab], "Second swipe fires without releasing Command")
}

// 6. Ignored when Command is not held alone
do {
    let r = SwipeRecognizer()
    let f1 = r.process(touches: threeFingers(x: 0.40), commandOnly: false, timestamp: 1.0)
    let f2 = r.process(touches: threeFingers(x: 0.60), commandOnly: false, timestamp: 1.1)
    expect(f1.actions.isEmpty && !f1.shouldSuppressSystemGesture, "No Command -> passthrough")
    expect(f2.actions.isEmpty && !f2.shouldSuppressSystemGesture, "No Command swipe -> passthrough")
}

// 7. Ignored for 2 or 4 fingers
do {
    let r = SwipeRecognizer()
    let two = [TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5)]
    let four = [TouchPoint(x: 0.3, y: 0.5), TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5), TouchPoint(x: 0.6, y: 0.5)]
    expect(!r.process(touches: two, commandOnly: true, timestamp: 1.0).shouldSuppressSystemGesture, "2 fingers ignored")
    expect(!r.process(touches: four, commandOnly: true, timestamp: 1.1).shouldSuppressSystemGesture, "4 fingers ignored")
}

// 8. Vertical swipe rejected and stays ignored until lift
do {
    let r = SwipeRecognizer()
    _ = r.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true, timestamp: 1.0)
    expect(r.process(touches: threeFingers(x: 0.505, y: 0.60), commandOnly: true, timestamp: 1.1).actions.isEmpty, "Vertical movement ignored")
    expect(r.process(touches: threeFingers(x: 0.70, y: 0.60), commandOnly: true, timestamp: 1.2).actions.isEmpty, "Subsequent drift ignored")
}

// 9. BrowserRegistry matching & shortcuts
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
