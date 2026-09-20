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
    private var lastProcessTime: Date = Date()
    private var lastHandSeenTime: Date = Date()

    private let deadzoneRadius: CGFloat = 0.022  // Compact center deadzone for quick toggle
    private let stepWidth: CGFloat = 0.038       // Compact physical travel per app detent (~4-5cm)
    private var lastDx: CGFloat = 0.0
    private var filteredVelocity: Double = 0.0

    // MARK: - Intentionality Gating Constants (Tunable for Laptop & Desktop)
    static let facingCameraSuppressEnter: Double = 0.24
    static let facingCameraSuppressExit: Double = 0.32
    static let facingCameraThreshold: Double = 0.28 // Nominal midpoint

    static let depthBandDeltaEnter: CGFloat = 0.07
    static let depthBandDeltaExit: CGFloat = 0.10
    static let depthBandDelta: CGFloat = 0.08 // Nominal midpoint

    static let faceBBoxExpansionFactor: CGFloat = 1.50

    enum GateSuppressReason: String {
        case faceProximity = "face_proximity"
        case edgeOnPalm = "edge_on_palm"
        case depthBand = "depth_band"
    }

    private var lastSuppressionLogTime: Date = .distantPast
    private var lastSuppressionReason: String?

    // Schmitt-trigger gate hysteresis state
    private var isSuppressedByFacingCamera: Bool = false
    private var isSuppressedByDepthBand: Bool = false

    // 3-frame temporal confirmation buffer to eliminate 5Hz chattering
    private var pendingSuppressReason: GateSuppressReason?
    private var pendingSuppressFrames: Int = 0
    private let requiredSuppressFrames: Int = 3

    func forceDischarge() {
        chargeLevel = 0.0
        lastDx = 0.0
        filteredVelocity = 0.0
        isSuppressedByFacingCamera = false
        isSuppressedByDepthBand = false
        pendingSuppressReason = nil
        pendingSuppressFrames = 0
        activeSuppressReason = nil
    }

    func evaluateIntentionalityGates(landmarks: HandLandmarks) -> GateSuppressReason? {
        let handZ = landmarks.estimatedDepth
        let faceZ = landmarks.faceImpliedDepth

        // 1. Face-exclusion: Hand near face/chin in 2D AND at/near face depth in 3D
        if let faceBox = landmarks.faceBBox {
            // Expand face box: 0.25x sides, 0.15x top, 0.35x bottom (covers chin and jawline)
            let expMinX = faceBox.minX - faceBox.width * 0.25
            let expWidth = faceBox.width * 1.50
            let expMinY = faceBox.minY - faceBox.height * 0.15
            let expHeight = faceBox.height * 1.50
            let expandedFaceBBox = CGRect(
                x: expMinX,
                y: expMinY,
                width: expWidth,
                height: expHeight
            )

            // Test unmirrored contact points only (not mirrored pinchCenter or drooping wrist)
            let contactPoints = [
                landmarks.handCentroid,
                landmarks.indexTip,
                landmarks.thumbTip
            ]

            let isInFace2D = contactPoints.contains(where: { expandedFaceBBox.contains($0) })

            if isInFace2D {
                // If face depth is known, verify hand is not reaching in the foreground (arm's length)
                if let fz = faceZ {
                    // Hand is touching or near face if it is within 14cm of face depth
                    if (fz - handZ) < 0.14 {
                        isSuppressedByFacingCamera = false
                        isSuppressedByDepthBand = false
                        return .faceProximity
                    }
                } else {
                    isSuppressedByFacingCamera = false
                    isSuppressedByDepthBand = false
                    return .faceProximity
                }
            }
        }

        // 2. Palm-orientation with Schmitt Trigger Hysteresis
        // Enter suppression when facingCamera < 0.36; Exit only when facingCamera > 0.44
        if isSuppressedByFacingCamera {
            if landmarks.facingCamera > GestureEngine.facingCameraSuppressExit {
                isSuppressedByFacingCamera = false
            }
        } else {
            if landmarks.facingCamera < GestureEngine.facingCameraSuppressEnter {
                isSuppressedByFacingCamera = true
            }
        }

        if isSuppressedByFacingCamera {
            return .edgeOnPalm
        }

        // 3. Depth-band with Schmitt Trigger Hysteresis
        // Depth-band only suppresses when hand is raised to head/ear/neck level
        // On laptops, hands down in front of keyboard/chest (y > faceBox.maxY + 0.08) are in normal interaction space
        let isNearHeadLevel: Bool = {
            guard let faceBox = landmarks.faceBBox else { return true }
            return landmarks.handCentroid.y < (faceBox.maxY + 0.08)
        }()

        if let fz = faceZ, isNearHeadLevel {
            let diff = abs(handZ - fz)
            if isSuppressedByDepthBand {
                if diff >= GestureEngine.depthBandDeltaExit {
                    isSuppressedByDepthBand = false
                }
            } else {
                if diff <= GestureEngine.depthBandDeltaEnter {
                    isSuppressedByDepthBand = true
                }
            }

            if isSuppressedByDepthBand {
                return .depthBand
            }
        } else {
            isSuppressedByDepthBand = false
        }

        return nil
    }

    private func logSuppression(reason: GateSuppressReason, centroid: CGPoint) {
        let now = Date()
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
        let now = Date()
        let dt = min(0.1, max(0.001, now.timeIntervalSince(lastProcessTime)))
        lastProcessTime = now

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

        lastHandSeenTime = now
        let isPinching = lm.isPinching
        let currentPoint = lm.pinchCenter

        switch state {
        case .standby:
            onArmedStatus?(false)

            // Intentionality Gates in Standby:
            // Drain charge gracefully under suppression instead of instant zero on single-frame noise
            if let reason = activeSuppressReason {
                logSuppression(reason: reason, centroid: lm.handCentroid)
                chargeLevel = max(0.0, chargeLevel - CGFloat(dt * 2.0))
                onScanProgress?(chargeLevel)
                return
            }

            // ONLY accumulate charge when hand is explicitly in flat open palm pose AND within intentional distance!
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
                ActionDispatcher.playFeedback(named: "Glass")
                state = .armed(expiresAt: now.addingTimeInterval(4.0))
                onArmedStatus?(true)
                onScanProgress?(1.0)
            }

        case .armed(let expiresAt):
            if now > expiresAt {
                state = .standby
                onArmedStatus?(false)
                onScanProgress?(0.0)
                return
            }

            // Gating in Armed State:
            // Only face proximity disarms when armed (e.g. scratching face/chin).
            // Do NOT disarm on edge-on palm: rotating the hand is naturally required to pinch!
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

            if isPinching {
                let apps = ActionDispatcher.getRecentApps()
                guard !apps.isEmpty else { return }

                // Index 1 is the previous app (instant Cmd+Tab toggle target)
                let initialIndex = (apps.count > 1) ? 1 : 0
                ActionDispatcher.playFeedback(named: "Pop")
                TelemetryLogger.shared.log(
                    action: "dock_open",
                    reason: nil,
                    chargeLevel: 1.0,
                    handCentroid: lm.handCentroid
                )
                onDockOpen?(apps, initialIndex)

                state = .engaged(
                    anchor: currentPoint,
                    selectedIndex: initialIndex,
                    appCount: apps.count,
                    openTime: now,
                    lastStableIndex: initialIndex,
                    stableSince: now
                )
            } else if lm.isOpenHand {
                // Prolong armed state while user comfortably presents hand
                state = .armed(expiresAt: now.addingTimeInterval(4.0))
            }

        case .engaged(let anchor, let selectedIndex, let appCount, let openTime, let lastStableIndex, let stableSince):
            onArmedStatus?(true)

            let dwellTime = now.timeIntervalSince(openTime)
            let rawDx = currentPoint.x - anchor.x
            let dy = currentPoint.y - anchor.y

            // Instant Cmd+Tab Quick Toggle:
            // If the hand stayed inside the resting deadzone, allow immediate pinch release!
            let isInDeadzone = abs(rawDx) <= deadzoneRadius
            let allowRelease = (!isPinching) && (isInDeadzone || dwellTime > 0.16)

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
                    ActionDispatcher.playFeedback(named: "Tink")
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

        case .cooldown:
            break
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
        ActionDispatcher.playFeedback(named: "Pop")
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
                state = .cooldown(until: now.addingTimeInterval(0.35))
                return
            }

            state = .standby
            onArmedStatus?(false)
            onScanProgress?(0.0)
            isSuppressedByFacingCamera = false
            isSuppressedByDepthBand = false
            pendingSuppressReason = nil
            pendingSuppressFrames = 0
            activeSuppressReason = nil
        }
    }
}
