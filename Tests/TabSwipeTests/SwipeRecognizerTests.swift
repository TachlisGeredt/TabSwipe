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

    func testQuickSwipeRightEmitsPreviousTab() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        // Anchor at x = 0.40
        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        XCTAssertEqual(r1.actions, [])
        XCTAssertTrue(r1.shouldSuppressSystemGesture)

        // Below threshold (dx = +0.02)
        let r2 = recognizer.process(touches: threeFingers(x: 0.42), commandOnly: true)
        XCTAssertEqual(r2.actions, [])
        XCTAssertTrue(r2.shouldSuppressSystemGesture)

        // Crosses initialThreshold (dx = +0.04) -> previousTab (natural macOS direction)
        let r3 = recognizer.process(touches: threeFingers(x: 0.44), commandOnly: true)
        XCTAssertEqual(r3.actions, [.previousTab])
        XCTAssertTrue(r3.shouldSuppressSystemGesture)
    }

    func testContinuousSwipeLeftEmitsStepAtEveryStepDistance() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        // Anchor at 0.60
        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true)

        // 1st step at 0.56 (dx = -0.04 >= 0.035) -> anchor advances to 0.565
        let step1 = recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true)
        XCTAssertEqual(step1.actions, [.nextTab])

        // Small extra move (0.54, delta -0.025 < 0.045) -> no step yet
        let between = recognizer.process(touches: threeFingers(x: 0.54), commandOnly: true)
        XCTAssertEqual(between.actions, [])

        // 2nd step at 0.515 (delta -0.05 >= 0.045) -> anchor advances to 0.520
        let step2 = recognizer.process(touches: threeFingers(x: 0.515), commandOnly: true)
        XCTAssertEqual(step2.actions, [.nextTab])

        // 3rd step at 0.47 (delta -0.05 >= 0.045) -> anchor advances to 0.475
        let step3 = recognizer.process(touches: threeFingers(x: 0.47), commandOnly: true)
        XCTAssertEqual(step3.actions, [.nextTab])
    }

    func testReverseDirectionMidSwipeStepsBackWithoutLifting() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true)
        // Step left (nextTab) -> anchor advances to 0.565
        XCTAssertEqual(recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true).actions, [.nextTab])

        // Reverse right by +0.05 (to 0.615, delta +0.05 >= 0.045) -> previousTab
        let reversed = recognizer.process(touches: threeFingers(x: 0.615), commandOnly: true)
        XCTAssertEqual(reversed.actions, [.previousTab])
    }

    func testLiftFingersWhileHoldingCommandResetsCleanly() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true)
        XCTAssertEqual(recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true).actions, [.nextTab])

        // Lift fingers while ⌘ remains held
        let lift = recognizer.process(touches: [], commandOnly: true)
        XCTAssertEqual(lift.actions, [])
        XCTAssertFalse(lift.shouldSuppressSystemGesture)

        // Fresh swipe without releasing ⌘
        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true)
        XCTAssertEqual(recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true).actions, [.nextTab])
    }

    func testIgnoredWhenCommandNotHeld() {
        let recognizer = SwipeRecognizer()

        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: false)
        let r2 = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: false)
        XCTAssertEqual(r1.actions, [])
        XCTAssertFalse(r1.shouldSuppressSystemGesture)
        XCTAssertEqual(r2.actions, [])
        XCTAssertFalse(r2.shouldSuppressSystemGesture)
    }

    func testIgnoredForTwoOrFourFingers() {
        let recognizer = SwipeRecognizer()

        let twoFingers = [TouchPoint(x: 0.4, y: 0.5), TouchPoint(x: 0.5, y: 0.5)]
        let fourFingers = [
            TouchPoint(x: 0.3, y: 0.5),
            TouchPoint(x: 0.4, y: 0.5),
            TouchPoint(x: 0.5, y: 0.5),
            TouchPoint(x: 0.6, y: 0.5),
        ]

        let r2 = recognizer.process(touches: twoFingers, commandOnly: true)
        let r4 = recognizer.process(touches: fourFingers, commandOnly: true)
        XCTAssertEqual(r2.actions, [])
        XCTAssertFalse(r2.shouldSuppressSystemGesture)
        XCTAssertEqual(r4.actions, [])
        XCTAssertFalse(r4.shouldSuppressSystemGesture)
    }

    func testVerticalSwipeIsRejectedAndStaysIgnoredUntilLift() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        _ = recognizer.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true)
        // Strong vertical movement
        let vertical = recognizer.process(touches: threeFingers(x: 0.505, y: 0.60), commandOnly: true)
        XCTAssertEqual(vertical.actions, [])
        XCTAssertTrue(vertical.shouldSuppressSystemGesture)

        // Subsequent horizontal drift in the same gesture must not trigger
        let drift = recognizer.process(touches: threeFingers(x: 0.70, y: 0.60), commandOnly: true)
        XCTAssertEqual(drift.actions, [])
    }

    func testResetClearsInProgressGesture() {
        let recognizer = SwipeRecognizer(initialThreshold: 0.035, stepDistance: 0.045)

        _ = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true)
        recognizer.reset()

        // Re-anchors at 0.50 instead of firing immediately against 0.40
        let afterReset = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true)
        XCTAssertEqual(afterReset.actions, [])
        XCTAssertTrue(afterReset.shouldSuppressSystemGesture)
    }
}
