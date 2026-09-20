import Foundation
import CoreGraphics

/// Single-pole IIR low-pass filter
struct LowPassFilter {
    private(set) var lastValue: Double?

    init(initialValue: Double? = nil) {
        self.lastValue = initialValue
    }

    mutating func filter(_ val: Double, alpha: Double) -> Double {
        guard let prev = lastValue else {
            lastValue = val
            return val
        }
        let result = alpha * val + (1.0 - alpha) * prev
        lastValue = result
        return result
    }

    mutating func reset() {
        lastValue = nil
    }
}

/// One-Euro ($1€$) Filter for 1D signal
/// Ref: Casiez, Roussel, Vogel (CHI 2012)
/// "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in Human-Computer Interaction"
final class OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private var xFilter = LowPassFilter()
    private var dxFilter = LowPassFilter()
    private var lastTimestamp: TimeInterval?

    var currentValue: Double? {
        xFilter.lastValue
    }

    init(minCutoff: Double = 1.0, beta: Double = 0.025, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    func filter(_ x: Double, timestamp: TimeInterval) -> Double {
        guard let prevTime = lastTimestamp else {
            lastTimestamp = timestamp
            return xFilter.filter(x, alpha: 1.0)
        }

        // Clamp dt to reasonable bounds (e.g. 1ms to 100ms) to prevent division by zero or large clock jumps
        let dt = max(0.001, min(0.1, timestamp - prevTime))
        lastTimestamp = timestamp

        // Estimate derivative (velocity) with anomaly protection clamp
        let prevX = xFilter.lastValue ?? x
        let rawDx = (x - prevX) / dt
        let maxVelocity: Double = 5.0 // normalized coordinate units / sec
        let clampedDx = max(-maxVelocity, min(maxVelocity, rawDx))

        let edx = dxFilter.filter(clampedDx, alpha: alpha(cutoff: dCutoff, dt: dt))

        // Speed-adaptive cutoff clamped to 60Hz nyquist ceiling
        let cutoff = min(60.0, minCutoff + beta * abs(edx))
        return xFilter.filter(x, alpha: alpha(cutoff: cutoff, dt: dt))
    }

    func reset() {
        xFilter.reset()
        dxFilter.reset()
        lastTimestamp = nil
    }
}

/// Speed-adaptive 2D point filter combining two One-Euro filters for X and Y with stationary noise gate
final class PointFilter2D {
    private let fx: OneEuroFilter
    private let fy: OneEuroFilter
    private let noiseGateThreshold: CGFloat
    private var anchor: CGPoint?

    var lastValue: CGPoint? {
        guard let x = fx.currentValue, let y = fy.currentValue else { return nil }
        return CGPoint(x: x, y: y)
    }

    init(minCutoff: Double = 1.0, beta: Double = 0.025, dCutoff: Double = 1.0, noiseGateThreshold: CGFloat = 0.0) {
        self.fx = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.fy = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.noiseGateThreshold = noiseGateThreshold
    }

    func filter(_ point: CGPoint, timestamp: TimeInterval) -> CGPoint {
        let smoothX = fx.filter(Double(point.x), timestamp: timestamp)
        let smoothY = fy.filter(Double(point.y), timestamp: timestamp)
        let candidate = CGPoint(x: smoothX, y: smoothY)

        if noiseGateThreshold > 0.0 {
            if let a = anchor {
                let dist = hypot(candidate.x - a.x, candidate.y - a.y)
                if dist < noiseGateThreshold {
                    return a
                }
            }
            anchor = candidate
        }

        return candidate
    }

    func reset() {
        fx.reset()
        fy.reset()
        anchor = nil
    }
}

/// Rigid Kinematic Bone-Length Clamping (NASA Hand Anthropometry & Projective Geometry)
/// Prevents joints from jittering outwards beyond maximum anatomical 3D projection,
/// completely eliminating "rubber hand" visual flutter.
struct KinematicHandLimiter {
    // Parent-child bone definitions and max length ratios relative to palm span (wrist -> middleMCP)
    // Ratios include 15% headroom over 99th percentile anthropometric dimensions
    static let boneLimits: [(parent: Int, child: Int, maxRatio: CGFloat)] = [
        // Palm / Knuckles
        (0, 1, 0.65),  // Wrist -> Thumb CMC
        (0, 5, 1.15),  // Wrist -> Index MCP
        (0, 9, 1.05),  // Wrist -> Middle MCP
        (0, 13, 1.10), // Wrist -> Ring MCP
        (0, 17, 1.00), // Wrist -> Little MCP

        // Thumb
        (1, 2, 0.55),  // CMC -> MP
        (2, 3, 0.48),  // MP -> IP
        (3, 4, 0.42),  // IP -> Tip

        // Index
        (5, 6, 0.60),  // MCP -> PIP
        (6, 7, 0.45),  // PIP -> DIP
        (7, 8, 0.38),  // DIP -> Tip

        // Middle
        (9, 10, 0.65), // MCP -> PIP
        (10, 11, 0.48),// PIP -> DIP
        (11, 12, 0.38),// DIP -> Tip

        // Ring
        (13, 14, 0.60),// MCP -> PIP
        (14, 15, 0.45),// PIP -> DIP
        (15, 16, 0.38),// DIP -> Tip

        // Pinky
        (17, 18, 0.52),// MCP -> PIP
        (18, 19, 0.40),// PIP -> DIP
        (19, 20, 0.35) // DIP -> Tip
    ]

    static func clampPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count == 21 else { return points }
        let wrist = points[0]
        guard wrist != .zero else { return points }

        let palmSpan: CGFloat
        if points[9] != .zero {
            palmSpan = hypot(points[9].x - wrist.x, points[9].y - wrist.y)
        } else if points[5] != .zero {
            palmSpan = hypot(points[5].x - wrist.x, points[5].y - wrist.y) * 1.05
        } else {
            return points
        }
        guard palmSpan > 0.02 else { return points }

        var clamped = points
        for bone in boneLimits {
            let pParent = clamped[bone.parent]
            let pChild = clamped[bone.child]
            guard pParent != .zero, pChild != .zero else { continue }

            let dx = pChild.x - pParent.x
            let dy = pChild.y - pParent.y
            let currentLen = hypot(dx, dy)
            let maxLen = palmSpan * bone.maxRatio

            if currentLen > maxLen && currentLen > 1e-5 {
                let scale = maxLen / currentLen
                clamped[bone.child] = CGPoint(
                    x: pParent.x + dx * scale,
                    y: pParent.y + dy * scale
                )
            }
        }
        return clamped
    }
}

/// Glitch-proof skeleton filter managing 21 hand joints with temporal persistence (Dead Reckoning)
/// and rigid kinematic skeletal constraints
final class SkeletonFilter {
    private var jointFilters: [PointFilter2D]
    private let pinchCenterFilter: PointFilter2D
    private let twoCenterFilter: PointFilter2D

    private var lastPoints: [CGPoint] = Array(repeating: .zero, count: 21)
    private var dropCounts: [Int] = Array(repeating: 0, count: 21)
    private var pinchDropCount = 0
    private var lastPinch: CGPoint = .zero
    private var twoDropCount = 0
    private var lastTwo: CGPoint = .zero

    private let maxHoldFrames = 10 // Hold position for up to 10 frames (~160ms) during brief occlusions

    init(
        jointMinCutoff: Double = 0.45,
        jointBeta: Double = 0.015,
        reticleMinCutoff: Double = 0.28,
        reticleBeta: Double = 0.018,
        reticleNoiseGate: CGFloat = 0.0022
    ) {
        self.jointFilters = (0..<21).map { _ in
            PointFilter2D(minCutoff: jointMinCutoff, beta: jointBeta, noiseGateThreshold: 0.0012)
        }
        self.pinchCenterFilter = PointFilter2D(minCutoff: reticleMinCutoff, beta: reticleBeta, noiseGateThreshold: reticleNoiseGate)
        self.twoCenterFilter = PointFilter2D(minCutoff: reticleMinCutoff, beta: reticleBeta, noiseGateThreshold: reticleNoiseGate)
    }

    func filter(
        points: [CGPoint],
        pinchCenter: CGPoint,
        twoCenter: CGPoint,
        timestamp: TimeInterval
    ) -> (points: [CGPoint], pinchCenter: CGPoint, twoCenter: CGPoint) {
        let clampedRaw = KinematicHandLimiter.clampPoints(points)
        var smoothedPoints: [CGPoint] = []
        smoothedPoints.reserveCapacity(clampedRaw.count)

        for (i, rawPt) in clampedRaw.enumerated() {
            guard i < jointFilters.count else {
                smoothedPoints.append(rawPt)
                continue
            }

            if rawPt == .zero {
                // Joint dropped in this frame
                dropCounts[i] += 1
                if dropCounts[i] <= maxHoldFrames && lastPoints[i] != .zero {
                    // Carry forward last known position smoothly without resetting filter
                    smoothedPoints.append(lastPoints[i])
                } else {
                    // Confirmed absent
                    smoothedPoints.append(.zero)
                    lastPoints[i] = .zero
                    jointFilters[i].reset()
                }
            } else {
                // Valid joint detected
                dropCounts[i] = 0
                let smoothed = jointFilters[i].filter(rawPt, timestamp: timestamp)
                lastPoints[i] = smoothed
                smoothedPoints.append(smoothed)
            }
        }

        let kinematicallySmoothedPoints = KinematicHandLimiter.clampPoints(smoothedPoints)

        // Filter Pinch Center with dead reckoning
        let smoothedPinch: CGPoint
        if pinchCenter == .zero {
            pinchDropCount += 1
            if pinchDropCount <= maxHoldFrames && lastPinch != .zero {
                smoothedPinch = lastPinch
            } else {
                smoothedPinch = .zero
                lastPinch = .zero
                pinchCenterFilter.reset()
            }
        } else {
            pinchDropCount = 0
            smoothedPinch = pinchCenterFilter.filter(pinchCenter, timestamp: timestamp)
            lastPinch = smoothedPinch
        }

        // Filter Two-finger Center with dead reckoning
        let smoothedTwo: CGPoint
        if twoCenter == .zero {
            twoDropCount += 1
            if twoDropCount <= maxHoldFrames && lastTwo != .zero {
                smoothedTwo = lastTwo
            } else {
                smoothedTwo = .zero
                lastTwo = .zero
                twoCenterFilter.reset()
            }
        } else {
            twoDropCount = 0
            smoothedTwo = twoCenterFilter.filter(twoCenter, timestamp: timestamp)
            lastTwo = smoothedTwo
        }

        return (kinematicallySmoothedPoints, smoothedPinch, smoothedTwo)
    }

    func reset() {
        for i in 0..<jointFilters.count {
            jointFilters[i].reset()
            lastPoints[i] = .zero
            dropCounts[i] = 0
        }
        pinchCenterFilter.reset()
        twoCenterFilter.reset()
        lastPinch = .zero
        lastTwo = .zero
        pinchDropCount = 0
        twoDropCount = 0
    }
}
