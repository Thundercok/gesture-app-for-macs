import Foundation
import AppKit
import ApplicationServices

struct AppItem: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage
    let runningApp: NSRunningApplication

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        return lhs.id == rhs.id
    }
}

enum ActionDispatcher {
    static var isSoundEnabled: Bool = true // Soft audio feedback for confirmed actions

    static func playFeedback(named soundName: String = "Pop") {
        if isSoundEnabled {
            NSSound(named: soundName)?.play()
        }

        // Multi-sensory tactile feedback on MacBook Force Touch trackpads (dispatched to main thread for reliable driver delivery)
        DispatchQueue.main.async {
            if soundName == "Tink" {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            } else if soundName == "Pop" || soundName == "Glass" || soundName == "Hero" {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    // MARK: - Hardware Media Keys (macOS SystemDefined Events)

    private static func postSystemDefinedKey(_ key: Int32) {
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = Int((key << 16) | (down ? 0xa00 : 0xb00))
            if let ev = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ), let cg = ev.cgEvent {
                cg.post(tap: .cghidEventTap)
            }
        }
        doKey(down: true)
        doKey(down: false)
    }

    /// Toggle Media Play / Pause (System-wide: Music, Spotify, YouTube, etc.)
    static func togglePlayPause() {
        postSystemDefinedKey(16) // NX_KEYTYPE_PLAY
    }

    /// Increase System Output Volume by 1 step
    static func volumeUp() {
        postSystemDefinedKey(0) // NX_KEYTYPE_SOUND_UP
    }

    /// Decrease System Output Volume by 1 step
    static func volumeDown() {
        postSystemDefinedKey(1) // NX_KEYTYPE_SOUND_DOWN
    }

    // MARK: - Spaces & Window Management

    enum SpaceDirection {
        case left
        case right
    }

    /// Switch Desktop Space Left or Right (Ctrl + Arrow)
    static func switchSpace(_ direction: SpaceDirection) {
        let keyCode: CGKeyCode = (direction == .left) ? 123 : 124 // 123: Left, 124: Right
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags = .maskControl
            up.flags = .maskControl
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Open Mission Control (Ctrl + Up Arrow)
    static func triggerMissionControl() {
        let keyCode: CGKeyCode = 126 // Up Arrow
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags = .maskControl
            up.flags = .maskControl
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Show Desktop (Cmd + F3)
    static func showDesktop() {
        let keyCode: CGKeyCode = 99 // F3
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Synthesize Escape key (keyCode 53) to exit Mission Control or modal overlays
    static func pressEscape() {
        let keyCode: CGKeyCode = 53
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Perform the inverse action for a recently auto-fired action (WP9.2, WP15).
    /// Returns a human-readable Vietnamese description of the inverse action performed, or nil if no inverse exists.
    @discardableResult
    static func performUndo(forAction action: String, sink: ActionSink = LiveActionSink.shared) -> String? {
        guard let inverseAction = UndoPlanner.inverse(for: action) else {
            return nil
        }
        switch inverseAction {
        case .switchSpace(let direction):
            sink.switchSpace(direction)
        case .pressEscape:
            sink.pressEscape()
        case .toggleShowDesktop:
            sink.showDesktop()
        }
        return UndoPlanner.description(for: inverseAction)
    }

    // MARK: - Air Scroll & Momentum Engine

    /// Query macOS "natural scrolling" preference from com.apple.AppleMultitouchTrackpad / GlobalPreferences
    static var isNaturalScrollingEnabled: Bool {
        if let globalVal = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, ".GlobalPreferences" as CFString) as? Bool {
            return globalVal
        }
        if let trackpad = UserDefaults.standard.persistentDomain(forName: "com.apple.AppleMultitouchTrackpad"),
           let scrollPref = trackpad["UserPreferences"] as? Int {
            return scrollPref != 0
        }
        return true // Default macOS behavior
    }

    private static var momentumTimer: DispatchSourceTimer?
    private static let momentumQueue = DispatchQueue(label: "com.gestureflow.momentumscroll", qos: .userInteractive)
    private static let momentumDecayFactor: Double = 0.942 // Smooth iOS-like ease-out decay per 16ms tick
    private static let momentumCutoffVelocity: Double = 0.8 // Cutoff threshold in pixels

    static var isMomentumActive: Bool {
        return momentumTimer != nil
    }

    static var onMomentumProgress: ((_ currentVelocityY: Double) -> Void)?
    static var onMomentumEnded: (() -> Void)?

    /// Direct scroll event respecting natural scrolling preference (2D vertical & horizontal)
    static func scroll(pixelDeltaX: Int32 = 0, pixelDeltaY: Int32) {
        let signY: Int32 = isNaturalScrollingEnabled ? 1 : -1
        let signX: Int32 = isNaturalScrollingEnabled ? 1 : -1
        let orientedDeltaY = pixelDeltaY * signY
        let orientedDeltaX = pixelDeltaX * signX
        if let scrollEv = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: orientedDeltaY,
            wheel2: orientedDeltaX,
            wheel3: 0
        ) {
            scrollEv.post(tap: .cghidEventTap)
        }
    }

    /// Implements momentum ease-out deceleration curve on gesture release (2D)
    static func releaseScrollWithMomentum(initialVelocityX: Double = 0.0, initialVelocityY: Double) {
        momentumTimer?.cancel()
        momentumTimer = nil

        var currentVelocityY = initialVelocityY
        var currentVelocityX = initialVelocityX
        guard abs(currentVelocityY) > momentumCutoffVelocity || abs(currentVelocityX) > momentumCutoffVelocity else {
            onMomentumEnded?()
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: momentumQueue)
        timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16))
        timer.setEventHandler {
            currentVelocityY *= momentumDecayFactor
            currentVelocityX *= momentumDecayFactor
            if abs(currentVelocityY) < momentumCutoffVelocity && abs(currentVelocityX) < momentumCutoffVelocity {
                momentumTimer?.cancel()
                momentumTimer = nil
                onMomentumEnded?()
                return
            }
            onMomentumProgress?(currentVelocityY)
            let deltaY = Int32(currentVelocityY.rounded())
            let deltaX = Int32(currentVelocityX.rounded())
            if deltaY != 0 || deltaX != 0 {
                scroll(pixelDeltaX: deltaX, pixelDeltaY: deltaY)
            }
        }
        momentumTimer = timer
        timer.resume()
    }

    // MARK: - Bimanual Spatial Zoom (System-wide Document / Canvas Zoom)

    private static var zoomAccumulator: CGFloat = 0.0
    private static let zoomStepThreshold: CGFloat = 0.030 // ~3cm hand displacement per zoom step

    /// Step Zoom In (Cmd + '+')
    static func zoomIn() {
        let keyCode: CGKeyCode = 24 // '=' / '+' key
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Step Zoom Out (Cmd + '-')
    static func zoomOut() {
        let keyCode: CGKeyCode = 27 // '-' key
        let src = CGEventSource(stateID: .hidSystemState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Continuous zoom driver: accumulates hand span delta and dispatches native zoom steps with haptic detents
    static func magnify(delta: CGFloat) {
        zoomAccumulator += delta
        if zoomAccumulator >= zoomStepThreshold {
            zoomIn()
            zoomAccumulator -= zoomStepThreshold
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        } else if zoomAccumulator <= -zoomStepThreshold {
            zoomOut()
            zoomAccumulator += zoomStepThreshold
            DispatchQueue.main.async {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    static func cancelMomentumScroll() {
        if momentumTimer != nil {
            momentumTimer?.cancel()
            momentumTimer = nil
            onMomentumEnded?()
        }
    }

    // MARK: - Application Switcher & Activation

    static func getRecentApps() -> [AppItem] {
        var result: [AppItem] = []
        var seenPIDs = Set<pid_t>()
        let myPID = NSRunningApplication.current.processIdentifier

        // 1. Get on-screen regular apps in exact Z-order (front to back)
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for win in windowList {
                guard let pid = win[kCGWindowOwnerPID as String] as? pid_t else { continue }
                if !seenPIDs.contains(pid) && pid != myPID {
                    seenPIDs.insert(pid)
                    if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                        let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
                        result.append(AppItem(id: pid, name: app.localizedName ?? "App", icon: icon, runningApp: app))
                    }
                }
            }
        }

        // 2. Append all other running regular apps
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != myPID
        }
        for app in regularApps {
            if !seenPIDs.contains(app.processIdentifier) {
                seenPIDs.insert(app.processIdentifier)
                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
                result.append(AppItem(id: app.processIdentifier, name: app.localizedName ?? "App", icon: icon, runningApp: app))
            }
        }

        // Ensure frontmost app is first
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           let frontIdx = result.firstIndex(where: { $0.id == frontmost.processIdentifier }) {
            let frontItem = result.remove(at: frontIdx)
            result.insert(frontItem, at: 0)
        }

        return Array(result.prefix(7))
    }

    static func activate(app: AppItem) {
        let runningApp = app.runningApp
        let pid = app.id

        if runningApp.isHidden {
            runningApp.unhide()
        }
        if #available(macOS 14.0, *) {
            runningApp.activate()
        } else {
            _ = runningApp.activate(options: [.activateIgnoringOtherApps])
        }

        if let bundleURL = runningApp.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            config.promptsUserIfNeeded = false
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config, completionHandler: nil)
        }

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var axWindows: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &axWindows) == .success,
           let windows = axWindows as? [AXUIElement], let frontWin = windows.first {
            AXUIElementPerformAction(frontWin, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(frontWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        }

        if let bundleId = runningApp.bundleIdentifier {
            let script = "tell application id \"\(bundleId)\" to activate"
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
            }
        }
    }
}
