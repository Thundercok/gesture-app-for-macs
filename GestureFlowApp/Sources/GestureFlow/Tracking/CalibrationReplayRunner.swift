import Foundation
import CoreGraphics

enum CalibrationReplayRunner {
    static func run(filePath: String) -> Int32 {
        let expanded = (filePath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded),
              let content = try? String(contentsOfFile: expanded, encoding: .utf8) else {
            FileHandle.standardError.write("Error: Could not read file at '\(expanded)'\n".data(using: .utf8)!)
            return 1
        }

        var palmSamples: [Double] = []
        var recordedSpeeds: [Double] = []
        var recordedDisplacements: [Double] = []
        var currentTrialPoints: [(point: CGPoint, t: TimeInterval)] = []
        var firstTimestamp: TimeInterval? = nil

        let decoder = JSONDecoder()

        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.starts(with: "{\"incident\":"),
                  let data = trimmed.data(using: .utf8),
                  let record = try? decoder.decode(HandFrameRecord.self, from: data) else {
                return
            }

            if firstTimestamp == nil {
                firstTimestamp = record.timestamp
            }

            let elapsed = record.timestamp - (firstTimestamp ?? record.timestamp)

            // Measure palm size if in the first 10 seconds of open palm
            if elapsed <= 10.0 && record.handDetected && record.primaryPoints.count > 9 && record.fingerCount >= 4 {
                let wrist = record.primaryPoints[0]
                let middleMCP = record.primaryPoints[9]
                let palmLen = Double(hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y))
                if palmLen > 0.02 {
                    palmSamples.append(palmLen)
                }
            }

            // Swipe trials: contiguous segments of swipe_left / swipe_right
            let gt = record.groundTruth.lowercased()
            let isSwipe = (gt == "swipe_left" || gt == "swipe_right")

            if isSwipe && record.handDetected && record.primaryPoints.count > 8 {
                let pt = CGPoint(x: 1.0 - record.primaryPoints[8].x, y: record.primaryPoints[8].y)
                currentTrialPoints.append((point: pt, t: record.timestamp))
            } else {
                if !currentTrialPoints.isEmpty {
                    let v = CalibrationMath.windowedPeakVelocity(samples: currentTrialPoints)
                    let d = CalibrationMath.windowedPeakDisplacement(samples: currentTrialPoints)
                    if v > 0.05 {
                        recordedSpeeds.append(v)
                    }
                    if d > 0.01 {
                        recordedDisplacements.append(d)
                    }
                    currentTrialPoints.removeAll()
                }
            }
        }

        if !currentTrialPoints.isEmpty {
            let v = CalibrationMath.windowedPeakVelocity(samples: currentTrialPoints)
            let d = CalibrationMath.windowedPeakDisplacement(samples: currentTrialPoints)
            if v > 0.05 {
                recordedSpeeds.append(v)
            }
            if d > 0.01 {
                recordedDisplacements.append(d)
            }
            currentTrialPoints.removeAll()
        }

        let medPalm = CalibrationMath.median(palmSamples) ?? 0.12
        let medSpeed = CalibrationMath.median(recordedSpeeds) ?? (GestureTuning.balanced.swipeMinVelocity / 0.65)
        let medDisp = CalibrationMath.median(recordedDisplacements) ?? (Double(GestureTuning.balanced.swipeMinDisplacement) / 0.65)
        let derived = CalibrationMath.derive(medianVelocity: medSpeed, medianDisplacement: medDisp, fraction: 0.65)

        print("[CalibrationReplay] File: \(filePath)")
        print("[CalibrationReplay] Trials: \(recordedSpeeds.count)")
        print(String(format: "[CalibrationReplay] Median Palm Size: %.4f (samples: %d)", medPalm, palmSamples.count))
        print("[CalibrationReplay] Peak Speeds: \(recordedSpeeds.map { String(format: "%.3f", $0) })")
        print("[CalibrationReplay] Displacements: \(recordedDisplacements.map { String(format: "%.3f", $0) })")
        print(String(format: "[CalibrationReplay] Median Speed: %.3f", medSpeed))
        print(String(format: "[CalibrationReplay] Median Displacement: %.3f", medDisp))
        print(String(format: "[CalibrationReplay] Derived Thresholds: swipeMinVelocity=%.2f, swipeMinDisplacement=%.3f", derived.velocity, derived.displacement))

        return 0
    }
}
