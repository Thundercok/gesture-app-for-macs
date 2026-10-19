import Foundation
import CoreGraphics

enum FeatureDumper {
    static func dumpFeatures(inputFile: String, outputFile: String, useRawPoints: Bool = false) -> Int32 {
        let expandedInput = (inputFile as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expandedInput),
              let content = try? String(contentsOfFile: expandedInput, encoding: .utf8) else {
            FileHandle.standardError.write("Error: Could not read input file '\(expandedInput)'\n".data(using: .utf8)!)
            return 1
        }

        let expandedOutput = (outputFile as NSString).expandingTildeInPath
        let outURL = URL(fileURLWithPath: expandedOutput)
        let outDir = outURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: expandedOutput, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: outURL) else {
            FileHandle.standardError.write("Error: Could not open output file '\(expandedOutput)'\n".data(using: .utf8)!)
            return 1
        }
        defer { try? handle.close() }

        // Construct HandLandmarks exactly as ReplayRunner does
        let primaryChannel = HandFeatureExtractor.Channel()
        let decoder = JSONDecoder()

        // Write CSV header
        var headerCols = ["frame_index"]
        for i in 0..<21 {
            headerCols.append("lm_\(i)_x")
            headerCols.append("lm_\(i)_y")
        }
        headerCols.append(contentsOf: [
            "eng_palm_width",
            "eng_thumb_index_dist",
            "eng_thumb_middle_dist",
            "eng_index_middle_dist",
            "eng_tip_wrist_thumb",
            "eng_tip_wrist_index",
            "eng_tip_wrist_middle",
            "eng_tip_wrist_ring",
            "eng_tip_wrist_pinky",
            "eng_curl_thumb",
            "eng_curl_index",
            "eng_curl_middle",
            "eng_curl_ring",
            "eng_curl_pinky"
        ])
        let headerLine = headerCols.joined(separator: ",") + "\n"
        handle.write(headerLine.data(using: .utf8)!)

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.starts(with: "{\"incident\":"),
                  let data = trimmed.data(using: .utf8),
                  let record = try? decoder.decode(HandFrameRecord.self, from: data) else {
                return
            }

            guard record.handDetected && record.primaryPoints.count == 21 else {
                primaryChannel.reset()
                return
            }

            let rawPoints = record.primaryPoints.map { CGPoint(x: $0.x, y: $0.y) }
            let confs = record.confidence ?? Array(repeating: 1.0, count: 21)
            let faceBox = record.faceBBox?.cgRect

            guard let lm = HandFeatureExtractor.landmarks(
                from: rawPoints,
                confidences: confs,
                channel: primaryChannel,
                nowTimestamp: record.timestamp,
                faceBBox: faceBox
            ) else {
                return
            }

            let features: [Float]?
            if useRawPoints {
                features = PostureClassifier.extractFeatures(fromPoints: rawPoints)
            } else {
                features = PostureClassifier.extractFeatures(from: lm)
            }

            guard let feats = features else { return }

            var row = ["\(record.frameIndex)"]
            for f in feats {
                row.append(String(format: "%.6f", f))
            }
            let rowLine = row.joined(separator: ",") + "\n"
            handle.write(rowLine.data(using: .utf8)!)
        }

        return 0
    }
}
