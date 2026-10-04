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
    private class HandChannel {
        let skeletonFilter = SkeletonFilter(
            jointMinCutoff: 0.45,
            jointBeta: 0.015,
            reticleMinCutoff: 0.28,
            reticleBeta: 0.018
        )
        let depthEstimator = MonocularDepthEstimator()
        let pitchFilter = OneEuroFilter(minCutoff: 0.22, beta: 0.02, dCutoff: 1.0)
        let yawFilter = OneEuroFilter(minCutoff: 0.22, beta: 0.02, dCutoff: 1.0)
        var lastPitchDeg: Double = 0.0
        var lastYawDeg: Double = 0.0
        var lastKnownJoints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        var jointDropCounts: [VNHumanHandPoseObservation.JointName: Int] = [:]
        var wasPinching: Bool = false
        var pinchDropoutCount: Int = 0
        var wasTwoFingers: Bool = false
        var twoFingerDropoutCount: Int = 0

        func reset() {
            skeletonFilter.reset()
            depthEstimator.reset()
            pitchFilter.reset()
            yawFilter.reset()
            lastPitchDeg = 0.0
            lastYawDeg = 0.0
            lastKnownJoints.removeAll(keepingCapacity: true)
            jointDropCounts.removeAll(keepingCapacity: true)
            wasPinching = false
            pinchDropoutCount = 0
            wasTwoFingers = false
            twoFingerDropoutCount = 0
        }
    }

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

        var pointsMap: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        var pointsList: [CGPoint] = []

        // Extract points with confidence threshold & temporal persistence
        for j in joints {
            if let pt = try? obs.recognizedPoint(j), pt.confidence > 0.20 {
                let p = CGPoint(x: pt.location.x, y: 1.0 - pt.location.y)
                pointsMap[j] = p
                channel.lastKnownJoints[j] = p
                channel.jointDropCounts[j] = 0
                pointsList.append(p)
            } else {
                let dropCount = (channel.jointDropCounts[j] ?? 0) + 1
                channel.jointDropCounts[j] = dropCount
                if dropCount <= 4, let lastPt = channel.lastKnownJoints[j] {
                    pointsMap[j] = lastPt
                    pointsList.append(lastPt)
                } else {
                    pointsList.append(.zero)
                }
            }
        }

        let wrist = pointsMap[.wrist] ?? channel.lastKnownJoints[.wrist]
        let middleMCPRaw = pointsMap[.middleMCP] ?? channel.lastKnownJoints[.middleMCP]
        let indexMCPRaw = pointsMap[.indexMCP] ?? channel.lastKnownJoints[.indexMCP]

        // On laptops, wrists are frequently clipped by the bottom frame border.
        // Synthesize valid wrist anchor from MCP knuckles if clipped/missing:
        let validWrist: CGPoint
        if let w = wrist, w != .zero {
            validWrist = w
        } else if let mm = middleMCPRaw, mm != .zero {
            validWrist = CGPoint(x: mm.x, y: min(0.99, mm.y + 0.16))
            pointsMap[.wrist] = validWrist
            channel.lastKnownJoints[.wrist] = validWrist
        } else if let im = indexMCPRaw, im != .zero {
            validWrist = CGPoint(x: im.x, y: min(0.99, im.y + 0.16))
            pointsMap[.wrist] = validWrist
            channel.lastKnownJoints[.wrist] = validWrist
        } else {
            channel.reset()
            return nil
        }

        let indexTip = pointsMap[.indexTip] ?? pointsMap[.indexDIP] ?? pointsMap[.indexPIP] ?? channel.lastKnownJoints[.indexTip]
        guard let validIndexTip = indexTip, validIndexTip != .zero else {
            channel.reset()
            return nil
        }

        func dist(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            return hypot(p1.x - p2.x, p1.y - p2.y)
        }

        func isFingerExtended(_ tip: VNHumanHandPoseObservation.JointName, _ pip: VNHumanHandPoseObservation.JointName, _ mcp: VNHumanHandPoseObservation.JointName) -> Bool {
            guard let t = pointsMap[tip] ?? channel.lastKnownJoints[tip],
                  let p = pointsMap[pip] ?? channel.lastKnownJoints[pip],
                  let m = pointsMap[mcp] ?? channel.lastKnownJoints[mcp],
                  t != .zero, p != .zero, m != .zero else { return false }
            let tipDist = dist(t, validWrist)
            let pipDist = dist(p, validWrist)
            let mcpDist = dist(m, validWrist)
            let knuckleToTip = dist(t, m)
            let knuckleToPip = dist(p, m)
            let isExtendedFromKnuckle = knuckleToTip > knuckleToPip * 1.06
            let isExtendedFromWrist = (tipDist > pipDist * 0.92) && (tipDist > mcpDist * 0.94)
            return isExtendedFromKnuckle || isExtendedFromWrist
        }

        let indexExt = isFingerExtended(.indexTip, .indexPIP, .indexMCP)
        let middleExt = isFingerExtended(.middleTip, .middlePIP, .middleMCP)
        let ringExt = isFingerExtended(.ringTip, .ringPIP, .ringMCP)
        let pinkyExt = isFingerExtended(.littleTip, .littlePIP, .littleMCP)

        var extCount = 0
        if indexExt { extCount += 1 }
        if middleExt { extCount += 1 }
        if ringExt { extCount += 1 }
        if pinkyExt { extCount += 1 }

        let middleMCP = pointsMap[.middleMCP] ?? channel.lastKnownJoints[.middleMCP] ?? .zero
        let indexMCP = pointsMap[.indexMCP] ?? channel.lastKnownJoints[.indexMCP] ?? .zero
        let pinkyMCP = pointsMap[.littleMCP] ?? channel.lastKnownJoints[.littleMCP] ?? .zero
        let ringMCP = pointsMap[.ringMCP] ?? channel.lastKnownJoints[.ringMCP] ?? .zero
        let ringTip = pointsMap[.ringTip] ?? pointsMap[.ringPIP] ?? channel.lastKnownJoints[.ringTip] ?? validWrist
        let middleTipRaw = pointsMap[.middleTip] ?? pointsMap[.middlePIP] ?? channel.lastKnownJoints[.middleTip] ?? validIndexTip

        let indexLen = dist(validIndexTip, indexMCP != .zero ? indexMCP : validWrist)
        let middleLen = dist(middleTipRaw, middleMCP != .zero ? middleMCP : validWrist)
        let ringLen = dist(ringTip, ringMCP != .zero ? ringMCP : validWrist)

        // Ergonomic Relaxed Two-Finger Detection:
        // Index and middle fingers extended; ring finger can be comfortably resting or folded
        let isTwoCandidate = indexExt && middleExt && (!ringExt || (indexLen > ringLen * 1.10 && middleLen > ringLen * 1.08)) && (extCount <= 3)

        let isTwo: Bool
        if isTwoCandidate {
            channel.wasTwoFingers = true
            channel.twoFingerDropoutCount = 0
            isTwo = true
        } else if channel.wasTwoFingers {
            let isFistOrOpen = (extCount == 0) || (extCount >= 4)
            if isFistOrOpen {
                channel.twoFingerDropoutCount += 4
            } else {
                channel.twoFingerDropoutCount += 1
            }

            if channel.twoFingerDropoutCount <= 8 {
                isTwo = true
            } else {
                channel.wasTwoFingers = false
                channel.twoFingerDropoutCount = 0
                isTwo = false
            }
        } else {
            isTwo = false
        }

        let isOne = indexExt && (!middleExt || indexLen > middleLen * 1.25) && (extCount <= 2)
        let isOpen = extCount >= 2
        let isFist = extCount == 0

        let isRaised = (validWrist.y < 0.995) && (validIndexTip.y < 0.985)

        let middleTip = pointsMap[.middleTip] ?? pointsMap[.middlePIP] ?? channel.lastKnownJoints[.middleTip] ?? validIndexTip
        let twoFingersDist = dist(validIndexTip, middleTip)
        let isCrossed = isTwo && (twoFingersDist < 0.052)
        let rawTwoCenter = CGPoint(x: (validIndexTip.x + middleTip.x) / 2.0, y: (validIndexTip.y + middleTip.y) / 2.0)
        let twoCenterScreen = CGPoint(x: 1.0 - rawTwoCenter.x, y: rawTwoCenter.y)

        let thumbTip = pointsMap[.thumbTip] ?? pointsMap[.thumbIP] ?? channel.lastKnownJoints[.thumbTip] ?? validIndexTip
        let thumbIP = pointsMap[.thumbIP] ?? channel.lastKnownJoints[.thumbIP] ?? thumbTip
        let indexDIP = pointsMap[.indexDIP] ?? channel.lastKnownJoints[.indexDIP] ?? validIndexTip
        let indexPIP = pointsMap[.indexPIP] ?? channel.lastKnownJoints[.indexPIP] ?? indexDIP
        let middleDIP = pointsMap[.middleDIP] ?? channel.lastKnownJoints[.middleDIP] ?? middleTip

        // Multi-joint contact cloud: test index & middle finger contact with thumb (laptop perspective)
        let p1 = dist(thumbTip, validIndexTip)
        let p2 = dist(thumbTip, indexDIP)
        let p3 = dist(thumbTip, indexPIP)
        let p4 = dist(thumbIP, validIndexTip)
        let p5 = dist(thumbIP, indexDIP)
        let p6 = dist(thumbTip, middleTip)
        let p7 = dist(thumbTip, middleDIP)
        let minPinchDist = min(p1, p2, p3, p4, p5, p6, p7)

        let contactPair: (CGPoint, CGPoint) = {
            if p1 <= p2 && p1 <= p3 && p1 <= p4 && p1 <= p5 && p1 <= p6 && p1 <= p7 { return (thumbTip, validIndexTip) }
            if p2 <= p3 && p2 <= p4 && p2 <= p5 && p2 <= p6 && p2 <= p7 { return (thumbTip, indexDIP) }
            if p3 <= p4 && p3 <= p5 && p3 <= p6 && p3 <= p7 { return (thumbTip, indexPIP) }
            if p4 <= p5 && p4 <= p6 && p4 <= p7 { return (thumbIP, validIndexTip) }
            if p5 <= p6 && p5 <= p7 { return (thumbIP, indexDIP) }
            if p6 <= p7 { return (thumbTip, middleTip) }
            return (thumbTip, middleDIP)
        }()

        // Anthropometric scale normalization: palm length from wrist to middleMCP
        let palmLength: CGFloat = {
            let mcp = middleMCP != .zero ? middleMCP : (indexMCP != .zero ? indexMCP : validIndexTip)
            let len = dist(validWrist, mcp)
            return max(0.045, len)
        }()
        let pinchRatio = minPinchDist / palmLength

        let middleThumbDist = dist(middleTip, thumbTip)
        let isNotFist = (extCount >= 1) || (minPinchDist < 0.085) || (middleThumbDist > 0.030)

        // Schmitt trigger with scale-invariant ratios: enter <= 0.42, sustain <= 0.58
        let isPinchCandidate: Bool = {
            guard isRaised && isNotFist else { return false }
            if channel.wasPinching {
                return (pinchRatio <= 0.58 && minPinchDist < 0.18) || (minPinchDist < 0.060)
            } else {
                return (pinchRatio <= 0.42 && minPinchDist < 0.14) || (minPinchDist < 0.046)
            }
        }()

        let isPinch: Bool
        if isPinchCandidate {
            channel.wasPinching = true
            channel.pinchDropoutCount = 0
            isPinch = true
        } else if channel.wasPinching {
            let isOpenHandRelease = extCount >= 3 || pinchRatio > 0.65 || minPinchDist > 0.18
            if isOpenHandRelease {
                channel.pinchDropoutCount += 4
            } else {
                channel.pinchDropoutCount += 1
            }

            if channel.pinchDropoutCount <= 10 {
                isPinch = true
            } else {
                channel.wasPinching = false
                channel.pinchDropoutCount = 0
                isPinch = false
            }
        } else {
            isPinch = false
        }

        let rawPinchCenter = CGPoint(x: (contactPair.0.x + contactPair.1.x) / 2.0, y: (contactPair.0.y + contactPair.1.y) / 2.0)
        let pinchCenterScreen = CGPoint(x: 1.0 - rawPinchCenter.x, y: rawPinchCenter.y)

        let (smoothedPoints, smoothedPinchCenter, smoothedTwoCenter) = channel.skeletonFilter.filter(
            points: pointsList,
            pinchCenter: pinchCenterScreen,
            twoCenter: twoCenterScreen,
            timestamp: nowTimestamp
        )

        let isThreePinch = isRaised && !isFist && (minPinchDist < 0.068) && (middleThumbDist < 0.072) && (twoFingersDist < 0.065)

        // Compute 3D palm normal vector using smoothed joints to eliminate sensor noise
        let smWrist = smoothedPoints.count >= 21 ? smoothedPoints[0] : validWrist
        let smIndexMCP = smoothedPoints.count >= 21 ? smoothedPoints[5] : indexMCP
        let smPinkyMCP = smoothedPoints.count >= 21 ? smoothedPoints[17] : pinkyMCP
        let smMiddleMCP = smoothedPoints.count >= 21 ? smoothedPoints[9] : middleMCP

        let normalVec: SIMD3<Double> = {
            guard smIndexMCP != .zero, smPinkyMCP != .zero else { return SIMD3<Double>(0, 0, 1) }

            let palmVec = SIMD2<Double>(Double(smIndexMCP.x - smWrist.x), Double(smIndexMCP.y - smWrist.y))
            let palmLen = simd_length(palmVec)
            guard palmLen > 0.01 else { return SIMD3<Double>(0, 0, 1) }

            let knuckleVec = SIMD2<Double>(Double(smPinkyMCP.x - smIndexMCP.x), Double(smPinkyMCP.y - smIndexMCP.y))
            let knuckleDist = simd_length(knuckleVec)

            let restKnuckleWidth = palmLen * 0.78
            let clampedKnuckle = min(restKnuckleWidth, knuckleDist)
            let dz = sqrt(max(0.0, restKnuckleWidth * restKnuckleWidth - clampedKnuckle * clampedKnuckle))

            let u = SIMD3<Double>(Double(smIndexMCP.x - smWrist.x), Double(smIndexMCP.y - smWrist.y), 0.0)
            let v = SIMD3<Double>(Double(smPinkyMCP.x - smWrist.x), Double(smPinkyMCP.y - smWrist.y), dz)

            let crossProd = simd_cross(u, v)
            let len = simd_length(crossProd)
            return len > 1e-6 ? (crossProd / len) : SIMD3<Double>(0, 0, 1)
        }()

        let cameraForward = SIMD3<Double>(0, 0, 1)
        let dotProduct = abs(simd_dot(normalVec, cameraForward))

        // Projected 2D palm triangle fullness: Area(wrist, indexMCP, pinkyMCP) / palmLen^2
        let palmTriangleArea = 0.5 * abs(
            Double((smIndexMCP.x - smWrist.x) * (smPinkyMCP.y - smWrist.y) - (smIndexMCP.y - smWrist.y) * (smPinkyMCP.x - smWrist.x))
        )
        let palmLengthDouble = max(0.01, Double(palmLength))
        let planarFullness = min(1.0, max(0.0, (palmTriangleArea * 4.2) / (palmLengthDouble * palmLengthDouble)))
        let facingCamera = max(dotProduct * 0.70 + planarFullness * 0.30, dotProduct)

        let smRingMCP = smoothedPoints.count >= 21 ? smoothedPoints[13] : (pointsMap[.ringMCP] ?? .zero)
        let depthResult = channel.depthEstimator.estimateDepth(
            wrist: validWrist,
            indexMCP: smIndexMCP,
            middleMCP: smMiddleMCP,
            ringMCP: smRingMCP,
            pinkyMCP: smPinkyMCP,
            facingCamera: facingCamera,
            timestamp: nowTimestamp
        )

        let handCentroid = CGPoint(x: (validWrist.x + middleMCP.x) / 2.0, y: (validWrist.y + middleMCP.y) / 2.0)

        // On laptops, camera looks up at user: hand is naturally angled forward/upward, not strictly upright
        let thumbSpread = (dist(thumbTip, validIndexTip) / palmLength > 0.34) || (dist(thumbTip, validIndexTip) > 0.050)
        let isHandPointingUpward = (validIndexTip.y < validWrist.y + 0.14)
        // Screen tilt and keyboard posture: allow facingCamera >= 0.28
        let isFacingDirectly = (facingCamera >= 0.28)
        let isStrictOpenPalm = (extCount >= 3) && indexExt && middleExt && thumbSpread && isHandPointingUpward && isFacingDirectly && (minPinchDist > 0.060)

        // Framing Corner (L-Shape / Viewfinder): Index finger extended, Thumb spread out,
        // at least one of middle/ring/pinky folded, not open palm, and strictly NOT pinching
        let isFramingCorner = indexExt && thumbSpread && !isPinch && (!middleExt || !pinkyExt || !ringExt) && !isStrictOpenPalm && (extCount <= 3)

        let depthMeters = depthResult.estimatedDepth
        // Comfortable laptop interaction range: 0.18m (close-up over keyboard) to 0.85m (office chair posture)
        let isInInteractionRange = (depthMeters >= 0.18 && depthMeters <= 0.85)
        let tiltAngleDegrees = acos(min(1.0, max(0.0, facingCamera))) * 180.0 / .pi

        // 3D Attitude Euler Angles & Perspective Depth Scale with 1€ Filter and Stationary Deadzone
        let rawPitchDeg = asin(min(1.0, max(-1.0, -normalVec.y))) * 180.0 / .pi
        let rawYawDeg = asin(min(1.0, max(-1.0, normalVec.x))) * 180.0 / .pi
        let filteredPitch = channel.pitchFilter.filter(rawPitchDeg, timestamp: nowTimestamp)
        let filteredYaw = channel.yawFilter.filter(rawYawDeg, timestamp: nowTimestamp)

        let finalPitch: Double
        if abs(filteredPitch - channel.lastPitchDeg) < 0.60 {
            finalPitch = channel.lastPitchDeg
        } else {
            finalPitch = filteredPitch
            channel.lastPitchDeg = filteredPitch
        }

        let finalYaw: Double
        if abs(filteredYaw - channel.lastYawDeg) < 0.60 {
            finalYaw = channel.lastYawDeg
        } else {
            finalYaw = filteredYaw
            channel.lastYawDeg = filteredYaw
        }

        let dxRoll = Double(smMiddleMCP.x - smWrist.x)
        let dyRoll = Double(smMiddleMCP.y - smWrist.y)
        let rollDeg = (atan2(dyRoll, dxRoll) * 180.0 / .pi) + 90.0
        let perspectiveScale = max(0.65, min(1.35, 0.45 / depthResult.estimatedDepth))

        let featureTensor = channel.depthEstimator.generateAIFeatureVector(
            landmarks: smoothedPoints,
            depth: depthResult.estimatedDepth,
            pinchDist: minPinchDist
        )

        return HandLandmarks(
            points: smoothedPoints,
            fingerCount: extCount,
            isTwoFingers: isTwo,
            isCrossedFingers: isCrossed,
            isOneFinger: isOne,
            isOpenHand: isOpen,
            isStrictOpenPalm: isStrictOpenPalm,
            isInInteractionRange: isInInteractionRange,
            tiltAngleDegrees: tiltAngleDegrees,
            isFist: isFist,
            pinchDistance: minPinchDist,
            isPinching: isPinch,
            isFramingCorner: isFramingCorner,
            isThreeFingerPinch: isThreePinch,
            thumbMiddleDistance: middleThumbDist,
            indexMiddleDistance: twoFingersDist,
            pinchCenter: smoothedPinchCenter,
            twoFingerCenter: smoothedTwoCenter,
            indexTip: validIndexTip,
            middleTip: middleTip,
            thumbTip: thumbTip,
            wrist: validWrist,
            isRaisedHand: isRaised,
            estimatedDepth: depthResult.estimatedDepth,
            depthVelocity: depthResult.depthVelocity,
            isAirPush: depthResult.isAirPush,
            featureTensor: featureTensor,
            handCentroid: handCentroid,
            facingCamera: facingCamera,
            faceBBox: faceBBox,
            faceImpliedDepth: faceImpliedDepth,
            pitchDegrees: finalPitch,
            yawDegrees: finalYaw,
            rollDegrees: rollDeg,
            perspectiveScale: perspectiveScale
        )
    }

    private func resetPersistence() {
        primaryChannel.reset()
        secondaryChannel.reset()
    }
}
