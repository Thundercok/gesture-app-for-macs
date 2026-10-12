import Foundation
import CoreGraphics
import AppKit

final class GestureEngine {
    enum State {
        case standby
        case armed(expiresAt: Date)
        case engaged(
            anchor: CGPoint,
            selectedIndex: Int,
            appCount: Int,
            openTime: Date,
            lastStableIndex: Int,
            stableSince: Date
        )
        case cooldown(until: Date)
    }

    private var state: State = .standby
    private var chargeLevel: CGFloat = 0.0       // 0.0 to 1.0 leaky charge accumulator
    private var lastProcessTime: Date
    private var lastHandSeenTime: Date

    private let clock: Clock
    private let actionSink: ActionSink
    private let arbiter: IntentArbiter

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
    }

    private let deadzoneRadius: CGFloat = 0.022  // Compact center deadzone for quick toggle
    private let stepWidth: CGFloat = 0.038       // Compact physical travel per app detent (~4-5cm)
    private var lastDx: CGFloat = 0.0
    private var filteredVelocity: Double = 0.0
    private var lastCentroid: CGPoint = .zero
    private var handSpeed: Double = 0.0
    private var stableOpenFrames: Int = 0
    private var openPalmSince: TimeInterval? = nil

    // MARK: - Trackpad Spatial Swipes (Mac Navigation Mode)
    private struct SwipeSample {
        let point: CGPoint
        let timestamp: TimeInterval
    }
    private var swipeHistory: [SwipeSample] = []
    private var swipeCooldownUntil: TimeInterval = 0.0
    private var lastPinchTime: TimeInterval = 0.0
    private var lastSwipeTime: TimeInterval = 0.0

    // MARK: - Intentionality Gating Constants
    static let facingCameraSuppressEnter: Double = 0.12
    static let facingCameraSuppressExit: Double = 0.20
    static let facingCameraThreshold: Double = 0.16

    static let faceBBoxExpansionFactor: CGFloat = 1.20

    enum GateSuppressReason: String {
        case faceProximity = "face_proximity"
        case edgeOnPalm = "edge_on_palm"
    }

    private var lastSuppressionLogTime: Date = .distantPast
    private var lastSuppressionReason: String?

    // 3-frame temporal confirmation buffer to eliminate single-frame chattering
    private var pendingSuppressReason: GateSuppressReason?
    private var pendingSuppressFrames: Int = 0
    private let requiredSuppressFrames: Int = 3

    func forceDischarge() {
        chargeLevel = 0.0
        lastDx = 0.0
        filteredVelocity = 0.0
        handSpeed = 0.0
        stableOpenFrames = 0
        openPalmSince = nil
        swipeHistory.removeAll(keepingCapacity: true)
        pendingSuppressReason = nil
        pendingSuppressFrames = 0
        activeSuppressReason = nil
        state = .standby
        arbiter.release(intent: .pinchDock)
        arbiter.release(intent: .swipe)
        onArmedStatus?(false)
        onScanProgress?(0.0)
    }

    func evaluateIntentionalityGates(landmarks: HandLandmarks) -> GateSuppressReason? {
        // 1. Simple robust 2D Face Exclusion: Hand overlapping face/chin area AND not an explicit open palm
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
            let isDeliberatePalm = landmarks.isStrictOpenPalm && landmarks.facingCamera >= 0.18

            if isInFace2D && !isDeliberatePalm {
                return .faceProximity
            }
        }

        // 2. Extreme edge-on palm: Only suppress if palm is turned almost completely edge-on to the camera (< 0.12)
        if landmarks.facingCamera < GestureEngine.facingCameraSuppressEnter {
            return .edgeOnPalm
        }

        return nil
    }


    private func logSuppression(reason: GateSuppressReason, centroid: CGPoint) {
        let now = clock.now
        if now.timeIntervalSince(lastSuppressionLogTime) > 0.35 || lastSuppressionReason != reason.rawValue {
            lastSuppressionLogTime = now
            lastSuppressionReason = reason.rawValue
            TelemetryLogger.shared.log(
                action: "suppressed",
                reason: reason.rawValue,
                chargeLevel: Double(chargeLevel),
                handCentroid: centroid
            )
        }
    }

    // UI & System Callbacks
    var onScanProgress: ((_ progress: CGFloat) -> Void)?
    var onArmedStatus: ((_ isArmed: Bool) -> Void)?
    var onDockOpen: ((_ apps: [AppItem], _ initialIndex: Int) -> Void)?
    var onDockSelectIndex: ((_ index: Int, _ tiltDelta: CGSize) -> Void)?
    var onDockCommit: (() -> Void)?
    var onDockCancel: (() -> Void)?
    var onAction: ((_ title: String) -> Void)?
    var onSuppressStatus: ((_ reason: GateSuppressReason?) -> Void)?

    private(set) var activeSuppressReason: GateSuppressReason?

    func process(_ landmarks: HandLandmarks?) {
        let now = clock.now
        let dt = min(0.1, max(0.001, now.timeIntervalSince(lastProcessTime)))
        lastProcessTime = now

        updateSuppressionState(landmarks: landmarks)

        // 1. Handle Cooldown
        if case .cooldown(let until) = state {
            if now < until {
                return
            } else {
                state = .standby
                onArmedStatus?(false)
                onScanProgress?(0.0)
            }
        }

        guard let lm = landmarks, lm.isRaisedHand else {
            handleHandLost(now: now, dt: dt)
            return
        }

        updateHandKinematics(lm: lm, now: now, dt: dt)

        let nowTimestamp = now.timeIntervalSinceReferenceDate
        let rawTrackingPoint = CGPoint(x: 1.0 - lm.indexTip.x, y: lm.indexTip.y)
        let tune = GestureTuning.current

        if evaluateSwipe(lm: lm, nowTimestamp: nowTimestamp, rawTrackingPoint: rawTrackingPoint, tune: tune) {
            return
        }

        switch state {
        case .standby:
            evaluateStandby(lm: lm, now: now, nowTimestamp: nowTimestamp, dt: dt, tune: tune)
        case .armed(let expiresAt):
            evaluateArmed(lm: lm, now: now, nowTimestamp: nowTimestamp, expiresAt: expiresAt, tune: tune)
        case .engaged(let anchor, let selectedIndex, let appCount, let openTime, let lastStableIndex, let stableSince):
            evaluateDockScrub(
                lm: lm,
                now: now,
                nowTimestamp: nowTimestamp,
                dt: dt,
                anchor: anchor,
                selectedIndex: selectedIndex,
                appCount: appCount,
                openTime: openTime,
                lastStableIndex: lastStableIndex,
                stableSince: stableSince
            )
        case .cooldown:
            break
        }
    }

    private func updateSuppressionState(landmarks: HandLandmarks?) {
        let rawReason = landmarks != nil ? evaluateIntentionalityGates(landmarks: landmarks!) : nil

        // Immediate safety latch for face proximity; 3-frame debounce for continuous angle/depth gates
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
    }

    private func updateHandKinematics(lm: HandLandmarks, now: Date, dt: Double) {
        lastHandSeenTime = now
        let nowTimestamp = now.timeIntervalSinceReferenceDate

        // Calculate hand movement speed to reject spurious pinch during transit
        if lastCentroid != .zero {
            let centroidDelta = hypot(lm.handCentroid.x - lastCentroid.x, lm.handCentroid.y - lastCentroid.y)
            let instSpeed = Double(centroidDelta) / dt
            handSpeed = 0.65 * handSpeed + 0.35 * instSpeed
        }
        lastCentroid = lm.handCentroid

        if lm.isPinching {
            lastPinchTime = nowTimestamp
        }

        // Open hand stability and dwell tracking
        let isOpenFingers = (lm.fingerCount >= 3) || lm.isOpenHand || lm.isStrictOpenPalm
        if isOpenFingers && !lm.isPinching {
            stableOpenFrames += 1
            if openPalmSince == nil {
                openPalmSince = nowTimestamp
            }
        } else {
            stableOpenFrames = 0
            openPalmSince = nil
        }
    }

    private func evaluateSwipe(
        lm: HandLandmarks,
        nowTimestamp: TimeInterval,
        rawTrackingPoint: CGPoint,
        tune: GestureTuning
    ) -> Bool {
        let isStandbyState: Bool = {
            if case .standby = state { return true }
            return false
        }()
        let canSwipe = arbiter.canBegin(intent: .swipe, now: nowTimestamp)
        let isOpenFingers = (lm.fingerCount >= 3) || lm.isOpenHand || lm.isStrictOpenPalm
        let palmDwell = nowTimestamp - (openPalmSince ?? nowTimestamp)
        let isPalmDwellSatisfied = (stableOpenFrames >= 3) && (palmDwell >= tune.openPalmDwellSeconds)
        let isPinchGuardClear = (nowTimestamp - lastPinchTime) > tune.postPinchSwipeGuardSeconds

        let isInteractionValid = lm.isInInteractionRange && isOpenFingers && isPalmDwellSatisfied
        let isGatingClear = (activeSuppressReason == nil) && isStandbyState && !lm.isPinching
        let isEligibleForSwipe = isGatingClear && isInteractionValid && isPinchGuardClear && canSwipe

        guard isEligibleForSwipe else {
            swipeHistory.removeAll(keepingCapacity: true)
            return false
        }

        swipeHistory.append(SwipeSample(point: rawTrackingPoint, timestamp: nowTimestamp))
        if swipeHistory.count > 14 {
            swipeHistory.removeFirst()
        }

        guard nowTimestamp > swipeCooldownUntil && swipeHistory.count >= 4 else {
            return false
        }

        for offset in 3...min(7, swipeHistory.count - 1) {
            let oldSample = swipeHistory[swipeHistory.count - 1 - offset]
            let sampleDt = nowTimestamp - oldSample.timestamp
            guard sampleDt >= 0.035 && sampleDt <= 0.180 else { continue }

            let dx = rawTrackingPoint.x - oldSample.point.x
            let dy = rawTrackingPoint.y - oldSample.point.y
            let vx = Double(dx) / sampleDt
            let vy = Double(dy) / sampleDt
            let absDx = abs(dx)
            let absDy = abs(dy)
            let absVx = abs(vx)
            let absVy = abs(vy)

            // 1. Horizontal Swipes (Switch Space Left / Right)
            let isHorizontalDominant = absDx >= (absDy * tune.swipeAxisDominance)
            let hasHorizontalSpeed = absVx >= tune.swipeMinVelocity
            let hasHorizontalDisplacement = absDx >= tune.swipeMinDisplacement
            if hasHorizontalDisplacement && hasHorizontalSpeed && isHorizontalDominant {
                arbiter.claim(intent: .swipe)
                if dx < 0 {
                    actionSink.switchSpace(.right)
                    actionSink.playFeedback(named: "Pop")
                    actionSink.playHaptic()
                    onAction?("Chuyển Space Phải →")
                } else {
                    actionSink.switchSpace(.left)
                    actionSink.playFeedback(named: "Pop")
                    actionSink.playHaptic()
                    onAction?("Chuyển Space Trái ←")
                }
                lastSwipeTime = nowTimestamp
                swipeCooldownUntil = nowTimestamp + tune.swipeCooldownSeconds
                swipeHistory.removeAll(keepingCapacity: true)
                let swipeAction = dx < 0 ? "swipe_left" : "swipe_right"
                arbiter.commitAction(gesture: .swipe, action: swipeAction, cooldown: tune.swipeCooldownSeconds, now: nowTimestamp)
                return true
            }

            // 2. Vertical Swipes (Mission Control / Show Desktop)
            let isVerticalDominant = absDy >= (absDx * tune.swipeAxisDominance)
            let hasVerticalSpeed = absVy >= tune.swipeMinVelocity
            let hasVerticalDisplacement = absDy >= tune.swipeMinDisplacement
            if hasVerticalDisplacement && hasVerticalSpeed && isVerticalDominant {
                arbiter.claim(intent: .swipe)
                if dy > 0 {
                    actionSink.triggerMissionControl()
                    actionSink.playFeedback(named: "Glass")
                    actionSink.playHaptic()
                    onAction?("Mission Control ↑")
                } else {
                    actionSink.showDesktop()
                    actionSink.playFeedback(named: "Tink")
                    actionSink.playHaptic()
                    onAction?("Hiện Desktop ↓")
                }
                lastSwipeTime = nowTimestamp
                swipeCooldownUntil = nowTimestamp + tune.swipeCooldownSeconds
                swipeHistory.removeAll(keepingCapacity: true)
                let swipeAction = dy > 0 ? "swipe_up" : "swipe_down"
                arbiter.commitAction(gesture: .swipe, action: swipeAction, cooldown: tune.swipeCooldownSeconds, now: nowTimestamp)
                return true
            }
        }
        return false
    }

    private func evaluatePinchDock(lm: HandLandmarks, now: Date) -> Bool {
        let apps = actionSink.getRecentApps()
        guard !apps.isEmpty else { return false }

        arbiter.claim(intent: .pinchDock)
        let initialIndex = (apps.count > 1) ? 1 : 0
        actionSink.playFeedback(named: "Pop")
        TelemetryLogger.shared.log(
            action: "dock_open",
            reason: nil,
            chargeLevel: 1.0,
            handCentroid: lm.handCentroid
        )
        onDockOpen?(apps, initialIndex)
        state = .engaged(
            anchor: lm.pinchCenter,
            selectedIndex: initialIndex,
            appCount: apps.count,
            openTime: now,
            lastStableIndex: initialIndex,
            stableSince: now
        )
        return true
    }

    private func evaluateStandby(
        lm: HandLandmarks,
        now: Date,
        nowTimestamp: TimeInterval,
        dt: Double,
        tune: GestureTuning
    ) {
        onArmedStatus?(false)

        let notInSwipeCooldown = (nowTimestamp - lastSwipeTime) > 0.40
        let canPinchDock = arbiter.canBegin(intent: .pinchDock, now: nowTimestamp)
        let isCalmHand = handSpeed < tune.pinchCalmHandSpeed
        let hasClearance = (activeSuppressReason == nil) && notInSwipeCooldown && canPinchDock
        let shouldOpenDock = lm.isPinching && lm.isInInteractionRange && hasClearance && isCalmHand

        if shouldOpenDock {
            if evaluatePinchDock(lm: lm, now: now) {
                return
            }
        }

        // Intentionality Gates in Standby:
        if let reason = activeSuppressReason {
            logSuppression(reason: reason, centroid: lm.handCentroid)
            chargeLevel = max(0.0, chargeLevel - CGFloat(dt * 2.0))
            onScanProgress?(chargeLevel)
            return
        }

        let isReadyToArm = lm.isStrictOpenPalm && lm.isInInteractionRange

        if isReadyToArm {
            chargeLevel = min(1.0, chargeLevel + CGFloat(dt / 0.28))
        } else {
            chargeLevel = max(0.0, chargeLevel - CGFloat(dt * 1.5))
        }
        onScanProgress?(chargeLevel)

        if chargeLevel >= 1.0 {
            chargeLevel = 0.0
            TelemetryLogger.shared.log(
                action: "trigger",
                reason: nil,
                chargeLevel: 1.0,
                handCentroid: lm.handCentroid
            )
            actionSink.playFeedback(named: "Glass")
            state = .armed(expiresAt: now.addingTimeInterval(4.0))
            onArmedStatus?(true)
            onScanProgress?(1.0)
        }
    }

    private func evaluateArmed(
        lm: HandLandmarks,
        now: Date,
        nowTimestamp: TimeInterval,
        expiresAt: Date,
        tune: GestureTuning
    ) {
        if now > expiresAt {
            state = .standby
            onArmedStatus?(false)
            onScanProgress?(0.0)
            return
        }

        // Gating in Armed State:
        if let reason = activeSuppressReason {
            if reason == .faceProximity {
                logSuppression(reason: reason, centroid: lm.handCentroid)
                forceDischarge()
                state = .standby
                onArmedStatus?(false)
                onScanProgress?(0.0)
                return
            }
        }

        onArmedStatus?(true)
        onScanProgress?(1.0)

        let canPinchArmed = arbiter.canBegin(intent: .pinchDock, now: nowTimestamp)
        let isCalmHand = handSpeed < tune.pinchCalmHandSpeed
        if lm.isPinching && canPinchArmed && isCalmHand {
            if evaluatePinchDock(lm: lm, now: now) {
                return
            }
        } else if lm.isOpenHand {
            state = .armed(expiresAt: now.addingTimeInterval(4.0))
        }
    }

    private func evaluateDockScrub(
        lm: HandLandmarks,
        now: Date,
        nowTimestamp: TimeInterval,
        dt: Double,
        anchor: CGPoint,
        selectedIndex: Int,
        appCount: Int,
        openTime: Date,
        lastStableIndex: Int,
        stableSince: Date
    ) {
        onArmedStatus?(true)

        let currentPoint = lm.pinchCenter
        let dwellTime = now.timeIntervalSince(openTime)
        let rawDx = currentPoint.x - anchor.x
        let dy = currentPoint.y - anchor.y

        // Instant Cmd+Tab Quick Toggle:
        let isInDeadzone = abs(rawDx) <= deadzoneRadius
        let allowRelease = (!lm.isPinching) && (isInDeadzone || dwellTime > 0.16)

        // 2. ROCK-SOLID PINCH RELEASE
        if allowRelease {
            let elapsedSinceChange = now.timeIntervalSince(stableSince)
            let commitIndex: Int
            if elapsedSinceChange < 0.12 && lastStableIndex != selectedIndex {
                commitIndex = lastStableIndex
            } else {
                commitIndex = selectedIndex
            }

            onDockSelectIndex?(commitIndex, .zero)
            commitSwitch(centroid: currentPoint)
            arbiter.commitAction(gesture: .pinchDock, action: "pinch_dock", cooldown: 0.38, now: nowTimestamp)
            lastDx = 0.0
            filteredVelocity = 0.0
            state = .cooldown(until: now.addingTimeInterval(0.30))
            return
        }

        // Velocity-Assisted Scrubbing (Flick-to-Switch):
        let instVel = Double(abs(rawDx - lastDx)) / dt
        lastDx = rawDx
        filteredVelocity = 0.70 * filteredVelocity + 0.30 * instVel

        let velocityMultiplier: CGFloat
        if filteredVelocity > 0.32 {
            velocityMultiplier = min(2.4, CGFloat(1.0 + 1.8 * (filteredVelocity - 0.32)))
        } else {
            velocityMultiplier = 1.0
        }
        let effectiveDx = (rawDx >= 0 ? 1.0 : -1.0) * (abs(rawDx) * velocityMultiplier)
        let tiltDelta = CGSize(width: rawDx, height: dy)

        // 3. CONTINUOUS HORIZONTAL SCRUBBING WITH TUNED DETENT HYSTERESIS
        if appCount > 0 {
            let rawIndexFloat: Double
            if effectiveDx > deadzoneRadius {
                rawIndexFloat = 1.0 + Double((effectiveDx - deadzoneRadius) / stepWidth)
            } else if effectiveDx < -deadzoneRadius {
                rawIndexFloat = 1.0 - Double((-effectiveDx - deadzoneRadius) / stepWidth)
            } else {
                rawIndexFloat = (appCount > 1) ? 1.0 : 0.0
            }

            // Schmitt trigger deadband (0.55 detent threshold) to prevent boundary jitter
            var targetIndex = selectedIndex
            if rawIndexFloat > Double(selectedIndex) + 0.55 {
                targetIndex = min(appCount - 1, Int(floor(rawIndexFloat + 0.45)))
            } else if rawIndexFloat < Double(selectedIndex) - 0.55 {
                targetIndex = max(0, Int(ceil(rawIndexFloat - 0.45)))
            }

            // Center deadzone cleanly stabilizes index 1 (previous app toggle)
            if abs(rawDx) <= deadzoneRadius {
                targetIndex = (appCount > 1) ? 1 : 0
            }

            if targetIndex != selectedIndex {
                actionSink.playFeedback(named: "Tink")
                onDockSelectIndex?(targetIndex, tiltDelta)
                state = .engaged(
                    anchor: anchor,
                    selectedIndex: targetIndex,
                    appCount: appCount,
                    openTime: openTime,
                    lastStableIndex: selectedIndex,
                    stableSince: now
                )
                return
            }

            onDockSelectIndex?(selectedIndex, tiltDelta)
        }
    }

    private func commitSwitch(centroid: CGPoint = .zero) {
        TelemetryLogger.shared.log(
            action: "dock_commit",
            reason: nil,
            chargeLevel: 1.0,
            handCentroid: centroid
        )
        onDockCommit?()
        actionSink.playFeedback(named: "Pop")
    }

    private func handleHandLost(now: Date, dt: Double) {
        if case .standby = state {
            chargeLevel = max(0.0, chargeLevel - CGFloat(dt * 1.2))
            onScanProgress?(chargeLevel)
        }

        let lostDuration = now.timeIntervalSince(lastHandSeenTime)
        if lostDuration > 0.60 {
            if case .engaged(_, let selectedIndex, _, _, let lastStableIndex, let stableSince) = state {
                // If hand was abruptly dropped while engaged, commit the last stable selection smoothly
                let elapsedSinceChange = now.timeIntervalSince(stableSince)
                let commitIndex = (elapsedSinceChange < 0.12) ? lastStableIndex : selectedIndex
                onDockSelectIndex?(commitIndex, .zero)
                commitSwitch(centroid: .zero)
                arbiter.commitAction(gesture: .pinchDock, action: "pinch_dock", cooldown: 0.35, now: now.timeIntervalSinceReferenceDate)
                state = .cooldown(until: now.addingTimeInterval(0.35))
                return
            }

            arbiter.release(intent: .pinchDock)
            state = .standby
            onArmedStatus?(false)
            onScanProgress?(0.0)
            pendingSuppressReason = nil
            pendingSuppressFrames = 0
            activeSuppressReason = nil
        }
    }
}
