import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSPanel?
    var dockPanel: NSPanel?
    var statusItem: NSStatusItem?
    let appState = AppState()
    let cameraManager = CameraManager()
    let tracker = HandTracker()
    let engine = GestureEngine()
    let scrollEngine = ScrollEngine()

    var frameCount = 0
    var lastRecordedCommitSequence = 0
    var guidedSession: GuidedSession?
    var fpsTimer = Date()
    var lastHandSeenTime = Date()
    var previousBimanualSpan: CGFloat = 0.0
    var cumulativeBimanualScale: CGFloat = 1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.onToggleCompact = { [weak self] compact in
            self?.setCompactHUD(compact)
        }
        setupMenuBar()
        setupKeyboardMonitoring()
        checkPermissions()
        setupWindow()
        setupDockPanel()
        setupPipeline()

        if let i = CommandLine.arguments.firstIndex(of: "--record") {
            let targetPath: String
            if i + 1 < CommandLine.arguments.count && !CommandLine.arguments[i + 1].hasPrefix("--") {
                targetPath = CommandLine.arguments[i + 1]
            } else {
                let df = DateFormatter()
                df.dateFormat = "yyyyMMdd_HHmmss"
                let defaultName = "gestures_\(df.string(from: Date())).jsonl"
                let defaultDir = ("~/Library/Application Support/GestureFlow/recordings" as NSString).expandingTildeInPath
                targetPath = "\(defaultDir)/\(defaultName)"
            }
            if DatasetRecorder.shared.startRecording(toPath: targetPath) {
                appState.isRecordingDataset = true
                appState.datasetLabel = DatasetRecorder.shared.currentLabel
            }
        }

        if let i = CommandLine.arguments.firstIndex(of: "--record-depth"), i + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[i + 1]
            DepthRecorder.shared.begin(
                path: path,
                width: cameraManager.bufferWidth,
                height: cameraManager.bufferHeight,
                device: cameraManager.deviceName
            )
        }

        if CommandLine.arguments.contains("--guided") {
            startGuidedSession()
        }
    }

    func startGuidedSession() {
        if !DatasetRecorder.shared.isRecording {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            let defaultDir = ("~/Library/Application Support/GestureFlow/recordings" as NSString).expandingTildeInPath
            let path = "\(defaultDir)/guided_\(df.string(from: Date())).jsonl"
            guard DatasetRecorder.shared.startRecording(toPath: path) else { return }
            appState.isRecordingDataset = true
        }
        let session = GuidedSession()
        DatasetRecorder.shared.labelsLocked = true
        session.onStep = { [weak self] label, display, index, total in
            self?.appState.datasetLabel = label
            self?.appState.setAction("[\(index + 1)/\(total)] \(display)")
        }
        session.onFinish = { [weak self] in
            DatasetRecorder.shared.labelsLocked = false
            DatasetRecorder.shared.stopRecording()
            self?.appState.isRecordingDataset = false
            self?.appState.setAction("Hoàn tất phiên thu dữ liệu")
            self?.guidedSession = nil
        }
        guidedSession = session
        print("[GuidedSession] Starting: ~\(Int(session.totalDuration / 60)) min. Follow the voice cues.")
        // Short lead-in so the user can position themselves in front of the camera.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { session.start() }
    }

    func setCompactHUD(_ compact: Bool) {
        guard let panel = self.window, let screen = NSScreen.main else { return }
        appState.isCompactHUD = compact
        let width: CGFloat = compact ? 252 : 380
        let height: CGFloat = compact ? 40 : 325
        let padding: CGFloat = 20
        let newOrigin = CGPoint(
            x: screen.visibleFrame.maxX - width - padding,
            y: screen.visibleFrame.maxY - height - padding
        )
        let newFrame = NSRect(origin: newOrigin, size: CGSize(width: width, height: height))
        panel.setFrame(newFrame, display: true, animate: false)
        if let hostingView = panel.contentView {
            hostingView.layer?.cornerRadius = compact ? 16 : 18
            hostingView.layer?.masksToBounds = true
        }
        panel.invalidateShadow()
    }

    @objc func toggleCompact() {
        setCompactHUD(!appState.isCompactHUD)
    }

    @objc func toggleHUD() {
        guard let panel = self.window else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quitApp() {
        DatasetRecorder.shared.stopRecording()
        NSApp.terminate(nil)
    }

    func checkPermissions() {
        let trusted = AXIsProcessTrusted()
        appState.isAccessibilityTrusted = trusted
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func setupWindow() {
        guard let screen = NSScreen.main else { return }

        let width: CGFloat = 252
        let height: CGFloat = 40
        let padding: CGFloat = 20

        let origin = CGPoint(
            x: screen.visibleFrame.maxX - width - padding,
            y: screen.visibleFrame.maxY - height - padding
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: CGSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "GestureFlow HUD"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: HUDView(state: appState, onHide: { [weak self] in
                self?.window?.orderOut(nil)
            })
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.cornerRadius = 16
        hostingView.layer?.masksToBounds = true

        panel.contentView = hostingView
        panel.invalidateShadow()
        panel.orderOut(nil)
        self.window = panel
    }

    func setupDockPanel() {
        guard let screen = NSScreen.main else { return }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "GestureFlow Spatial Switcher"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(
            rootView: ApplicationSwitcherView(state: appState, onSelectApp: { [weak self] target in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.dockPanel?.orderOut(nil)
                    self.appState.isDockOpen = false
                    ActionDispatcher.activate(app: target)
                }
            })
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.contentView = hostingView
        self.dockPanel = panel
    }

    func applicationWillTerminate(_ notification: Notification) {
        DatasetRecorder.shared.stopRecording()
        cameraManager.stop()
    }
}
