import XCTest
import CoreGraphics
@testable import GestureFlow

final class CursorEngineTests: XCTestCase {
    private func makeLandmarks(
        middleMCP: CGPoint,
        thumbTip: CGPoint,
        indexTip: CGPoint,
        middleTip: CGPoint? = nil,
        wrist: CGPoint = CGPoint(x: 0.50, y: 0.85),
        isRaised: Bool = true,
        facingCamera: Double = 0.80,
        isPinching: Bool = false,
        isTwoFingers: Bool = false
    ) -> HandLandmarks {
        let actualMiddleTip = middleTip ?? CGPoint(x: middleMCP.x, y: middleMCP.y - 0.15)
        var points = Array(repeating: CGPoint.zero, count: 21)
        points[0] = wrist
        points[4] = thumbTip
        points[5] = CGPoint(x: middleMCP.x - 0.05, y: middleMCP.y)
        points[8] = indexTip
        points[9] = middleMCP
        points[12] = actualMiddleTip
        points[17] = CGPoint(x: middleMCP.x + 0.05, y: middleMCP.y)

        return HandLandmarks(
            points: points,
            fingerCount: isTwoFingers ? 2 : 4,
            isTwoFingers: isTwoFingers,
            isCrossedFingers: false,
            isOneFinger: false,
            isOpenHand: !isTwoFingers,
            isStrictOpenPalm: !isTwoFingers,
            isInInteractionRange: true,
            tiltAngleDegrees: 10.0,
            isFist: false,
            pinchDistance: hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y),
            isPinching: isPinching,
            isFramingCorner: false,
            isThreeFingerPinch: false,
            thumbMiddleDistance: hypot(thumbTip.x - actualMiddleTip.x, thumbTip.y - actualMiddleTip.y),
            indexMiddleDistance: hypot(indexTip.x - actualMiddleTip.x, indexTip.y - actualMiddleTip.y),
            pinchCenter: CGPoint(x: 0.5, y: 0.5),
            twoFingerCenter: CGPoint(x: 0.5, y: 0.5),
            indexTip: indexTip,
            middleTip: actualMiddleTip,
            thumbTip: thumbTip,
            wrist: wrist,
            isRaisedHand: isRaised,
            estimatedDepth: 0.40,
            depthVelocity: 0.0,
            isAirPush: false,
            featureTensor: [],
            handCentroid: middleMCP,
            facingCamera: facingCamera,
            faceBBox: nil,
            faceImpliedDepth: nil
        )
    }

    func testHoverMoveDispatchesMouseMove() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))

        clock.advance(to: 1.00)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.40, y: 0.40),
            indexTip: CGPoint(x: 0.50, y: 0.40)
        )
        engine.process(lm1)

        XCTAssertEqual(engine.state, .pointing)
        XCTAssertTrue(sink.actions.contains { $0.starts(with: "mouse_move_") })
    }

    func testPreClickAnchorLockingEliminatesDeflection() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0 // 1:1 mapping for exact coordinate assertions

        // Frame 1: Resting hover at (0.50, 0.50) with open aperture ~0.80
        clock.advance(to: 1.00)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40)
        )
        engine.process(lm1)
        XCTAssertEqual(engine.state, .pointing)

        // Frame 2: Rapid aperture contraction (0.80 -> 0.35 in 16ms, dAp = -28/s) -> triggers preClickLock!
        clock.advance(to: 1.016)
        let lm2 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.45, y: 0.40),
            indexTip: CGPoint(x: 0.55, y: 0.40)
        )
        engine.process(lm2)

        guard case .preClickLocked(let lockedPos, _) = engine.state else {
            XCTFail("Expected state to be preClickLocked, got \(engine.state)")
            return
        }

        // Frame 3: During clamp, user hand mechanical twitch drifts middleMCP by 0.06 (60px)
        clock.advance(to: 1.032)
        let lm3 = makeLandmarks(
            middleMCP: CGPoint(x: 0.56, y: 0.54), // Deflection tremor!
            thumbTip: CGPoint(x: 0.56, y: 0.40),
            indexTip: CGPoint(x: 0.56, y: 0.40),
            isPinching: true
        )
        engine.process(lm3)

        // The click down position must match the PRE-CLICK LOCKED coordinate, completely immune to tremor drift!
        guard case .clicking(let downPos, _) = engine.state else {
            XCTFail("Expected state to be clicking, got \(engine.state)")
            return
        }

        XCTAssertEqual(downPos.x, lockedPos.x, accuracy: 0.001)
        XCTAssertEqual(downPos.y, lockedPos.y, accuracy: 0.001)

        // Frame 4: Release pinch -> Click commits
        clock.advance(to: 1.080)
        let lm4 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            isPinching: false
        )
        engine.process(lm4)

        XCTAssertEqual(engine.state, .pointing)
        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_click")
    }

    func testDraggingTransitionsBeyondThreshold() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0

        // Frame 0: Open hand wakes engine from idle into pointing
        clock.advance(to: 1.00)
        let lm0 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            isPinching: false
        )
        engine.process(lm0)
        XCTAssertEqual(engine.state, .pointing)

        // Frame 1: Pinch down at (0.50, 0.50)
        clock.advance(to: 1.02)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.50, y: 0.40),
            indexTip: CGPoint(x: 0.50, y: 0.40),
            isPinching: true
        )
        engine.process(lm1)
        XCTAssertTrue(sink.actions.contains { $0.starts(with: "mouse_down_") })

        // Frame 2: Sustained motion while pinched -> triggers dragging
        clock.advance(to: 1.05)
        let lm2a = makeLandmarks(
            middleMCP: CGPoint(x: 0.35, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.35, y: 0.40),
            isPinching: true
        )
        engine.process(lm2a)

        clock.advance(to: 1.10)
        let lm2b = makeLandmarks(
            middleMCP: CGPoint(x: 0.30, y: 0.50),
            thumbTip: CGPoint(x: 0.30, y: 0.40),
            indexTip: CGPoint(x: 0.30, y: 0.40),
            isPinching: true
        )
        engine.process(lm2b)

        XCTAssertTrue(sink.actions.contains { $0.starts(with: "mouse_dragged_") })

        // Frame 3: Release pinch -> commits cursor_drag
        clock.advance(to: 1.15)
        let lm3 = makeLandmarks(
            middleMCP: CGPoint(x: 0.30, y: 0.50),
            thumbTip: CGPoint(x: 0.20, y: 0.40),
            indexTip: CGPoint(x: 0.45, y: 0.40),
            isPinching: false
        )
        engine.process(lm3)

        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_drag")
    }



    func testUnraisedHandSuppressesCursor() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter)

        clock.advance(to: 1.00)
        let lm = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.40, y: 0.40),
            indexTip: CGPoint(x: 0.50, y: 0.40),
            isRaised: false
        )
        engine.process(lm)
        XCTAssertEqual(engine.state, .idle)
    }

    func testAdaptiveViscousDampingDampsLowSpeedAndGlidesHighSpeed() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter)

        var t = 1.00
        // Phase 1: Stationary / micro-tremor frames at 60 FPS (dt = 0.016)
        // Hand moves by at most 0.0005 (micro-tremor), speed <= 0.04 units/sec
        for i in 0..<15 {
            clock.advance(to: t)
            let jitter = (i % 2 == 0) ? 0.0005 : -0.0005
            let lm = makeLandmarks(
                middleMCP: CGPoint(x: 0.50 + jitter, y: 0.50),
                thumbTip: CGPoint(x: 0.40, y: 0.40),
                indexTip: CGPoint(x: 0.50, y: 0.40)
            )
            engine.process(lm)
            t += 0.016
        }

        // At low speed, cutoff must drop near low-speed floor (<= 0.65 Hz) for heavy tremor absorption
        XCTAssertLessThanOrEqual(engine.currentCutoff, 0.65, "Low speed pointing should drop cutoff into viscous damping field")

        // Phase 2: Rapid ballistic flick (hand travels 0.05 units per frame -> speed ~ 3.1 units/sec >> 0.30)
        var posX = 0.50
        for _ in 0..<10 {
            clock.advance(to: t)
            posX += 0.05
            let lm = makeLandmarks(
                middleMCP: CGPoint(x: posX, y: 0.50),
                thumbTip: CGPoint(x: posX - 0.10, y: 0.40),
                indexTip: CGPoint(x: posX, y: 0.40)
            )
            engine.process(lm)
            t += 0.016
        }

        // At high speed, cutoff must open to high-speed glide (>= 2.40 Hz) for lag-free tracking
        XCTAssertGreaterThanOrEqual(engine.currentCutoff, 2.40, "High speed flick should open cutoff to ballistic glide")
    }

    func testDoubleClickDispatchesClickCountTwo() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0

        // Frame 0: Wake to pointing
        clock.advance(to: 1.00)
        let lm0 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40)
        )
        engine.process(lm0)
        XCTAssertEqual(engine.state, .pointing)

        // Click 1: Pinch down
        clock.advance(to: 1.05)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.50, y: 0.40),
            indexTip: CGPoint(x: 0.50, y: 0.40),
            isPinching: true
        )
        engine.process(lm1)

        // Click 1: Release pinch (commit single click)
        clock.advance(to: 1.10)
        let lm2 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            isPinching: false
        )
        engine.process(lm2)
        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_click")

        // Click 2: Rapid second pinch within doubleClickInterval (1.20 - 1.10 = 0.10s < 0.35s)
        clock.advance(to: 1.20)
        let lm3 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.50, y: 0.40),
            indexTip: CGPoint(x: 0.50, y: 0.40),
            isPinching: true
        )
        engine.process(lm3)

        // Click 2: Release pinch -> Double click triggers!
        clock.advance(to: 1.25)
        let lm4 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            isPinching: false
        )
        engine.process(lm4)

        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_double_click")
        XCTAssertTrue(sink.actions.contains { $0.starts(with: "mouse_double_click_") })
    }

    func testRightClickDispatchesOnMiddleThumbPinch() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0

        // Frame 0: Pointing with open hand
        clock.advance(to: 1.00)
        let lm0 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            middleTip: CGPoint(x: 0.50, y: 0.30)
        )
        engine.process(lm0)
        XCTAssertEqual(engine.state, .pointing)

        // Frame 1: Thumb touches middle finger (middle-thumb pinch), index finger stays extended
        clock.advance(to: 1.05)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.50, y: 0.32),
            indexTip: CGPoint(x: 0.65, y: 0.40), // far from thumb (currentAperture ~ 0.45 > 0.28)
            middleTip: CGPoint(x: 0.50, y: 0.32)  // touching thumb (thumbMiddleAperture = 0.0 < 0.22)
        )
        engine.process(lm1)
        guard case .rightClicking = engine.state else {
            XCTFail("Expected .rightClicking, got \(engine.state)")
            return
        }

        // Frame 2: Release middle-thumb pinch
        clock.advance(to: 1.10)
        let lm2 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40),
            middleTip: CGPoint(x: 0.50, y: 0.30)
        )
        engine.process(lm2)

        XCTAssertEqual(engine.state, .pointing)
        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_right_click")
        XCTAssertTrue(sink.actions.contains { $0.starts(with: "right_click_") })
    }

    func testInCursorTwoFingerScrollDispatchesScrollWheel() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0

        // Frame 0: Pointing
        clock.advance(to: 1.00)
        let lm0 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.65, y: 0.40)
        )
        engine.process(lm0)
        XCTAssertEqual(engine.state, .pointing)

        // Frame 1: Two fingers posture entered at Y = 0.50
        clock.advance(to: 1.05)
        let lm1 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.50),
            thumbTip: CGPoint(x: 0.35, y: 0.40),
            indexTip: CGPoint(x: 0.48, y: 0.35),
            middleTip: CGPoint(x: 0.52, y: 0.35),
            isTwoFingers: true
        )
        engine.process(lm1)
        guard case .scrolling = engine.state else {
            XCTFail("Expected .scrolling, got \(engine.state)")
            return
        }

        // Frame 2: Hand moves vertically downwards (Y = 0.50 -> 0.55), generating deltaY displacement
        clock.advance(to: 1.10)
        let lm2 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.55),
            thumbTip: CGPoint(x: 0.35, y: 0.45),
            indexTip: CGPoint(x: 0.48, y: 0.40),
            middleTip: CGPoint(x: 0.52, y: 0.40),
            isTwoFingers: true
        )
        engine.process(lm2)

        XCTAssertTrue(sink.actions.contains { $0.starts(with: "scroll_wheel_") })

        // Frame 3: Return to open palm (ends two-finger scroll)
        clock.advance(to: 1.15)
        let lm3 = makeLandmarks(
            middleMCP: CGPoint(x: 0.50, y: 0.55),
            thumbTip: CGPoint(x: 0.35, y: 0.45),
            indexTip: CGPoint(x: 0.65, y: 0.45),
            isTwoFingers: false
        )
        engine.process(lm3)

        XCTAssertEqual(engine.state, .pointing)
        XCTAssertEqual(arbiter.lastCommittedActionName, "cursor_scroll")
    }
}
