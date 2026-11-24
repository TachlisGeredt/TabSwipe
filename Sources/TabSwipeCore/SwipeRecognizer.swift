import Foundation

/// A normalized trackpad touch position where x and y are in [0.0, 1.0].
public struct TouchPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Tab switch direction emitted by `SwipeRecognizer`.
public enum SwipeAction: Equatable, Sendable {
    /// Natural swipe left (`dx < 0`) → move 1 tab to the right.
    case nextTab
    /// Natural swipe right (`dx > 0`) → move 1 tab to the left.
    case previousTab
}

/// Result of processing a single trackpad touch frame.
public struct SwipeResult: Equatable, Sendable {
    public let actions: [SwipeAction]
    public let shouldSuppressSystemGesture: Bool

    public init(actions: [SwipeAction] = [], shouldSuppressSystemGesture: Bool = false) {
        self.actions = actions
        self.shouldSuppressSystemGesture = shouldSuppressSystemGesture
    }
}

/// Pure-Swift, continuous step-by-step 3-finger horizontal swipe recognizer.
///
/// Behavior:
/// - Activates only when `commandOnly == true` and exactly 3 fingers are touching.
/// - Natural macOS direction: swipe fingers left (`dx < 0`) → `.nextTab` (right);
///   swipe fingers right (`dx > 0`) → `.previousTab` (left).
/// - First tab switches after `initialThreshold` of horizontal travel; each additional
///   `stepDistance` of horizontal travel switches another tab (including mid-swipe direction
///   reversals without lifting fingers).
public final class SwipeRecognizer {
    private enum State {
        case idle
        case tracking(anchorX: Double, anchorY: Double)
        case scrubbing(anchorX: Double)
        case ignored
    }

    /// Horizontal displacement (in normalized trackpad width, 0.0...1.0) required to switch the first tab.
    public let initialThreshold: Double

    /// Horizontal displacement (in normalized trackpad width, 0.0...1.0) required for each subsequent tab.
    public let stepDistance: Double

    /// Minimum ratio of horizontal-to-vertical movement (`|dx| / |dy|`) to lock in as horizontal.
    public let horizontalDominanceRatio: Double

    /// Safety cap on how many tab steps a single touch frame can emit.
    private let maxStepsPerFrame = 3

    private var state: State = .idle

    public init(
        initialThreshold: Double = 0.035,
        stepDistance: Double = 0.045,
        horizontalDominanceRatio: Double = 1.35
    ) {
        self.initialThreshold = initialThreshold
        self.stepDistance = stepDistance
        self.horizontalDominanceRatio = horizontalDominanceRatio
    }

    /// Resets gesture state immediately (e.g., when ⌘ is released or focus leaves the browser).
    public func reset() {
        state = .idle
    }

    /// Processes a trackpad touch frame and returns any triggered tab actions and whether the
    /// underlying system gesture (e.g., Spaces switching) should be suppressed.
    public func process(touches: [TouchPoint], commandOnly: Bool) -> SwipeResult {
        guard commandOnly else {
            state = .idle
            return SwipeResult(actions: [], shouldSuppressSystemGesture: false)
        }

        guard touches.count == 3 else {
            // Finger lifted or extra finger added: reset so user can swipe again while still holding ⌘.
            state = .idle
            return SwipeResult(actions: [], shouldSuppressSystemGesture: false)
        }

        let avgX = (touches[0].x + touches[1].x + touches[2].x) / 3.0
        let avgY = (touches[0].y + touches[1].y + touches[2].y) / 3.0

        switch state {
        case .idle:
            state = .tracking(anchorX: avgX, anchorY: avgY)
            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)

        case .tracking(let anchorX, let anchorY):
            let dx = avgX - anchorX
            let dy = avgY - anchorY
            let absX = abs(dx)
            let absY = abs(dy)

            // Reject clearly vertical 3-finger movements so they don't later drift into a tab switch.
            if absY >= initialThreshold && absY > absX * horizontalDominanceRatio {
                state = .ignored
                return SwipeResult(actions: [], shouldSuppressSystemGesture: true)
            }

            if absX >= initialThreshold && absX > absY * horizontalDominanceRatio {
                var actions: [SwipeAction] = [dx < 0 ? .nextTab : .previousTab]
                var currentAnchorX = anchorX + (dx > 0 ? initialThreshold : -initialThreshold)

                // If a single fast frame crossed additional detents, emit them smoothly too.
                while actions.count < maxStepsPerFrame {
                    let remaining = avgX - currentAnchorX
                    guard abs(remaining) >= stepDistance else { break }
                    actions.append(remaining < 0 ? .nextTab : .previousTab)
                    currentAnchorX += (remaining > 0 ? stepDistance : -stepDistance)
                }

                state = .scrubbing(anchorX: currentAnchorX)
                return SwipeResult(actions: actions, shouldSuppressSystemGesture: true)
            }

            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)

        case .scrubbing(let anchorX):
            var currentAnchorX = anchorX
            var actions: [SwipeAction] = []

            while actions.count < maxStepsPerFrame {
                let dx = avgX - currentAnchorX
                guard abs(dx) >= stepDistance else { break }
                actions.append(dx < 0 ? .nextTab : .previousTab)
                currentAnchorX += (dx > 0 ? stepDistance : -stepDistance)
            }

            state = .scrubbing(anchorX: currentAnchorX)
            return SwipeResult(actions: actions, shouldSuppressSystemGesture: true)

        case .ignored:
            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)
        }
    }
}
