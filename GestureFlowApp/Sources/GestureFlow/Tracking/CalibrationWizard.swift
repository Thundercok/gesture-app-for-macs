import Foundation
import CoreGraphics
import AVFoundation

/// Raw biometric and kinematic measurements captured during the 60-second Calibration Wizard (WP9.3).
/// Stored alongside derived GestureTuning thresholds so raw measurements are never lost.
struct CalibrationMeasurements: Codable, Equatable {
    let recordedAt: String
    let medianPalmSize: Double
    let palmSizeSamplesCount: Int
    let swipePeakSpeeds: [Double]
    let swipeDisplacements: [Double]
    let medianSwipeSpeed: Double
    let medianSwipeDisplacement: Double
    let derivedSwipeMinVelocity: Double
    let derivedSwipeMinDisplacement: Double
}

/// 60-second Calibration Onboarding Wizard (WP9.3).
/// Measures typical palm size (10s) and natural swipe speed/displacement across 5 user swipes (5 × 10s),
/// stores the raw measurements in UserDefaults and `~/Library/Application Support/GestureFlow/calibration.json`,
/// and sets `GestureTuning.current` thresholds as a fraction (0.65×) of the user's natural median motion.
final class CalibrationWizard {
    static let shared = CalibrationWizard()
    private static let userDefaultsKey = "gf.calibration.raw.v1"

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isRunning: Bool = false
    private var workItems: [DispatchWorkItem] = []

    private enum Phase {
        case idle
        case palmMeasurement
        case swipeTrial(index: Int)
    }

    private var phase: Phase = .idle
    private var palmSamples: [Double] = []
    private var currentTrialSpeeds: [Double] = []
    private var currentTrialPoints: [(point: CGPoint, time: TimeInterval)] = []
    private var recordedSwipeSpeeds: [Double] = []
    private var recordedSwipeDisplacements: [Double] = []
    private var lastPoint: CGPoint?
    private var lastTime: TimeInterval?

    var onStatus: ((String) -> Void)?
    var onFinish: ((CalibrationMeasurements?) -> Void)?

    /// Total duration of the wizard: 10s palm measurement + 5 × 10s swipe trials = 60 seconds.
    let totalDurationSeconds: TimeInterval = 60.0

    var latestMeasurements: CalibrationMeasurements? {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(CalibrationMeasurements.self, from: data) {
            return decoded
        }
        return nil
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        palmSamples.removeAll()
        recordedSwipeSpeeds.removeAll()
        recordedSwipeDisplacements.removeAll()
        resetTrialBuffer()

        phase = .palmMeasurement
        speak("Hold your open palm naturally in front of the camera for ten seconds.")
        onStatus?("Hiệu chuẩn [1/6]: Giơ bàn tay mở tự nhiên (10s)...")

        for trial in 1...5 {
            let startOffset = Double(trial) * 10.0
            let item = DispatchWorkItem { [weak self] in
                guard let self = self, self.isRunning else { return }
                if trial > 1 {
                    self.finalizeCurrentSwipeTrial()
                }
                self.resetTrialBuffer()
                self.phase = .swipeTrial(index: trial)
                self.speak("Swipe \(trial) of 5. Perform one natural horizontal swipe.")
                self.onStatus?("Hiệu chuẩn [\(trial + 1)/6]: Vuốt ngang tự nhiên lần \(trial)/5...")
            }
            workItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + startOffset, execute: item)
        }

        let finishItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.finalizeCurrentSwipeTrial()
            self.completeCalibration()
        }
        workItems.append(finishItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDurationSeconds, execute: finishItem)
    }

    func cancel() {
        guard isRunning else { return }
        isRunning = false
        phase = .idle
        for item in workItems {
            item.cancel()
        }
        workItems.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        onStatus?("Đã huỷ hiệu chuẩn")
    }

    /// Called per camera frame while `isRunning == true`.
    func ingest(landmarks: HandLandmarks?, timestamp: TimeInterval) {
        guard isRunning, let lm = landmarks else {
            lastPoint = nil
            lastTime = nil
            return
        }

        switch phase {
        case .idle:
            break
        case .palmMeasurement:
            guard lm.points.count > 9 else { break }
            let wrist = lm.points[0]
            let middleMCP = lm.points[9]
            let palmLen = Double(hypot(middleMCP.x - wrist.x, middleMCP.y - wrist.y))
            if palmLen > 0.02 {
                palmSamples.append(palmLen)
            }
        case .swipeTrial:
            let pt = CGPoint(x: 1.0 - lm.indexTip.x, y: lm.indexTip.y)
            if let prevPt = lastPoint, let prevT = lastTime {
                let dt = max(0.001, timestamp - prevT)
                if dt < 0.25 {
                    let speed = Double(hypot(pt.x - prevPt.x, pt.y - prevPt.y)) / dt
                    currentTrialSpeeds.append(speed)
                }
            }
            currentTrialPoints.append((point: pt, time: timestamp))
            lastPoint = pt
            lastTime = timestamp
        }
    }

    private func resetTrialBuffer() {
        currentTrialSpeeds.removeAll()
        currentTrialPoints.removeAll()
        lastPoint = nil
        lastTime = nil
    }

    private func finalizeCurrentSwipeTrial() {
        let peakSpeed = currentTrialSpeeds.max() ?? 0.0
        var maxDisp: Double = 0.0
        if currentTrialPoints.count >= 2 {
            for i in 0..<currentTrialPoints.count {
                for j in (i + 1)..<currentTrialPoints.count {
                    let dt = currentTrialPoints[j].time - currentTrialPoints[i].time
                    if dt <= 0.25 {
                        let d = Double(abs(currentTrialPoints[j].point.x - currentTrialPoints[i].point.x))
                        if d > maxDisp {
                            maxDisp = d
                        }
                    }
                }
            }
        }
        if peakSpeed > 0.05 {
            recordedSwipeSpeeds.append(peakSpeed)
        }
        if maxDisp > 0.01 {
            recordedSwipeDisplacements.append(maxDisp)
        }
    }

    private func completeCalibration() {
        isRunning = false
        phase = .idle
        workItems.removeAll()

        let medPalm = Self.median(palmSamples) ?? 0.12
        let medSpeed = Self.median(recordedSwipeSpeeds) ?? GestureTuning.balanced.swipeMinVelocity / 0.65
        let medDisp = Self.median(recordedSwipeDisplacements) ?? Double(GestureTuning.balanced.swipeMinDisplacement) / 0.65

        // Set GestureTuning thresholds as a fraction (65%) of the user's natural median swipe
        let derivedVel = max(0.30, min(0.85, medSpeed * 0.65))
        let derivedDisp = max(0.045, min(0.110, medDisp * 0.65))

        let iso = ISO8601DateFormatter()
        let measurements = CalibrationMeasurements(
            recordedAt: iso.string(from: Date()),
            medianPalmSize: medPalm,
            palmSizeSamplesCount: palmSamples.count,
            swipePeakSpeeds: recordedSwipeSpeeds,
            swipeDisplacements: recordedSwipeDisplacements,
            medianSwipeSpeed: medSpeed,
            medianSwipeDisplacement: medDisp,
            derivedSwipeMinVelocity: derivedVel,
            derivedSwipeMinDisplacement: derivedDisp
        )

        saveMeasurements(measurements)

        var tuned = GestureTuning.current
        tuned.swipeMinVelocity = derivedVel
        tuned.swipeMinDisplacement = CGFloat(derivedDisp)
        GestureTuning.current = tuned

        speak("Calibration complete.")
        onStatus?(String(format: "Hiệu chuẩn xong: v≥%.2f, d≥%.3f", derivedVel, derivedDisp))
        onFinish?(measurements)
    }

    private func saveMeasurements(_ m: CalibrationMeasurements) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(m) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)

        let dir = ("~/Library/Application Support/GestureFlow" as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = (dir as NSString).appendingPathComponent("calibration.json")
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        synthesizer.speak(utterance)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}
