import Foundation
import CoreGraphics
import simd

final class HandFeatureExtractor {
    class Channel {
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
        var lastKnownPoints: [Int: CGPoint] = [:]
        var pointDropCounts: [Int: Int] = [:]
        var wasPinching: Bool = false
        var pinchDropoutCount: Int = 0
        var wasTwoFingers: Bool = false
        var twoFingerDropoutCount: Int = 0

        init() {}

        func reset() {
            skeletonFilter.reset()
            depthEstimator.reset()
            pitchFilter.reset()
            yawFilter.reset()
            lastPitchDeg = 0.0
            lastYawDeg = 0.0
            lastKnownPoints.removeAll(keepingCapacity: true)
            pointDropCounts.removeAll(keepingCapacity: true)
            wasPinching = false
            pinchDropoutCount = 0
            wasTwoFingers = false
            twoFingerDropoutCount = 0
        }
    }

    /// Joint index mappings matching Apple Vision hand pose:
    /// 0: Wrist
    /// 1..4: Thumb CMC, MP, IP, Tip
    /// 5..8: Index MCP, PIP, DIP, Tip
    /// 9..12: Middle MCP, PIP, DIP, Tip
    /// 13..16: Ring MCP, PIP, DIP, Tip
    /// 17..20: Little MCP, PIP, DIP, Tip
    static func landmarks(
        from rawPoints: [CGPoint],
        confidences: [Float]? = nil,
        channel: Channel,
        nowTimestamp: TimeInterval,
        faceBBox: CGRect? = nil,
        faceImpliedDepth: CGFloat? = nil
    ) -> HandLandmarks? {
        guard rawPoints.count >= 21 else { return nil }

        var pointsList: [CGPoint] = []
        for i in 0..<21 {
            let p = rawPoints[i]
            let conf = (confidences != nil && confidences!.count > i) ? confidences![i] : 1.0
            if conf > 0.40 && p != .zero {
                channel.lastKnownPoints[i] = p
                channel.pointDropCounts[i] = 0
                pointsList.append(p)
            } else {
                let drop = (channel.pointDropCounts[i] ?? 0) + 1
                channel.pointDropCounts[i] = drop
                if drop <= 2, let last = channel.lastKnownPoints[i] {
                    pointsList.append(last)
                } else {
                    pointsList.append(.zero)
                }
            }
        }

        let wrist = pointsList[0] != .zero ? pointsList[0] : channel.lastKnownPoints[0]
        let middleMCPRaw = pointsList[9] != .zero ? pointsList[9] : channel.lastKnownPoints[9]
        let indexMCPRaw = pointsList[5] != .zero ? pointsList[5] : channel.lastKnownPoints[5]

        let validWrist: CGPoint
        if let w = wrist, w != .zero {
            validWrist = w
        } else if let mm = middleMCPRaw, mm != .zero {
            validWrist = CGPoint(x: mm.x, y: min(0.99, mm.y + 0.16))
            channel.lastKnownPoints[0] = validWrist
        } else if let im = indexMCPRaw, im != .zero {
            validWrist = CGPoint(x: im.x, y: min(0.99, im.y + 0.16))
            channel.lastKnownPoints[0] = validWrist
        } else {
            channel.reset()
            return nil
        }

        let indexTip = pointsList[8] != .zero ? pointsList[8] :
                       (pointsList[7] != .zero ? pointsList[7] :
                       (pointsList[6] != .zero ? pointsList[6] : channel.lastKnownPoints[8]))
        guard let validIndexTip = indexTip, validIndexTip != .zero else {
            channel.reset()
            return nil
        }

        func dist(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            return hypot(p1.x - p2.x, p1.y - p2.y)
        }

        func isFingerExtended(tipIdx: Int, pipIdx: Int, mcpIdx: Int) -> Bool {
            let t = pointsList[tipIdx] != .zero ? pointsList[tipIdx] : channel.lastKnownPoints[tipIdx]
            let p = pointsList[pipIdx] != .zero ? pointsList[pipIdx] : channel.lastKnownPoints[pipIdx]
            let m = pointsList[mcpIdx] != .zero ? pointsList[mcpIdx] : channel.lastKnownPoints[mcpIdx]
            guard let t = t, let p = p, let m = m, t != .zero, p != .zero, m != .zero else { return false }
            let tipDist = dist(t, validWrist)
            let pipDist = dist(p, validWrist)
            let mcpDist = dist(m, validWrist)
            let knuckleToTip = dist(t, m)
            let knuckleToPip = dist(p, m)
            let isExtendedFromKnuckle = knuckleToTip > knuckleToPip * 1.06
            let isExtendedFromWrist = (tipDist > pipDist * 0.92) && (tipDist > mcpDist * 0.94)
            return isExtendedFromKnuckle || isExtendedFromWrist
        }

        let indexExt = isFingerExtended(tipIdx: 8, pipIdx: 6, mcpIdx: 5)
        let middleExt = isFingerExtended(tipIdx: 12, pipIdx: 10, mcpIdx: 9)
        let ringExt = isFingerExtended(tipIdx: 16, pipIdx: 14, mcpIdx: 13)
        let pinkyExt = isFingerExtended(tipIdx: 20, pipIdx: 18, mcpIdx: 17)

        var extCount = 0
        if indexExt { extCount += 1 }
        if middleExt { extCount += 1 }
        if ringExt { extCount += 1 }
        if pinkyExt { extCount += 1 }

        let middleMCP = pointsList[9] != .zero ? pointsList[9] : (channel.lastKnownPoints[9] ?? .zero)
        let indexMCP = pointsList[5] != .zero ? pointsList[5] : (channel.lastKnownPoints[5] ?? .zero)
        let pinkyMCP = pointsList[17] != .zero ? pointsList[17] : (channel.lastKnownPoints[17] ?? .zero)
        let ringMCP = pointsList[13] != .zero ? pointsList[13] : (channel.lastKnownPoints[13] ?? .zero)
        let ringTip = pointsList[16] != .zero ? pointsList[16] : (pointsList[14] != .zero ? pointsList[14] : (channel.lastKnownPoints[16] ?? validWrist))
        let middleTipRaw = pointsList[12] != .zero ? pointsList[12] : (pointsList[10] != .zero ? pointsList[10] : (channel.lastKnownPoints[12] ?? validIndexTip))

        let indexLen = dist(validIndexTip, indexMCP != .zero ? indexMCP : validWrist)
        let middleLen = dist(middleTipRaw, middleMCP != .zero ? middleMCP : validWrist)
        let ringLen = dist(ringTip, ringMCP != .zero ? ringMCP : validWrist)

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

        let middleTip = pointsList[12] != .zero ? pointsList[12] : (pointsList[10] != .zero ? pointsList[10] : (channel.lastKnownPoints[12] ?? validIndexTip))
        let twoFingersDist = dist(validIndexTip, middleTip)
        let isCrossed = isTwo && (twoFingersDist < 0.052)
        let rawTwoCenter = CGPoint(x: (validIndexTip.x + middleTip.x) / 2.0, y: (validIndexTip.y + middleTip.y) / 2.0)
        let twoCenterScreen = CGPoint(x: 1.0 - rawTwoCenter.x, y: rawTwoCenter.y)

        let thumbTip = pointsList[4] != .zero ? pointsList[4] : (pointsList[3] != .zero ? pointsList[3] : (channel.lastKnownPoints[4] ?? validIndexTip))
        let thumbIP = pointsList[3] != .zero ? pointsList[3] : (channel.lastKnownPoints[3] ?? thumbTip)
        let indexDIP = pointsList[7] != .zero ? pointsList[7] : (channel.lastKnownPoints[7] ?? validIndexTip)

        let tipToTip = dist(thumbTip, validIndexTip)
        let tipToDip = dist(thumbTip, indexDIP)
        let ipToTip = dist(thumbIP, validIndexTip)
        let minPinchDist = min(tipToTip, tipToDip, ipToTip)

        let contactPair: (CGPoint, CGPoint) = {
            if tipToTip <= tipToDip && tipToTip <= ipToTip {
                return (thumbTip, validIndexTip)
            } else if tipToDip <= ipToTip {
                return (thumbTip, indexDIP)
            } else {
                return (thumbIP, validIndexTip)
            }
        }()

        let palmLength: CGFloat = {
            let mcp = middleMCP != .zero ? middleMCP : (indexMCP != .zero ? indexMCP : validIndexTip)
            let len = dist(validWrist, mcp)
            return max(0.045, len)
        }()
        let pinchRatio = minPinchDist / palmLength

        let middleThumbDist = dist(middleTip, thumbTip)
        let isSeparatedMiddle = middleThumbDist > (minPinchDist * 1.15) || middleThumbDist > 0.055
        let isNotFist = (extCount >= 1) && isSeparatedMiddle

        let isPinchCandidate: Bool = {
            guard isRaised && isNotFist else { return false }
            if channel.wasPinching {
                return (pinchRatio <= 0.44 && minPinchDist <= 0.075)
            } else {
                return (pinchRatio <= 0.32 && minPinchDist <= 0.055)
            }
        }()

        let isPinch: Bool
        if isPinchCandidate {
            channel.wasPinching = true
            channel.pinchDropoutCount = 0
            isPinch = true
        } else if channel.wasPinching {
            channel.pinchDropoutCount += 1
            if channel.pinchDropoutCount <= 2 {
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

        let palmTriangleArea = 0.5 * abs(
            Double((smIndexMCP.x - smWrist.x) * (smPinkyMCP.y - smWrist.y) - (smIndexMCP.y - smWrist.y) * (smPinkyMCP.x - smWrist.x))
        )
        let palmLengthDouble = max(0.01, Double(palmLength))
        let planarFullness = min(1.0, max(0.0, (palmTriangleArea * 4.2) / (palmLengthDouble * palmLengthDouble)))
        let facingCamera = max(dotProduct * 0.70 + planarFullness * 0.30, dotProduct)

        let smRingMCP = smoothedPoints.count >= 21 ? smoothedPoints[13] : (pointsList[13] != .zero ? pointsList[13] : (channel.lastKnownPoints[13] ?? .zero))
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

        let thumbSpread = (dist(thumbTip, validIndexTip) / palmLength > 0.34) || (dist(thumbTip, validIndexTip) > 0.050)
        let isHandPointingUpward = (validIndexTip.y < validWrist.y + 0.14)
        let isFacingDirectly = (facingCamera >= 0.28)
        let isStrictOpenPalm = (extCount >= 3) && indexExt && middleExt && thumbSpread && isHandPointingUpward && isFacingDirectly && (minPinchDist > 0.060)

        let isFramingCorner = indexExt && thumbSpread && !isPinch && (!middleExt || !pinkyExt || !ringExt) && !isStrictOpenPalm && (extCount <= 3)

        let depthMeters = depthResult.estimatedDepth
        let isInInteractionRange = (depthMeters >= 0.18 && depthMeters <= 0.85)
        let tiltAngleDegrees = acos(min(1.0, max(0.0, facingCamera))) * 180.0 / .pi

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
}
