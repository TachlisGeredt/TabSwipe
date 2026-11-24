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

    func testVelocityGradientInterpolatesSmoothlyAndClamps() {
        let recognizer = SwipeRecognizer(
            initialThreshold: 0.035,
            maxStepDistance: 0.045,
            minStepDistance: 0.028,
            slowSpeed: 0.25,
            fastSpeed: 2.20
        )

        // Slow floor clamps at maxStepDistance
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 0.0), 0.045, accuracy: 1e-6)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 0.25), 0.045, accuracy: 1e-6)

        // Midpoint speed (1.225) sits halfway (0.0365)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 1.225), 0.0365, accuracy: 1e-6)

        // Fast ceiling clamps at minStepDistance
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 2.20), 0.028, accuracy: 1e-6)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 5.00), 0.028, accuracy: 1e-6)
    }

    func testFastSwipeTriggersMoreTabsThanSlowSwipeAndRespectsRateCap() {
        let slowRecognizer = SwipeRecognizer()
        let fastRecognizer = SwipeRecognizer()

        // Both swipe left from 0.90 to 0.60 (total distance 0.30 in 30 frames of 0.01)
        var slowTabs = 0
        var fastTabs = 0

        for i in 0...30 {
            let x = 0.90 - Double(i) * 0.01
            // Slow: 0.10s per 0.01 -> speed = 0.10 widths/sec (uses maxStepDistance = 0.045)
            slowTabs += slowRecognizer.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.10).actions.count

            // Brisk/fast: 0.012s per 0.01 -> speed = ~0.83 widths/sec, total 0.36s (respects 55ms rate cap)
            fastTabs += fastRecognizer.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.012).actions.count
        }

        XCTAssertGreaterThan(fastTabs, slowTabs)
        // Rate cap keeps even a fast sweep visually readable (max ~9 tabs in 0.36s at 38ms/tab)
        XCTAssertLessThanOrEqual(fastTabs, 9)
    }

    func testReverseDirectionMidSwipeStepsBackWithoutLifting() {
        let recognizer = SwipeRecognizer()

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 1.0)
        // Slow step left (nextTab) -> anchor advances to 0.565
        XCTAssertEqual(
            recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 1.5).actions,
            [.nextTab]
        )

        // Reverse right slowly by +0.05 (to 0.615, delta +0.05 >= 0.045) -> previousTab
        let reversed = recognizer.process(touches: threeFingers(x: 0.615), commandOnly: true, timestamp: 2.0)
        XCTAssertEqual(reversed.actions, [.previousTab])
    }

    func testLiftFingersWhileHoldingCommandResetsCleanly() {
        let recognizer = SwipeRecognizer()

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 1.0)
        XCTAssertEqual(
            recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 1.5).actions,
            [.nextTab]
        )

        let lift = recognizer.process(touches: [], commandOnly: true, timestamp: 1.6)
        XCTAssertEqual(lift.actions, [])
        XCTAssertFalse(lift.shouldSuppressSystemGesture)

        _ = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: true, timestamp: 2.0)
        XCTAssertEqual(
            recognizer.process(touches: threeFingers(x: 0.56), commandOnly: true, timestamp: 2.5).actions,
            [.nextTab]
        )
    }

    func testIgnoredWhenCommandNotHeld() {
        let recognizer = SwipeRecognizer()

        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: false, timestamp: 1.0)
        let r2 = recognizer.process(touches: threeFingers(x: 0.60), commandOnly: false, timestamp: 1.1)
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

        let r2 = recognizer.process(touches: twoFingers, commandOnly: true, timestamp: 1.0)
        let r4 = recognizer.process(touches: fourFingers, commandOnly: true, timestamp: 1.1)
        XCTAssertEqual(r2.actions, [])
        XCTAssertFalse(r2.shouldSuppressSystemGesture)
        XCTAssertEqual(r4.actions, [])
        XCTAssertFalse(r4.shouldSuppressSystemGesture)
    }

    func testVerticalSwipeIsRejectedAndStaysIgnoredUntilLift() {
        let recognizer = SwipeRecognizer()

        _ = recognizer.process(touches: threeFingers(x: 0.50, y: 0.50), commandOnly: true, timestamp: 1.0)
        let vertical = recognizer.process(touches: threeFingers(x: 0.505, y: 0.60), commandOnly: true, timestamp: 1.1)
        XCTAssertEqual(vertical.actions, [])
        XCTAssertTrue(vertical.shouldSuppressSystemGesture)

        let drift = recognizer.process(touches: threeFingers(x: 0.70, y: 0.60), commandOnly: true, timestamp: 1.2)
        XCTAssertEqual(drift.actions, [])
    }

    func testResetClearsInProgressGesture() {
        let recognizer = SwipeRecognizer()

        _ = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true, timestamp: 1.0)
        recognizer.reset()

        let afterReset = recognizer.process(touches: threeFingers(x: 0.50), commandOnly: true, timestamp: 1.1)
        XCTAssertEqual(afterReset.actions, [])
        XCTAssertTrue(afterReset.shouldSuppressSystemGesture)
    }
}
