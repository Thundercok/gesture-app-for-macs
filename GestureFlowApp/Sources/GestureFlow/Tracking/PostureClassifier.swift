import Foundation
import CoreGraphics
import CoreML

final class PostureClassifier {
    static let shared = PostureClassifier()

    static let classes = ["none", "open_palm", "pinch", "two_fingers", "fist"]

    private var model: MLModel? = nil
    private(set) var isAvailable: Bool = false

    // Temporal smoothing: majority vote over 5 frames
    private var history: [String] = []
    private let historyCapacity = 5

    // Hysteresis: change candidate state only when new class prob >= 0.7 for 3 frames
    private var currentState: String = "none"
    private var candidateState: String = "none"
    private var candidateConsecutiveFrames: Int = 0
    private let requiredHysteresisFrames: Int = 3
    private let hysteresisConfidenceThreshold: Float = 0.70

    init(modelURL: URL? = nil) {
        if let url = modelURL {
            loadModel(at: url)
        } else {
            discoverAndLoadModel()
        }
    }

    private func discoverAndLoadModel() {
        // Look in Bundle resources or relative app directory
        if let resourceURL = Bundle.main.url(forResource: "PostureClassifier", withExtension: "mlmodelc") {
            loadModel(at: resourceURL)
            return
        }
        if let resourceURL = Bundle.main.url(forResource: "PostureClassifier", withExtension: "mlmodel") {
            loadModel(at: resourceURL)
            return
        }

        // Relative check for dev/local builds
        let candidatePaths = [
            "Resources/PostureClassifier.mlmodelc",
            "Resources/PostureClassifier.mlmodel",
            "../Resources/PostureClassifier.mlmodelc",
            "../Resources/PostureClassifier.mlmodel"
        ]
        for p in candidatePaths {
            let u = URL(fileURLWithPath: p)
            if FileManager.default.fileExists(atPath: u.path) {
                loadModel(at: u)
                return
            }
        }
    }

    private func loadModel(at url: URL) {
        do {
            let compiledURL: URL
            if url.pathExtension == "mlmodel" {
                compiledURL = try MLModel.compileModel(at: url)
            } else {
                compiledURL = url
            }
            let config = MLModelConfiguration()
            config.computeUnits = .all
            self.model = try MLModel(contentsOf: compiledURL, configuration: config)
            self.isAvailable = true
        } catch {
            self.isAvailable = false
            self.model = nil
        }
    }

    /// Normalizes 21 raw landmarks into a canonical 56D feature vector matching tools/export_features.py.
    static func extractFeatures(from landmarks: HandLandmarks) -> [Float]? {
        return extractFeatures(fromPoints: landmarks.points)
    }

    /// Normalizes 21 landmark points into a canonical 56D feature vector matching tools/export_features.py.
    static func extractFeatures(fromPoints pts: [CGPoint]) -> [Float]? {
        guard pts.count == 21 else { return nil }

        let w = pts[0]
        // Translate with screen-to-Cartesian Y inversion: x_cart = x - w.x, y_cart = w.y - y
        let translated = pts.map { CGPoint(x: $0.x - w.x, y: w.y - $0.y) }

        let m9 = translated[9]
        let rawScale = hypot(m9.x, m9.y)
        let scale: CGFloat = (rawScale < 1e-6) ? 1.0 : rawScale

        let scaled = translated.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }

        // Rotate so wrist -> middleMCP (point 9) points vertically up (+Y, angle pi/2)
        let currentAngle = atan2(scaled[9].y, scaled[9].x)
        let deltaTheta = CGFloat.pi / 2.0 - currentAngle

        let cosD = cos(deltaTheta)
        let sinD = sin(deltaTheta)

        let rotated = scaled.map { p in
            CGPoint(
                x: p.x * cosD - p.y * sinD,
                y: p.x * sinD + p.y * cosD
            )
        }

        // Mirror check: Pinky MCP (17) vs Index MCP (5)
        let isMirrored = (rotated[17].x - rotated[5].x) < 0.0
        let canonical = rotated.map { p in
            CGPoint(x: isMirrored ? -p.x : p.x, y: p.y)
        }

        var vec: [Float] = []
        vec.reserveCapacity(56)

        // 42 coordinates
        for p in canonical {
            vec.append(Float(p.x))
            vec.append(Float(p.y))
        }

        // Engineered metrics
        func dist(_ i: Int, _ j: Int) -> Float {
            return Float(hypot(canonical[i].x - canonical[j].x, canonical[i].y - canonical[j].y))
        }

        let palmWidth = dist(5, 17)
        let thumbIndexDist = dist(4, 8)
        let thumbMiddleDist = dist(4, 12)
        let indexMiddleDist = dist(8, 12)

        vec.append(palmWidth)
        vec.append(thumbIndexDist)
        vec.append(thumbMiddleDist)
        vec.append(indexMiddleDist)

        // Tip to wrist distances
        for tipIdx in [4, 8, 12, 16, 20] {
            vec.append(Float(hypot(canonical[tipIdx].x, canonical[tipIdx].y)))
        }

        // Joint cosine curls
        func jointCos(_ base: Int, _ mid: Int, _ tip: Int) -> Float {
            let v1x = canonical[mid].x - canonical[base].x
            let v1y = canonical[mid].y - canonical[base].y
            let v2x = canonical[tip].x - canonical[mid].x
            let v2y = canonical[tip].y - canonical[mid].y
            let n1 = hypot(v1x, v1y)
            let n2 = hypot(v2x, v2y)
            if n1 < 1e-6 || n2 < 1e-6 { return 1.0 }
            let dot = (v1x * v2x + v1y * v2y) / (n1 * n2)
            return Float(max(-1.0, min(1.0, dot)))
        }

        vec.append(jointCos(1, 2, 4))
        vec.append(jointCos(5, 6, 8))
        vec.append(jointCos(9, 10, 12))
        vec.append(jointCos(13, 14, 16))
        vec.append(jointCos(17, 18, 20))

        return vec
    }

    /// Evaluates shadow-mode posture classifier against heuristic baseline.
    /// Returns (shadowPosture, shadowAgrees).
    func evaluateShadow(landmarks: HandLandmarks?, heuristicPosture: String) -> (shadowPosture: String, shadowAgrees: Bool) {
        guard let lm = landmarks else {
            history.removeAll(keepingCapacity: true)
            currentState = "none"
            candidateState = "none"
            candidateConsecutiveFrames = 0
            return ("none", true)
        }

        guard isAvailable, let model = self.model, let feats = PostureClassifier.extractFeatures(from: lm) else {
            // Model absent: gracefully no-op in shadow mode, agreeing with heuristics
            return (heuristicPosture, true)
        }

        var rawPosture = heuristicPosture
        var topConfidence: Float = 1.0

        do {
            let mlArray = try MLMultiArray(shape: [1, NSNumber(value: feats.count)], dataType: .float32)
            for (idx, val) in feats.enumerated() {
                mlArray[idx] = NSNumber(value: val)
            }

            let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["features": mlArray])
            let output = try model.prediction(from: inputProvider)

            if let probs = output.featureValue(for: "softmax_0")?.multiArrayValue {
                var maxVal: Float = -1.0
                var maxIdx = 0
                for i in 0..<min(probs.count, PostureClassifier.classes.count) {
                    let v = probs[i].floatValue
                    if v > maxVal {
                        maxVal = v
                        maxIdx = i
                    }
                }
                rawPosture = PostureClassifier.classes[maxIdx]
                topConfidence = maxVal
            }
        } catch {
            return (heuristicPosture, true)
        }

        // Rolling majority vote buffer (5 frames)
        history.append(rawPosture)
        if history.count > historyCapacity {
            history.removeFirst()
        }

        let counts = history.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let majorityPosture = counts.max(by: { $0.value < $1.value })?.key ?? rawPosture

        // Hysteresis filter: change state only when new class prob >= 0.7 for 3 frames
        if majorityPosture == candidateState {
            candidateConsecutiveFrames += 1
        } else {
            candidateState = majorityPosture
            candidateConsecutiveFrames = 1
        }

        if candidateConsecutiveFrames >= requiredHysteresisFrames && topConfidence >= hysteresisConfidenceThreshold {
            currentState = candidateState
        }

        let agrees = (currentState == heuristicPosture)
        return (currentState, agrees)
    }

    /// Derives heuristic baseline posture name for shadow comparison.
    static func deriveHeuristicPosture(from landmarks: HandLandmarks?) -> String {
        guard let lm = landmarks else { return "none" }
        if lm.isPinching { return "pinch" }
        if lm.isStrictOpenPalm || lm.isOpenHand { return "open_palm" }
        if lm.isTwoFingers { return "two_fingers" }
        if lm.isFist { return "fist" }
        return "none"
    }
}
