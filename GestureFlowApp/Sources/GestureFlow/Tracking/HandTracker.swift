import Foundation
import Vision
import AppKit
import CoreMedia
import QuartzCore

struct HandLandmarks {
    let points: [CGPoint]          // 21 points normalized 0.0 - 1.0 (Top-left origin)
    let fingerCount: Int
    let isTwoFingers: Bool         // Index & Middle up, Ring & Pinky down (Two Fingers / Crossed)
    let isCrossedFingers: Bool     // Index & Middle touching / crossed
    let isOneFinger: Bool          // Index up, Middle, Ring & Pinky down
    let isOpenHand: Bool           // 4-5 fingers extended
    let isStrictOpenPalm: Bool     // Explicit flat open palm with 5 extended fingers facing camera
    let isInInteractionRange: Bool// Metric depth Z within [0.28m ... 0.65m]
    let tiltAngleDegrees: Double   // Out-of-plane tilt angle in degrees [0° ... 90°]
    let isFist: Bool               // 0 fingers extended
    let pinchDistance: CGFloat
    let isPinching: Bool
    let isFramingCorner: Bool      // Index extended, Thumb spread, other fingers folded, not pinching (Viewfinder Frame corner)
    let isThreeFingerPinch: Bool   // Thumb + Index + Middle touching together (Trackpad Pick)
    let thumbMiddleDistance: CGFloat
    let indexMiddleDistance: CGFloat
    let pinchCenter: CGPoint       // Mirrored screen coordinate (0..1)
    let twoFingerCenter: CGPoint   // Mirrored screen coordinate (0..1)
    let indexTip: CGPoint
    let middleTip: CGPoint
    let thumbTip: CGPoint
    let wrist: CGPoint
    let isRaisedHand: Bool         // Hand is raised up in the air off desk
    let estimatedDepth: CGFloat    // Anthropometric metric depth [0.1..1.0]
    let depthVelocity: CGFloat     // dZ/dt forward push velocity
    let isAirPush: Bool            // Forward spatial pulse
    let featureTensor: [Float]     // Canonical 64D normalized hand feature embedding for AI/ML
    let handCentroid: CGPoint      // Palm centroid (wrist + middleMCP)/2
    let facingCamera: Double       // dot(palmNormal, cameraForward) in [0.0 ... 1.0]
    let faceBBox: CGRect?          // Detected face bounding box in normalized top-left coords
    let faceImpliedDepth: CGFloat? // Face-implied metric depth derived from face bbox size
    var pitchDegrees: Double = 0.0       // 3D Pitch tilt forward/backward [-90° ... +90°]
    var yawDegrees: Double = 0.0         // 3D Yaw tilt left/right [-90° ... +90°]
    var rollDegrees: Double = 0.0        // 3D In-plane roll [-180° ... +180°]
    var perspectiveScale: CGFloat = 1.0  // Dynamic depth scale factor [0.65 ... 1.35]
}

struct MultiHandLandmarks {
    let primary: HandLandmarks
    let secondary: HandLandmarks?
}

final class HandTracker {
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let faceRequest = VNDetectFaceRectanglesRequest()

    // Isolated tracking channel for each hand (filters, persistence & pinch state)
    private typealias HandChannel = HandFeatureExtractor.Channel

    private let primaryChannel = HandChannel()
    private let secondaryChannel = HandChannel()

    // Bipedal Clap Gesture Detector (Mode Switcher)
    var onClapDetected: (() -> Void)?
    private var lastClapTime: Date = .distantPast
    private var interHandDistanceHistory: [(distance: CGFloat, time: Date)] = []
    private var lastTwoHandsTime: Date = .distantPast
    private var lastObservedHandDistance: CGFloat = 1.0
    private var isRapidlyApproaching: Bool = false
    private var wasHandsSeparated: Bool = false

    init() {
        handRequest.maximumHandCount = 2
    }

    private func evaluateClap(results: [VNHumanHandPoseObservation], now: Date) {
        guard now.timeIntervalSince(lastClapTime) > 0.70 else { return }

        func palmCenter(from obs: VNHumanHandPoseObservation) -> CGPoint? {
            let mm = try? obs.recognizedPoint(.middleMCP)
            let wr = try? obs.recognizedPoint(.wrist)
            let im = try? obs.recognizedPoint(.indexMCP)

            var validPts: [CGPoint] = []
            if let m = mm, m.confidence > 0.12 { validPts.append(CGPoint(x: m.location.x, y: 1.0 - m.location.y)) }
            if let w = wr, w.confidence > 0.12 { validPts.append(CGPoint(x: w.location.x, y: 1.0 - w.location.y)) }
            if let i = im, i.confidence > 0.12 { validPts.append(CGPoint(x: i.location.x, y: 1.0 - i.location.y)) }

            guard !validPts.isEmpty else { return nil }
            let sumX = validPts.reduce(0) { $0 + $1.x }
            let sumY = validPts.reduce(0) { $0 + $1.y }
            return CGPoint(x: sumX / CGFloat(validPts.count), y: sumY / CGFloat(validPts.count))
        }

        func palmSpan(from obs: VNHumanHandPoseObservation) -> CGFloat {
            if let mm = try? obs.recognizedPoint(.middleMCP),
               let wr = try? obs.recognizedPoint(.wrist),
               mm.confidence > 0.12, wr.confidence > 0.12 {
                return hypot(mm.location.x - wr.location.x, mm.location.y - wr.location.y)
            }
            return 0.10
        }

        if results.count >= 2 {
            guard let c1 = palmCenter(from: results[0]),
                  let c2 = palmCenter(from: results[1]) else { return }

            let dist = hypot(c1.x - c2.x, c1.y - c2.y)
            let bothRaised = c1.y < 0.985 && c2.y < 0.985

            interHandDistanceHistory.append((distance: dist, time: now))
            interHandDistanceHistory.removeAll { now.timeIntervalSince($0.time) > 0.45 }

            let maxPastDist = interHandDistanceHistory.map(\.distance).max() ?? 0.0
            wasHandsSeparated = maxPastDist > 0.12

            let span1 = palmSpan(from: results[0])
            let span2 = palmSpan(from: results[1])
            let avgPalm = (span1 + span2) / 2.0
            // Adaptive collision threshold: 0.09 at 65cm, expanding up to 0.24 at 25cm on laptops
            let collisionThreshold = max(0.09, min(0.24, avgPalm * 1.25))

            // Check inward approach velocity
            if interHandDistanceHistory.count >= 2 {
                let earliest = interHandDistanceHistory.first!
                let dt = max(0.01, now.timeIntervalSince(earliest.time))
                let speed = (earliest.distance - dist) / CGFloat(dt) // positive if closing in
                isRapidlyApproaching = (speed > 0.18)
            }

            lastTwoHandsTime = now
            lastObservedHandDistance = dist

            // Trigger Condition 1: Both hands tracked and reached collision distance
            if wasHandsSeparated && dist < collisionThreshold && bothRaised {
                triggerClap(now: now)
                return
            }
        } else if results.count == 1 {
            // Trigger Condition 2: Hands were approaching/separated and suddenly collapsed into 1 observation upon impact
            let dtSinceTwoHands = now.timeIntervalSince(lastTwoHandsTime)
            if dtSinceTwoHands < 0.35 && lastObservedHandDistance < 0.28 && (isRapidlyApproaching || wasHandsSeparated) {
                triggerClap(now: now)
                return
            }
        }
    }

    private func triggerClap(now: Date) {
        lastClapTime = now
        interHandDistanceHistory.removeAll()
        isRapidlyApproaching = false
        wasHandsSeparated = false
        lastObservedHandDistance = 1.0
        DispatchQueue.main.async {
            self.onClapDetected?()
        }
    }

    func processMultiHand(_ pixelBuffer: CVPixelBuffer, pts: CMTime = .zero) -> MultiHandLandmarks? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([handRequest, faceRequest])
        } catch {
            resetPersistence()
            DepthRecorder.shared.record(nil, zEstMM: nil, pts: CMTimeGetSeconds(pts), now: CACurrentMediaTime())
            return nil
        }

        guard let results = handRequest.results, !results.isEmpty else {
            resetPersistence()
            DepthRecorder.shared.record(nil, zEstMM: nil, pts: CMTimeGetSeconds(pts), now: CACurrentMediaTime())
            return nil
        }

        let now = Date()
        let nowTimestamp = now.timeIntervalSinceReferenceDate

        // Evaluate bipedal clap gesture (handles both 2-hand collision and 1-hand impact collapse)
        evaluateClap(results: results, now: now)

        let faceBBox: CGRect? = {
            guard let faceObs = faceRequest.results?.first else { return nil }
            let b = faceObs.boundingBox
            return CGRect(x: b.origin.x, y: 1.0 - b.origin.y - b.size.height, width: b.size.width, height: b.size.height)
        }()

        let faceImpliedDepth: CGFloat? = {
            guard let box = faceBBox else { return nil }
            let faceDim = max(box.width, box.height * 0.75)
            guard faceDim > 0.04 else { return nil }
            return 0.16 / faceDim
        }()

        // Sort hands left-to-right (in normalized camera space)
        let sorted = results.sorted { obs1, obs2 in
            let x1 = (try? obs1.recognizedPoint(.wrist))?.location.x ?? 0.5
            let x2 = (try? obs2.recognizedPoint(.wrist))?.location.x ?? 0.5
            return x1 < x2
        }

        guard let primaryLandmarks = parseObservation(
            sorted[0],
            channel: primaryChannel,
            nowTimestamp: nowTimestamp,
            faceBBox: faceBBox,
            faceImpliedDepth: faceImpliedDepth
        ) else {
            primaryChannel.reset()
            DepthRecorder.shared.record(nil, zEstMM: nil, pts: CMTimeGetSeconds(pts), now: CACurrentMediaTime())
            return nil
        }

        // Tap raw primary observation for offline depth & latency analysis (Step 0)
        DepthRecorder.shared.record(
            sorted[0],
            face: faceBBox,
            zEstMM: Double(primaryLandmarks.estimatedDepth * 1000.0),
            pts: CMTimeGetSeconds(pts),
            now: CACurrentMediaTime()
        )

        var secondaryLandmarks: HandLandmarks? = nil
        if sorted.count >= 2 {
            secondaryLandmarks = parseObservation(
                sorted[1],
                channel: secondaryChannel,
                nowTimestamp: nowTimestamp,
                faceBBox: faceBBox,
                faceImpliedDepth: faceImpliedDepth
            )
        } else {
            secondaryChannel.reset()
        }

        return MultiHandLandmarks(primary: primaryLandmarks, secondary: secondaryLandmarks)
    }

    func process(_ pixelBuffer: CVPixelBuffer, pts: CMTime = .zero) -> HandLandmarks? {
        return processMultiHand(pixelBuffer, pts: pts)?.primary
    }

    private func parseObservation(
        _ obs: VNHumanHandPoseObservation,
        channel: HandChannel,
        nowTimestamp: TimeInterval,
        faceBBox: CGRect?,
        faceImpliedDepth: CGFloat?
    ) -> HandLandmarks? {
        let joints: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        var rawPoints: [CGPoint] = []
        var confs: [Float] = []
        for j in joints {
            if let pt = try? obs.recognizedPoint(j) {
                let p = CGPoint(x: pt.location.x, y: 1.0 - pt.location.y)
                rawPoints.append(p)
                confs.append(pt.confidence)
            } else {
                rawPoints.append(.zero)
                confs.append(0.0)
            }
        }

        return HandFeatureExtractor.landmarks(
            from: rawPoints,
            confidences: confs,
            channel: channel,
            nowTimestamp: nowTimestamp,
            faceBBox: faceBBox,
            faceImpliedDepth: faceImpliedDepth
        )
    }

    private func resetPersistence() {
        primaryChannel.reset()
        secondaryChannel.reset()
    }
}
