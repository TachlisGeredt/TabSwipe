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
    public let action: SwipeAction?
    public let shouldSuppressSystemGesture: Bool

    public init(action: SwipeAction? = nil, shouldSuppressSystemGesture: Bool = false) {
        self.action = action
        self.shouldSuppressSystemGesture = shouldSuppressSystemGesture
    }
}

/// Pure-Swift, single-step 3-finger horizontal swipe recognizer.
///
/// Behavior:
/// - Activates only when `commandOnly == true` and exactly 3 fingers are touching.
/// - Swipe right (`dx > 0`) emits `.nextTab`; swipe left (`dx < 0`) emits `.previousTab`.
/// - Strictly single-step: once triggered, ignores further movement until fingers lift (< 3 touches),
///   allowing repeated swipes while keeping ⌘ held down.
public final class SwipeRecognizer {
    private enum State {
        case idle
        case tracking(anchorX: Double, anchorY: Double)
        case triggered
        case ignored
    }

    /// Horizontal displacement (in normalized trackpad width, 0.0...1.0) required to switch 1 tab.
    public let horizontalThreshold: Double

    /// Minimum ratio of horizontal-to-vertical movement (`|dx| / |dy|`) to qualify as horizontal.
    public let horizontalDominanceRatio: Double

    private var state: State = .idle

    public init(
        horizontalThreshold: Double = 0.075,
        horizontalDominanceRatio: Double = 1.5
    ) {
        self.horizontalThreshold = horizontalThreshold
        self.horizontalDominanceRatio = horizontalDominanceRatio
    }

    /// Resets gesture state immediately (e.g., when ⌘ is released or focus leaves the browser).
    public func reset() {
        state = .idle
    }

    /// Processes a trackpad touch frame and returns any triggered tab action and whether the
    /// underlying system gesture (e.g., Spaces switching) should be suppressed.
    public func process(touches: [TouchPoint], commandOnly: Bool) -> SwipeResult {
        guard commandOnly else {
            state = .idle
            return SwipeResult(action: nil, shouldSuppressSystemGesture: false)
        }

        guard touches.count == 3 else {
            // Finger lifted or extra finger added: reset so user can swipe again while still holding ⌘.
            state = .idle
            return SwipeResult(action: nil, shouldSuppressSystemGesture: false)
        }

        let avgX = (touches[0].x + touches[1].x + touches[2].x) / 3.0
        let avgY = (touches[0].y + touches[1].y + touches[2].y) / 3.0

        switch state {
        case .idle:
            state = .tracking(anchorX: avgX, anchorY: avgY)
            return SwipeResult(action: nil, shouldSuppressSystemGesture: true)

        case .tracking(let anchorX, let anchorY):
            let dx = avgX - anchorX
            let dy = avgY - anchorY
            let absX = abs(dx)
            let absY = abs(dy)

            // Reject clearly vertical 3-finger movements so they don't later drift into a tab switch.
            if absY >= horizontalThreshold && absY > absX * horizontalDominanceRatio {
                state = .ignored
                return SwipeResult(action: nil, shouldSuppressSystemGesture: true)
            }

            if absX >= horizontalThreshold && absX > absY * horizontalDominanceRatio {
                state = .triggered
                // Natural macOS direction: swipe fingers left (dx < 0) -> next tab (right);
                // swipe fingers right (dx > 0) -> previous tab (left).
                let action: SwipeAction = dx < 0 ? .nextTab : .previousTab
                return SwipeResult(action: action, shouldSuppressSystemGesture: true)
            }

            return SwipeResult(action: nil, shouldSuppressSystemGesture: true)

        case .triggered, .ignored:
            // Stay locked until fingers lift (< 3 touches) so 1 swipe strictly moves 1 tab.
            return SwipeResult(action: nil, shouldSuppressSystemGesture: true)
        }
    }
}
