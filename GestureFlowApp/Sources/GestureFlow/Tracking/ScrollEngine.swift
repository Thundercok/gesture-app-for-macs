import Foundation
import CoreGraphics
import AppKit

final class ScrollEngine {
    enum ClutchType: String {
        case twoFingers = "Two-Finger"
        case pinch = "Pinch"
        case oneFinger = "One-Finger"
        case wholeHand = "Whole-Hand"
    }

    enum FlickDirection {
        case up    // Hand flicked upwards (Vision y increases) -> Viewport scrolls down (shows lower content, like smartphone)
        case down  // Hand flicked downwards (Vision y decreases) -> Viewport scrolls up (shows higher content)
    }

    private struct TrajectorySample {
        let point: CGPoint
        let timestamp: TimeInterval
    }

    // 1€ Filter to remove camera micro-jitter while preserving fast stroke peaks
    private let pointFilter = PointFilter2D(minCutoff: 1.10, beta: 0.035, noiseGateThreshold: 0.0010)

    // Trajectory history ring buffer
    private var history: [TrajectorySample] = []
    private let maxHistorySamples = 14

    // Stroke Tracking State
    private var isTrackingStroke: Bool = false
    private var strokeDirection: FlickDirection? = nil
    private var strokeStartPoint: CGPoint = .zero
    private var strokeStartTime: TimeInterval = 0.0
    private var strokePeakVelocity: Double = 0.0
    private var strokePeakPoint: CGPoint = .zero

    // Cooldown refractory timer to ignore the natural return/recoil stroke
    private var cooldownUntilTimestamp: TimeInterval = 0.0
    private let recoilCooldownDuration: TimeInterval = 0.22

    // Brake / Freeze detector (Touch screen to stop)
    private var stationaryFramesCount: Int = 0
    private let requiredStationaryFramesForBrake: Int = 4

    // Live momentum tracking
    private var liveMomentumVelocity: Double = 0.0
    private var lastProcessTime: Date
    private var lastHandSeenTime: Date

    private let clock: Clock
    private let actionSink: ActionSink
    private let arbiter: IntentArbiter

    // Intentionality Gating Constants
    static let facingCameraSuppressEnter: Double = 0.20
    static let facingCameraSuppressExit: Double = 0.28
    static let depthBandDeltaEnter: CGFloat = 0.07
    static let depthBandDeltaExit: CGFloat = 0.10

    private var isSuppressedByFacingCamera: Bool = false
    private var isSuppressedByDepthBand: Bool = false

    private var pendingSuppressReason: GestureEngine.GateSuppressReason?
    private var pendingSuppressFrames: Int = 0
    private let requiredSuppressFrames: Int = 3
    private(set) var activeSuppressReason: GestureEngine.GateSuppressReason?

    // Callbacks
    var onScrollStatus: ((_ isScrolling: Bool, _ clutch: ClutchType?, _ velocityY: Double) -> Void)?
    var onScrollDelta: ((_ deltaY: CGFloat, _ velocityY: Double) -> Void)?
    var onSuppressStatus: ((_ reason: GestureEngine.GateSuppressReason?) -> Void)?
    var onAction: ((_ title: String) -> Void)?

    init(
        clock: Clock = SystemClock.shared,
        actionSink: ActionSink = LiveActionSink.shared,
        arbiter: IntentArbiter = .shared
    ) {
        self.clock = clock
        self.actionSink = actionSink
        self.arbiter = arbiter
        self.lastProcessTime = clock.now
        self.lastHandSeenTime = clock.now

        // Wire actionSink momentum callbacks
        self.actionSink.onMomentumProgress = { [weak self] currentVel in
            guard let self = self else { return }
            self.liveMomentumVelocity = currentVel
            self.onScrollDelta?(currentVel < 0 ? -1.0 : 1.0, currentVel / 160.0)
            self.onScrollStatus?(true, nil, currentVel / 160.0)
        }

        self.actionSink.onMomentumEnded = { [weak self] in
            guard let self = self else { return }
            self.liveMomentumVelocity = 0.0
            self.onScrollDelta?(0.0, 0.0)
            self.onScrollStatus?(false, nil, 0.0)
        }
    }

    func forceDischarge() {
        actionSink.cancelMomentumScroll()
        pointFilter.reset()
        history.removeAll(keepingCapacity: true)
        isTrackingStroke = false
        strokeDirection = nil
        strokePeakVelocity = 0.0
        stationaryFramesCount = 0
        cooldownUntilTimestamp = 0.0
        liveMomentumVelocity = 0.0
        pendingSuppressReason = nil
        pendingSuppressFrames = 0
        activeSuppressReason = nil
        arbiter.release(intent: .airScroll)
        onScrollStatus?(false, nil, 0.0)
        onScrollDelta?(0.0, 0.0)
    }

    func evaluateIntentionalityGates(landmarks: HandLandmarks) -> GestureEngine.GateSuppressReason? {
        // 1. Simple robust 2D Face Exclusion: Hand overlapping face/chin in 2D AND not an intentional pose
        if let faceBox = landmarks.faceBBox {
            let expMinX = faceBox.minX - faceBox.width * 0.10
            let expWidth = faceBox.width * 1.20
            let expMinY = faceBox.minY - faceBox.height * 0.05
            let expHeight = faceBox.height * 1.15
            let expandedFaceBBox = CGRect(x: expMinX, y: expMinY, width: expWidth, height: expHeight)

            let contactPoints = [
                landmarks.handCentroid,
                landmarks.indexTip,
                landmarks.thumbTip
            ]

            let isInFace2D = contactPoints.contains(where: { expandedFaceBBox.contains($0) })
            let isDeliberatePose = (landmarks.isTwoFingers || landmarks.isStrictOpenPalm) && landmarks.facingCamera >= 0.18

            if isInFace2D && !isDeliberatePose {
                return .faceProximity
            }
        }

        // 2. Extreme edge-on palm
        if landmarks.facingCamera < ScrollEngine.facingCameraSuppressEnter {
            return .edgeOnPalm
        }

        return nil
    }


    func process(_ landmarks: HandLandmarks?) {
        let tune = GestureTuning.current
        let now = clock.now
        let nowTimestamp = now.timeIntervalSinceReferenceDate
        lastProcessTime = now

        let rawReason = landmarks != nil ? evaluateIntentionalityGates(landmarks: landmarks!) : nil

        if rawReason == .faceProximity {
            pendingSuppressReason = .faceProximity
            pendingSuppressFrames = requiredSuppressFrames
            if activeSuppressReason != .faceProximity {
                activeSuppressReason = .faceProximity
                onSuppressStatus?(.faceProximity)
            }
        } else if rawReason == pendingSuppressReason {
            pendingSuppressFrames += 1
        } else {
            pendingSuppressReason = rawReason
            pendingSuppressFrames = 1
        }

        if pendingSuppressFrames >= requiredSuppressFrames {
            if activeSuppressReason != pendingSuppressReason {
                activeSuppressReason = pendingSuppressReason
                onSuppressStatus?(activeSuppressReason)
            }
        }

        guard let lm = landmarks, lm.isRaisedHand else {
            handleHandLost(now: now)
            return
        }

        lastHandSeenTime = now

        // Check intentionality suppression
        if let reason = activeSuppressReason {
            if isTrackingStroke {
                resetStroke()
            }
            onSuppressStatus?(reason)
            return
        }

        guard lm.isInInteractionRange else {
            if isTrackingStroke {
                resetStroke()
            }
            return
        }

        // Primary fingertip tracking with horizontal flip for intuitive mirror interaction
        let rawTrackingPoint: CGPoint = CGPoint(x: 1.0 - lm.indexTip.x, y: lm.indexTip.y)
        let filteredPoint = pointFilter.filter(rawTrackingPoint, timestamp: nowTimestamp)

        // Identify current hand pose clutch
        let clutchType: ClutchType
        if lm.isTwoFingers {
            clutchType = .twoFingers
        } else if lm.isPinching {
            clutchType = .pinch
        } else if lm.isOneFinger {
            clutchType = .oneFinger
        } else {
            clutchType = .wholeHand
        }

        // Record history sample
        let currentSample = TrajectorySample(point: filteredPoint, timestamp: nowTimestamp)
        history.append(currentSample)
        if history.count > maxHistorySamples {
            history.removeFirst()
        }

        // Calculate instantaneous velocity over the latest 2 frames
        var instVelocityY: Double = 0.0
        var instVelocityX: Double = 0.0
        if history.count >= 2 {
            let prev = history[history.count - 2]
            let dt = max(0.001, currentSample.timestamp - prev.timestamp)
            instVelocityY = Double(currentSample.point.y - prev.point.y) / dt
            instVelocityX = Double(currentSample.point.x - prev.point.x) / dt
        }

        let isStationary = abs(instVelocityY) < 0.075 && abs(instVelocityX) < 0.075
        if isStationary {
            stationaryFramesCount += 1
        } else {
            stationaryFramesCount = 0
        }

        // =====================================================================
        // 1. BRAKE / TOUCH SCREEN STOP GESTURE ("Chạm vào màn hình để dừng lại")
        // =====================================================================
        // If momentum is actively scrolling, user can brake instantly by:
        // A. Freezing hand stationary for 4 frames (~65ms)
        // B. Making a pinch gesture (👌)
        // C. Raising flat stop palm
        let isActivelyCoasting = actionSink.isMomentumActive
        if isActivelyCoasting {
            let shouldBrake = (stationaryFramesCount >= requiredStationaryFramesForBrake) ||
                              lm.isPinching ||
                              ((lm.fingerCount >= 4 || lm.isOpenHand) && isStationary)

            if shouldBrake {
                actionSink.cancelMomentumScroll()
                actionSink.playFeedback(named: "Tink")
                actionSink.playHaptic()
                onAction?("Dừng cuộn (Brake)")
                onScrollStatus?(false, clutchType, 0.0)
                onScrollDelta?(0.0, 0.0)
                resetStroke()
                cooldownUntilTimestamp = nowTimestamp + 0.15
                stationaryFramesCount = 0
                arbiter.commitAction(gesture: .airScroll, action: "scroll_brake", cooldown: 0.15, now: nowTimestamp)
                return
            }
        }

        // =====================================================================
        // 2. SMARTPHONE FLICK DETECTION ("Flick như điện thoại")
        // =====================================================================
        // If in recoil cooldown, suppress starting any stroke
        if nowTimestamp < cooldownUntilTimestamp {
            return
        }

        if !isTrackingStroke {
            // Scan trajectory window (last 3 to 7 frames, approx 45ms to 120ms) for high-velocity flick impulse
            let canScroll = arbiter.canBegin(intent: .airScroll, now: nowTimestamp)
            if canScroll && history.count >= 4 {
                for offset in 3...min(7, history.count - 1) {
                    let oldSample = history[history.count - 1 - offset]
                    let dt = currentSample.timestamp - oldSample.timestamp
                    guard dt >= 0.035 && dt <= 0.180 else { continue }

                    let dy = currentSample.point.y - oldSample.point.y
                    let dx = currentSample.point.x - oldSample.point.x
                    let velY = Double(dy) / dt
                    let absDy = abs(dy)
                    let absDx = abs(dx)

                    // Flick Criteria:
                    // 1. Minimum travel: >= 0.026 (~2-3 cm physical movement)
                    // 2. High velocity: >= tune.scrollFlickMinVelocity
                    // 3. Dominantly vertical: |dy| >= 1.15 * |dx|
                    if absDy >= 0.026 && abs(velY) >= tune.scrollFlickMinVelocity && absDy >= (1.15 * absDx) {
                        arbiter.claim(intent: .airScroll)
                        isTrackingStroke = true
                        strokeDirection = dy > 0 ? .up : .down
                        strokeStartPoint = oldSample.point
                        strokeStartTime = oldSample.timestamp
                        strokePeakVelocity = velY
                        strokePeakPoint = currentSample.point
                        break
                    }
                }
            }
        } else {
            // Already tracking stroke: monitor velocity peak and follow-through
            guard let dir = strokeDirection else {
                resetStroke()
                return
            }

            let strokeDt = currentSample.timestamp - strokeStartTime
            let totalDy = currentSample.point.y - strokeStartPoint.y
            let totalDx = currentSample.point.x - strokeStartPoint.x
            let isSameDirection = (dir == .up && instVelocityY > 0) || (dir == .down && instVelocityY < 0)

            // Update peak velocity if still accelerating in stroke direction
            if isSameDirection && abs(instVelocityY) > abs(strokePeakVelocity) {
                strokePeakVelocity = instVelocityY
                strokePeakPoint = currentSample.point
            }

            // Stroke Completion Criteria:
            // 1. Hand decelerated significantly (inst velocity dropped to < 50% of peak), OR
            // 2. Velocity reversed direction (hand reached stroke crest/apex and recoiled), OR
            // 3. Traveled far enough with high velocity (> 0.048 travel and dt > 0.05)
            let isDecelerating = abs(instVelocityY) < (abs(strokePeakVelocity) * 0.50)
            let isReversed = (dir == .up && instVelocityY < -0.10) || (dir == .down && instVelocityY > 0.10)
            let isLongStroke = abs(totalDy) >= 0.048 && strokeDt >= 0.050

            if isDecelerating || isReversed || isLongStroke || strokeDt > 0.20 {
                // Confirm valid flick
                let absPeak = abs(strokePeakVelocity)
                let absDy = abs(totalDy)

                let confirmVelocity = tune.scrollFlickMinVelocity * (0.40 / 0.42)
                if absDy >= 0.025 && absPeak >= confirmVelocity && absDy >= (1.10 * abs(totalDx)) {
                    // Trigger the Kinetic Flick!
                    fireFlick(direction: dir, peakVelocity: strokePeakVelocity, clutch: clutchType, nowTimestamp: nowTimestamp, landmarks: lm)
                }
                resetStroke()
            }
        }
    }

    private func fireFlick(direction: FlickDirection, peakVelocity: Double, clutch: ClutchType, nowTimestamp: TimeInterval, landmarks: HandLandmarks) {
        // Map peak flick velocity to physical impulse
        // Normalized speed: 0.45 (gentle flick) to 3.20 (energetic flick)
        let speed = min(3.20, max(0.45, abs(peakVelocity)))
        let normalizedRatio = (speed - 0.45) / (3.20 - 0.45) // 0.0 to 1.0

        // Impulse curve: Gentle flick produces ~30 px/tick, energetic flick produces ~165 px/tick
        let impulseMagnitude = 28.0 + pow(normalizedRatio, 1.25) * 135.0

        // DIRECTION MAPPING:
        // On Smartphone / Trackpad Natural Scrolling:
        // - Flick UP (hand moves upwards, dy > 0): Moves viewport DOWN (reading downward).
        //   In macOS CGEvent, negative wheel1 delta scrolls down.
        // - Flick DOWN (hand moves downwards, dy < 0): Moves viewport UP (reading upward).
        //   In macOS CGEvent, positive wheel1 delta scrolls up.
        var targetVelocityY = (direction == .up ? -1.0 : 1.0) * impulseMagnitude

        // Compound Momentum: If user flicks again in the SAME direction while coasting, add to existing momentum!
        if (targetVelocityY > 0 && liveMomentumVelocity > 0) || (targetVelocityY < 0 && liveMomentumVelocity < 0) {
            targetVelocityY += liveMomentumVelocity * 0.45
            targetVelocityY = max(-220.0, min(220.0, targetVelocityY))
        }

        // Dispatch kinetic momentum scroll
        actionSink.releaseScrollWithMomentum(initialVelocityX: 0.0, initialVelocityY: targetVelocityY)

        // Crisp multi-sensory feedback
        actionSink.playFeedback(named: "Pop")
        actionSink.playHaptic()

        // Set refractory cooldown to swallow the return recoil movement
        cooldownUntilTimestamp = nowTimestamp + recoilCooldownDuration
        let flickAction = direction == .up ? "scroll_down" : "scroll_up"
        arbiter.commitAction(gesture: .airScroll, action: flickAction, cooldown: 0.25, now: nowTimestamp)

        // Notify UI and listeners
        let actionName = direction == .up ? "Lướt xuống ↓" : "Lướt lên ↑"
        onAction?("Flick (\(actionName))")
        onScrollStatus?(true, clutch, targetVelocityY / 160.0)
        onScrollDelta?(direction == .up ? -1.0 : 1.0, targetVelocityY / 160.0)

        TelemetryLogger.shared.log(
            action: "flick_scroll",
            reason: direction == .up ? "flick_up_scrolldown" : "flick_down_scrollup",
            chargeLevel: 1.0,
            handCentroid: landmarks.handCentroid
        )
    }

    private func resetStroke() {
        if isTrackingStroke {
            arbiter.release(intent: .airScroll)
        }
        isTrackingStroke = false
        strokeDirection = nil
        strokePeakVelocity = 0.0
        strokeStartPoint = .zero
        strokeStartTime = 0.0
    }


    private func handleHandLost(now: Date) {
        let lostDuration = now.timeIntervalSince(lastHandSeenTime)
        if lostDuration > 0.35 {
            resetStroke()
            pointFilter.reset()
            history.removeAll(keepingCapacity: true)
        }
    }
}
