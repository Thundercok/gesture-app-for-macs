import Foundation
import AppKit

protocol ActionSink: AnyObject {
    func switchSpace(_ direction: ActionDispatcher.SpaceDirection)
    func playFeedback(named soundName: String)
    func playHaptic()
    func triggerMissionControl()
    func showDesktop()
    func pressEscape()
    func getRecentApps() -> [AppItem]
    func activate(app: AppItem)
    func releaseScrollWithMomentum(initialVelocityX: Double, initialVelocityY: Double)
    func cancelMomentumScroll()
    var isMomentumActive: Bool { get }
    var onMomentumProgress: ((Double) -> Void)? { get set }
    var onMomentumEnded: (() -> Void)? { get set }
}

final class LiveActionSink: ActionSink {
    static let shared = LiveActionSink()
    private init() {}

    func switchSpace(_ direction: ActionDispatcher.SpaceDirection) {
        ActionDispatcher.switchSpace(direction)
    }

    func playFeedback(named soundName: String) {
        ActionDispatcher.playFeedback(named: soundName)
    }

    func playHaptic() {
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func triggerMissionControl() {
        ActionDispatcher.triggerMissionControl()
    }

    func showDesktop() {
        ActionDispatcher.showDesktop()
    }

    func pressEscape() {
        ActionDispatcher.pressEscape()
    }

    func getRecentApps() -> [AppItem] {
        return ActionDispatcher.getRecentApps()
    }

    func activate(app: AppItem) {
        ActionDispatcher.activate(app: app)
    }

    func releaseScrollWithMomentum(initialVelocityX: Double, initialVelocityY: Double) {
        ActionDispatcher.releaseScrollWithMomentum(initialVelocityX: initialVelocityX, initialVelocityY: initialVelocityY)
    }

    func cancelMomentumScroll() {
        ActionDispatcher.cancelMomentumScroll()
    }

    var isMomentumActive: Bool {
        return ActionDispatcher.isMomentumActive
    }

    var onMomentumProgress: ((Double) -> Void)? {
        get { ActionDispatcher.onMomentumProgress }
        set { ActionDispatcher.onMomentumProgress = newValue }
    }

    var onMomentumEnded: (() -> Void)? {
        get { ActionDispatcher.onMomentumEnded }
        set { ActionDispatcher.onMomentumEnded = newValue }
    }
}

final class RecordingActionSink: ActionSink {
    struct DispatchedRecord: Equatable {
        let action: String
        let timestamp: TimeInterval
    }

    private let lock = NSLock()
    private(set) var actions: [String] = []
    private(set) var records: [DispatchedRecord] = []
    private var mockApps: [AppItem] = []
    private var momentumActive: Bool = false
    private let clock: Clock?

    init(clock: Clock? = nil, mockApps: [AppItem]? = nil) {
        self.clock = clock
        if let apps = mockApps {
            self.mockApps = apps
        } else {
            let app = NSRunningApplication.current
            self.mockApps = [
                AppItem(id: 101, name: "Finder", icon: NSImage(), runningApp: app),
                AppItem(id: 102, name: "Safari", icon: NSImage(), runningApp: app)
            ]
        }
    }

    func setMockApps(_ apps: [AppItem]) {
        lock.lock()
        defer { lock.unlock() }
        mockApps = apps
    }

    func switchSpace(_ direction: ActionDispatcher.SpaceDirection) {
        record(direction == .left ? "switchSpace_left" : "switchSpace_right")
    }

    func playFeedback(named soundName: String) {
        record("playFeedback_\(soundName)")
    }

    func playHaptic() {
        record("playHaptic")
    }

    func triggerMissionControl() {
        record("triggerMissionControl")
    }

    func showDesktop() {
        record("showDesktop")
    }

    func pressEscape() {
        record("press_escape")
    }

    func getRecentApps() -> [AppItem] {
        lock.lock()
        defer { lock.unlock() }
        return mockApps
    }

    func activate(app: AppItem) {
        record("activateApp_\(app.name)")
    }

    func releaseScrollWithMomentum(initialVelocityX: Double, initialVelocityY: Double) {
        record("releaseScrollWithMomentum_vy_\(initialVelocityY)")
        momentumActive = true
    }

    func cancelMomentumScroll() {
        record("cancelMomentumScroll")
        momentumActive = false
        onMomentumEnded?()
    }

    var isMomentumActive: Bool {
        return momentumActive
    }

    var onMomentumProgress: ((Double) -> Void)?
    var onMomentumEnded: (() -> Void)?

    private func record(_ action: String) {
        lock.lock()
        defer { lock.unlock() }
        actions.append(action)
        records.append(DispatchedRecord(action: action, timestamp: clock?.uptime ?? 0.0))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        actions.removeAll()
        records.removeAll()
        momentumActive = false
    }
}
