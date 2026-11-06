import XCTest
import CoreGraphics
@testable import GestureFlow

final class MagneticSnappingEngineTests: XCTestCase {
    func testNoSnappingWhenTargetsEmpty() {
        let engine = MagneticSnappingEngine()
        let pos = CGPoint(x: 350, y: 450)
        let snapped = engine.applySnapping(cursorPos: pos, speedPxPerSec: 50.0)
        XCTAssertEqual(snapped.x, pos.x, accuracy: 0.001)
        XCTAssertEqual(snapped.y, pos.y, accuracy: 0.001)
    }

    func testAttractionInsidePotentialWellAtLowSpeed() {
        let engine = MagneticSnappingEngine()
        let target = SnapTarget(id: "btn1", rect: CGRect(x: 470, y: 480, width: 60, height: 40), snapRadius: 60, strength: 0.80)
        engine.registerTarget(target)

        // Target center is (500, 500)
        // Cursor at (485, 500) -> 15px to the left
        let rawPos = CGPoint(x: 485, y: 500)
        let snapped = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 80.0)

        // Snapped position should be pulled closer to center (500.0)
        XCTAssertGreaterThan(snapped.x, rawPos.x, "Magnetic potential should pull cursor toward target center")
        XCTAssertEqual(snapped.y, 500.0, accuracy: 0.001)

        let initialDist = abs(target.center.x - rawPos.x)
        let finalDist = abs(target.center.x - snapped.x)
        XCTAssertLessThan(finalDist, initialDist * 0.50, "At 80% strength, final distance should be reduced by more than half")
    }

    func testZeroAttractionOutsideBasin() {
        let engine = MagneticSnappingEngine()
        let target = SnapTarget(id: "btn1", rect: CGRect(x: 480, y: 480, width: 40, height: 40), snapRadius: 40)
        engine.registerTarget(target)

        // Cursor at (750, 500), 250px away, far outside the 40px radius
        let rawPos = CGPoint(x: 750, y: 500)
        let snapped = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 50.0)

        XCTAssertEqual(snapped.x, rawPos.x, accuracy: 0.001, "Outside basin, attraction must be zero")
        XCTAssertEqual(snapped.y, rawPos.y, accuracy: 0.001)
    }

    func testBreakawayEscapeAtHighSpeed() {
        let engine = MagneticSnappingEngine()
        let target = SnapTarget(id: "btn1", rect: CGRect(x: 480, y: 480, width: 40, height: 40), snapRadius: 50, strength: 0.80)
        engine.registerTarget(target)

        let rawPos = CGPoint(x: 490, y: 500) // 10px from center

        // At low speed (100 px/s <= 200), strong attraction
        let lowSpeedSnapped = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 100.0)
        XCTAssertGreaterThan(lowSpeedSnapped.x, rawPos.x)

        // At ballistic breakaway speed (750 px/s >= 650), magnetic attraction completely disengages
        let highSpeedSnapped = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 750.0)
        XCTAssertEqual(highSpeedSnapped.x, rawPos.x, accuracy: 0.001, "Ballistic flick should breakaway with zero stickiness")
        XCTAssertEqual(highSpeedSnapped.y, rawPos.y, accuracy: 0.001)
    }

    func testSmoothBreakawayModulation() {
        let engine = MagneticSnappingEngine()
        let target = SnapTarget(id: "btn1", rect: CGRect(x: 480, y: 480, width: 40, height: 40), snapRadius: 50, strength: 0.80)
        engine.registerTarget(target)

        let rawPos = CGPoint(x: 490, y: 500)
        let pullLow = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 150.0).x - rawPos.x
        let pullMid = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 425.0).x - rawPos.x
        let pullHigh = engine.applySnapping(cursorPos: rawPos, speedPxPerSec: 700.0).x - rawPos.x

        XCTAssertGreaterThan(pullLow, pullMid, "Mid speed should have less pull than low speed")
        XCTAssertGreaterThan(pullMid, pullHigh, "High speed should have less pull than mid speed")
        XCTAssertEqual(pullHigh, 0.0, accuracy: 0.001)
    }

    func testTargetRegistrationAndUnregistration() {
        let engine = MagneticSnappingEngine()
        let t1 = SnapTarget(id: "t1", rect: CGRect(x: 100, y: 100, width: 50, height: 50))
        let t2 = SnapTarget(id: "t2", rect: CGRect(x: 200, y: 200, width: 50, height: 50))

        engine.registerTarget(t1)
        engine.registerTarget(t2)
        XCTAssertEqual(engine.targets.count, 2)

        engine.unregisterTarget(id: "t1")
        XCTAssertEqual(engine.targets.count, 1)
        XCTAssertEqual(engine.targets.first?.id, "t2")

        engine.clearTargets()
        XCTAssertTrue(engine.targets.isEmpty)
    }

    func testCursorEngineSnapsWithRegisteredTarget() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let engine = CursorEngine(clock: clock, actionSink: sink, arbiter: arbiter, screenSize: CGSize(width: 1000, height: 1000))
        engine.interactionMargin = 0.0

        // Target at center (500, 500)
        let target = SnapTarget(id: "center_button", rect: CGRect(x: 480, y: 480, width: 40, height: 40), snapRadius: 60, strength: 0.75)
        engine.snappingEngine.registerTarget(target)

        var lastPos: CGPoint = .zero
        engine.onCursorMoved = { pos in
            lastPos = pos
        }

        // Send landmark near (0.51, 0.50) -> screen pos ~ (490, 500) with mirroring
        clock.advance(to: 1.00)
        let lm = HandLandmarks(
            points: Array(repeating: CGPoint(x: 0.51, y: 0.50), count: 21),
            fingerCount: 4,
            isTwoFingers: false,
            isCrossedFingers: false,
            isOneFinger: false,
            isOpenHand: true,
            isStrictOpenPalm: true,
            isInInteractionRange: true,
            tiltAngleDegrees: 10.0,
            isFist: false,
            pinchDistance: 0.50,
            isPinching: false,
            isFramingCorner: false,
            isThreeFingerPinch: false,
            thumbMiddleDistance: 0.40,
            indexMiddleDistance: 0.20,
            pinchCenter: CGPoint(x: 0.5, y: 0.5),
            twoFingerCenter: CGPoint(x: 0.5, y: 0.5),
            indexTip: CGPoint(x: 0.51, y: 0.40),
            middleTip: CGPoint(x: 0.51, y: 0.35),
            thumbTip: CGPoint(x: 0.40, y: 0.40),
            wrist: CGPoint(x: 0.51, y: 0.85),
            isRaisedHand: true,
            estimatedDepth: 0.40,
            depthVelocity: 0.0,
            isAirPush: false,
            featureTensor: [],
            handCentroid: CGPoint(x: 0.51, y: 0.50),
            facingCamera: 0.80,
            faceBBox: nil,
            faceImpliedDepth: nil
        )

        engine.process(lm)
        XCTAssertEqual(engine.state, .pointing)

        // Raw mirrored X without snapping would be (1.0 - 0.51) * 1000 = 490
        // With snapping towards target at 500, lastPos.x should be pulled towards 500 (> 490)
        XCTAssertGreaterThan(lastPos.x, 491.0, "Magnetic snapping should attract cursor towards target center")
    }
}
