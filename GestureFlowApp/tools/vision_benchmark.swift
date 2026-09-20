#!/usr/bin/env swift
// vision_benchmark.swift
// Measures Apple Vision VNDetectHumanHandPoseRequest performance on macOS (Apple Neural Engine / GPU):
// 1. Inference latency (p50, p95, max ms)
// 2. Per-joint confidence distributions (detecting dropouts & noisy joints)
// 3. Hand detection rate across images / poses
//
// Usage:
//   swift tools/vision_benchmark.swift <image_or_directory>
//   swift tools/vision_benchmark.swift --synthetic [n_frames]

import Foundation
import Vision
import CoreGraphics
import ImageIO

let joints: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip
]

struct BenchmarkResult {
    var totalFrames: Int = 0
    var detectedFrames: Int = 0
    var latenciesMs: [Double] = []
    var jointConfidences: [VNHumanHandPoseObservation.JointName: [Double]] = [:]
}

func processImage(cgImage: CGImage, result: inout BenchmarkResult) {
    let request = VNDetectHumanHandPoseRequest()
    request.maximumHandCount = 1
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    
    let t0 = DispatchTime.now()
    do {
        try handler.perform([request])
    } catch {
        print("Vision perform error: \(error)")
        return
    }
    let t1 = DispatchTime.now()
    let latencyMs = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000.0
    
    result.totalFrames += 1
    result.latenciesMs.append(latencyMs)
    
    guard let observation = request.results?.first else {
        return
    }
    
    result.detectedFrames += 1
    if let points = try? observation.recognizedPoints(.all) {
        for j in joints {
            if let p = points[j] {
                result.jointConfidences[j, default: []].append(Double(p.confidence))
            }
        }
    }
}

func generateSyntheticHandImage(width: Int = 1280, height: Int = 720) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    
    // Background
    ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    
    // Draw synthetic hand silhouette (palm + 5 fingers) in flesh tone
    ctx.setFillColor(CGColor(red: 0.85, green: 0.65, blue: 0.55, alpha: 1.0))
    let cx = CGFloat(width) / 2.0
    let cy = CGFloat(height) / 2.0
    
    // Palm
    ctx.fillEllipse(in: CGRect(x: cx - 60, y: cy - 70, width: 120, height: 110))
    // Wrist
    ctx.fill(CGRect(x: cx - 40, y: cy - 140, width: 80, height: 80))
    // Fingers
    let fingerXOffsets: [CGFloat] = [-45, -20, 5, 30, 55]
    let fingerLengths: [CGFloat] = [70, 95, 105, 95, 75]
    for (ox, fl) in zip(fingerXOffsets, fingerLengths) {
        ctx.fillEllipse(in: CGRect(x: cx + ox - 12, y: cy + 30, width: 24, height: fl))
    }
    
    return ctx.makeImage()
}

func printReport(_ res: BenchmarkResult) {
    print("\n" + String(repeating: "=", count: 70))
    print("      APPLE VISION HAND POSE BENCHMARK REPORT (macOS ANE/GPU)")
    print(String(repeating: "=", count: 70))
    
    let detRate = res.totalFrames > 0 ? (Double(res.detectedFrames) / Double(res.totalFrames) * 100.0) : 0.0
    print("Total Frames Evaluated : \(res.totalFrames)")
    print("Frames with Hand Pose  : \(res.detectedFrames) (\(String(format: "%.1f", detRate))% detection rate)")
    
    if !res.latenciesMs.isEmpty {
        let sorted = res.latenciesMs.sorted()
        let p50 = sorted[Int(Double(sorted.count) * 0.50)]
        let p95 = sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        print("\n--- INFERENCE LATENCY (ms per frame) ---")
        print("Mean: \(String(format: "%.2f", mean)) ms | p50: \(String(format: "%.2f", p50)) ms | p95: \(String(format: "%.2f", p95)) ms | Max: \(String(format: "%.2f", sorted.last!)) ms")
        print("FPS Capacity (Single Hand): ~\(Int(1000.0 / mean)) FPS theoretical throughput")
    }
    
    print("\n--- PER-JOINT CONFIDENCE DISTRIBUTION (0.0 to 1.0) ---")
    print(String(format: "%-15@ | %-10@ | %-10@ | %-10@", "Joint Group", "Mean Conf", "Min Conf", "Dropout %"))
    print(String(repeating: "-", count: 55))
    
    let groups: [(String, [VNHumanHandPoseObservation.JointName])] = [
        ("Wrist", [.wrist]),
        ("Knuckles (MCP)", [.indexMCP, .middleMCP, .ringMCP, .littleMCP]),
        ("Mid Joints (PIP)", [.indexPIP, .middlePIP, .ringPIP, .littlePIP]),
        ("Fingertips", [.indexTip, .middleTip, .ringTip, .littleTip]),
        ("Thumb", [.thumbCMC, .thumbMP, .thumbIP, .thumbTip])
    ]
    
    for (name, grp) in groups {
        var confs: [Double] = []
        var totalExpected = 0
        var found = 0
        for j in grp {
            if let c = res.jointConfidences[j] {
                confs.append(contentsOf: c)
                found += c.count
            }
            totalExpected += res.detectedFrames
        }
        let meanC = confs.isEmpty ? 0.0 : confs.reduce(0, +) / Double(confs.count)
        let minC = confs.isEmpty ? 0.0 : confs.min()!
        let dropP = totalExpected > 0 ? (Double(totalExpected - found) / Double(totalExpected) * 100.0) : 0.0
        print(String(format: "%-15@ | %-10.2f | %-10.2f | %-9.1f%%", name, meanC, minC, dropP))
    }
    print(String(repeating: "=", count: 70))
}

func main() {
    var res = BenchmarkResult()
    let args = CommandLine.arguments
    
    if args.contains("--synthetic") || args.count < 2 {
        let n = args.firstIndex(of: "--synthetic").flatMap { idx in
            idx + 1 < args.count ? Int(args[idx + 1]) : nil
        } ?? 50
        print("Running Vision benchmark with \(n) synthetic test frames on Apple Silicon...")
        guard let img = generateSyntheticHandImage() else {
            print("Error: Could not generate synthetic image")
            return
        }
        // Warmup
        var warmupRes = BenchmarkResult()
        for _ in 0..<5 { processImage(cgImage: img, result: &warmupRes) }
        
        for _ in 0..<n {
            processImage(cgImage: img, result: &res)
        }
    } else {
        let path = args[1]
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            let imgFiles = files.filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") || $0.hasSuffix(".jpeg") }
            print("Processing \(imgFiles.count) images from \(url.path)...")
            for f in imgFiles {
                let fUrl = url.appendingPathComponent(f)
                if let src = CGImageSourceCreateWithURL(fUrl as CFURL, nil),
                   let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                    processImage(cgImage: cg, result: &res)
                }
            }
        } else if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            print("Processing single image \(url.path)...")
            processImage(cgImage: cg, result: &res)
        }
    }
    
    printReport(res)
}

main()
