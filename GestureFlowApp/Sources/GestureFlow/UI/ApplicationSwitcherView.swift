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

                    // Bimanual Spatial Interaction (Photographer's Viewfinder Frame)
                    if state.isBimanualActive, let p = state.currentLandmarks, let s = state.secondaryLandmarks {
                        let pScreen = CGPoint(x: (1.0 - p.handCentroid.x) * screenW, y: p.handCentroid.y * screenH)
                        let sScreen = CGPoint(x: (1.0 - s.handCentroid.x) * screenW, y: s.handCentroid.y * screenH)
                        let midPt = CGPoint(x: (pScreen.x + sScreen.x) / 2.0, y: (pScreen.y + sScreen.y) / 2.0)
                        let isFraming = state.isFramingZoomActive

                        if isFraming {
                            // 1. PHOTOGRAPHER'S VIEWFINDER FRAME (Corner Brackets ⌜ ⌝ ⌞ ⌟)
                            let pTipScreen = CGPoint(x: (1.0 - p.indexTip.x) * screenW, y: p.indexTip.y * screenH)
                            let sTipScreen = CGPoint(x: (1.0 - s.indexTip.x) * screenW, y: s.indexTip.y * screenH)
                            let pThumbScreen = CGPoint(x: (1.0 - p.thumbTip.x) * screenW, y: p.thumbTip.y * screenH)
                            let sThumbScreen = CGPoint(x: (1.0 - s.thumbTip.x) * screenW, y: s.thumbTip.y * screenH)

                            let allX = [pTipScreen.x, sTipScreen.x, pThumbScreen.x, sThumbScreen.x]
                            let allY = [pTipScreen.y, sTipScreen.y, pThumbScreen.y, sThumbScreen.y]

                            let rawMinX = allX.min() ?? (midPt.x - 100)
                            let rawMaxX = allX.max() ?? (midPt.x + 100)
                            let rawMinY = allY.min() ?? (midPt.y - 80)
                            let rawMaxY = allY.max() ?? (midPt.y + 80)

                            let centerBox = CGPoint(x: (rawMinX + rawMaxX) / 2.0, y: (rawMinY + rawMaxY) / 2.0)
                            let boxW = max(140.0, (rawMaxX - rawMinX) + 40.0)
                            let boxH = max(100.0, max(boxW * 0.55, (rawMaxY - rawMinY) + 40.0))

                            let minX = centerBox.x - boxW / 2.0
                            let maxX = centerBox.x + boxW / 2.0
                            let minY = centerBox.y - boxH / 2.0
                            let maxY = centerBox.y + boxH / 2.0
                            let bLen: CGFloat = min(28.0, min(boxW, boxH) * 0.35)

                            // Frame Border (Subtle dashed line)
                            Path { path in
                                path.addRect(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
                            }
                            .stroke(
                                Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.32),
                                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [6, 6])
                            )

                            // 4 Corner Brackets ⌜ ⌝ ⌞ ⌟
                            Path { path in
                                // Top-Left ⌜
                                path.move(to: CGPoint(x: minX, y: minY + bLen))
                                path.addLine(to: CGPoint(x: minX, y: minY))
                                path.addLine(to: CGPoint(x: minX + bLen, y: minY))
                                // Top-Right ⌝
                                path.move(to: CGPoint(x: maxX - bLen, y: minY))
                                path.addLine(to: CGPoint(x: maxX, y: minY))
                                path.addLine(to: CGPoint(x: maxX, y: minY + bLen))
                                // Bottom-Left ⌞
                                path.move(to: CGPoint(x: minX, y: maxY - bLen))
                                path.addLine(to: CGPoint(x: minX, y: maxY))
                                path.addLine(to: CGPoint(x: minX + bLen, y: maxY))
                                // Bottom-Right ⌟
                                path.move(to: CGPoint(x: maxX - bLen, y: maxY))
                                path.addLine(to: CGPoint(x: maxX, y: maxY))
                                path.addLine(to: CGPoint(x: maxX, y: maxY - bLen))
                            }
                            .stroke(
                                Color(red: 0.0, green: 0.95, blue: 0.70),
                                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .miter)
                            )
                            .shadow(color: Color(red: 0.0, green: 0.95, blue: 0.70).opacity(0.70), radius: 6)

                            // Center Viewfinder Crosshair (+)
                            Path { path in
                                path.move(to: CGPoint(x: midPt.x - 10, y: midPt.y))
                                path.addLine(to: CGPoint(x: midPt.x + 10, y: midPt.y))
                                path.move(to: CGPoint(x: midPt.x, y: midPt.y - 10))
                                path.addLine(to: CGPoint(x: midPt.x, y: midPt.y + 10))
                            }
                            .stroke(Color.white.opacity(0.60), lineWidth: 1.5)

                            // Viewfinder Readout Capsule
                            HStack(spacing: 8) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.70))

                                Text("VIEWFINDER ZOOM")
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
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.90))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color(red: 0.0, green: 0.95, blue: 0.70).opacity(0.50), lineWidth: 1.0)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.40), radius: 10, y: 3)
                            .position(CGPoint(x: midPt.x, y: maxY + 24))
                            .animation(.spring(response: 0.20, dampingFraction: 0.80), value: isFraming)

                        } else {
                            // Viewfinder Standby Guide (Subtle tether & instruction pill)
                            Path { path in
                                path.move(to: pScreen)
                                path.addLine(to: sScreen)
                            }
                            .stroke(
                                Color.white.opacity(0.20),
                                style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [4, 6])
                            )

                            // Viewfinder Standby Capsule
                            HStack(spacing: 8) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.60))

                                Text("SPATIAL ZOOM")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.85))

                                Rectangle()
                                    .fill(Color.white.opacity(0.20))
                                    .frame(width: 1, height: 10)

                                Text("KÉO 2 TAY RA XA / LẠI GẦN ĐỂ THU PHÓNG")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.70))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.88))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.40), radius: 10, y: 3)
                            .position(midPt)
                        }
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

                // 5. Spatial Air Scroll HUD & Reticle (When in Air Scroll Mode)
                if state.currentMode == .airScroll && (state.isAirScrollActive || (state.currentLandmarks?.isTwoFingers == true && state.currentLandmarks?.isInInteractionRange == true)) {
                    SpatialAirScrollView(state: state, screenW: screenW, screenH: screenH)
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

// MARK: - Native Apple VisionOS Spatial Air Scroll HUD & Reticle
struct SpatialAirScrollView: View {
    @ObservedObject var state: AppState
    let screenW: CGFloat
    let screenH: CGFloat

    var body: some View {
        let handPt = CGPoint(
            x: max(80, min(screenW - 80, state.gesturePoint.x * screenW + 55)),
            y: max(90, min(screenH - 90, state.gesturePoint.y * screenH))
        )

        let isScrollingUp = state.airScrollVelocity > 0.05
        let isScrollingDown = state.airScrollVelocity < -0.05
        let pearlOffset: CGFloat = {
            if isScrollingDown {
                return min(46.0, max(0.0, CGFloat(-state.airScrollVelocity * 45.0)))
            } else if isScrollingUp {
                return max(-46.0, min(0.0, CGFloat(-state.airScrollVelocity * 45.0)))
            } else {
                return 0.0
            }
        }()

        VStack(spacing: 8) {
            ZStack {
                // Frosted Glass Vertical Cylinder Track
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.88))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                                lineWidth: 1.0
                            )
                    )
                    .frame(width: 44, height: 140)

                VStack(spacing: 0) {
                    // Top Arrow (Scrolled Up Indicator)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isScrollingUp ? Color(red: 0.0, green: 0.88, blue: 1.0) : Color.white.opacity(0.30))
                        .scaleEffect(isScrollingUp ? 1.30 : 1.0)
                        .padding(.top, 12)
                        .animation(.easeOut(duration: 0.15), value: isScrollingUp)

                    Spacer()

                    // Center Guideline / Scale Tick
                    Rectangle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 14, height: 1)

                    Spacer()

                    // Bottom Arrow (Scrolled Down Indicator)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isScrollingDown ? Color(red: 0.0, green: 0.88, blue: 1.0) : Color.white.opacity(0.30))
                        .scaleEffect(isScrollingDown ? 1.30 : 1.0)
                        .padding(.bottom, 12)
                        .animation(.easeOut(duration: 0.15), value: isScrollingDown)
                }
                .frame(width: 44, height: 140)

                // Glowing Tactile Pearl Thumb
                ZStack {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.30))
                        .frame(width: 26, height: 26)
                        .blur(radius: 6)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white,
                                    Color(red: 0.0, green: 0.88, blue: 1.0)
                                ],
                                center: .center,
                                startRadius: 1,
                                endRadius: 10
                            )
                        )
                        .frame(width: 18, height: 18)
                        .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0).opacity(0.6), radius: 6)
                }
                .offset(y: pearlOffset)
                .animation(.spring(response: 0.20, dampingFraction: 0.72), value: pearlOffset)
            }
            .shadow(color: Color.black.opacity(0.50), radius: 20, y: 8)

            // Dynamic Status Badge
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.0, green: 0.85, blue: 1.0))
                    .frame(width: 5, height: 5)
                    .shadow(color: Color(red: 0.0, green: 0.85, blue: 1.0), radius: 3)

                Text(state.isAirScrollActive ? (isScrollingDown ? "Lướt xuống ↓" : "Lướt lên ↑") : "Flick để lướt")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.90))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            )
            .shadow(color: Color.black.opacity(0.40), radius: 8, y: 3)
        }
        .position(handPt)
        .transition(.scale(scale: 0.88).combined(with: .opacity))
    }
}
