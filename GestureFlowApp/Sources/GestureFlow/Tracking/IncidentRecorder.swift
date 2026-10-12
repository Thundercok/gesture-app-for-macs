import Foundation
import CoreGraphics

enum IncidentKind: String {
    case fire
    case misfire
    case missed
    case quiet
}

struct IncidentHeader: Codable {
    let incident: String
    let createdAt: String
    let appVersion: String
    let note: String
}

final class IncidentRecorder {
    static let shared = IncidentRecorder()

    private let userDefaultsKey = "gf.passiveIncidents"
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "com.gestureflow.incidents", qos: .utility)
    private let isoFormatter = ISO8601DateFormatter()

    // 4.0 seconds @ 60 FPS = 240 frames
    private let maxBufferFrames = 240
    private var frameBuffer: [HandFrameRecord] = []

    // Quiet snapshot tracking
    private var lastQuietTime: Date = Date()
    private let quietInterval: TimeInterval = 600.0 // 10 minutes

    // Post-window auto-fire state
    private var pendingAutoFires: [(triggerTime: Double, intent: String, captureDeadline: Date)] = []

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return true // default true
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }

    private var incidentsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GestureFlow").appendingPathComponent("incidents")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    /// Ingests each frame into in-memory ring buffer and checks quiet/auto-fire triggers.
    func ingest(frame: HandFrameRecord) {
        guard isEnabled && !DatasetRecorder.shared.isRecording else { return }

        lock.lock()
        frameBuffer.append(frame)
        if frameBuffer.count > maxBufferFrames {
            frameBuffer.removeFirst(frameBuffer.count - maxBufferFrames)
        }

        let now = Date()

        // Check if any pending auto-fire has finished its post-window (1.0s after trigger)
        var readyFires: [(triggerTime: Double, intent: String)] = []
        pendingAutoFires.removeAll { item in
            if now >= item.captureDeadline {
                readyFires.append((item.triggerTime, item.intent))
                return true
            }
            return false
        }

        // Check quiet snapshot trigger (hand seen, 10 min passed)
        var triggerQuiet = false
        if frame.handDetected && now.timeIntervalSince(lastQuietTime) >= quietInterval {
            lastQuietTime = now
            triggerQuiet = true
        }

        // Extract frame buffer snapshots while locked
        let currentSnapshot = frameBuffer
        lock.unlock()

        // Process ready auto-fire dumps
        for item in readyFires {
            // 2.0s before to 1.0s after trigger
            let t0 = item.triggerTime - 2.0
            let t1 = item.triggerTime + 1.0
            let windowFrames = currentSnapshot.filter { $0.timestamp >= t0 && $0.timestamp <= t1 }
            dumpFrames(windowFrames, kind: .fire, note: "auto-fire: \(item.intent)", groundTruthLabel: "unlabeled")
        }

        // Process quiet snapshot
        if triggerQuiet {
            let t0 = frame.timestamp - 2.0
            let windowFrames = currentSnapshot.filter { $0.timestamp >= t0 }
            dumpFrames(windowFrames, kind: .quiet, note: "10-minute periodic baseline", groundTruthLabel: "unlabeled")
        }
    }

    /// Called when an action is committed (IntentArbiter.commitSequence incremented).
    func markAutoFire(intent: String) {
        guard isEnabled && !DatasetRecorder.shared.isRecording else { return }

        lock.lock()
        let triggerTime = frameBuffer.last?.timestamp ?? ProcessInfo.processInfo.systemUptime
        let deadline = Date().addingTimeInterval(1.0) // wait 1.0s post-window
        pendingAutoFires.append((triggerTime: triggerTime, intent: intent, captureDeadline: deadline))
        lock.unlock()
    }

    /// Called on manual user hotkey ⌃⌥⌘M (.misfire) or ⌃⌥⌘N (.missed).
    func markUser(_ kind: IncidentKind) {
        guard isEnabled && !DatasetRecorder.shared.isRecording else { return }

        lock.lock()
        let framesToDump = frameBuffer
        lock.unlock()

        let gtLabel = kind.rawValue
        dumpFrames(framesToDump, kind: kind, note: "user marked \(kind.rawValue)", groundTruthLabel: gtLabel)
    }

    private func dumpFrames(_ frames: [HandFrameRecord], kind: IncidentKind, note: String, groundTruthLabel: String) {
        guard !frames.isEmpty else { return }

        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(df.string(from: now))_\(kind.rawValue).jsonl"
        let fileURL = incidentsDirectoryURL.appendingPathComponent(filename)

        let createdAt = isoFormatter.string(from: now)
        let header = IncidentHeader(
            incident: kind.rawValue,
            createdAt: createdAt,
            appVersion: "revision/gestures",
            note: note
        )

        writeQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                var data = try encoder.encode(header)
                if let nl = "\n".data(using: .utf8) { data.append(nl) }

                for f in frames {
                    // Update groundTruth label if needed for the dump
                    let adjusted = HandFrameRecord(
                        timestamp: f.timestamp,
                        frameIndex: f.frameIndex,
                        groundTruth: groundTruthLabel,
                        predictedIntent: f.predictedIntent,
                        firedIntent: f.firedIntent,
                        handDetected: f.handDetected,
                        fingerCount: f.fingerCount,
                        isPinching: f.isPinching,
                        isTwoFingers: f.isTwoFingers,
                        isRaisedHand: f.isRaisedHand,
                        estimatedDepth: f.estimatedDepth,
                        facingCamera: f.facingCamera,
                        primaryPoints: f.primaryPoints,
                        secondaryPoints: f.secondaryPoints
                    )
                    let frameData = try encoder.encode(adjusted)
                    data.append(frameData)
                    if let nl = "\n".data(using: .utf8) { data.append(nl) }
                }

                try data.write(to: fileURL)
                print("[IncidentRecorder] Saved \(kind.rawValue) incident (\(frames.count) frames) to \(filename)")
                self.enforceStorageCap()
            } catch {
                print("[IncidentRecorder] Failed to save incident file: \(error)")
            }
        }
    }

    /// Enforces max 200 MB storage cap by deleting oldest incident files.
    func enforceStorageCap() {
        let maxBytes: Int64 = 200 * 1024 * 1024 // 200 MB
        let fm = FileManager.default
        let dir = incidentsDirectoryURL

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: .skipsHiddenFiles) else {
            return
        }

        var fileInfos: [(url: URL, size: Int64, date: Date)] = []
        var totalSize: Int64 = 0

        for file in files {
            guard file.pathExtension == "jsonl" else { continue }
            if let res = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]),
               let size = res.fileSize,
               let date = res.creationDate {
                let s = Int64(size)
                totalSize += s
                fileInfos.append((url: file, size: s, date: date))
            }
        }

        guard totalSize > maxBytes else { return }

        // Sort oldest first
        fileInfos.sort { $0.date < $1.date }

        for info in fileInfos {
            if totalSize <= maxBytes { break }
            try? fm.removeItem(at: info.url)
            totalSize -= info.size
            print("[IncidentRecorder] Storage cap reached: removed oldest incident \(info.url.lastPathComponent)")
        }
    }
}
