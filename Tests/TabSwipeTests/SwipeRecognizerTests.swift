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
            minStepDistance: 0.020,
            slowSpeed: 0.20,
            fastSpeed: 1.40
        )

        // Slow floor clamps at maxStepDistance
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 0.0), 0.045, accuracy: 1e-6)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 0.20), 0.045, accuracy: 1e-6)

        // Midpoint speed (0.80) sits halfway (0.0325)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 0.80), 0.0325, accuracy: 1e-6)

        // Fast ceiling clamps at minStepDistance
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 1.40), 0.020, accuracy: 1e-6)
        XCTAssertEqual(recognizer.stepDistance(forSpeed: 5.00), 0.020, accuracy: 1e-6)
    }

    func testQuickSwipeRightEmitsPreviousTab() {
        let recognizer = SwipeRecognizer()

        let r1 = recognizer.process(touches: threeFingers(x: 0.40), commandOnly: true, timestamp: 1.00)
        XCTAssertEqual(r1.actions, [])
        XCTAssertTrue(r1.shouldSuppressSystemGesture)

        let r2 = recognizer.process(touches: threeFingers(x: 0.42), commandOnly: true, timestamp: 1.20)
        XCTAssertEqual(r2.actions, [])
        XCTAssertTrue(r2.shouldSuppressSystemGesture)

        let r3 = recognizer.process(touches: threeFingers(x: 0.44), commandOnly: true, timestamp: 1.40)
        XCTAssertEqual(r3.actions, [.previousTab])
        XCTAssertTrue(r3.shouldSuppressSystemGesture)
    }

    func testFastSwipeTriggersMoreTabsThanSlowSwipeOverSameDistance() {
        let slowRecognizer = SwipeRecognizer()
        let fastRecognizer = SwipeRecognizer()

        // Both swipe left from 0.80 to 0.60 (total distance 0.20 in 20 frames of 0.01)
        var slowTabs = 0
        var fastTabs = 0

        for i in 0...20 {
            let x = 0.80 - Double(i) * 0.01
            // Slow: 0.10s per 0.01 -> speed = 0.10 widths/sec (uses maxStepDistance = 0.045)
            let slowRes = slowRecognizer.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.10)
            slowTabs += slowRes.actions.count

            // Fast: 0.005s per 0.01 -> speed = 2.0 widths/sec (uses minStepDistance = 0.020)
            let fastRes = fastRecognizer.process(touches: threeFingers(x: x), commandOnly: true, timestamp: Double(i) * 0.005)
            fastTabs += fastRes.actions.count
        }

        // Slow: 1st at 0.035 + 3 steps of 0.045 = 4 tabs
        XCTAssertEqual(slowTabs, 4)
        // Fast: 1st at 0.035 + 8 steps of 0.020 = 9 tabs
        XCTAssertEqual(fastTabs, 9)
        XCTAssertGreaterThan(fastTabs, slowTabs)
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
