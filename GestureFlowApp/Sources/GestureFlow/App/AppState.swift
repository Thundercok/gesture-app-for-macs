import AppKit
import SwiftUI
import Combine

enum CameraDisplayMode: String, CaseIterable, Identifiable {
    case minimal = "Minimal"
    case monochrome = "Monochrome"
    case cameraFeed = "Camera Feed"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .minimal: return "sparkles"
        case .monochrome: return "circle.lefthalf.filled"
        case .cameraFeed: return "video.fill"
        }
    }
    var localizedTitle: String {
        switch self {
        case .minimal: return "Tối giản (Vector)"
        case .monochrome: return "Đơn sắc (Monochrome)"
        case .cameraFeed: return "Hình ảnh Camera"
        }
    }
}

enum SystemMode: String, CaseIterable, Identifiable {
    case airScroll = "AIR_SCROLL"
    case macNavigation = "MAC_NAVIGATION"
    case spatialZoom = "SPATIAL_ZOOM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .airScroll: return "Air Scroll"
        case .macNavigation: return "Mac Navigation"
        case .spatialZoom: return "Spatial Zoom"
        }
    }

    var iconName: String {
        switch self {
        case .airScroll: return "arrow.up.and.down.circle.fill"
        case .macNavigation: return "macwindow.on.rectangle"
        case .spatialZoom: return "plus.magnifyingglass"
        }
    }

    var shortCode: String {
        switch self {
        case .airScroll: return "SCROLL"
        case .macNavigation: return "NAV"
        case .spatialZoom: return "ZOOM"
        }
    }

    var subtitle: String {
        switch self {
        case .airScroll: return "Hất tay để lướt như điện thoại"
        case .macNavigation: return "Vuốt ngang chuyển App • Vuốt lên Mission Control"
        case .spatialZoom: return "Đưa 2 tay ra xa / lại gần để thu phóng"
        }
    }

    func next() -> SystemMode {
        switch self {
        case .airScroll: return .macNavigation
        case .macNavigation: return .spatialZoom
        case .spatialZoom: return .airScroll
        }
    }
}

final class CurrentModeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _mode: SystemMode = .airScroll

    var mode: SystemMode {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _mode
        }
        set {
            lock.lock()
            _mode = newValue
            lock.unlock()
        }
    }

    init(mode: SystemMode = .airScroll) {
        self._mode = mode
    }
}

final class AppState: ObservableObject {
    static let undoOnMisfireKey = "gf.undoOnMisfire.v1"
    let currentModeBox = CurrentModeBox()

    @Published var currentFrame: NSImage?
    @Published var currentLandmarks: HandLandmarks?
    @Published var handDetected: Bool = false
    @Published var fingerCount: Int = 0
    @Published var fps: Int = 0
    @Published var latestAction: String?
    @Published var isAccessibilityTrusted: Bool = true
    @Published var isGestureActive: Bool = false
    @Published var isCrossed: Bool = false
    @Published var isTwoFingers: Bool = false
    @Published var isPinching: Bool = false
    @Published var gesturePoint: CGPoint = .zero
    @Published var dragDelta: CGSize = .zero
    @Published var cameraAspectRatio: CGFloat = 16.0 / 9.0

    // Air Scroll Engine State
    @Published var isAirScrollActive: Bool = false
    @Published var airScrollVelocity: Double = 0.0
    @Published var airScrollClutch: String? = nil
    @Published var airScrollDeltaY: CGFloat = 0.0

    // Camera Canvas Display Mode
    @Published var displayMode: CameraDisplayMode = .minimal

    func cycleDisplayMode() {
        switch displayMode {
        case .minimal: displayMode = .monochrome
        case .monochrome: displayMode = .cameraFeed
        case .cameraFeed: displayMode = .minimal
        }
    }

    // Spatial Multi-Mode Engine State (Clap Gesture Switcher)
    @Published var currentMode: SystemMode = .airScroll {
        didSet {
            currentModeBox.mode = currentMode
        }
    }
    @Published var isModeBannerVisible: Bool = false
    @Published var modeBannerTitle: String = ""
    @Published var modeBannerSubtitle: String = ""
    private var modeBannerTimer: AnyCancellable?

    func setMode(_ mode: SystemMode) {
        guard currentMode != mode else { return }
        currentMode = mode
        showModeBanner(title: currentMode.displayName, subtitle: currentMode.subtitle)
    }

    func cycleMode() {
        currentMode = currentMode.next()
        showModeBanner(title: currentMode.displayName, subtitle: currentMode.subtitle)
    }

    func showModeBanner(title: String, subtitle: String) {
        modeBannerTitle = title
        modeBannerSubtitle = subtitle
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            isModeBannerVisible = true
        }
        modeBannerTimer?.cancel()
        modeBannerTimer = Just(())
            .delay(for: .seconds(2.2), scheduler: RunLoop.main)
            .sink { [weak self] in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.isModeBannerVisible = false
                }
            }
    }

    // Spatial Application Switcher State
    @Published var isDockOpen: Bool = false
    @Published var dockApps: [AppItem] = []
    @Published var selectedDockIndex: Int = 0
    @Published var scanProgress: CGFloat = 0.0
    @Published var isArmed: Bool = false

    // Spatial Telemetry & Intentionality Gating Diagnostics
    @Published var estimatedDepth: CGFloat = 0.0
    @Published var facingCamera: Double = 1.0
    @Published var activeSuppressReason: String? = nil

    // Bimanual Spatial Interaction State (Two-Handed Zoom & Optical Caliper)
    @Published var secondaryLandmarks: HandLandmarks? = nil
    @Published var bimanualSpanMeters: CGFloat = 0.0
    @Published var bimanualZoomPercent: Int = 100
    @Published var isBimanualActive: Bool = false
    @Published var isDualPinchClutched: Bool = false
    @Published var isFramingZoomActive: Bool = false

    // Compact Mode State (Default true for sleek zero-distraction UX)
    @Published var isCompactHUD: Bool = true
    var onToggleCompact: ((Bool) -> Void)?

    // Dataset Recording State (Phase 1 Benchmark & Confusion Matrix)
    @Published var isRecordingDataset: Bool = false
    @Published var datasetLabel: String = "idle"

    // Why-not-recognised HUD Badge State (WP9.1)
    @Published var lastRejectReason: RejectReason? = nil
    private var rejectReasonTimer: AnyCancellable?

    // Undo on Misfire Feedback Loop (WP9.2, default false)
    @Published var undoOnMisfire: Bool = UserDefaults.standard.bool(forKey: AppState.undoOnMisfireKey) {
        didSet {
            UserDefaults.standard.set(undoOnMisfire, forKey: AppState.undoOnMisfireKey)
        }
    }

    private var actionTimer: AnyCancellable?

    func setRejectReason(_ reason: RejectReason?) {
        DispatchQueue.main.async {
            self.lastRejectReason = reason
            self.rejectReasonTimer?.cancel()
            guard reason != nil else { return }
            self.rejectReasonTimer = Just(())
                .delay(for: .seconds(1.0), scheduler: RunLoop.main)
                .sink { [weak self] in
                    self?.lastRejectReason = nil
                }
        }
    }

    func setAction(_ label: String) {
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.latestAction = label
            }
            self.actionTimer?.cancel()
            self.actionTimer = Just(())
                .delay(for: .seconds(1.2), scheduler: RunLoop.main)
                .sink { [weak self] in
                    withAnimation(.easeOut(duration: 0.2)) {
                        self?.latestAction = nil
                    }
                }
        }
    }
}
