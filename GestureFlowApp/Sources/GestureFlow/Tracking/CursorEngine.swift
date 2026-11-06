import Foundation
import CoreGraphics
import AppKit

/// Mode 4: Spatial Air Cursor & Mouse Engine
/// Features:
/// 1. Metacarpophalangeal (Middle MCP) Pointing Anchor with 1€ filter for minimal tremor.
/// 2. Pre-Click Anchor Locking: Freezes cursor coordinate during the 35-50ms pinch deceleration window,
///    eliminating the 5-15px Heisenberg Click Deflection.
/// 3. Smooth Pointer Dragging & Native Mouse Event Dispatching.
final class CursorEngine {
    enum CursorState: Equatable {
        case idle
        case pointing
        case preClickLocked(anchorPos: CGPoint, lockUntil: TimeInterval)
        case clicking(downPos: CGPoint, startTime: TimeInterval)
        case dragging(downPos: CGPoint)
    }

    // Dependencies
    private let clock: Clock
    private let actionSink: ActionSink
    private let arbiter: IntentArbiter

    // Screen geometry
    var screenSize: CGSize = CGSize(width: 1440, height: 900)
    var interactionMargin: CGFloat = 0.12 // 12% padding around camera frame for edge reachability

    // Kinematic Filtering & Adaptive Viscous Damping Field
    // Low speed -> viscous damping (0.40 Hz) absorbs 8-12Hz physiological tremor ("viscous honey").
    // High speed -> ballistic glide (2.50 Hz) provides zero-lag rapid tracking.
    var minCutoffLowSpeed: Double = 0.40
    var minCutoffHighSpeed: Double = 2.50
    var speedThreshold: Double = 0.30 // Normalized coordinate velocity threshold (units/sec)
    private(set) var currentCutoff: Double = 0.40
    private var previousRawAnchor: CGPoint?
    private var smoothedAnchorSpeed: Double = 0.0
    private let pointFilter = PointFilter2D(minCutoff: 0.40, beta: 0.035, noiseGateThreshold: 0.0008)

    // State Tracking
    private(set) var state: CursorState = .idle
    private var lastValidScreenPos: CGPoint = CGPoint(x: 720, y: 450)
    private var lastProcessTimestamp: TimeInterval = 0.0
    private var previousAperture: CGFloat = 0.80

    // Thresholds & Tunings
    var preClickApertureThreshold: CGFloat = 0.48
    var preClickVelocityThreshold: CGFloat = -0.70 // norm_aperture / sec
    var preClickLockDuration: TimeInterval = 0.045 // 45ms freeze
    var pinchCommitAperture: CGFloat = 0.22
    var pinchReleaseAperture: CGFloat = 0.28
    var dragThresholdPx: CGFloat = 16.0

    // Callbacks
    var onAction: ((String) -> Void)?
    var onRejectReason: ((RejectReason?) -> Void)?
    var onCursorMoved: ((CGPoint) -> Void)?

    init(
        clock: Clock = SystemClock.shared,
        actionSink: ActionSink = LiveActionSink.shared,
        arbiter: IntentArbiter = .shared,
        screenSize: CGSize? = nil
    ) {
        self.clock = clock
        self.actionSink = actionSink
        self.arbiter = arbiter
        if let size = screenSize {
            self.screenSize = size
        } else if let mainScreen = NSScreen.main {
            self.screenSize = mainScreen.frame.size
        }
    }

    func forceDischarge() {
        cleanReleaseIfNeeded()
        state = .idle
        pointFilter.reset()
        previousRawAnchor = nil
        smoothedAnchorSpeed = 0.0
        currentCutoff = minCutoffLowSpeed
        pointFilter.minCutoff = minCutoffLowSpeed
    }

    func process(_ landmarks: HandLandmarks?) {
        let now = clock.now.timeIntervalSinceReferenceDate
        let dt = max(0.001, min(0.100, lastProcessTimestamp > 0.0 ? now - lastProcessTimestamp : 0.016))
        lastProcessTimestamp = now

        // 1. Guard Hand Presence
        guard let lm = landmarks else {
            handleLostHand()
            return
        }

        // 2. Intentionality Gates
        if !lm.isRaisedHand {
            cleanReleaseIfNeeded()
            state = .idle
            onRejectReason?(.notStable)
            return
        }

        if lm.facingCamera < 0.20 {
            cleanReleaseIfNeeded()
            state = .idle
            onRejectReason?(.edgeOnPalm)
            return
        }

        if let face = lm.faceBBox {
            let wrist = lm.wrist
            if face.contains(wrist) || face.insetBy(dx: -0.05, dy: -0.05).contains(wrist) {
                cleanReleaseIfNeeded()
                state = .idle
                onRejectReason?(.faceOverlap)
                return
            }
        }

        // 3. Compute Pointing Coordinate (Middle MCP preferred for physiological tremor damping)
        let anchor = lm.points.count >= 21 ? lm.points[9] : lm.handCentroid

        // Adaptive Viscous Damping Field:
        // Dynamic cutoff based on anchor velocity v = Δpos / Δt
        if let prev = previousRawAnchor {
            let dist = hypot(anchor.x - prev.x, anchor.y - prev.y)
            let instSpeed = Double(dist) / dt
            smoothedAnchorSpeed = (smoothedAnchorSpeed == 0.0) ? instSpeed : (0.35 * instSpeed + 0.65 * smoothedAnchorSpeed)
            let linearRatio = min(1.0, max(0.0, smoothedAnchorSpeed / speedThreshold))
            let speedRatio = linearRatio * linearRatio // Quadratic nonlinear viscous damping field
            currentCutoff = minCutoffLowSpeed + (minCutoffHighSpeed - minCutoffLowSpeed) * speedRatio
            pointFilter.minCutoff = currentCutoff
        } else {
            currentCutoff = minCutoffLowSpeed
            pointFilter.minCutoff = minCutoffLowSpeed
        }
        previousRawAnchor = anchor

        let smoothedAnchor = pointFilter.filter(anchor, timestamp: now)

        // Map normalized camera coordinates to display space with edge margin expansion
        let normX = max(0.0, min(1.0, (1.0 - smoothedAnchor.x - interactionMargin) / (1.0 - 2.0 * interactionMargin)))
        let normY = max(0.0, min(1.0, (smoothedAnchor.y - interactionMargin) / (1.0 - 2.0 * interactionMargin)))
        let currentScreenPos = CGPoint(x: normX * screenSize.width, y: normY * screenSize.height)

        // 4. Compute Normalized Aperture & Velocity
        let wrist = lm.points.count >= 21 ? lm.points[0] : lm.wrist
        let thumbTip = lm.points.count >= 21 ? lm.points[4] : lm.thumbTip
        let indexTip = lm.points.count >= 21 ? lm.points[8] : lm.indexTip
        let middleMCP = lm.points.count >= 21 ? lm.points[9] : anchor

        let palmSpan = max(0.05, hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y))
        let currentAperture = hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y) / palmSpan
        let apertureVelocity = (currentAperture - previousAperture) / CGFloat(dt)
        previousAperture = currentAperture

        let isPinchDetected = lm.isPinching || (currentAperture < pinchCommitAperture)

        // 5. State Machine Transition Logic
        switch state {
        case .idle:
            if arbiter.canBegin(intent: .airCursor, now: now) {
                state = .pointing
                lastValidScreenPos = currentScreenPos
                actionSink.mouseMove(to: currentScreenPos)
                onCursorMoved?(currentScreenPos)
            }

        case .pointing:
            if isPinchDetected {
                // Pinch already committed (fingers in contact)
                commitPinchDown(at: currentScreenPos, now: now)
            } else if currentAperture <= preClickApertureThreshold && apertureVelocity <= preClickVelocityThreshold {
                // Fingers rapidly clamping toward pinch: freeze cursor coordinate
                state = .preClickLocked(anchorPos: currentScreenPos, lockUntil: now + preClickLockDuration)
                lastValidScreenPos = currentScreenPos
            } else {
                lastValidScreenPos = currentScreenPos
                actionSink.mouseMove(to: currentScreenPos)
                onCursorMoved?(currentScreenPos)
            }


        case .preClickLocked(let lockedPos, let lockUntil):
            if isPinchDetected {
                // Pinch completed at locked coordinate! Zero deflection achieved.
                commitPinchDown(at: lockedPos, now: now)
            } else if now >= lockUntil || currentAperture > preClickApertureThreshold {
                // Window expired without commitment -> Return to standard pointing
                state = .pointing
                lastValidScreenPos = currentScreenPos
                actionSink.mouseMove(to: currentScreenPos)
                onCursorMoved?(currentScreenPos)
            }

        case .clicking(let downPos, let startTime):
            if isPinchDetected {
                // Check if user has begun dragging beyond drag threshold
                let travel = hypot(currentScreenPos.x - downPos.x, currentScreenPos.y - downPos.y)
                if travel >= dragThresholdPx {
                    state = .dragging(downPos: downPos)
                    actionSink.mouseDragged(to: currentScreenPos)
                    lastValidScreenPos = currentScreenPos
                    onCursorMoved?(currentScreenPos)
                }
            } else if currentAperture >= pinchReleaseAperture {
                // Released pinch -> Click commit
                actionSink.mouseUp(at: downPos)
                let duration = now - startTime
                if duration <= 0.40 {
                    arbiter.commitAction(gesture: .airCursor, action: "cursor_click", now: now)
                    onAction?("Click")
                } else {
                    arbiter.commitAction(gesture: .airCursor, action: "cursor_release", now: now)
                }
                arbiter.release(intent: .airCursor)
                state = .pointing
                lastValidScreenPos = currentScreenPos
                actionSink.mouseMove(to: currentScreenPos)
                onCursorMoved?(currentScreenPos)
            }

        case .dragging:
            if isPinchDetected {
                actionSink.mouseDragged(to: currentScreenPos)

                lastValidScreenPos = currentScreenPos
                onCursorMoved?(currentScreenPos)
            } else if currentAperture >= pinchReleaseAperture {
                actionSink.mouseUp(at: currentScreenPos)
                arbiter.commitAction(gesture: .airCursor, action: "cursor_drag", now: now)
                arbiter.release(intent: .airCursor)

                onAction?("Drag & Drop")
                state = .pointing
                lastValidScreenPos = currentScreenPos
                actionSink.mouseMove(to: currentScreenPos)
                onCursorMoved?(currentScreenPos)
            }
        }
    }

    private func commitPinchDown(at pos: CGPoint, now: TimeInterval) {
        arbiter.claim(intent: .airCursor)
        actionSink.mouseDown(at: pos)
        state = .clicking(downPos: pos, startTime: now)
        lastValidScreenPos = pos
        onCursorMoved?(pos)
    }

    private func handleLostHand() {
        cleanReleaseIfNeeded()
        state = .idle
        pointFilter.reset()
        previousRawAnchor = nil
        smoothedAnchorSpeed = 0.0
        currentCutoff = minCutoffLowSpeed
        pointFilter.minCutoff = minCutoffLowSpeed
    }

    private func cleanReleaseIfNeeded() {
        switch state {
        case .clicking(let downPos, _):
            actionSink.mouseUp(at: downPos)
            arbiter.release(intent: .airCursor)
        case .dragging:
            actionSink.mouseUp(at: lastValidScreenPos)
            arbiter.release(intent: .airCursor)
        default:
            break
        }
    }
}
