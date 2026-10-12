import Foundation
import AVFoundation

/// Voice-guided, auto-labelled data collection session (`--guided`).
///
/// Removes the need to hold number keys while gesturing: the app speaks a cue,
/// the user performs the gesture inside the "perform" window, and ground-truth
/// labels are assigned from the schedule. Transition windows (hand moving into
/// position / returning) are labelled `ignore` so reaction lag is never scored
/// as a recognition error.
final class GuidedSession {
    struct Step {
        let label: String
        let cue: String          // Spoken at step start; empty = silent
        let display: String      // Shown in the HUD action line
        let seconds: TimeInterval
    }

    private struct GestureSpec {
        let label: String
        let spoken: String
        let display: String
        let reps: Int
        let performSeconds: TimeInterval
    }

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var steps: [Step] = []
    private var stepIndex = 0
    private var pending: DispatchWorkItem?
    private(set) var isRunning = false

    /// Called on the main queue at each step: (label, display text, stepIndex, totalSteps)
    var onStep: ((String, String, Int, Int) -> Void)?
    var onFinish: (() -> Void)?

    init() {
        steps = GuidedSession.buildSchedule()
    }

    var totalDuration: TimeInterval { steps.reduce(0) { $0 + $1.seconds } }

    static func buildSchedule() -> [Step] {
        var out: [Step] = []

        let idleBlocks: [(String, String, TimeInterval)] = [
            ("Type on the keyboard like normal work", "Idle: gõ phím", 20),
            ("Scratch your face and touch your chin", "Idle: gãi mặt / chạm cằm", 15),
            ("Talk and move your hands casually", "Idle: nói chuyện, tay tự nhiên", 15),
            ("Rest your hand on the desk", "Idle: tay nghỉ trên bàn", 10),
            ("Wave your hand around without any deliberate gesture", "Idle: vẫy tay vô tư", 10)
        ]
        for (spoken, display, secs) in idleBlocks {
            out.append(Step(label: "ignore", cue: spoken, display: "Chuẩn bị — \(display)", seconds: 2.5))
            out.append(Step(label: "idle", cue: "", display: display, seconds: secs))
        }

        let gestures: [GestureSpec] = [
            GestureSpec(label: "swipe_left", spoken: "Swipe left", display: "Vuốt TRÁI (lòng bàn tay mở)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "swipe_right", spoken: "Swipe right", display: "Vuốt PHẢI (lòng bàn tay mở)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "swipe_up", spoken: "Swipe up", display: "Vuốt LÊN (lòng bàn tay mở)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "swipe_down", spoken: "Swipe down", display: "Vuốt XUỐNG (lòng bàn tay mở)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "scroll_down", spoken: "Scroll down", display: "Cuộn xuống (hai ngón, hất lên)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "scroll_up", spoken: "Scroll up", display: "Cuộn lên (hai ngón, hất xuống)", reps: 10, performSeconds: 1.6),
            GestureSpec(label: "pinch_dock", spoken: "Pinch and hold, then drag, then release", display: "Pinch giữ → kéo ngang → thả", reps: 10, performSeconds: 3.2),
            GestureSpec(label: "zoom", spoken: "Two hands, pinch and spread", display: "Hai tay pinch rồi giãn ra", reps: 6, performSeconds: 2.5)
        ]

        // Round-robin so gesture order is not memorisable and fatigue is spread evenly.
        let maxReps = gestures.map(\.reps).max() ?? 0
        for round in 0..<maxReps {
            for g in gestures where round < g.reps {
                out.append(Step(label: "ignore", cue: g.spoken, display: "Chuẩn bị: \(g.display)", seconds: 1.4))
                out.append(Step(label: g.label, cue: "Go", display: g.display, seconds: g.performSeconds))
                out.append(Step(label: "ignore", cue: "", display: "Hạ tay xuống", seconds: 1.0))
            }
        }

        out.append(Step(label: "ignore", cue: "Session complete. Thank you.", display: "Hoàn tất", seconds: 2.0))
        return out
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        stepIndex = 0
        runCurrentStep()
    }

    func stop() {
        isRunning = false
        pending?.cancel()
        pending = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func runCurrentStep() {
        guard isRunning else { return }
        guard stepIndex < steps.count else {
            isRunning = false
            onFinish?()
            return
        }
        let step = steps[stepIndex]
        DatasetRecorder.shared.setGroundTruthLabel(step.label)
        onStep?(step.label, step.display, stepIndex, steps.count)

        if !step.cue.isEmpty {
            let utterance = AVSpeechUtterance(string: step.cue)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.52
            synthesizer.speak(utterance)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.stepIndex += 1
            self.runCurrentStep()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + step.seconds, execute: work)
    }
}
