import SwiftUI
import AppKit

// MARK: - Spatial Application Switcher View
// High-performance, full-screen spatial computing interface for macOS application navigation.
struct ApplicationSwitcherView: View {
    @ObservedObject var state: AppState
    var onSelectApp: ((AppItem) -> Void)? = nil
    @Namespace private var animationNamespace

    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height
            let dockCenterY = screenH * 0.50

            ZStack {
                // 1. Cinematic Ambient Backdrop (Focus dimming)
                if state.isDockOpen {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .transition(.opacity)
                } else if state.scanProgress > 0.05 {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // 2. High-Contrast Spatial Hand Skeleton & Depth Tracking
                if let landmarks = state.currentLandmarks {
                    let handScreenPt = CGPoint(
                        x: state.gesturePoint.x * screenW,
                        y: state.gesturePoint.y * screenH
                    )

                    // A. Palm Scan Arming Ring (During initial charge)
                    if state.scanProgress > 0.05 && state.scanProgress < 1.0 && !state.isDockOpen {
                        ZStack {
                            Circle()
                                .stroke(Color.black.opacity(0.85), lineWidth: 5.0)
                                .frame(width: 48, height: 48)

                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 3.0)
                                .frame(width: 48, height: 48)

                            Circle()
                                .trim(from: 0.0, to: state.scanProgress)
                                .stroke(
                                    Color.yellow,
                                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                                )
                                .frame(width: 48, height: 48)
                                .rotationEffect(.degrees(-90))
                        }
                        .position(handScreenPt)
                        .animation(.easeOut(duration: 0.1), value: state.scanProgress)
                    }

                    // B. Prominent Spatial Hand Skeleton with On-Screen Telemetry
                    let isHandDeliberate = (landmarks.isStrictOpenPalm && landmarks.isInInteractionRange) || state.scanProgress > 0.0 || state.isArmed || state.isDockOpen || state.isBimanualActive
                    if isHandDeliberate {
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

                    // Secondary Spatial Hand Skeleton (Two-Handed Interaction)
                    if let secondary = state.secondaryLandmarks {
                        HolographicSkeletonView(
                            landmarks: secondary,
                            isPinching: secondary.isPinching,
                            showTelemetryGimbal: false,
                            colorTheme: .visionPro,
                            scanProgress: 0.0,
                            isArmed: false,
                            isDockOpen: false,
                            activeSuppressReason: nil,
                            showOnScreenTelemetry: false,
                            currentModeCode: state.currentMode.shortCode
                        )
                    }

                    // Bimanual Optical Caliper Tension Bridge (Zoom HUD)
                    if state.isBimanualActive, let p = state.currentLandmarks, let s = state.secondaryLandmarks {
                        let pScreen = CGPoint(x: (1.0 - p.handCentroid.x) * screenW, y: p.handCentroid.y * screenH)
                        let sScreen = CGPoint(x: (1.0 - s.handCentroid.x) * screenW, y: s.handCentroid.y * screenH)
                        let midPt = CGPoint(x: (pScreen.x + sScreen.x) / 2.0, y: (pScreen.y + sScreen.y) / 2.0)
                        let clutched = state.isDualPinchClutched

                        // Ambient laser shadow
                        Path { path in
                            path.move(to: pScreen)
                            path.addLine(to: sScreen)
                        }
                        .stroke(Color.black.opacity(clutched ? 0.40 : 0.20), style: StrokeStyle(lineWidth: clutched ? 4.5 : 3.0, lineCap: .round))

                        // Optical Caliper Laser Beam (Solid when clutched, delicate dashed cord when standby)
                        Path { path in
                            path.move(to: pScreen)
                            path.addLine(to: sScreen)
                        }
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.85, blue: 1.0).opacity(clutched ? 0.92 : 0.38),
                                    Color.white.opacity(clutched ? 0.98 : 0.45),
                                    Color(red: 0.0, green: 0.85, blue: 1.0).opacity(clutched ? 0.92 : 0.38)
                                ],
                                startPoint: UnitPoint(x: pScreen.x / screenW, y: pScreen.y / screenH),
                                endPoint: UnitPoint(x: sScreen.x / screenW, y: sScreen.y / screenH)
                            ),
                            style: StrokeStyle(lineWidth: clutched ? 2.2 : 1.4, lineCap: .round, dash: clutched ? [] : [5, 5])
                        )
                        .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(clutched ? 0.70 : 0.15), radius: clutched ? 10 : 3)
                        .animation(.spring(response: 0.20, dampingFraction: 0.80), value: clutched)

                        // Anchor Terminal Beads
                        Circle()
                            .fill(clutched ? Color(red: 0.0, green: 0.95, blue: 0.70) : Color.white.opacity(0.60))
                            .frame(width: clutched ? 9 : 6, height: clutched ? 9 : 6)
                            .shadow(color: clutched ? Color(red: 0.0, green: 0.95, blue: 0.70) : .clear, radius: 6)
                            .position(pScreen)

                        Circle()
                            .fill(clutched ? Color(red: 0.0, green: 0.95, blue: 0.70) : Color.white.opacity(0.60))
                            .frame(width: clutched ? 9 : 6, height: clutched ? 9 : 6)
                            .shadow(color: clutched ? Color(red: 0.0, green: 0.95, blue: 0.70) : .clear, radius: 6)
                            .position(sScreen)

                        // Optical Caliper Metric Readout Capsule (Anti-Vibecoded Native HUD)
                        HStack(spacing: 8) {
                            if clutched {
                                Circle()
                                    .fill(Color(red: 0.0, green: 0.95, blue: 0.70))
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Color(red: 0.0, green: 0.95, blue: 0.70), radius: 3)

                                Text("CLUTCH ENGAGED")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.70))

                                Rectangle()
                                    .fill(Color.white.opacity(0.20))
                                    .frame(width: 1, height: 10)

                                Text(String(format: "SPAN: %.1f CM", state.bimanualSpanMeters * 100.0))
                                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                                    .foregroundColor(.white)

                                Rectangle()
                                    .fill(Color.white.opacity(0.20))
                                    .frame(width: 1, height: 10)

                                Text(String(format: "ZOOM: %d%%", state.bimanualZoomPercent))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundColor(Color(red: 0.0, green: 0.85, blue: 1.0))
                            } else {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.50))

                                Text("CALIPER READY")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.85))

                                Rectangle()
                                    .fill(Color.white.opacity(0.20))
                                    .frame(width: 1, height: 10)

                                Text("PINCH BOTH HANDS TO ZOOM")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.55))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.88))
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            clutched ? Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.40) : Color.white.opacity(0.18),
                                            lineWidth: 0.8
                                        )
                                )
                        )
                        .shadow(color: Color.black.opacity(0.40), radius: 10, y: 3)
                        .position(midPt)
                        .animation(.spring(response: 0.20, dampingFraction: 0.80), value: clutched)
                    }

                    // C. Apple VisionOS Elastic Catenary Pearl Tether
                    if state.isDockOpen && !state.dockApps.isEmpty {
                        let selectedIdx = min(state.selectedDockIndex, max(0, state.dockApps.count - 1))
                        let appCount = state.dockApps.count
                        let itemsWidth = CGFloat(appCount) * 74.0 + CGFloat(max(0, appCount - 1)) * 14.0
                        let startX = screenW * 0.50 - itemsWidth / 2.0
                        let targetAppX = startX + CGFloat(selectedIdx) * (74.0 + 14.0) + 37.0
                        let targetAppPt = CGPoint(x: targetAppX, y: dockCenterY - 6.0)

                        // Catenary spring physics: 32px sag when relaxed, 8px taut thread when pinched
                        let sag: CGFloat = state.isPinching ? 8.0 : 32.0
                        let dx = handScreenPt.x - targetAppPt.x
                        let sway: CGFloat = max(-55.0, min(55.0, dx * 0.20))
                        let midY = (handScreenPt.y + targetAppPt.y) / 2.0 + sag
                        let cp1 = CGPoint(x: (handScreenPt.x * 0.65 + targetAppPt.x * 0.35) - sway, y: midY)
                        let cp2 = CGPoint(x: (handScreenPt.x * 0.35 + targetAppPt.x * 0.65) + sway * 0.4, y: midY - sag * 0.25)

                        // Soft ambient shadow pass
                        Path { path in
                            path.move(to: handScreenPt)
                            path.addCurve(to: targetAppPt, control1: cp1, control2: cp2)
                        }
                        .stroke(
                            Color.black.opacity(state.isPinching ? 0.38 : 0.22),
                            style: StrokeStyle(lineWidth: state.isPinching ? 4.2 : 3.0, lineCap: .round)
                        )

                        // Liquid pearl glass tether core (taut solid beam when pinched, delicate dashed cord when hovering)
                        Path { path in
                            path.move(to: handScreenPt)
                            path.addCurve(to: targetAppPt, control1: cp1, control2: cp2)
                        }
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(state.isPinching ? 0.90 : 0.45),
                                    Color.white.opacity(state.isPinching ? 0.65 : 0.20)
                                ],
                                startPoint: UnitPoint(x: handScreenPt.x / screenW, y: handScreenPt.y / screenH),
                                endPoint: UnitPoint(x: targetAppPt.x / screenW, y: targetAppPt.y / screenH)
                            ),
                            style: StrokeStyle(
                                lineWidth: state.isPinching ? 2.2 : 1.4,
                                lineCap: .round,
                                dash: state.isPinching ? [] : [5, 5]
                            )
                        )
                        .animation(.interpolatingSpring(stiffness: 190, damping: 16), value: targetAppPt)
                        .animation(.spring(response: 0.18, dampingFraction: 0.78), value: state.isPinching)

                        // Magnetic anchor bead at target app
                        Circle()
                            .fill(Color.white.opacity(state.isPinching ? 0.95 : 0.60))
                            .frame(width: state.isPinching ? 7 : 5, height: state.isPinching ? 7 : 5)
                            .shadow(color: Color.white.opacity(state.isPinching ? 0.8 : 0.3), radius: state.isPinching ? 6 : 2)
                            .position(targetAppPt)
                            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: state.isPinching)
                    }

                    // E. Minimalist Spatial Pinch Lens
                    ZStack {
                        Circle()
                            .strokeBorder(Color.black.opacity(0.30), lineWidth: 3.0)
                            .frame(width: state.isPinching ? 22 : 26, height: state.isPinching ? 22 : 26)

                        Circle()
                            .strokeBorder(
                                Color.white.opacity(state.isPinching ? 0.90 : 0.40),
                                lineWidth: state.isPinching ? 1.8 : 1.2
                            )
                            .frame(width: state.isPinching ? 20 : 24, height: state.isPinching ? 20 : 24)

                        if state.isPinching {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .position(handScreenPt)
                    .animation(.spring(response: 0.16, dampingFraction: 0.80), value: state.isPinching)
                }

                // 3. Center Stage: Horizontal Minimalist Apple Dock Switcher
                if state.isDockOpen {
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            // Left navigation chevron
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.selectedDockIndex > 0 ? Color.white.opacity(0.70) : Color.white.opacity(0.15))
                                .padding(.trailing, 2)

                            HStack(spacing: 14) {
                                ForEach(Array(state.dockApps.enumerated()), id: \.element.id) { index, app in
                                    let isSelected = (index == state.selectedDockIndex)
                                    ZStack {
                                        // Subtle underglow
                                        if isSelected {
                                            Ellipse()
                                                .fill(Color.white.opacity(0.12))
                                                .frame(width: 72, height: 20)
                                                .offset(y: 42)
                                                .blur(radius: 8)

                                            // Floating App Title Capsule
                                            Text(app.name)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4.5)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.black.opacity(0.80))
                                                        .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.8))
                                                )
                                                .shadow(color: Color.black.opacity(0.5), radius: 6, y: 3)
                                                .offset(y: -54)
                                                .transition(.opacity.combined(with: .scale(scale: 0.90)))
                                        }

                                        // Sliding Frosted Glass Selection Spotlight
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .fill(Color.white.opacity(0.18))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                        .strokeBorder(
                                                            LinearGradient(
                                                                colors: [
                                                                    Color.white.opacity(0.80),
                                                                    Color.white.opacity(0.25)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            ),
                                                            lineWidth: 1.2
                                                        )
                                                )
                                                .shadow(color: Color.white.opacity(0.20), radius: 12)
                                                .matchedGeometryEffect(id: "appSelectionCradle", in: animationNamespace)
                                        }

                                        Image(nsImage: app.icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: isSelected ? 62 : 48, height: isSelected ? 62 : 48)
                                            .shadow(color: Color.black.opacity(isSelected ? 0.45 : 0.20), radius: isSelected ? 10 : 4, y: isSelected ? 4 : 2)
                                    }
                                    .frame(width: 74, height: 74)
                                    .offset(y: isSelected ? -6 : 0)
                                    .scaleEffect(isSelected ? 1.16 : 0.94)
                                    .opacity(isSelected ? 1.0 : 0.55)
                                    .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isSelected)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelectApp?(app)
                                    }
                                }
                            }

                            // Right navigation chevron
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(state.selectedDockIndex < state.dockApps.count - 1 ? Color.white.opacity(0.70) : Color.white.opacity(0.15))
                                .padding(.leading, 2)
                        }

                        // Minimalist Pagination Indicators (Index Pill Dots)
                        HStack(spacing: 6) {
                            ForEach(0..<state.dockApps.count, id: \.self) { idx in
                                let isCurrent = (idx == state.selectedDockIndex)
                                Capsule()
                                    .fill(isCurrent ? Color.white : Color.white.opacity(0.20))
                                    .frame(width: isCurrent ? 16 : 4, height: 3.5)
                                    .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isCurrent)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color(red: 0.05, green: 0.06, blue: 0.09).opacity(0.88))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.10),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.60), radius: 40, x: 0, y: 18)
                    .shadow(color: Color.black.opacity(0.30), radius: 14, x: 0, y: 5)
                    .position(x: screenW * 0.50, y: dockCenterY)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }

                // 4. Center High-Tech Mode Transition Banner (Triggered by Clap)
                if state.isModeBannerVisible {
                    ModeTransitionBannerView(mode: state.currentMode)
                        .position(x: screenW * 0.50, y: screenH * 0.32)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Native Apple macOS Mode Transition Bezel (Anti-Vibecoded HUD)
struct ModeTransitionBannerView: View {
    let mode: SystemMode

    var body: some View {
        HStack(spacing: 14) {
            // Native SF Symbol Tile
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: mode.iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.white)

                Text(mode.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.65))
            }

            Spacer(minLength: 12)

            // Segmented mode indicator dots
            HStack(spacing: 5) {
                ForEach(SystemMode.allCases) { m in
                    Circle()
                        .fill(m == mode ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 5.5, height: 5.5)
                }
            }
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.88))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 10)
    }
}
