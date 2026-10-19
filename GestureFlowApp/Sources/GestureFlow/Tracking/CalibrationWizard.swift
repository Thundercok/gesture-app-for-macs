import Foundation
import CoreGraphics
import AVFoundation

/// Raw biometric and kinematic measurements captured during the 60-second Calibration Wizard (WP9.3, WP16).
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

/// 60-second Calibration Onboarding Wizard (WP9.3, WP16).
/// Measures typical palm size (10s) and natural swipe speed/displacement across 5 user swipes (5 × 10s),
/// stores the raw measurements in UserDefaults and `~/Library/Application Support/GestureFlow/calibration.json`,
/// and sets `GestureTuning.current` thresholds as a fraction (0.65×) of the user's natural median motion.
final class CalibrationWizard {
    static let shared = CalibrationWizard()
    private static let userDefaultsKey = "gf.calibration.raw.v1"

    private let lock = NSLock()
    private let synthesizer = AVSpeechSynthesizer()
    private var isRunningState: Bool = false
    private var workItems: [DispatchWorkItem] = []

    private enum Phase {
        case idle
        case palmMeasurement
        case swipeTrial(index: Int)
    }

    private var phase: Phase = .idle
    private var palmSamples: [Double] = []
    private var currentTrialPoints: [(point: CGPoint, time: TimeInterval)] = []
    private var recordedSwipeSpeeds: [Double] = []
    private var recordedSwipeDisplacements: [Double] = []
    private var previousTuningBeforeCalibration: GestureTuning?

    var onStatus: ((String) -> Void)?
    var onFinish: ((CalibrationMeasurements?) -> Void)?

    /// Total duration of the wizard: 10s palm measurement + 5 × 10s swipe trials = 60 seconds.
    let totalDurationSeconds: TimeInterval = 60.0

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunningState
    }

    var latestMeasurements: CalibrationMeasurements? {
        if let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
           let decoded = try? JSONDecoder().decode(CalibrationMeasurements.self, from: data) {
            return decoded
        }
        return nil
    }

    func start() {
        lock.lock()
        guard !isRunningState else {
            lock.unlock()
            return
        }
        isRunningState = true
        palmSamples.removeAll()
        recordedSwipeSpeeds.removeAll()
        recordedSwipeDisplacements.removeAll()
        currentTrialPoints.removeAll()
        phase = .palmMeasurement
        for item in workItems { item.cancel() }
        workItems.removeAll()
        lock.unlock()

        speak("Hold your open palm naturally in front of the camera for ten seconds.")
        notifyStatus("Hiệu chuẩn [1/6]: Giơ bàn tay mở tự nhiên (10s)...")

        for trial in 1...5 {
            let startOffset = Double(trial) * 10.0
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                guard self.isRunningState else {
                    self.lock.unlock()
                    return
                }
                if trial > 1 {
                    self.finalizeCurrentSwipeTrialLocked()
                }
                self.currentTrialPoints.removeAll()
                self.phase = .swipeTrial(index: trial)
                self.lock.unlock()

                self.speak("Swipe \(trial) of 5. Perform one natural horizontal swipe.")
                self.notifyStatus("Hiệu chuẩn [\(trial + 1)/6]: Vuốt ngang tự nhiên lần \(trial)/5...")
            }
            lock.lock()
            workItems.append(item)
            lock.unlock()
            DispatchQueue.main.asyncAfter(deadline: .now() + startOffset, execute: item)
        }

        let finishItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            guard self.isRunningState else {
                self.lock.unlock()
                return
            }
            self.finalizeCurrentSwipeTrialLocked()
            self.completeCalibrationLocked()
            self.lock.unlock()
        }
        lock.lock()
        workItems.append(finishItem)
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDurationSeconds, execute: finishItem)
    }

    func cancel() {
        lock.lock()
        guard isRunningState else {
            lock.unlock()
            return
        }
        isRunningState = false
        phase = .idle
        for item in workItems {
            item.cancel()
        }
        workItems.removeAll()
        currentTrialPoints.removeAll()
        lock.unlock()

        synthesizer.stopSpeaking(at: .immediate)
        notifyStatus("Đã huỷ hiệu chuẩn")
    }

    func revertLastCalibration() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let previous = previousTuningBeforeCalibration else { return false }
        GestureTuning.current = previous
        previousTuningBeforeCalibration = nil
        return true
    }

    /// Called per camera frame while `isRunning == true`.
    func ingest(landmarks: HandLandmarks?, timestamp: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard isRunningState, let lm = landmarks else { return }

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
            currentTrialPoints.append((point: pt, time: timestamp))
        }
    }

    private func finalizeCurrentSwipeTrialLocked() {
        let samples = currentTrialPoints.map { ($0.point, $0.time) }
        let peakSpeed = CalibrationMath.windowedPeakVelocity(samples: samples)
        let maxDisp = CalibrationMath.windowedPeakDisplacement(samples: samples)
        if peakSpeed > 0.05 {
            recordedSwipeSpeeds.append(peakSpeed)
        }
        if maxDisp > 0.01 {
            recordedSwipeDisplacements.append(maxDisp)
        }
        currentTrialPoints.removeAll()
    }

    private func completeCalibrationLocked() {
        isRunningState = false
        phase = .idle
        workItems.removeAll()

        let medPalm = CalibrationMath.median(palmSamples) ?? 0.12
        let medSpeed = CalibrationMath.median(recordedSwipeSpeeds) ?? GestureTuning.balanced.swipeMinVelocity / 0.65
        let medDisp = CalibrationMath.median(recordedSwipeDisplacements) ?? Double(GestureTuning.balanced.swipeMinDisplacement) / 0.65

        let derived = CalibrationMath.derive(medianVelocity: medSpeed, medianDisplacement: medDisp, fraction: 0.65)

        let iso = ISO8601DateFormatter()
        let measurements = CalibrationMeasurements(
            recordedAt: iso.string(from: Date()),
            medianPalmSize: medPalm,
            palmSizeSamplesCount: palmSamples.count,
            swipePeakSpeeds: recordedSwipeSpeeds,
            swipeDisplacements: recordedSwipeDisplacements,
            medianSwipeSpeed: medSpeed,
            medianSwipeDisplacement: medDisp,
            derivedSwipeMinVelocity: derived.velocity,
            derivedSwipeMinDisplacement: derived.displacement
        )

        saveMeasurements(measurements)

        previousTuningBeforeCalibration = GestureTuning.current
        var tuned = GestureTuning.current
        tuned.preset = .custom
        tuned.swipeMinVelocity = derived.velocity
        tuned.swipeMinDisplacement = CGFloat(derived.displacement)
        GestureTuning.current = tuned

        speak("Calibration complete.")
        let statusMsg = String(format: "Hiệu chuẩn xong: v≥%.2f, d≥%.3f", derived.velocity, derived.displacement)
        notifyStatus(statusMsg)
        notifyFinish(measurements)
    }

    private func notifyStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onStatus?(message)
        }
    }

    private func notifyFinish(_ measurements: CalibrationMeasurements?) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?(measurements)
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.52
            self.synthesizer.speak(utterance)
        }
    }
}
