import Foundation
import CoreGraphics

struct LandmarkPointRecord: Codable {
    let x: Double
    let y: Double
}

struct HandFrameRecord: Codable {
    let timestamp: Double
    let frameIndex: Int
    let groundTruth: String
    let predictedIntent: String
    let handDetected: Bool
    let fingerCount: Int
    let isPinching: Bool
    let isTwoFingers: Bool
    let isRaisedHand: Bool
    let estimatedDepth: Double
    let facingCamera: Double
    let primaryPoints: [LandmarkPointRecord]
    let secondaryPoints: [LandmarkPointRecord]?
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

    func setLabelFromKey(_ keyChar: Character) -> Bool {
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
        predictedIntent: String
    ) {
        guard isRecording, let handle = fileHandle else { return }

        let pPoints = primary?.points.map { LandmarkPointRecord(x: Double($0.x), y: Double($0.y)) } ?? []
        let sPoints = secondary?.points.map { LandmarkPointRecord(x: Double($0.x), y: Double($0.y)) }

        let record = HandFrameRecord(
            timestamp: timestamp,
            frameIndex: frameIndex,
            groundTruth: currentLabel,
            predictedIntent: predictedIntent,
            handDetected: primary != nil,
            fingerCount: primary?.fingerCount ?? 0,
            isPinching: primary?.isPinching ?? false,
            isTwoFingers: primary?.isTwoFingers ?? false,
            isRaisedHand: primary?.isRaisedHand ?? false,
            estimatedDepth: Double(primary?.estimatedDepth ?? 0.0),
            facingCamera: primary?.facingCamera ?? 1.0,
            primaryPoints: pPoints,
            secondaryPoints: sPoints
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
