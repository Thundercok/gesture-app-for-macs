import XCTest
import CoreGraphics
@testable import GestureFlow

final class PostureClassifierTests: XCTestCase {
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

    private func makeFistPoints(cx: CGFloat = 0.50, cy: CGFloat = 0.50, scale: CGFloat = 1.0) -> [CGPoint] {
        var pts = makeOpenPalmPoints(cx: cx, cy: cy, scale: scale)
        pts[6] = CGPoint(x: cx - 0.04 * scale, y: cy - 0.02 * scale)
        pts[7] = CGPoint(x: cx - 0.04 * scale, y: cy - 0.01 * scale)
        pts[8] = CGPoint(x: cx - 0.04 * scale, y: cy + 0.01 * scale)
        pts[10] = CGPoint(x: cx, y: cy - 0.02 * scale)
        pts[11] = CGPoint(x: cx, y: cy - 0.01 * scale)
        pts[12] = CGPoint(x: cx, y: cy + 0.01 * scale)
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
        // Fallback synthetic constructor
        return HandLandmarks(
            points: points,
            fingerCount: 4,
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

    func testPostureClassifierModelIsLoaded() {
        let classifier = PostureClassifier()
        XCTAssertTrue(classifier.isAvailable, "PostureClassifier must discover and load the bundled CoreML model")
    }

    func testExtractFeaturesProduces56DCanonicalVector() {
        let pts = makeOpenPalmPoints()
        let feats = PostureClassifier.extractFeatures(fromPoints: pts)
        XCTAssertNotNil(feats)
        XCTAssertEqual(feats?.count, 56, "Canonical feature vector must be exactly 56 dimensions (42 coords + 14 engineered)")

        // In canonical right-hand frame, wrist is at origin (0, 0)
        XCTAssertEqual(feats?[0] ?? -1.0, 0.0, accuracy: 0.001)
        XCTAssertEqual(feats?[1] ?? -1.0, 0.0, accuracy: 0.001)

        // Middle MCP (point 9) must point vertically up (+Y) at distance 1.0
        XCTAssertEqual(feats?[18] ?? -1.0, 0.0, accuracy: 0.001)
        XCTAssertEqual(feats?[19] ?? -1.0, 1.0, accuracy: 0.001)
    }

    func testEvaluateShadowInferenceOnCanonicalPostures() {
        let classifier = PostureClassifier()
        XCTAssertTrue(classifier.isAvailable)

        // Test Open Palm
        let openLm = makeHandLandmarks(from: makeOpenPalmPoints())
        _ = classifier.evaluateShadow(landmarks: nil, heuristicPosture: "none")
        var res: (shadowPosture: String, shadowAgrees: Bool) = ("none", false)
        for _ in 0..<8 {
            res = classifier.evaluateShadow(landmarks: openLm, heuristicPosture: "open_palm")
        }
        XCTAssertEqual(res.shadowPosture, "open_palm")

        // Test Pinch
        let pinchLm = makeHandLandmarks(from: makePinchPoints(), isPinching: true)
        _ = classifier.evaluateShadow(landmarks: nil, heuristicPosture: "none")
        for _ in 0..<8 {
            res = classifier.evaluateShadow(landmarks: pinchLm, heuristicPosture: "pinch")
        }
        XCTAssertEqual(res.shadowPosture, "pinch")

        // Test Two Fingers
        let twoLm = makeHandLandmarks(from: makeTwoFingerPoints(), isTwoFingers: true)
        _ = classifier.evaluateShadow(landmarks: nil, heuristicPosture: "none")
        for _ in 0..<8 {
            res = classifier.evaluateShadow(landmarks: twoLm, heuristicPosture: "two_fingers")
        }
        XCTAssertEqual(res.shadowPosture, "two_fingers")

        // Test Fist
        let fistLm = makeHandLandmarks(from: makeFistPoints())
        _ = classifier.evaluateShadow(landmarks: nil, heuristicPosture: "none")
        for _ in 0..<8 {
            res = classifier.evaluateShadow(landmarks: fistLm, heuristicPosture: "fist")
        }
        XCTAssertEqual(res.shadowPosture, "fist")
    }
}
