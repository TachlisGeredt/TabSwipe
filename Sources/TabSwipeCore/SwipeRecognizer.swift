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

/// Pure-Swift, velocity-sensitive continuous 3-finger horizontal swipe recognizer.
///
/// Behavior:
/// - Activates only when `commandOnly == true` and exactly 3 fingers are touching.
/// - Natural macOS direction: swipe fingers left (`dx < 0`) → `.nextTab` (right);
///   swipe fingers right (`dx > 0`) → `.previousTab` (left).
/// - First tab switches after `initialThreshold` of horizontal travel; subsequent tabs use a
///   smooth continuous velocity gradient from `maxStepDistance` (slow, deliberate control) down
///   to `minStepDistance` (fast sweeps), including mid-swipe direction reversals.
public final class SwipeRecognizer {
    private enum State {
        case idle
        case tracking(anchorX: Double, anchorY: Double)
        case scrubbing(anchorX: Double)
        case ignored
    }

    /// Horizontal displacement (normalized trackpad width, 0.0...1.0) to switch the first tab.
    public let initialThreshold: Double

    /// Maximum horizontal distance per tab when swiping slowly (deliberate 1–2 tab control).
    public let maxStepDistance: Double

    /// Minimum horizontal distance per tab when swiping quickly (floor for fast sweeps).
    public let minStepDistance: Double

    /// Normalized finger speed (trackpad widths/sec) at or below which `maxStepDistance` applies.
    public let slowSpeed: Double

    /// Normalized finger speed (trackpad widths/sec) at or above which `minStepDistance` applies.
    public let fastSpeed: Double

    /// Minimum time (seconds) between consecutive tab switches so every tab & click stays readable.
    public let minStepInterval: TimeInterval

    /// Minimum ratio of horizontal-to-vertical movement (`|dx| / |dy|`) to lock in as horizontal.
    public let horizontalDominanceRatio: Double

    /// EMA smoothing factor for finger velocity (0.0...1.0).
    private let velocitySmoothingAlpha: Double = 0.35

    /// Minimum time delta (seconds) between frames to prevent velocity spikes on jittered timestamps.
    private let minDeltaTime: TimeInterval = 0.004

    private var state: State = .idle
    private var lastX: Double?
    private var lastTimestamp: TimeInterval?
    private var lastStepTimestamp: TimeInterval = -.infinity
    private var smoothedSpeed: Double = 0.0

    public init(
        initialThreshold: Double = 0.035,
        maxStepDistance: Double = 0.045,
        minStepDistance: Double = 0.028,
        slowSpeed: Double = 0.25,
        fastSpeed: Double = 2.20,
        minStepInterval: TimeInterval = 0.038,
        horizontalDominanceRatio: Double = 1.35
    ) {
        self.initialThreshold = initialThreshold
        self.maxStepDistance = maxStepDistance
        self.minStepDistance = minStepDistance
        self.slowSpeed = slowSpeed
        self.fastSpeed = fastSpeed
        self.minStepInterval = minStepInterval
        self.horizontalDominanceRatio = horizontalDominanceRatio
    }

    /// Resets gesture and velocity state immediately (e.g., when ⌘ is released or focus leaves the browser).
    public func reset() {
        state = .idle
        lastX = nil
        lastTimestamp = nil
        lastStepTimestamp = -.infinity
        smoothedSpeed = 0.0
    }

    /// Computes the continuous step distance for a given horizontal speed (normalized widths/sec).
    public func stepDistance(forSpeed speed: Double) -> Double {
        guard fastSpeed > slowSpeed else { return maxStepDistance }
        let t = min(max((speed - slowSpeed) / (fastSpeed - slowSpeed), 0.0), 1.0)
        return maxStepDistance - t * (maxStepDistance - minStepDistance)
    }

    /// Processes a trackpad touch frame and returns any triggered tab actions and whether the
    /// underlying system gesture (e.g., Spaces switching) should be suppressed.
    public func process(
        touches: [TouchPoint],
        commandOnly: Bool,
        timestamp: TimeInterval
    ) -> SwipeResult {
        guard commandOnly else {
            reset()
            return SwipeResult(actions: [], shouldSuppressSystemGesture: false)
        }

        guard touches.count == 3 else {
            // Finger lifted or extra finger added: reset so user can swipe again while still holding ⌘.
            reset()
            return SwipeResult(actions: [], shouldSuppressSystemGesture: false)
        }

        let avgX = (touches[0].x + touches[1].x + touches[2].x) / 3.0
        let avgY = (touches[0].y + touches[1].y + touches[2].y) / 3.0

        updateVelocity(avgX: avgX, timestamp: timestamp)
        let currentStep = stepDistance(forSpeed: smoothedSpeed)

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
                let action: SwipeAction = dx < 0 ? .nextTab : .previousTab
                lastStepTimestamp = timestamp
                state = .scrubbing(anchorX: avgX)
                return SwipeResult(actions: [action], shouldSuppressSystemGesture: true)
            }

            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)

        case .scrubbing(let anchorX):
            let dx = avgX - anchorX
            if abs(dx) >= currentStep && (timestamp - lastStepTimestamp) >= minStepInterval {
                let action: SwipeAction = dx < 0 ? .nextTab : .previousTab
                lastStepTimestamp = timestamp
                state = .scrubbing(anchorX: avgX)
                return SwipeResult(actions: [action], shouldSuppressSystemGesture: true)
            }

            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)

        case .ignored:
            return SwipeResult(actions: [], shouldSuppressSystemGesture: true)
        }
    }

    private func updateVelocity(avgX: Double, timestamp: TimeInterval) {
        if let prevX = lastX, let prevT = lastTimestamp {
            let dt = max(timestamp - prevT, minDeltaTime)
            let instantSpeed = abs(avgX - prevX) / dt
            if smoothedSpeed == 0.0 {
                smoothedSpeed = instantSpeed
            } else {
                smoothedSpeed =
                    velocitySmoothingAlpha * instantSpeed +
                    (1.0 - velocitySmoothingAlpha) * smoothedSpeed
            }
        }
        lastX = avgX
        lastTimestamp = timestamp
    }
}
