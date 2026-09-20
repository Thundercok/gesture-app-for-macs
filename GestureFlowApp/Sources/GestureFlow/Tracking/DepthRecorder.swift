// DepthRecorder.swift  (measurement first: record raw landmarks once, iterate on estimators offline)
//
//   GestureFlow --record-depth ~/gf_depth.jsonl
//   then type a label + Enter, e.g.  d40_flat  (palm centre on the 40 cm mark, palm parallel to the screen).
//   It waits `settleSeconds`, records `cellSeconds`, prints the frame count. Empty line quits.
//
//   depth cells : d<cm>_<pose>, pose in flat | pitch30 | roll30 | pr30 | pr45 | spin45   -> tools/depth_eval.py
//   any other label (n_chin, n_cheek, n_talk ...) is recorded too: nuisance-motion sets for replaying the gates offline.

import Foundation
import Vision

final class DepthRecorder {
    static let shared = DepthRecorder()

    var settleSeconds = 2.0
    var cellSeconds = 3.0

    private let lock = NSLock()
    private let writer = DispatchQueue(label: "gf.depth-recorder")
    private var file: FileHandle?
    private var label: String?                          // non-nil while a cell is being recorded
    private var frames = 0
    private var misses = 0

    private static let joints: [(VNHumanHandPoseObservation.JointName, String)] = [
        (.wrist, "wrist"),
        (.thumbCMC, "thumbCMC"), (.thumbMP, "thumbMP"), (.thumbIP, "thumbIP"), (.thumbTip, "thumbTip"),
        (.indexMCP, "indexMCP"), (.indexPIP, "indexPIP"), (.indexDIP, "indexDIP"), (.indexTip, "indexTip"),
        (.middleMCP, "middleMCP"), (.middlePIP, "middlePIP"), (.middleDIP, "middleDIP"), (.middleTip, "middleTip"),
        (.ringMCP, "ringMCP"), (.ringPIP, "ringPIP"), (.ringDIP, "ringDIP"), (.ringTip, "ringTip"),
        (.littleMCP, "littleMCP"), (.littlePIP, "littlePIP"), (.littleDIP, "littleDIP"), (.littleTip, "littleTip"),
    ]

    /// Once at startup when `--record-depth <path>` is present. `width`/`height` = the CVPixelBuffer size Vision actually sees.
    func begin(path: String, width: Int, height: Int, device: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let fh = try? FileHandle(forWritingTo: url) else { print("Cannot open \(url.path)"); return }
        file = fh
        write("{\"t\":\"h\",\"w\":\(width),\"h\":\(height),\"device\":\"\(device)\"}\n")
        print("Recording to \(url.path). Type a label + Enter (d40_flat, d40_pr30, n_chin ...); empty line quits.")
        Thread.detachNewThread { [self] in
            while let line = readLine(strippingNewline: true), !line.isEmpty { runCell(line) }
            writer.sync {}                              // flush pending writes
            exit(0)
        }
    }

    /// Every camera frame, with the RAW Vision observation (before any filtering). `obs == nil` = no hand this frame.
    /// `face` = Vision-normalized face box (needed later to replay the face-clearance gate offline); optional.
    func record(_ obs: VNHumanHandPoseObservation?, face: CGRect? = nil, zEstMM: Double?, pts: TimeInterval, now: TimeInterval) {
        lock.lock()
        guard let l = label else { lock.unlock(); return }
        frames += 1
        if obs == nil { misses += 1 }
        lock.unlock()

        var joints = "null"
        if let obs, let points = try? obs.recognizedPoints(.all) {
            let parts: [String] = Self.joints.compactMap { jn, name in
                guard let p = points[jn] else { return nil }
                return String(format: "\"%@\":[%.5f,%.5f,%.2f]",
                              name, Double(p.location.x), Double(p.location.y), Double(p.confidence))
            }
            joints = "{" + parts.joined(separator: ",") + "}"
        }
        let z = zEstMM.map { String(format: "%.1f", $0) } ?? "null"
        let fc = face.map { String(format: "[%.5f,%.5f,%.5f,%.5f]", Double($0.origin.x), Double($0.origin.y), Double($0.width), Double($0.height)) } ?? "null"
        write(String(format: "{\"t\":\"f\",\"l\":\"%@\",\"pts\":%.6f,\"now\":%.6f,\"z\":%@,\"face\":%@,\"j\":%@}\n",
                     l, pts, now, z, fc, joints))
    }

    // MARK: Internals

    private func runCell(_ raw: String) {
        let l = raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }          // keeps the JSON valid
        guard !l.isEmpty else { return }
        print("\(l): hold the pose, recording in \(Int(settleSeconds)) s")
        Thread.sleep(forTimeInterval: settleSeconds)
        lock.lock(); label = l; frames = 0; misses = 0; lock.unlock()
        Thread.sleep(forTimeInterval: cellSeconds)
        lock.lock(); label = nil; let (f, m) = (frames, misses); lock.unlock()
        print("\(l): \(f) frames, \(m) without a hand")
    }

    private func write(_ s: String) {
        writer.async { [file] in file?.write(Data(s.utf8)) }
    }
}
