import Foundation
import CoreGraphics

// MARK: - Monocular Metric Depth & Spatial Kinematics Estimator
// Anthropometric projective geometry engine providing metric depth Z and intent features from monocular video.
final class MonocularDepthEstimator {
    // Anthropometric Invariants (NASA / Anthropometry Survey of US Army Personnel)
    // Adult human hand metrics: Palm length ≈ 88mm, Palm breadth ≈ 82mm, Diagonal span ≈ 120mm
    static let handDiagonalSpanMeters: CGFloat = 0.120
    // Normalized focal length for standard Mac FaceTime camera (65° horizontal FOV)
    // f_norm = 1.0 / (2.0 * tan(65° / 2)) ≈ 0.785
    static let normalizedFocalLength: CGFloat = 0.785

    // Depth Temporal Filtering (One-Euro Filter for Depth Z)
    private var depthFilter = OneEuroFilter(minCutoff: 0.35, beta: 0.025)
    private var previousDepth: CGFloat = 0.50
    private var previousTimestamp: TimeInterval = 0
    private var currentDepthVelocity: CGFloat = 0.0 // dZ/dt in meters/sec

    // Optical Flow Divergence tracking for zero-lag depth velocity
    private var previousPalmPoints: [CGPoint] = []
    private var previousCentroid: CGPoint = .zero

    // Forward Predictive Kinematic Extrapolator
    // Compensates for webcam exposure/shutter latency
    private let latencyLeadSeconds: Double = 0.035

    struct DepthResult {
        let estimatedDepth: CGFloat      // Metric depth in meters (e.g. 0.25m ... 0.95m)
        let depthVelocity: CGFloat       // dZ/dt in m/s (negative when advancing, positive when retracting)
        let opticalDivergence: CGFloat   // div(v): expansion rate of hand surface
        let isAirPush: Bool              // Intentional zero-lag forward spatial pulse
        let confidence: CGFloat
    }

    func estimateDepth(
        wrist: CGPoint,
        middleMCP: CGPoint,
        indexMCP: CGPoint,
        pinkyMCP: CGPoint,
        facingCamera: Double = 1.0,
        timestamp: TimeInterval
    ) -> DepthResult {
        guard wrist != .zero, middleMCP != .zero else {
            return DepthResult(estimatedDepth: previousDepth, depthVelocity: 0, opticalDivergence: 0, isAirPush: false, confidence: 0)
        }

        // 1. ANTHROPOMETRIC PnP (Perspective-n-Point) METRIC DEPTH SOLVER
        let palmLength = hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y)
        let knuckleWidth = (indexMCP != .zero && pinkyMCP != .zero) ? hypot(pinkyMCP.x - indexMCP.x, pinkyMCP.y - indexMCP.y) : (palmLength * 0.85)

        // Aspect-ratio invariant 2D diagonal span (orthogonal axes compensate for roll)
        let observedSpan = sqrt(palmLength * palmLength + knuckleWidth * knuckleWidth)
        guard observedSpan > 0.025 else {
            return DepthResult(estimatedDepth: previousDepth, depthVelocity: 0, opticalDivergence: 0, isAirPush: false, confidence: 0)
        }

        // Out-of-plane pitch/yaw foreshortening compensation using palm orientation normal
        let foreshortenFactor = sqrt(max(0.25, CGFloat(facingCamera)))
        let correctedSpan = observedSpan / foreshortenFactor

        // Pinhole projection equation: Z = (f * D) / s
        // Produces actual physical metric distance in meters (e.g. 0.25m to 1.0m)
        let metricZRaw = (MonocularDepthEstimator.normalizedFocalLength * MonocularDepthEstimator.handDiagonalSpanMeters) / max(0.03, correctedSpan)
        let clampedZ = min(1.10, max(0.20, metricZRaw))

        // One-Euro Filter smoothing of metric depth (0.35Hz cutoff eliminates sensor grain)
        let filteredZ = CGFloat(depthFilter.filter(Double(clampedZ), timestamp: timestamp))

        // 2. OPTICAL FLOW DIVERGENCE (Zero-Lag Radial Expansion/Contraction)
        let currentPoints = [wrist, middleMCP, indexMCP, pinkyMCP].filter { $0 != .zero }
        let currentCentroid = CGPoint(
            x: currentPoints.reduce(0) { $0 + $1.x } / CGFloat(max(1, currentPoints.count)),
            y: currentPoints.reduce(0) { $0 + $1.y } / CGFloat(max(1, currentPoints.count))
        )

        var opticalDivergence: CGFloat = 0.0
        var opticalVelocityZ: CGFloat = 0.0

        if previousPalmPoints.count == currentPoints.count && previousTimestamp > 0 {
            let dt = max(0.001, timestamp - previousTimestamp)
            var sumExpansionRate: CGFloat = 0.0

            for i in 0..<currentPoints.count {
                let rCurrent = hypot(currentPoints[i].x - currentCentroid.x, currentPoints[i].y - currentCentroid.y)
                let rPrev = hypot(previousPalmPoints[i].x - previousCentroid.x, previousPalmPoints[i].y - previousCentroid.y)
                let expansionRate = (rCurrent - rPrev) / CGFloat(dt * max(0.01, Double(rPrev)))
                sumExpansionRate += expansionRate
            }

            opticalDivergence = sumExpansionRate / CGFloat(currentPoints.count)
            // Optical physics: div(v) = - (dZ/dt) / Z  =>  dZ/dt = - Z * div(v)
            opticalVelocityZ = -filteredZ * opticalDivergence
        }

        previousPalmPoints = currentPoints
        previousCentroid = currentCentroid

        // 3. COMPLEMENTARY DEPTH VELOCITY FUSION
        if previousTimestamp > 0 {
            let dt = max(0.001, timestamp - previousTimestamp)
            let finiteDiffVel = (filteredZ - previousDepth) / CGFloat(dt)

            // Fuse high-frequency zero-lag optical flow with stable low-frequency position derivative
            let fusedVelocity = (0.65 * opticalVelocityZ) + (0.35 * finiteDiffVel)
            currentDepthVelocity = (currentDepthVelocity * 0.60) + (fusedVelocity * 0.40)
        }

        previousDepth = filteredZ
        previousTimestamp = timestamp

        // 4. Zero-Lag Air Push detection: rapid forward surge (negative dZ/dt) within active range
        let isAirPush = currentDepthVelocity < -0.42 && filteredZ < 0.70

        return DepthResult(
            estimatedDepth: filteredZ,
            depthVelocity: currentDepthVelocity,
            opticalDivergence: opticalDivergence,
            isAirPush: isAirPush,
            confidence: min(1.0, observedSpan / 0.15)
        )
    }

    // MARK: - Predictive Shutter-Lag Compensator
    // Extrapolates current 2D/3D coordinates ahead by `latencyLeadSeconds` using instantaneous velocity
    func predictForward(point: CGPoint, velocity: CGSize) -> CGPoint {
        let px = point.x + velocity.width * CGFloat(latencyLeadSeconds)
        let py = point.y + velocity.height * CGFloat(latencyLeadSeconds)
        return CGPoint(
            x: min(1.0, max(0.0, px)),
            y: min(1.0, max(0.0, py))
        )
    }

    // MARK: - AI 64-Dimensional Feature Vector Generator
    // Structures the hand pose into a canonical, scale-invariant, wrist-centered 64D tensor
    // Ready for CoreML / Transformer / DDQN real-time micro-gesture intent inference
    func generateAIFeatureVector(
        landmarks: [CGPoint],
        depth: CGFloat,
        pinchDist: CGFloat
    ) -> [Float] {
        var features = [Float](repeating: 0.0, count: 64)
        guard landmarks.count >= 21 else { return features }

        let wrist = landmarks[0]
        let middleMCP = landmarks[9]
        let palmScale = max(0.05, Float(hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y)))

        // 1. 21 Joints normalized relative to wrist origin & divided by palm scale (63 dimensions: X, Y, Z for 21 joints)
        for i in 0..<21 {
            let pt = landmarks[i]
            let relX = (Float(pt.x - wrist.x)) / palmScale
            let relY = (Float(pt.y - wrist.y)) / palmScale
            let relZ = (i >= 4 && i % 4 == 0) ? Float(depth * 0.2) : 0.0 // Fingertip depth offset

            features[i * 3 + 0] = relX
            features[i * 3 + 1] = relY
            features[i * 3 + 2] = relZ
        }

        // 2. Feature 63: Scale-invariant pinch proximity [0.0 = contact, 1.0 = wide open]
        features[63] = min(1.0, Float(pinchDist) / (palmScale * 0.6))

        return features
    }

    func reset() {
        depthFilter.reset()
        previousDepth = 0.5
        previousTimestamp = 0
        currentDepthVelocity = 0.0
    }
}