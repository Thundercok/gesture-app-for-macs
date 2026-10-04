import SwiftUI
import AppKit

// MARK: - Apple VisionOS Spatial Hand Skeleton View
// Elegant, minimal, translucent pearl-glass anatomical hand skeleton
// designed to look completely native to macOS Sequoia and Apple VisionOS.
struct HolographicSkeletonView: View {
    let landmarks: HandLandmarks
    let isPinching: Bool
    var showTelemetryGimbal: Bool = true
    var colorTheme: SkeletonTheme = .visionPro
    var scanProgress: CGFloat = 0.0
    var isArmed: Bool = false
    var isDockOpen: Bool = false
    var activeSuppressReason: String? = nil
    var showOnScreenTelemetry: Bool = true
    var currentModeCode: String = "APP_SW"

    enum SkeletonTheme {
        case visionPro      // Refined Apple VisionOS Pearl Glass (Default)
        case cyberNeon      // Kept for backward compatibility
        case emerald        // Kept for backward compatibility
        case monochrome     // Jet Black & Pure White
    }

    // Anatomical Finger Phalanx Chains
    private let fingerPhalanges: [[Int]] = [
        [1, 2, 3, 4],          // Thumb
        [5, 6, 7, 8],          // Index
        [9, 10, 11, 12],       // Middle
        [13, 14, 15, 16],      // Ring
        [17, 18, 19, 20]       // Pinky
    ]

    // Metacarpal Palm Rays
    private let metacarpalRays: [[Int]] = [
        [0, 1],                // Wrist to Thumb
        [0, 5],                // Wrist to Index
        [0, 9],                // Wrist to Middle
        [0, 13],               // Wrist to Ring
        [0, 17]                // Wrist to Pinky
    ]

    private func screenCoord(_ pt: CGPoint, w: CGFloat, h: CGFloat) -> CGPoint {
        CGPoint(x: (1.0 - pt.x) * w, y: pt.y * h)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let centroid = screenCoord(landmarks.handCentroid, w: w, h: h)
            let anchor = UnitPoint(x: centroid.x / max(1.0, w), y: centroid.y / max(1.0, h))

            let pitch = min(40.0, max(-40.0, landmarks.pitchDegrees))
            let yaw = min(40.0, max(-40.0, landmarks.yawDegrees))
            let pScale = landmarks.perspectiveScale

            ZStack {
                // 1. LiDAR Topographic Iso-Depth Contour Field (With 3D Parallax Stacking)
                if landmarks.points.count >= 21 {
                    lidarIsoDepthContoursView(w: w, h: h, pitch: pitch, yaw: yaw)
                        .rotation3DEffect(
                            .degrees(-pitch * 0.8),
                            axis: (x: 1.0, y: 0.0, z: 0.0),
                            anchor: anchor,
                            perspective: 0.32
                        )
                        .rotation3DEffect(
                            .degrees(yaw * 0.8),
                            axis: (x: 0.0, y: 1.0, z: 0.0),
                            anchor: anchor,
                            perspective: 0.32
                        )
                }

                // 2. Anatomical Hand Skeleton (Pearl Glass Bones, Shield & Joints in 3D Perspective)
                ZStack {
                    // Frosted Translucent Palm Shield
                    palmShieldView(w: w, h: h)

                    // Subtle Metacarpal Tendons
                    metacarpalRaysView(w: w, h: h)

                    // Clean Pearl Finger Bones
                    fingerBonesView(w: w, h: h)

                    // Minimalist Haptic Pinch Indicator
                    pinchIndicatorView(w: w, h: h)

                    // Refined Pearl Joint Nodes
                    jointNodesView(w: w, h: h)
                }
                .rotation3DEffect(
                    .degrees(-pitch),
                    axis: (x: 1.0, y: 0.0, z: 0.0),
                    anchor: anchor,
                    perspective: 0.35
                )
                .rotation3DEffect(
                    .degrees(yaw),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    anchor: anchor,
                    perspective: 0.35
                )
                .scaleEffect(pScale, anchor: anchor)

                // 3. 6-DOF Spatial Attitude Gimbal (Pitch, Roll, Yaw & Palm Normal Vector)
                if showTelemetryGimbal && landmarks.points.count >= 21 {
                    spatialAttitudeGimbalView(w: w, h: h)
                }

                // 4. Research-Grade In-Situ Telemetry Matrix
                if showOnScreenTelemetry && landmarks.points.count >= 21 {
                    researchTelemetryMatrixBadge(w: w, h: h)
                }
            }
        }
    }

    // MARK: - Subviews

    // 1. Palm Shield: Subtle frosted glass backing
    @ViewBuilder
    private func palmShieldView(w: CGFloat, h: CGFloat) -> some View {
        if landmarks.points.count >= 21 {
            let p0 = screenCoord(landmarks.points[0], w: w, h: h)
            let p1 = screenCoord(landmarks.points[1], w: w, h: h)
            let p5 = screenCoord(landmarks.points[5], w: w, h: h)
            let p9 = screenCoord(landmarks.points[9], w: w, h: h)
            let p13 = screenCoord(landmarks.points[13], w: w, h: h)
            let p17 = screenCoord(landmarks.points[17], w: w, h: h)

            let boundary = [p0, p1, p5, p9, p13, p17]

            if boundary.allSatisfy({ $0.x > 0 && $0.y > 0 }) {
                Path { path in
                    path.move(to: boundary[0])
                    for pt in boundary.dropFirst() {
                        path.addLine(to: pt)
                    }
                    path.closeSubpath()
                }
                .fill(Color.black.opacity(0.18))

                Path { path in
                    path.move(to: boundary[0])
                    for pt in boundary.dropFirst() {
                        path.addLine(to: pt)
                    }
                    path.closeSubpath()
                }
                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            }
        }
    }

    // 2. Metacarpal Tendons: Delicate connecting lines
    @ViewBuilder
    private func metacarpalRaysView(w: CGFloat, h: CGFloat) -> some View {
        Path { path in
            drawChains(metacarpalRays, into: &path, w: w, h: h)
        }
        .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    // 3. Finger Bones: Refined frosted pearl lines with soft ambient shadow
    @ViewBuilder
    private func fingerBonesView(w: CGFloat, h: CGFloat) -> some View {
        // Subtle drop shadow for clarity over light desktop items
        Path { path in
            drawChains(fingerPhalanges, into: &path, w: w, h: h)
        }
        .stroke(
            Color.black.opacity(0.35),
            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
        )

        // Main pearl bone line
        Path { path in
            drawChains(fingerPhalanges, into: &path, w: w, h: h)
        }
        .stroke(
            Color.white.opacity(0.85),
            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        )
    }

    // 4. Minimalist Haptic Pinch Indicator (VisionOS Style)
    @ViewBuilder
    private func pinchIndicatorView(w: CGFloat, h: CGFloat) -> some View {
        if landmarks.points.count > 8 {
            let pThumb = screenCoord(landmarks.points[4], w: w, h: h)
            let pIndex = screenCoord(landmarks.points[8], w: w, h: h)
            let pinchDist = hypot(pThumb.x - pIndex.x, pThumb.y - pIndex.y)
            let midPt = CGPoint(x: (pThumb.x + pIndex.x) / 2.0, y: (pThumb.y + pIndex.y) / 2.0)

            if isPinching {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.90), lineWidth: 1.8)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.black.opacity(0.40), radius: 2)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 4.5, height: 4.5)
                }
                .position(midPt)
            } else if pinchDist < 36.0 {
                // Subtle proximity hint
                Path { path in
                    path.move(to: pThumb)
                    path.addLine(to: pIndex)
                }
                .stroke(Color.white.opacity(0.30), style: StrokeStyle(lineWidth: 1.0, dash: [2, 3]))
            }
        }
    }

    // 5. Joint Nodes: Small minimalist pearl glass beads
    @ViewBuilder
    private func jointNodesView(w: CGFloat, h: CGFloat) -> some View {
        ForEach(0..<min(21, landmarks.points.count), id: \.self) { i in
            let pt = landmarks.points[i]
            if pt != .zero {
                let screenPt = screenCoord(pt, w: w, h: h)
                let isTip = [4, 8, 12, 16, 20].contains(i)
                let isWrist = (i == 0)

                ZStack {
                    if isTip {
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 9, height: 9)

                        Circle()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 5.5, height: 5.5)
                    } else if isWrist {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1.2)
                            .frame(width: 10, height: 10)
                            .background(Circle().fill(Color.black.opacity(0.30)))

                        Circle()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: 3.5, height: 3.5)
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.30))
                            .frame(width: 6, height: 6)

                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 4, height: 4)
                    }
                }
                .position(screenPt)
            }
        }
    }

    // MARK: - Powerhouse Subviews

    // 1. LiDAR Topographic Iso-Depth Contour Field (Multi-Layer Depth Parallax)
    @ViewBuilder
    private func lidarIsoDepthContoursView(w: CGFloat, h: CGFloat, pitch: Double, yaw: Double) -> some View {
        let centroid = screenCoord(landmarks.handCentroid, w: w, h: h)
        // Scaled inversely with metric depth Z: closer hand = wider contour rings
        let baseR = max(28.0, min(130.0, 46.0 / max(0.20, landmarks.estimatedDepth)))

        // Parallax shift for stacked depth planes
        let outerShift = CGPoint(x: CGFloat(yaw * 0.35), y: CGFloat(-pitch * 0.35))
        let midShift = CGPoint(x: CGFloat(yaw * 0.15), y: CGFloat(-pitch * 0.15))

        ZStack {
            // Core Reticle Crosshair
            Path { path in
                path.move(to: CGPoint(x: centroid.x - 6, y: centroid.y))
                path.addLine(to: CGPoint(x: centroid.x + 6, y: centroid.y))
                path.move(to: CGPoint(x: centroid.x, y: centroid.y - 6))
                path.addLine(to: CGPoint(x: centroid.x, y: centroid.y + 6))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.8)

            // Outer Field Ring (Iso-Depth Perimeter - Farther Depth Plane)
            Circle()
                .stroke(
                    Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.18),
                    style: StrokeStyle(lineWidth: 0.9, dash: [4, 6])
                )
                .frame(width: baseR * 2.8, height: baseR * 2.8)
                .position(x: centroid.x + outerShift.x, y: centroid.y + outerShift.y)

            // Primary Iso-Depth Elevation Contour Ring (Mid Depth Plane)
            Circle()
                .stroke(
                    Color(red: 0.10, green: 0.95, blue: 0.65).opacity(0.32),
                    style: StrokeStyle(lineWidth: 1.1, dash: [2, 3])
                )
                .frame(width: baseR * 2.0, height: baseR * 2.0)
                .position(x: centroid.x + midShift.x, y: centroid.y + midShift.y)

            // Inner Core Reticle Ring (Anchor Plane)
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                .frame(width: baseR * 1.3, height: baseR * 1.3)
                .position(centroid)

            // Technical LiDAR Elevation Tag
            Text(String(format: "ISO Z.%.2fM", landmarks.estimatedDepth))
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.10, green: 0.95, blue: 0.65).opacity(0.60))
                .position(x: centroid.x, y: centroid.y + baseR * 1.0 + 9.0)
        }
    }

    // 2. 6-DOF Spatial Attitude Gimbal
    @ViewBuilder
    private func spatialAttitudeGimbalView(w: CGFloat, h: CGFloat) -> some View {
        let centroid = screenCoord(landmarks.handCentroid, w: w, h: h)
        let wristPt = screenCoord(landmarks.wrist, w: w, h: h)
        let middleMcp = screenCoord(landmarks.points[9], w: w, h: h)
        let indexMcp = screenCoord(landmarks.points[5], w: w, h: h)
        let pinkyMcp = screenCoord(landmarks.points[17], w: w, h: h)

        // Vector Y: Wrist to Middle MCP (Longitudinal palm axis)
        let dy = middleMcp.y - wristPt.y
        let dx = middleMcp.x - wristPt.x
        let lenY = max(1.0, hypot(dx, dy))
        let dirY = CGPoint(x: dx / lenY, y: dy / lenY)

        // Vector X: Knuckle span Index MCP to Pinky MCP (Lateral palm axis)
        let dkx = pinkyMcp.x - indexMcp.x
        let dky = pinkyMcp.y - indexMcp.y
        let lenX = max(1.0, hypot(dkx, dky))
        let dirX = CGPoint(x: dkx / lenX, y: dky / lenX)

        let rayLengthX: CGFloat = 28.0
        let rayLengthY: CGFloat = 34.0
        let rayLengthZ: CGFloat = max(10.0, 32.0 * CGFloat(landmarks.facingCamera))

        let endX = CGPoint(x: centroid.x + dirX.x * rayLengthX, y: centroid.y + dirX.y * rayLengthX)
        let endY = CGPoint(x: centroid.x + dirY.x * rayLengthY, y: centroid.y + dirY.y * rayLengthY)
        // Projected normal vector (Z)
        let endZ = CGPoint(x: centroid.x - dirY.y * (rayLengthZ * 0.4), y: centroid.y + dirY.x * (rayLengthZ * 0.4) - rayLengthZ * 0.7)

        ZStack {
            // Attitude Reticle Circle
            Circle()
                .stroke(Color.white.opacity(0.20), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                .frame(width: 44, height: 44)
                .position(centroid)

            // Vector X (Coral / Lateral)
            Path { path in
                path.move(to: centroid)
                path.addLine(to: endX)
            }
            .stroke(Color(red: 1.0, green: 0.38, blue: 0.38).opacity(0.85), lineWidth: 1.2)

            Text("X")
                .font(.system(size: 7.0, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 1.0, green: 0.38, blue: 0.38))
                .position(x: endX.x + dirX.x * 6, y: endX.y + dirX.y * 6)

            // Vector Y (Mint / Elevation)
            Path { path in
                path.move(to: centroid)
                path.addLine(to: endY)
            }
            .stroke(Color(red: 0.25, green: 0.88, blue: 0.65).opacity(0.85), lineWidth: 1.2)

            Text("Y")
                .font(.system(size: 7.0, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.25, green: 0.88, blue: 0.65))
                .position(x: endY.x + dirY.x * 6, y: endY.y + dirY.y * 6)

            // Vector Z (Cyan / Normal Projection)
            Path { path in
                path.move(to: centroid)
                path.addLine(to: endZ)
            }
            .stroke(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.90), lineWidth: 1.4)

            Circle()
                .fill(Color(red: 0.0, green: 0.85, blue: 1.0))
                .frame(width: 3.5, height: 3.5)
                .position(endZ)

            Text("Z")
                .font(.system(size: 7.0, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
                .position(x: endZ.x, y: endZ.y - 7)
        }
    }

    // MARK: - Native Apple In-Situ Telemetry Badge (Anti-Vibecoded)
    @ViewBuilder
    private func researchTelemetryMatrixBadge(w: CGFloat, h: CGFloat) -> some View {
        let wristPt = screenCoord(landmarks.wrist, w: w, h: h)
        let isDistanceOk = landmarks.isInInteractionRange
        let isTiltOk = landmarks.facingCamera >= 0.48
        let badgeX = min(max(140, wristPt.x), w - 140)
        let badgeY = min(h - 32, max(32, wristPt.y + 36))

        let statusText: String = {
            if let reason = activeSuppressReason {
                switch reason {
                case "face_proximity": return "Face Lock"
                case "depth_band": return "Face Depth Lock"
                default: return "Tilt Palm to Camera"
                }
            } else if isDockOpen {
                return "Release to Select"
            } else if landmarks.isFramingCorner {
                return "Viewfinder Frame"
            } else if isArmed {
                return "Pinch to Select"
            } else if scanProgress > 0.05 {
                return "Readying \(Int(scanProgress * 100))%"
            } else if !isDistanceOk {
                return landmarks.estimatedDepth < 0.28 ? "Too Close (<0.28m)" : "Too Far (>0.65m)"
            } else if !isTiltOk {
                return "Face Camera Directly"
            } else if !landmarks.isStrictOpenPalm {
                return "Open Flat Palm"
            } else {
                return "Ready"
            }
        }()

        let statusColor: Color = {
            if activeSuppressReason != nil {
                return .orange
            } else if isDockOpen {
                return Color(red: 0.2, green: 0.7, blue: 1.0)
            } else if landmarks.isFramingCorner {
                return Color(red: 0.0, green: 0.95, blue: 0.70)
            } else if isArmed || (isDistanceOk && isTiltOk && landmarks.isStrictOpenPalm) {
                return Color(red: 0.1, green: 0.9, blue: 0.5)
            } else if scanProgress > 0.05 {
                return .yellow
            } else {
                return Color.white.opacity(0.7)
            }
        }()

        HStack(spacing: 8) {
            // Status LED
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)

            // High-Tech Mode Chip
            Text(currentModeCode)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(currentModeCode == "SCROLL" ? Color(red: 0.0, green: 0.90, blue: 1.0) : Color.white.opacity(0.80))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(currentModeCode == "SCROLL" ? Color(red: 0.0, green: 0.50, blue: 0.80).opacity(0.30) : Color.white.opacity(0.12))
                )

            // Subtle divider
            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(width: 1, height: 10)

            // Clean, human-centered metrics with monospaced digits
            HStack(spacing: 4) {
                Text(String(format: "%.2f m", landmarks.estimatedDepth))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(isDistanceOk ? Color.white.opacity(0.9) : .orange)

                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(Color.white.opacity(0.35))

                Text(String(format: "%.0f°", landmarks.tiltAngleDegrees))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(isTiltOk ? Color.white.opacity(0.85) : .orange)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.86))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
        )
        .shadow(color: Color.black.opacity(0.40), radius: 10, y: 3)
        .position(x: badgeX, y: badgeY)
    }

    // MARK: - Helpers

    private func drawChains(_ chains: [[Int]], into path: inout Path, w: CGFloat, h: CGFloat) {
        for chain in chains {
            drawSingleChain(chain, into: &path, w: w, h: h)
        }
    }

    private func drawSingleChain(_ chain: [Int], into path: inout Path, w: CGFloat, h: CGFloat) {
        guard chain.count > 1 else { return }
        var started = false
        for idx in chain {
            if idx < landmarks.points.count {
                let pt = landmarks.points[idx]
                if pt != .zero {
                    let screenPt = CGPoint(x: (1.0 - pt.x) * w, y: pt.y * h)
                    if !started {
                        path.move(to: screenPt)
                        started = true
                    } else {
                        path.addLine(to: screenPt)
                    }
                }
            }
        }
    }
}

// MARK: - 64D Neural Feature Oscilloscope Sparkline View
struct NeuralOscilloscopeView: View {
    let tensor: [Float]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = tensor.count

            ZStack {
                // Baseline grid
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.5))
                    path.addLine(to: CGPoint(x: w, y: h * 0.5))
                }
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))

                if count >= 2 {
                    let minV = tensor.min() ?? -1.0
                    let maxV = tensor.max() ?? 1.0
                    let span = max(0.001, maxV - minV)

                    Path { path in
                        for i in 0..<count {
                            let x = CGFloat(i) / CGFloat(count - 1) * w
                            let norm = CGFloat((tensor[i] - minV) / span)
                            let y = (1.0 - norm) * (h - 2.0) + 1.0
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        Color(red: 0.1, green: 0.95, blue: 0.65).opacity(0.85),
                        style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }
}
