import Foundation
import CoreGraphics

struct LandmarkPointRecord: Codable, Equatable {
    let x: Double
    let y: Double
}

struct FaceBBoxRecord: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct HandFrameRecord: Codable {
    let timestamp: Double
    let frameIndex: Int
    let groundTruth: String
    let predictedIntent: String
    /// Non-empty only on the frame where an action was actually committed (event, not state).
    let firedIntent: String
    /// Concrete action name including direction (e.g. "swipe_left", "scroll_down").
    let firedAction: String
    let handDetected: Bool
    let fingerCount: Int
    let isPinching: Bool
    let isTwoFingers: Bool
    let isRaisedHand: Bool
    let estimatedDepth: Double
    let facingCamera: Double
    let primaryPoints: [LandmarkPointRecord]
    let secondaryPoints: [LandmarkPointRecord]?
    let confidence: [Float]?
    let faceBBox: FaceBBoxRecord?
    let isInInteractionRange: Bool?
    let handCentroid: LandmarkPointRecord?
    let tiltAngleDegrees: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp, frameIndex, groundTruth, predictedIntent, firedIntent, firedAction
        case handDetected, fingerCount, isPinching, isTwoFingers, isRaisedHand
        case estimatedDepth, facingCamera, primaryPoints, secondaryPoints
        case confidence, confidences, faceBBox, isInInteractionRange, handCentroid, tiltAngleDegrees
    }

    init(
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
        tiltAngleDegrees: Double? = nil
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
    }

    init(from decoder: Decoder) throws {
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
    }

    func encode(to encoder: Encoder) throws {
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
    confidence: [Float]? = nil
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
        tiltAngleDegrees: primary?.tiltAngleDegrees
    )
}

final class DatasetRecorder {
    static let shared = DatasetRecorder()

    private var fileHandle: FileHandle?
    private(set) var isRecording: Bool = false
    private let queue = DispatchQueue(label: "com.gestureflow.recorder", qos: .utility)
    private(set) var currentLabel: String = "idle"
    private(set) var recordedFrameCount: Int = 0
    private var outputPath: String = ""

    private init() {}

    func startRecording(toPath path: String) -> Bool {
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
            fileHandle = try FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
            isRecording = true
            outputPath = expandedPath
            recordedFrameCount = 0
            currentLabel = "idle"
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

    func setGroundTruthLabel(_ label: String) {
        currentLabel = label
        print("[DatasetRecorder] Ground-Truth Label => [\(label)]")
    }

    /// When true (guided session running) manual hotkeys are ignored so they can't corrupt schedule labels.
    var labelsLocked: Bool = false

    func setLabelFromKey(_ keyChar: Character) -> Bool {
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

    func stopRecording() {
        queue.sync {
            guard isRecording else { return }
            isRecording = false
            try? fileHandle?.synchronize()
            try? fileHandle?.close()
            fileHandle = nil
            print("[DatasetRecorder] Recording STOPPED. Recorded \(recordedFrameCount) frames to \(outputPath)")
        }
    }

    func recordFrame(
        frameIndex: Int,
        timestamp: TimeInterval,
        primary: HandLandmarks?,
        secondary: HandLandmarks?,
        predictedIntent: String,
        firedIntent: String = "",
        firedAction: String = ""
    ) {
        guard isRecording, let handle = fileHandle else { return }

        let record = makeFrameRecord(
            frameIndex: frameIndex,
            timestamp: timestamp,
            primary: primary,
            secondary: secondary,
            predictedIntent: predictedIntent,
            firedIntent: firedIntent,
            firedAction: firedAction,
            groundTruth: currentLabel
        )

        queue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(record)
                handle.write(data)
                if let newline = "\n".data(using: .utf8) {
                    handle.write(newline)
                }
                self.recordedFrameCount += 1
            } catch {
                print("[DatasetRecorder] Error encoding frame: \(error)")
            }
        }
    }
}
