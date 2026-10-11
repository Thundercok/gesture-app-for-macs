import SwiftUI
import AppKit

struct HUDView: View {
    @ObservedObject var state: AppState
    var onHide: (() -> Void)?

    var body: some View {
        ZStack {
            // Refined Frosted Obsidian Glass Chassis (Exact shape masking, zero corner spilling)
            RoundedRectangle(cornerRadius: state.isCompactHUD ? 16 : 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: state.isCompactHUD ? 16 : 18, style: .continuous)
                        .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.88))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: state.isCompactHUD ? 16 : 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.30),
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )

            if state.isCompactHUD {
                // MARK: - Mini Dynamic Pill (VisionOS Style Status Capsule)
                HStack(spacing: 8) {
                    // Pulsing Multi-State Organic Dot
                    ZStack {
                        Circle()
                            .fill(pillDotColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: pillDotColor.opacity(0.85), radius: 4)

                        if state.scanProgress > 0 && !state.isArmed {
                            Circle()
                                .stroke(Color.yellow.opacity(0.7), lineWidth: 1.2)
                                .frame(width: 13, height: 13)
                        }
                    }

                    if state.isRecordingDataset {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("REC [\(state.datasetLabel)]")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                        .fixedSize()
                    }

                    pillStatusView


                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                            state.onToggleCompact?(false)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Mở rộng HUD")

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 18, height: 18)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Thoát")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            } else {
                // MARK: - Full Settings & Spatial Inspector
                VStack(spacing: 8) {
                    // Header Bar
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.90))

                            Text("GestureFlow")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("SPATIAL")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.70))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }

                        Spacer()

                        // Status Badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(pillDotColor)
                                .frame(width: 5, height: 5)

                            Text(state.isArmed ? "Armed" : (state.handDetected ? "Active" : "Standby"))
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(state.isArmed ? Color(red: 0.0, green: 0.95, blue: 0.55) : (state.handDetected ? .white.opacity(0.85) : .white.opacity(0.50)))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Capsule())

                        // Mode Selector Button
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                state.cycleMode()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: state.currentMode.iconName)
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text(state.currentMode.shortCode)
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Chế độ: \(state.currentMode.displayName) (Nhấp để đổi)")

                        // Camera View Mode
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                state.cycleDisplayMode()
                            }
                        } label: {
                            Image(systemName: state.displayMode.icon)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Chế độ hiển thị: \(state.displayMode.rawValue)")

                        // Minimize to Pill Button
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                state.onToggleCompact?(true)
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Thu gọn thành Mini Pill")

                        // Quit Button
                        Button {
                            NSApp.terminate(nil)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Thoát")
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    // Spatial Hand Tracking Viewport
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.02, green: 0.03, blue: 0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )

                        let cameraAspect = state.cameraAspectRatio > 0.5 ? state.cameraAspectRatio : (16.0 / 9.0)

                        if state.displayMode != .minimal, let image = state.currentFrame {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(cameraAspect, contentMode: .fit)
                                .scaleEffect(x: -1, y: 1)
                                .opacity(state.displayMode == .monochrome ? 0.25 : 1.0)
                                .saturation(state.displayMode == .monochrome ? 0.0 : 1.0)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // Holographic Vector Hand Skeleton (Apple VisionOS Theme)
                        if let landmarks = state.currentLandmarks {
                            HolographicSkeletonView(
                                landmarks: landmarks,
                                isPinching: state.isPinching,
                                showTelemetryGimbal: true,
                                colorTheme: .visionPro,
                                scanProgress: state.scanProgress,
                                isArmed: state.isArmed,
                                isDockOpen: state.isDockOpen,
                                activeSuppressReason: state.activeSuppressReason,
                                showOnScreenTelemetry: true,
                                currentModeCode: state.currentMode.shortCode
                            )
                        }

                        // Top Telemetry Header inside Viewport
                        VStack {
                            HStack {
                                // Real-time Metric Distance & Palm Tilt readout
                                if state.handDetected {
                                    HStack(spacing: 5) {
                                        Text(String(format: "Z: %.2fm", state.estimatedDepth))
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                            .foregroundColor(state.estimatedDepth > 0.25 && state.estimatedDepth < 0.65 ? Color(red: 0.1, green: 0.95, blue: 0.55) : Color.white.opacity(0.80))

                                        Text("•")
                                            .font(.system(size: 7))
                                            .foregroundColor(.white.opacity(0.3))

                                        Text(String(format: "TILT: %.0f°", (1.0 - state.facingCamera) * 90.0))
                                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                            .foregroundColor(state.facingCamera > 0.5 ? Color.white.opacity(0.85) : .orange)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                                }

                                Spacer()

                                // Intentionality Gating Diagnostic Shield Badge
                                if let reason = state.activeSuppressReason {
                                    HStack(spacing: 4) {
                                        Image(systemName: "shield.lefthalf.filled")
                                            .font(.system(size: 8))
                                        Text(reason == "face_proximity" ? "VÙNG MẶT" : (reason == "edge_on_palm" ? "NGHIÊNG TAY" : "KHOẢNG CÁCH"))
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.orange.opacity(0.25)).overlay(Capsule().stroke(Color.orange.opacity(0.50), lineWidth: 0.8)))
                                } else if state.handDetected {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(state.isArmed ? Color(red: 0.0, green: 0.95, blue: 0.55) : Color.white.opacity(0.60))
                                            .frame(width: 4, height: 4)
                                        Text(state.isArmed ? "ARMED" : "TRACKING")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(state.isArmed ? Color(red: 0.0, green: 0.95, blue: 0.55) : Color.white.opacity(0.85))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.black.opacity(0.65)))
                                }
                            }
                            .padding(8)

                            Spacer()
                        }

                        // Guidance Text when hand is absent
                        if !state.handDetected {
                            VStack(spacing: 5) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundColor(.white.opacity(0.40))

                                Text("Giơ lòng bàn tay để quét kích hoạt")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .transition(.opacity)
                        } else if state.scanProgress > 0 && !state.isArmed {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                                        .frame(width: 44, height: 44)
                                    Circle()
                                        .trim(from: 0.0, to: state.scanProgress)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.yellow, Color.orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                        )
                                        .frame(width: 44, height: 44)
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(state.scanProgress * 100))%")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.yellow)
                                }

                                Text("Đang xác thực lòng bàn tay...")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        } else if state.isArmed && !state.isDockOpen {
                            VStack {
                                Spacer()
                                Text("Chụm để mở App Switcher")
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.55))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().stroke(Color(red: 0.0, green: 0.95, blue: 0.55).opacity(0.6), lineWidth: 1)))
                                    .padding(.bottom, 8)
                            }
                        }

                        // Live Action Banner
                        if let action = state.latestAction {
                            VStack {
                                Spacer()
                                Text(action)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 1)))
                                    .shadow(color: Color.black.opacity(0.40), radius: 6)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .aspectRatio(state.cameraAspectRatio > 0.5 ? state.cameraAspectRatio : (16.0 / 9.0), contentMode: .fit)
                    .padding(.horizontal, 12)

                    // Streamlined Step-by-Step Guidance Footer
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.raised")
                                .font(.system(size: 8.5))
                            Text("Giơ tay")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Text("→").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                        HStack(spacing: 4) {
                            Image(systemName: "circle.circle")
                                .font(.system(size: 8.5))
                            Text("Chụm ngón")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Text("→").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 8.5))
                            Text("Vẩy ngang")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        Text("→").font(.system(size: 8)).foregroundColor(.white.opacity(0.3))
                        HStack(spacing: 4) {
                            Image(systemName: "hand.point.up.left")
                                .font(.system(size: 8.5))
                            Text("Thả đổi App")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: state.isCompactHUD ? 252 : 380, height: state.isCompactHUD ? 40 : 325)
        .clipShape(RoundedRectangle(cornerRadius: state.isCompactHUD ? 16 : 18, style: .continuous))
    }

    @ViewBuilder
    private var pillStatusView: some View {
        if let action = state.latestAction {
            Text(action)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if let reason = state.activeSuppressReason {
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 8.5))
                Text(reason == "face_proximity" ? "Vùng mặt" : (reason == "edge_on_palm" ? "Nghiêng tay" : "Khoảng cách"))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
            }
            .foregroundColor(.orange)
            .fixedSize()
        } else if state.isAirScrollActive {
            HStack(spacing: 4) {
                Image(systemName: state.airScrollVelocity < -0.05 ? "arrow.down" : (state.airScrollVelocity > 0.05 ? "arrow.up" : "arrow.up.and.down"))
                    .font(.system(size: 9.5, weight: .bold))
                Text(state.airScrollVelocity < -0.05 ? "Lướt xuống ↓" : (state.airScrollVelocity > 0.05 ? "Lướt lên ↑" : "Đang lướt"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
            .fixedSize()
        } else if state.currentMode == .airScroll {
            HStack(spacing: 4) {
                Text("Air Scroll")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                if state.handDetected {
                    Text("• Hất tay để lướt")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
                } else {
                    Text("• Chờ hất tay")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
            .fixedSize()
        } else if state.currentMode == .macNavigation {
            HStack(spacing: 4) {
                Text("Navigation")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                if state.isDockOpen {
                    Text("• Chọn App")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else if state.handDetected {
                    Text("• Vuốt chuyển App")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.55))
                } else {
                    Text("• Sẵn sàng")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
            .fixedSize()
        } else if state.currentMode == .spatialZoom {
            HStack(spacing: 4) {
                Text("Spatial Zoom")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.90))
                if state.isBimanualActive {
                    Text("• \(state.bimanualZoomPercent)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.70))
                } else {
                    Text("• Giơ 2 tay")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.50))
                }
            }
            .fixedSize()
        } else if state.isDockOpen {
            Text("Chuyển App")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .fixedSize()
        } else if state.isArmed {
            Text("Sẵn sàng")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.55))
                .fixedSize()
        } else if state.scanProgress > 0 {
            HStack(spacing: 4) {
                Text("Quét bàn tay")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.yellow)
                    .fixedSize()
                Text("\(Int(state.scanProgress * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .fixedSize()
            }
        } else {
            Text("GestureFlow")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.90))
                .fixedSize()

            if state.handDetected {
                Text(String(format: "• %.2fm", state.estimatedDepth))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize()
            } else {
                Text("• Đang chờ")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.50))
                    .fixedSize()
            }
        }
    }

    private var pillDotColor: Color {

        if state.isAirScrollActive {
            return Color(red: 0.0, green: 0.85, blue: 1.0)
        } else if state.currentMode == .airScroll && state.handDetected {
            return Color(red: 0.20, green: 0.75, blue: 0.95).opacity(0.85)
        } else if state.currentMode == .macNavigation && state.handDetected {
            return Color(red: 0.0, green: 0.95, blue: 0.55)
        } else if state.currentMode == .spatialZoom && state.isBimanualActive {
            return Color(red: 0.0, green: 0.95, blue: 0.70)
        } else if state.isArmed {
            return Color(red: 0.0, green: 0.95, blue: 0.55)
        } else if state.scanProgress > 0 {
            return Color.yellow
        } else if state.activeSuppressReason != nil {
            return Color.orange
        } else if state.handDetected {
            return Color.white.opacity(0.80)
        } else {
            return Color.white.opacity(0.35)
        }
    }
}
