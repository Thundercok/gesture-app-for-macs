import Foundation
import CoreGraphics

final class ReplayRunner {
    let replayFilePath: String
    let tuningOption: String?
    let outputFilePath: String?
    let modeOption: String?

    init(
        replayFilePath: String,
        tuningOption: String? = nil,
        outputFilePath: String? = nil,
        modeOption: String? = nil
    ) {
        self.replayFilePath = replayFilePath
        self.tuningOption = tuningOption
        self.outputFilePath = outputFilePath
        self.modeOption = modeOption
    }

    func run() -> Int32 {
        // 1. Configure Tuning
        if let opt = tuningOption {
            switch opt.lowercased() {
            case "safe":
                GestureTuning.current = .safe
                print("[Replay] Tuning preset: safe")
            case "balanced":
                GestureTuning.current = .balanced
                print("[Replay] Tuning preset: balanced")
            case "sensitive":
                GestureTuning.current = .sensitive
                print("[Replay] Tuning preset: sensitive")
            default:
                let expanded = (opt as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: expanded),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: expanded)),
                   let tuning = try? JSONDecoder().decode(GestureTuning.self, from: data) {
                    GestureTuning.current = tuning
                    print("[Replay] Tuning loaded from file: \(expanded)")
                } else if let data = opt.data(using: .utf8),
                          let tuning = try? JSONDecoder().decode(GestureTuning.self, from: data) {
                    GestureTuning.current = tuning
                    print("[Replay] Tuning loaded from JSON string")
                } else {
                    FileHandle.standardError.write("Error: Invalid --tuning option: \(opt)\n".data(using: .utf8)!)
                    return 1
                }
            }
        }

        let tune = GestureTuning.current
        print(String(format: "[Replay] Active Tuning Parameters: swipeMinVel=%.2f, swipeMinDisp=%.3f, openPalmDwell=%.3fs, scrollFlickMinVel=%.2f",
                     tune.swipeMinVelocity, tune.swipeMinDisplacement, tune.openPalmDwellSeconds, tune.scrollFlickMinVelocity))

        // 2. Validate input file
        let expandedInput = (replayFilePath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedInput) else {
            FileHandle.standardError.write("Error: Input file not found at '\(expandedInput)'\n".data(using: .utf8)!)
            return 1
        }

        guard let inputContent = try? String(contentsOfFile: expandedInput, encoding: .utf8) else {
            FileHandle.standardError.write("Error: Could not read file at '\(expandedInput)'\n".data(using: .utf8)!)
            return 1
        }

        // 3. Setup output file handle if requested
        var outHandle: FileHandle? = nil
        if let outPath = outputFilePath {
            let expandedOut = (outPath as NSString).expandingTildeInPath
            let outURL = URL(fileURLWithPath: expandedOut)
            let outDir = outURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: expandedOut, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: outURL) else {
                FileHandle.standardError.write("Error: Could not create output file at '\(expandedOut)'\n".data(using: .utf8)!)
                return 1
            }
            outHandle = handle
        }
        defer {
            try? outHandle?.close()
        }

        // 4. Initialize replay engines and clocks
        let clock = ReplayClock()
        let actionSink = RecordingActionSink(clock: clock)
        let arbiter = IntentArbiter(clock: clock)
        let gestureEngine = GestureEngine(clock: clock, actionSink: actionSink, arbiter: arbiter)
        let scrollEngine = ScrollEngine(clock: clock, actionSink: actionSink, arbiter: arbiter)
        let primaryChannel = HandFeatureExtractor.Channel()
        let secondaryChannel = HandFeatureExtractor.Channel()

        let runMode = modeOption?.lowercased() ?? "all"
        let enableNav = (runMode == "all" || runMode == "nav" || runMode == "macnavigation")
        let enableScroll = (runMode == "all" || runMode == "scroll" || runMode == "airscroll")

        var lastCommitSeq = 0
        var totalFrames = 0
        var firedActionCounts: [String: Int] = [:]
        var firedActionsList: [(action: String, frame: Int, time: Double)] = []
        var isDegradedReplay = false

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        // 5. Process lines
        inputContent.enumerateLines { line, stop in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return }

            if trimmed.starts(with: "{\"incident\":") {
                if let handle = outHandle, let d = (trimmed + "\n").data(using: .utf8) {
                    handle.write(d)
                }
                return
            }

            guard let lineData = trimmed.data(using: .utf8),
                  let record = try? decoder.decode(HandFrameRecord.self, from: lineData) else {
                return
            }

            if record.confidence == nil && record.faceBBox == nil {
                isDegradedReplay = true
            }

            // Advance clock to this frame's timestamp
            clock.advance(to: record.timestamp)

            // Extract primary landmarks
            var primaryLandmarks: HandLandmarks? = nil
            if record.handDetected && !record.primaryPoints.isEmpty {
                let rawPoints = record.primaryPoints.map { CGPoint(x: $0.x, y: $0.y) }
                let confs = record.confidence ?? Array(repeating: 1.0, count: rawPoints.count)
                let faceBox = record.faceBBox?.cgRect
                primaryLandmarks = HandFeatureExtractor.landmarks(
                    from: rawPoints,
                    confidences: confs,
                    channel: primaryChannel,
                    nowTimestamp: record.timestamp,
                    faceBBox: faceBox
                )
            } else {
                primaryChannel.reset()
            }

            // Extract secondary landmarks if present
            var secondaryLandmarks: HandLandmarks? = nil
            if let secPoints = record.secondaryPoints, !secPoints.isEmpty {
                let rawPoints = secPoints.map { CGPoint(x: $0.x, y: $0.y) }
                secondaryLandmarks = HandFeatureExtractor.landmarks(
                    from: rawPoints,
                    confidences: nil,
                    channel: secondaryChannel,
                    nowTimestamp: record.timestamp,
                    faceBBox: record.faceBBox?.cgRect
                )
            } else {
                secondaryChannel.reset()
            }

            // Feed active engines
            if enableNav {
                gestureEngine.process(primaryLandmarks)
            }
            if enableScroll {
                if secondaryLandmarks != nil {
                    scrollEngine.forceDischarge()
                } else {
                    scrollEngine.process(primaryLandmarks)
                }
            }

            // Check if any action fired
            let seq = arbiter.commitSequence
            let replayedFiredIntent = (seq != lastCommitSeq) ? arbiter.lastCommitted.rawValue : ""
            let replayedFiredAction = (seq != lastCommitSeq) ? arbiter.lastCommittedActionName : ""
            if seq != lastCommitSeq {
                lastCommitSeq = seq
                firedActionCounts[replayedFiredAction, default: 0] += 1
                firedActionsList.append((action: replayedFiredAction, frame: record.frameIndex, time: record.timestamp))
            }

            totalFrames += 1

            // Write output record if output handle is available
            if let handle = outHandle {
                let outRecord = HandFrameRecord(
                    timestamp: record.timestamp,
                    frameIndex: record.frameIndex,
                    groundTruth: record.groundTruth,
                    predictedIntent: arbiter.currentIntent.rawValue,
                    firedIntent: replayedFiredIntent,
                    firedAction: replayedFiredAction,
                    handDetected: record.handDetected,
                    fingerCount: primaryLandmarks?.fingerCount ?? record.fingerCount,
                    isPinching: primaryLandmarks?.isPinching ?? record.isPinching,
                    isTwoFingers: primaryLandmarks?.isTwoFingers ?? record.isTwoFingers,
                    isRaisedHand: primaryLandmarks?.isRaisedHand ?? record.isRaisedHand,
                    estimatedDepth: primaryLandmarks != nil ? Double(primaryLandmarks!.estimatedDepth) : record.estimatedDepth,
                    facingCamera: primaryLandmarks?.facingCamera ?? record.facingCamera,
                    primaryPoints: record.primaryPoints,
                    secondaryPoints: record.secondaryPoints,
                    confidence: record.confidence,
                    faceBBox: record.faceBBox,
                    isInInteractionRange: primaryLandmarks?.isInInteractionRange ?? record.isInInteractionRange,
                    handCentroid: primaryLandmarks != nil ? LandmarkPointRecord(x: Double(primaryLandmarks!.handCentroid.x), y: Double(primaryLandmarks!.handCentroid.y)) : record.handCentroid,
                    tiltAngleDegrees: primaryLandmarks?.tiltAngleDegrees ?? record.tiltAngleDegrees
                )

                if let encoded = try? encoder.encode(outRecord),
                   let newline = "\n".data(using: .utf8) {
                    handle.write(encoded)
                    handle.write(newline)
                }
            }
        }

        print("=== GestureFlow Replay Summary ===")
        print("Frames processed: \(totalFrames)")
        if isDegradedReplay {
            print("Notice: Degraded replay mode (some optional fields like faceBBox/confidence missing from input)")
        }
        print("Total fired actions: \(firedActionsList.count)")
        for (action, count) in firedActionCounts.sorted(by: { $0.key < $1.key }) {
            print("  - \(action): \(count)")
        }
        if !firedActionsList.isEmpty {
            print("Action Sequence:")
            for item in firedActionsList {
                print(String(format: "  Frame %5d (t=%7.3fs): %@", item.frame, item.time, item.action))
            }
        }
        print("==================================")
        return 0
    }
}
