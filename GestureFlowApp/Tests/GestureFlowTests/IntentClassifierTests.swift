import XCTest
import CoreGraphics
@testable import GestureFlow

final class IntentClassifierTests: XCTestCase {
    private func makeOpenPalmPoints(cx: CGFloat = 0.50, cy: CGFloat = 0.50, scale: CGFloat = 1.0) -> [CGPoint] {
        return [
            CGPoint(x: cx, y: cy + 0.10 * scale),               // 0: wrist
            CGPoint(x: cx - 0.04 * scale, y: cy + 0.05 * scale), // 1: thumb CMC
            CGPoint(x: cx - 0.07 * scale, y: cy + 0.02 * scale), // 2: thumb MP
            CGPoint(x: cx - 0.09 * scale, y: cy - 0.01 * scale), // 3: thumb IP
            CGPoint(x: cx - 0.11 * scale, y: cy - 0.03 * scale), // 4: thumb tip
            CGPoint(x: cx - 0.04 * scale, y: cy),               // 5: index MCP
            CGPoint(x: cx - 0.04 * scale, y: cy - 0.05 * scale), // 6: index PIP
            CGPoint(x: cx - 0.04 * scale, y: cy - 0.09 * scale), // 7: index DIP
            CGPoint(x: cx - 0.04 * scale, y: cy - 0.13 * scale), // 8: index tip
            CGPoint(x: cx, y: cy),                              // 9: middle MCP
            CGPoint(x: cx, y: cy - 0.06 * scale),               // 10: middle PIP
            CGPoint(x: cx, y: cy - 0.10 * scale),               // 11: middle DIP
            CGPoint(x: cx, y: cy - 0.15 * scale),               // 12: middle tip
            CGPoint(x: cx + 0.04 * scale, y: cy),               // 13: ring MCP
            CGPoint(x: cx + 0.04 * scale, y: cy - 0.05 * scale), // 14: ring PIP
            CGPoint(x: cx + 0.04 * scale, y: cy - 0.09 * scale), // 15: ring DIP
            CGPoint(x: cx + 0.04 * scale, y: cy - 0.13 * scale), // 16: ring tip
            CGPoint(x: cx + 0.07 * scale, y: cy + 0.02 * scale), // 17: pinky MCP
            CGPoint(x: cx + 0.07 * scale, y: cy - 0.03 * scale), // 18: pinky PIP
            CGPoint(x: cx + 0.07 * scale, y: cy - 0.06 * scale), // 19: pinky DIP
            CGPoint(x: cx + 0.07 * scale, y: cy - 0.09 * scale)  // 20: pinky tip
        ]
    }

    private func makePinchPoints(cx: CGFloat = 0.50, cy: CGFloat = 0.50, scale: CGFloat = 1.0) -> [CGPoint] {
        var pts = makeOpenPalmPoints(cx: cx, cy: cy, scale: scale)
        let touch = CGPoint(x: cx - 0.03 * scale, y: cy - 0.04 * scale)
        pts[4] = touch
        pts[8] = touch
        pts[7] = CGPoint(x: cx - 0.03 * scale, y: cy - 0.01 * scale)
        return pts
    }

    private func makeTwoFingerPoints(cx: CGFloat = 0.50, cy: CGFloat = 0.50, scale: CGFloat = 1.0) -> [CGPoint] {
        var pts = makeOpenPalmPoints(cx: cx, cy: cy, scale: scale)
        pts[2] = CGPoint(x: cx - 0.05 * scale, y: cy + 0.03 * scale)
        pts[3] = CGPoint(x: cx - 0.04 * scale, y: cy + 0.01 * scale)
        pts[4] = CGPoint(x: cx - 0.02 * scale, y: cy + 0.02 * scale)
        pts[14] = CGPoint(x: cx + 0.04 * scale, y: cy - 0.02 * scale)
        pts[15] = CGPoint(x: cx + 0.04 * scale, y: cy - 0.01 * scale)
        pts[16] = CGPoint(x: cx + 0.04 * scale, y: cy + 0.01 * scale)
        pts[18] = CGPoint(x: cx + 0.07 * scale, y: cy - 0.01 * scale)
        pts[19] = CGPoint(x: cx + 0.07 * scale, y: cy + 0.01 * scale)
        pts[20] = CGPoint(x: cx + 0.07 * scale, y: cy + 0.02 * scale)
        return pts
    }

    private func makeHandLandmarks(from points: [CGPoint], isPinching: Bool = false, isTwoFingers: Bool = false) -> HandLandmarks {
        let channel = HandFeatureExtractor.Channel()
        if let lm = HandFeatureExtractor.landmarks(
            from: points,
            confidences: Array(repeating: 1.0, count: 21),
            channel: channel,
            nowTimestamp: 1.0
        ) {
            return lm
        }
        return HandLandmarks(
            points: points,
            fingerCount: isTwoFingers ? 2 : 4,
            isTwoFingers: isTwoFingers,
            isCrossedFingers: false,
            isOneFinger: false,
            isOpenHand: true,
            isStrictOpenPalm: true,
            isInInteractionRange: true,
            tiltAngleDegrees: 0.0,
            isFist: false,
            pinchDistance: hypot(points[4].x - points[8].x, points[4].y - points[8].y),
            isPinching: isPinching,
            isFramingCorner: false,
            isThreeFingerPinch: false,
            thumbMiddleDistance: 0.10,
            indexMiddleDistance: 0.05,
            pinchCenter: CGPoint(x: 0.5, y: 0.5),
            twoFingerCenter: CGPoint(x: 0.5, y: 0.5),
            indexTip: points[8],
            middleTip: points[12],
            thumbTip: points[4],
            wrist: points[0],
            isRaisedHand: true,
            estimatedDepth: 0.40,
            depthVelocity: 0.0,
            isAirPush: false,
            featureTensor: [],
            handCentroid: points[9],
            facingCamera: 0.90,
            faceBBox: nil,
            faceImpliedDepth: nil
        )
    }

    func testIntentClassifierModelIsLoaded() {
        let classifier = IntentClassifier()
        XCTAssertTrue(classifier.isAvailable, "IntentClassifier must load the bundled CoreML model")
    }

    func testWindowAccumulationAndFallback() {
        let classifier = IntentClassifier()
        classifier.reset()
        XCTAssertTrue(classifier.isAvailable)

        let lm = makeHandLandmarks(from: makeOpenPalmPoints())

        // First 9 frames must return fallback (window size 10 not yet reached)
        for _ in 0..<9 {
            let pred = classifier.process(landmarks: lm)
            XCTAssertEqual(pred, .fallback)
        }

        // 10th frame triggers inference
        let pred10 = classifier.process(landmarks: lm)
        XCTAssertTrue(IntentClassifier.classes.contains(pred10.intent))
        XCTAssertGreaterThan(pred10.confidence, 0.0)
    }

    func testHoverIntentClassification() {
        let classifier = IntentClassifier()
        classifier.reset()

        // 10 frames of open palm hovering
        var lastPred = IntentPrediction.fallback
        for i in 0..<12 {
            let cx = 0.40 + CGFloat(i) * 0.01
            let lm = makeHandLandmarks(from: makeOpenPalmPoints(cx: cx, cy: 0.50))
            lastPred = classifier.process(landmarks: lm)
        }

        XCTAssertEqual(lastPred.intent, "hover")
        XCTAssertFalse(lastPred.isPreClickAnticipated)
    }

    func testTwoFingerScrollClassification() {
        let classifier = IntentClassifier()
        classifier.reset()

        // 10 frames of two-finger vertical motion
        var lastPred = IntentPrediction.fallback
        for i in 0..<12 {
            let cy = 0.40 + CGFloat(i) * 0.015
            let lm = makeHandLandmarks(from: makeTwoFingerPoints(cx: 0.50, cy: cy), isTwoFingers: true)
            lastPred = classifier.process(landmarks: lm)
        }

        XCTAssertEqual(lastPred.intent, "scroll")
    }

    func testResetClearsWindow() {
        let classifier = IntentClassifier()
        classifier.reset()

        let lm = makeHandLandmarks(from: makeOpenPalmPoints())
        for _ in 0..<10 {
            _ = classifier.process(landmarks: lm)
        }

        // Reset
        classifier.reset()
        let nextPred = classifier.process(landmarks: lm)
        XCTAssertEqual(nextPred, .fallback, "After reset, window must start empty and return fallback")
    }
}
