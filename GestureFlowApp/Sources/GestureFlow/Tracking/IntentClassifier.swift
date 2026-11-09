import Foundation
import CoreGraphics
import CoreML

struct IntentPrediction: Equatable {
    let intent: String
    let confidence: Float
    let isPreClickAnticipated: Bool
    let probabilities: [String: Float]

    static let fallback = IntentPrediction(
        intent: "hover",
        confidence: 1.0,
        isPreClickAnticipated: false,
        probabilities: ["hover": 1.0]
    )
}

/// Phase 2: Causal Temporal Intent Classifier (Module 1 of RESEARCH_ROADMAP.md)
///
/// Operates on a sliding window of K=10 frames (167ms at 60 FPS) x 56D canonical features = 560D.
/// Predicts user intention 35-50ms ahead of physical contact:
///   - idle: ambient rest, non-pointing drift
///   - hover: deliberate pointer flight
///   - pre_click: rapid aperture contraction prior to click contact
///   - drag: sustained translation while pinched
///   - scroll: two-finger vertical/horizontal translation
final class IntentClassifier {
    static let shared = IntentClassifier()

    static let classes = ["idle", "hover", "pre_click", "drag", "scroll"]
    static let windowSize = 10
    static let nFeatures = 560

    private var model: MLModel? = nil
    private(set) var isAvailable: Bool = false

    // Sliding window ring buffer (K=10 frames)
    private var featureWindow: [[Float]] = []

    // Pre-click anticipation threshold
    var preClickThreshold: Float = 0.65

    init(modelURL: URL? = nil) {
        if let url = modelURL {
            loadModel(at: url)
        } else {
            discoverAndLoadModel()
        }
    }

    func reset() {
        featureWindow.removeAll(keepingCapacity: true)
    }

    private func discoverAndLoadModel() {
        if let resourceURL = Bundle.main.url(forResource: "IntentClassifier", withExtension: "mlmodelc") {
            loadModel(at: resourceURL)
            return
        }
        if let resourceURL = Bundle.main.url(forResource: "IntentClassifier", withExtension: "mlmodel") {
            loadModel(at: resourceURL)
            return
        }

        let candidatePaths = [
            "Resources/IntentClassifier.mlmodelc",
            "Resources/IntentClassifier.mlmodel",
            "../Resources/IntentClassifier.mlmodelc",
            "../Resources/IntentClassifier.mlmodel",
            "GestureFlowApp/Resources/IntentClassifier.mlmodelc",
            "GestureFlowApp/Resources/IntentClassifier.mlmodel",
            "Sources/GestureFlow/Resources/IntentClassifier.mlmodelc",
            "Sources/GestureFlow/Resources/IntentClassifier.mlmodel"
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
            self.model = nil
            self.isAvailable = false
        }
    }

    /// Evaluates causal intent over the sliding temporal window.
    func process(landmarks: HandLandmarks?) -> IntentPrediction {
        guard let lm = landmarks else {
            reset()
            return IntentPrediction(intent: "idle", confidence: 1.0, isPreClickAnticipated: false, probabilities: ["idle": 1.0])
        }

        guard let feats = PostureClassifier.extractFeatures(from: lm) else {
            return .fallback
        }

        featureWindow.append(feats)
        if featureWindow.count > IntentClassifier.windowSize {
            featureWindow.removeFirst()
        }

        // Window requires K=10 frames to evaluate sequence dynamics
        guard featureWindow.count == IntentClassifier.windowSize, let model = self.model else {
            return .fallback
        }

        var flattened: [Float] = []
        flattened.reserveCapacity(IntentClassifier.nFeatures)
        for w in featureWindow {
            flattened.append(contentsOf: w)
        }

        do {
            let mlArray = try MLMultiArray(shape: [1, NSNumber(value: IntentClassifier.nFeatures)], dataType: .float32)
            for (idx, val) in flattened.enumerated() {
                mlArray[idx] = NSNumber(value: val)
            }

            let inputProvider = try MLDictionaryFeatureProvider(dictionary: ["features": mlArray])
            let output = try model.prediction(from: inputProvider)

            if let probs = output.featureValue(for: "softmax_0")?.multiArrayValue {
                var probMap: [String: Float] = [:]
                var topClass = "hover"
                var topVal: Float = -1.0

                for i in 0..<min(probs.count, IntentClassifier.classes.count) {
                    let v = probs[i].floatValue
                    let cls = IntentClassifier.classes[i]
                    probMap[cls] = v
                    if v > topVal {
                        topVal = v
                        topClass = cls
                    }
                }

                let pPreClick = probMap["pre_click"] ?? 0.0
                let isPreClick = (pPreClick >= preClickThreshold) || (topClass == "pre_click")

                return IntentPrediction(
                    intent: topClass,
                    confidence: topVal,
                    isPreClickAnticipated: isPreClick,
                    probabilities: probMap
                )
            }
        } catch {
            return .fallback
        }

        return .fallback
    }
}
