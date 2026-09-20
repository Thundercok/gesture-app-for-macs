import Foundation
import CoreGraphics

final class TelemetryLogger {
    static let shared = TelemetryLogger()

    private let logFileURL: URL
    private var fileDescriptor: Int32 = -1
    private let writeQueue = DispatchQueue(label: "com.gestureflow.telemetry", qos: .utility)
    private let isoFormatter = ISO8601DateFormatter()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GestureFlow")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("gesture_log.jsonl")
        self.logFileURL = file

        let path = file.path
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        self.fileDescriptor = fd
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }

    func log(action: String, reason: String?, chargeLevel: Double, handCentroid: CGPoint) {
        writeQueue.async { [weak self] in
            guard let self = self, self.fileDescriptor >= 0 else { return }
            let ts = self.isoFormatter.string(from: Date())
            let reasonString = reason != nil ? "\"\(reason!)\"" : "null"
            let line = "{\"timestamp\":\"\(ts)\",\"action\":\"\(action)\",\"reason\":\(reasonString),\"chargeLevel\":\(String(format: "%.3f", chargeLevel)),\"handCentroid\":{\"x\":\(String(format: "%.4f", handCentroid.x)),\"y\":\(String(format: "%.4f", handCentroid.y))}}\n"

            if let cStr = line.cString(using: .utf8) {
                let len = strlen(cStr)
                _ = write(self.fileDescriptor, cStr, len)
                fsync(self.fileDescriptor)
            }
        }
    }
}
