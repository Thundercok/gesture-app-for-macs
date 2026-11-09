import Foundation
import CoreGraphics

public struct LandmarkPointRecord: Codable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct FaceBBoxRecord: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct HandFrameRecord: Codable {
    public let timestamp: Double
    public let frameIndex: Int
    public let groundTruth: String
    public let predictedIntent: String
    /// Non-empty only on the frame where an action was actually committed (event, not state).
    public let firedIntent: String
    /// Concrete action name including direction (e.g. "swipe_left", "scroll_down").
    public let firedAction: String
    public let handDetected: Bool
    public let fingerCount: Int
    public let isPinching: Bool
    public let isTwoFingers: Bool
    public let isRaisedHand: Bool
    public let estimatedDepth: Double
    public let facingCamera: Double
    public let primaryPoints: [LandmarkPointRecord]
    public let secondaryPoints: [LandmarkPointRecord]?
    public let confidence: [Float]?
    public let faceBBox: FaceBBoxRecord?
    public let isInInteractionRange: Bool?
    public let handCentroid: LandmarkPointRecord?
    public let tiltAngleDegrees: Double?
    public let shadowPosture: String?
    public let shadowAgrees: Bool?
    /// Optional context metadata for Experiment 001 (Context-Aware Intent Inference)
    public let desktopContext: DesktopContextRecord?
    /// High-level research intent class (IDLE, SCROLL, WINDOW_MANIPULATE, WORKSPACE_NAVIGATE, SELECT, OTHER)
    public let researchIntent: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, frameIndex, groundTruth, predictedIntent, firedIntent, firedAction
        case handDetected, fingerCount, isPinching, isTwoFingers, isRaisedHand
        case estimatedDepth, facingCamera, primaryPoints, secondaryPoints
        case confidence, confidences, faceBBox, isInInteractionRange, handCentroid, tiltAngleDegrees
        case shadowPosture, shadowAgrees
        case desktopContext = "desktop_context"
        case desktopContextAlt = "desktopContext"
        case researchIntent = "research_intent"
        case researchIntentAlt = "researchIntent"
    }

    public init(
        timestamp: Double,
        frameIndex: Int,
        groundTruth: String,
        predictedIntent: String,
        firedIntent: String,
        firedAction: String = "",
        handDetected: Bool,
        fingerCount: Int,
        isPinching: Bool,
        isTwoFingers: Bool,
        isRaisedHand: Bool,
        estimatedDepth: Double,
        facingCamera: Double,
        primaryPoints: [LandmarkPointRecord],
        secondaryPoints: [LandmarkPointRecord]?,
        confidence: [Float]? = nil,
        faceBBox: FaceBBoxRecord? = nil,
        isInInteractionRange: Bool? = nil,
        handCentroid: LandmarkPointRecord? = nil,
        tiltAngleDegrees: Double? = nil,
        shadowPosture: String? = nil,
        shadowAgrees: Bool? = nil,
        desktopContext: DesktopContextRecord? = nil,
        researchIntent: String? = nil
    ) {
        self.timestamp = timestamp
        self.frameIndex = frameIndex
        self.groundTruth = groundTruth
        self.predictedIntent = predictedIntent
        self.firedIntent = firedIntent
        self.firedAction = firedAction
        self.handDetected = handDetected
        self.fingerCount = fingerCount
        self.isPinching = isPinching
        self.isTwoFingers = isTwoFingers
        self.isRaisedHand = isRaisedHand
        self.estimatedDepth = estimatedDepth
        self.facingCamera = facingCamera
        self.primaryPoints = primaryPoints
        self.secondaryPoints = secondaryPoints
        self.confidence = confidence
        self.faceBBox = faceBBox
        self.isInInteractionRange = isInInteractionRange
        self.handCentroid = handCentroid
        self.tiltAngleDegrees = tiltAngleDegrees
        self.shadowPosture = shadowPosture
        self.shadowAgrees = shadowAgrees
        self.desktopContext = desktopContext
        self.researchIntent = researchIntent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
        frameIndex = try container.decode(Int.self, forKey: .frameIndex)
        groundTruth = try container.decode(String.self, forKey: .groundTruth)
        predictedIntent = try container.decode(String.self, forKey: .predictedIntent)
        firedIntent = try container.decode(String.self, forKey: .firedIntent)
        firedAction = try container.decodeIfPresent(String.self, forKey: .firedAction) ?? ""
        handDetected = try container.decode(Bool.self, forKey: .handDetected)
        fingerCount = try container.decode(Int.self, forKey: .fingerCount)
        isPinching = try container.decode(Bool.self, forKey: .isPinching)
        isTwoFingers = try container.decode(Bool.self, forKey: .isTwoFingers)
        isRaisedHand = try container.decode(Bool.self, forKey: .isRaisedHand)
        estimatedDepth = try container.decode(Double.self, forKey: .estimatedDepth)
        facingCamera = try container.decode(Double.self, forKey: .facingCamera)
        primaryPoints = try container.decode([LandmarkPointRecord].self, forKey: .primaryPoints)
        secondaryPoints = try container.decodeIfPresent([LandmarkPointRecord].self, forKey: .secondaryPoints)

        if let conf = try? container.decodeIfPresent([Float].self, forKey: .confidence) {
            confidence = conf
        } else if let confs = try? container.decodeIfPresent([Float].self, forKey: .confidences) {
            confidence = confs
        } else {
            confidence = nil
        }

        if let bbox = try? container.decodeIfPresent(FaceBBoxRecord.self, forKey: .faceBBox) {
            faceBBox = bbox
        } else if let arr = try? container.decodeIfPresent([Double].self, forKey: .faceBBox), arr.count >= 4 {
            faceBBox = FaceBBoxRecord(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
        } else {
            faceBBox = nil
        }

        isInInteractionRange = try? container.decodeIfPresent(Bool.self, forKey: .isInInteractionRange)

        if let centroid = try? container.decodeIfPresent(LandmarkPointRecord.self, forKey: .handCentroid) {
            handCentroid = centroid
        } else if let arr = try? container.decodeIfPresent([Double].self, forKey: .handCentroid), arr.count >= 2 {
            handCentroid = LandmarkPointRecord(x: arr[0], y: arr[1])
        } else {
            handCentroid = nil
        }

        tiltAngleDegrees = try? container.decodeIfPresent(Double.self, forKey: .tiltAngleDegrees)
        shadowPosture = try? container.decodeIfPresent(String.self, forKey: .shadowPosture)
        shadowAgrees = try? container.decodeIfPresent(Bool.self, forKey: .shadowAgrees)

        // Desktop Context: supports snake_case (desktop_context) or camelCase (desktopContext)
        if let ctx = try? container.decodeIfPresent(DesktopContextRecord.self, forKey: .desktopContext) {
            desktopContext = ctx
        } else if let ctxAlt = try? container.decodeIfPresent(DesktopContextRecord.self, forKey: .desktopContextAlt) {
            desktopContext = ctxAlt
        } else {
            desktopContext = nil
        }

        // Research Intent: supports snake_case (research_intent) or camelCase (researchIntent)
        if let ri = try? container.decodeIfPresent(String.self, forKey: .researchIntent) {
            researchIntent = ri
        } else if let riAlt = try? container.decodeIfPresent(String.self, forKey: .researchIntentAlt) {
            researchIntent = riAlt
        } else {
            researchIntent = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(frameIndex, forKey: .frameIndex)
        try container.encode(groundTruth, forKey: .groundTruth)
        try container.encode(predictedIntent, forKey: .predictedIntent)
        try container.encode(firedIntent, forKey: .firedIntent)
        try container.encode(firedAction, forKey: .firedAction)
        try container.encode(handDetected, forKey: .handDetected)
        try container.encode(fingerCount, forKey: .fingerCount)
        try container.encode(isPinching, forKey: .isPinching)
        try container.encode(isTwoFingers, forKey: .isTwoFingers)
        try container.encode(isRaisedHand, forKey: .isRaisedHand)
        try container.encode(estimatedDepth, forKey: .estimatedDepth)
        try container.encode(facingCamera, forKey: .facingCamera)
        try container.encode(primaryPoints, forKey: .primaryPoints)
        try container.encodeIfPresent(secondaryPoints, forKey: .secondaryPoints)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(faceBBox, forKey: .faceBBox)
        try container.encodeIfPresent(isInInteractionRange, forKey: .isInInteractionRange)
        try container.encodeIfPresent(handCentroid, forKey: .handCentroid)
        try container.encodeIfPresent(tiltAngleDegrees, forKey: .tiltAngleDegrees)
        try container.encodeIfPresent(shadowPosture, forKey: .shadowPosture)
        try container.encodeIfPresent(shadowAgrees, forKey: .shadowAgrees)
        try container.encodeIfPresent(desktopContext, forKey: .desktopContext)
        try container.encodeIfPresent(researchIntent, forKey: .researchIntent)
    }
}

func makeFrameRecord(
    frameIndex: Int,
    timestamp: TimeInterval,
    primary: HandLandmarks?,
    secondary: HandLandmarks?,
    predictedIntent: String,
    firedIntent: String = "",
    firedAction: String = "",
    groundTruth: String,
    confidence: [Float]? = nil,
    shadowPosture: String? = nil,
    shadowAgrees: Bool? = nil,
    desktopContext: DesktopContextRecord? = nil,
    researchIntent: String? = nil
) -> HandFrameRecord {
    let pPoints = primary?.points.map { LandmarkPointRecord(x: Double($0.x), y: Double($0.y)) } ?? []
    let sPoints = secondary?.points.map { LandmarkPointRecord(x: Double($0.x), y: Double($0.y)) }
    let faceRec: FaceBBoxRecord? = primary?.faceBBox.map {
        FaceBBoxRecord(x: Double($0.origin.x), y: Double($0.origin.y), width: Double($0.size.width), height: Double($0.size.height))
    }
    let centroidRec: LandmarkPointRecord? = primary.map {
        LandmarkPointRecord(x: Double($0.handCentroid.x), y: Double($0.handCentroid.y))
    }

    return HandFrameRecord(
        timestamp: timestamp,
        frameIndex: frameIndex,
        groundTruth: groundTruth,
        predictedIntent: predictedIntent,
        firedIntent: firedIntent,
        firedAction: firedAction,
        handDetected: primary != nil,
        fingerCount: primary?.fingerCount ?? 0,
        isPinching: primary?.isPinching ?? false,
        isTwoFingers: primary?.isTwoFingers ?? false,
        isRaisedHand: primary?.isRaisedHand ?? false,
        estimatedDepth: Double(primary?.estimatedDepth ?? 0.0),
        facingCamera: primary?.facingCamera ?? 1.0,
        primaryPoints: pPoints,
        secondaryPoints: sPoints,
        confidence: confidence ?? (primary != nil ? Array(repeating: 1.0, count: 21) : nil),
        faceBBox: faceRec,
        isInInteractionRange: primary?.isInInteractionRange,
        handCentroid: centroidRec,
        tiltAngleDegrees: primary?.tiltAngleDegrees,
        shadowPosture: shadowPosture,
        shadowAgrees: shadowAgrees,
        desktopContext: desktopContext,
        researchIntent: researchIntent
    )
}

public final class DatasetRecorder {
    public static let shared = DatasetRecorder()

    private let stateLock = NSLock()
    private var fileHandle: FileHandle?
    private var _isRecording: Bool = false
    private var _currentLabel: String = "idle"
    private var _currentResearchIntent: String? = ResearchIntent.idle.rawValue
    private var _labelsLocked: Bool = false
    private var _recordedFrameCount: Int = 0
    private var _outputPath: String = ""

    private let queue = DispatchQueue(label: "com.gestureflow.recorder", qos: .utility)
    private var contextProvider: DesktopContextProviderProtocol = DesktopContextProvider.shared

    public var isRecording: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isRecording
    }

    public var currentLabel: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentLabel
    }

    public var currentResearchIntent: String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _currentResearchIntent
    }

    public var recordedFrameCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _recordedFrameCount
    }

    /// When true (guided session running) manual hotkeys are ignored so they can't corrupt schedule labels.
    public var labelsLocked: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _labelsLocked
        }
        set {
            stateLock.lock()
            _labelsLocked = newValue
            stateLock.unlock()
        }
    }

    public init() {}

    public func setContextProvider(_ provider: DesktopContextProviderProtocol) {
        stateLock.lock()
        self.contextProvider = provider
        stateLock.unlock()
    }

    public func startRecording(toPath path: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        // If already recording, stop previous stream safely
        if _isRecording {
            _isRecording = false
            queue.sync {
                try? fileHandle?.synchronize()
                try? fileHandle?.close()
                fileHandle = nil
            }
        }

        let fileManager = FileManager.default
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        // Ensure parent directory exists
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if !fileManager.fileExists(atPath: expandedPath) {
            fileManager.createFile(atPath: expandedPath, contents: nil, attributes: nil)
        }

        do {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            self.fileHandle = handle
            self._isRecording = true
            self._outputPath = expandedPath
            self._recordedFrameCount = 0
            self._currentLabel = "idle"
            self._currentResearchIntent = ResearchIntent.idle.rawValue
            print("""
            ====================================================================
            [DatasetRecorder] Recording ENABLED: \(expandedPath)
            Active Ground-Truth Label Keys:
              [0] -> idle (scratching face, typing, resting hand, talking)
              [1] -> pinch_dock (index-thumb pinch to open/scrub dock)
              [2] -> swipe_left (open palm 3-finger swipe physical left)
              [3] -> swipe_right (open palm 3-finger swipe physical right)
              [4] -> swipe_up (open palm swipe physical up -> Mission Control)
              [5] -> swipe_down (open palm swipe physical down -> Show Desktop)
              [6] -> scroll_down (flick physical up -> read downwards)
              [7] -> scroll_up (flick physical down -> read upwards)
              [8] -> zoom (two hands framing/spreading)
            ====================================================================
            """)
            return true
        } catch {
            print("[DatasetRecorder] Failed to open file for recording at \(expandedPath): \(error)")
            return false
        }
    }

    public func setGroundTruthLabel(_ label: String, researchIntent: ResearchIntent? = nil) {
        stateLock.lock()
        _currentLabel = label
        _currentResearchIntent = researchIntent?.rawValue ?? ResearchIntent.baselineMapping(forGestureLabel: label)?.rawValue
        stateLock.unlock()
        print("[DatasetRecorder] Ground-Truth Label => [\(label)] (ResearchIntent: \(_currentResearchIntent ?? "nil"))")
    }

    public func setResearchIntent(_ intent: ResearchIntent) {
        stateLock.lock()
        _currentResearchIntent = intent.rawValue
        stateLock.unlock()
    }

    public func setLabelFromKey(_ keyChar: Character) -> Bool {
        guard !labelsLocked else { return false }
        let labelMap: [Character: String] = [
            "0": "idle",
            "1": "pinch_dock",
            "2": "swipe_left",
            "3": "swipe_right",
            "4": "swipe_up",
            "5": "swipe_down",
            "6": "scroll_down",
            "7": "scroll_up",
            "8": "zoom"
        ]
        if let label = labelMap[keyChar] {
            setGroundTruthLabel(label)
            return true
        }
        return false
    }

    public func stopRecording() {
        stateLock.lock()
        guard _isRecording else {
            stateLock.unlock()
            return
        }
        _isRecording = false
        stateLock.unlock()

        // Wait for all queued frames to be written to file before closing
        queue.sync {
            self.stateLock.lock()
            let handle = self.fileHandle
            self.fileHandle = nil
            let totalCount = self._recordedFrameCount
            let path = self._outputPath
            self.stateLock.unlock()

            try? handle?.synchronize()
            try? handle?.close()
            print("[DatasetRecorder] Recording STOPPED. Recorded \(totalCount) frames to \(path)")
        }
    }

    func recordFrame(
        frameIndex: Int,
        timestamp: TimeInterval,
        primary: HandLandmarks?,
        secondary: HandLandmarks?,
        predictedIntent: String,
        firedIntent: String = "",
        firedAction: String = "",
        shadowPosture: String? = nil,
        shadowAgrees: Bool? = nil,
        customDesktopContext: DesktopContextRecord? = nil,
        customResearchIntent: String? = nil
    ) {
        stateLock.lock()
        guard _isRecording else {
            stateLock.unlock()
            return
        }
        let currentGt = _currentLabel
        let currentIntent = customResearchIntent ?? _currentResearchIntent
        let provider = self.contextProvider
        stateLock.unlock()

        // Non-blocking context acquisition
        let context = customDesktopContext ?? provider.currentContext()

        let record = makeFrameRecord(
            frameIndex: frameIndex,
            timestamp: timestamp,
            primary: primary,
            secondary: secondary,
            predictedIntent: predictedIntent,
            firedIntent: firedIntent,
            firedAction: firedAction,
            groundTruth: currentGt,
            shadowPosture: shadowPosture,
            shadowAgrees: shadowAgrees,
            desktopContext: context,
            researchIntent: currentIntent
        )

        queue.async { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            guard let handle = self.fileHandle else {
                self.stateLock.unlock()
                return
            }
            self.stateLock.unlock()

            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(record)
                handle.write(data)
                if let newline = "\n".data(using: .utf8) {
                    handle.write(newline)
                }
                self.stateLock.lock()
                self._recordedFrameCount += 1
                self.stateLock.unlock()
            } catch {
                print("[DatasetRecorder] Error encoding frame: \(error)")
            }
        }
    }
}
