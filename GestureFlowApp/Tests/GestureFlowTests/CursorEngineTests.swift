import XCTest
import CoreGraphics
@testable import GestureFlow

final class CursorEngineTests: XCTestCase {
    private func makeLandmarks(
        middleMCP: CGPoint,
        thumbTip: CGPoint,
        indexTip: CGPoint,
        wrist: CGPoint = CGPoint(x: 0.50, y: 0.85),
        isRaised: Bool = true,
        facingCamera: Double = 0.80,
        isPinching: Bool = false
    ) -> HandLandmarks {
        var points = Array(repeating: CGPoint.zero, count: 21)
        points[0] = wrist
        points[4] = thumbTip
        points[5] = CGPoint(x: middleMCP.x - 0.05, y: middleMCP.y)
        points[8] = indexTip
        points[9] = middleMCP
        points[17] = CGPoint(x: middleMCP.x + 0.05, y: middleMCP.y)

        return HandLandmarks(
            points: points,
            fingerCount: 4,
            isTwoFingers: false,
            isCrossedFingers: false,
            isOneFinger: false,
            isOpenHand: true,
            isStrictOpenPalm: true,
            isInInteractionRange: true,
            tiltAngleDegrees: 10.0,
            isFist: false,
            pinchDistance: hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y),
            isPinching: isPinching,
            isFramingCorner: false,
            isThreeFingerPinch: false,
            thumbMiddleDistance: 0.10,
            indexMiddleDistance: 0.05,
            pinchCenter: CGPoint(x: 0.5, y: 0.5),
            twoFingerCenter: CGPoint(x: 0.5, y: 0.5),
            indexTip: indexTip,
            middleTip: CGPoint(x: middleMCP.x, y: middleMCP.y - 0.15),
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
}
