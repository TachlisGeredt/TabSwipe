import XCTest
@testable import TabSwipeCore

final class SwipeRecognizerTests: XCTestCase {
    private func threeFingers(x: Double, y: Double = 0.5) -> [TouchPoint] {
        [
            TouchPoint(x: x - 0.05, y: y),
            TouchPoint(x: x, y: y),
            TouchPoint(x: x + 0.05, y: y),
        ]
    }

    func testSwipeRightEmitsNextTabOnce() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        // Anchor at x = 0.40
        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        XCTAssertNil(r1.action)
        XCTAssertTrue(r1.shouldSuppressSystemGesture)

        // Below threshold (dx = +0.04)
        let r2 = recognizer.process(touches: threeFingers(x: 0.44), commandOnly: true)
        XCTAssertNil(r2.action)
        XCTAssertTrue(r2.shouldSuppressSystemGesture)

        // Crosses threshold (dx = +0.09) -> nextTab
        let r3 = recognizer.process(touches: threeFingers(x: 0.49), commandOnly: true)
        XCTAssertEqual(r3.action, .nextTab)
        XCTAssertTrue(r3.shouldSuppressSystemGesture)

        // Continuing to slide right stays locked (strictly single-step: 1 swipe = 1 tab)
        let r4 = recognizer.process(touches: threeFingers(x: 0.70), commandOnly: true)
        XCTAssertNil(r4.action)
        XCTAssertTrue(r4.shouldSuppressSystemGesture)
    }

    func testSwipeLeftEmitsPreviousTabOnce() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true)
        let result = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true)
        XCTAssertEqual(result.action, .previousTab)
        XCTAssertTrue(result.shouldSuppressSystemGesture)

        // Continued left movement does not double-trigger
        let continued = recognizer.process(touches: threeFingers(x: 0.30), commandOnly: true)
        XCTAssertNil(continued.action)
        XCTAssertTrue(continued.shouldSuppressSystemGesture)
    }

    func testLiftFingersWhileHoldingCommandAllowsRepeatSwipe() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        // First swipe right
        _ = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        let first = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true)
        XCTAssertEqual(first.action, .nextTab)

        // Lift fingers while ⌘ remains held
        let lift = recognizer.process(touches: [], commandOnly: true)
        XCTAssertNil(lift.action)
        XCTAssertFalse(lift.shouldSuppressSystemGesture)

        // Second swipe right without releasing ⌘
        _ = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        let second = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true)
        XCTAssertEqual(second.action, .nextTab)
    }

    func testIgnoredWhenCommandNotHeld() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: false)
        let r2 = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: false)
        XCTAssertNil(r1.action)
        XCTAssertFalse(r1.shouldSuppressSystemGesture)
        XCTAssertNil(r2.action)
        XCTAssertFalse(r2.shouldSuppressSystemGesture)
    }

    func testIgnoredForTwoOrFourFingers() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        let twoFingers = [TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5)]
        let fourFingers = [
            TouchPoint(x: 0.3, y: 0.5),
            TouchPoint(x: 0.4, y: 0.5),
            TouchPoint(x: 0.5, y: 0.5),
            TouchPoint(x: 0.6, y: 0.5),
        ]

        let r2 = recognizer.process(touches: twoFingers, commandOnly: true)
        let r4 = recognizer.process(touches: fourFingers, commandOnly: true)
        XCTAssertNil(r2.action)
        XCTAssertFalse(r2.shouldSuppressSystemGesture)
        XCTAssertNil(r4.action)
        XCTAssertFalse(r4.shouldSuppressSystemGesture)
    }

    func testVerticalSwipeIsRejectedAndStaysIgnoredUntilLift() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        _ = recognizer.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true)
        // Strong vertical movement
        let vertical = recognizer.process(touches: threeFingers(x: 0.51, y: 0.65), commandOnly: true)
        XCTAssertNil(vertical.action)
        XCTAssertTrue(vertical.shouldSuppressSystemGesture)

        // Subsequent horizontal drift in the same gesture must not trigger
        let drift = recognizer.process(touches: threeFingers(x: 0.70, y: 0.65), commandOnly: true)
        XCTAssertNil(drift.action)
    }

    func testResetClearsInProgressGesture() {
        let recognizer = SwipeRecognizer(horizontalThreshold: 0.075)

        _ = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        recognizer.reset()

        // Re-anchors at 0.50 instead of firing immediately against 0.40
        let afterReset = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true)
        XCTAssertNil(afterReset.action)
        XCTAssertTrue(afterReset.shouldSuppressSystemGesture)
    }
}
