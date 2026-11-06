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

    // Spatial Air Cursor & Mouse Actions
    func mouseMove(to point: CGPoint)
    func mouseDown(at point: CGPoint)
    func mouseDragged(to point: CGPoint)
    func mouseUp(at point: CGPoint)
    func mouseClick(at point: CGPoint)
    func mouseClick(at point: CGPoint, clickCount: Int)
    func rightMouseDown(at point: CGPoint)
    func rightMouseUp(at point: CGPoint)
    func rightClick(at point: CGPoint)
    func scrollWheel(deltaX: CGFloat, deltaY: CGFloat)
    func magnifyContinuous(delta: CGFloat)
}

extension ActionSink {
    func mouseClick(at point: CGPoint) {
        mouseClick(at: point, clickCount: 1)
    }
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

    func mouseMove(to point: CGPoint) {
        ActionDispatcher.mouseMove(to: point)
    }

    func mouseDown(at point: CGPoint) {
        ActionDispatcher.mouseDown(at: point)
    }

    func mouseDragged(to point: CGPoint) {
        ActionDispatcher.mouseDragged(to: point)
    }

    func mouseUp(at point: CGPoint) {
        ActionDispatcher.mouseUp(at: point)
    }

    func mouseClick(at point: CGPoint) {
        ActionDispatcher.mouseClick(at: point, clickCount: 1)
    }

    func mouseClick(at point: CGPoint, clickCount: Int) {
        ActionDispatcher.mouseClick(at: point, clickCount: clickCount)
    }

    func rightMouseDown(at point: CGPoint) {
        ActionDispatcher.rightMouseDown(at: point)
    }

    func rightMouseUp(at point: CGPoint) {
        ActionDispatcher.rightMouseUp(at: point)
    }

    func rightClick(at point: CGPoint) {
        ActionDispatcher.rightClick(at: point)
    }

    func scrollWheel(deltaX: CGFloat, deltaY: CGFloat) {
        ActionDispatcher.scrollWheel(deltaX: deltaX, deltaY: deltaY)
    }

    func magnifyContinuous(delta: CGFloat) {
        ActionDispatcher.magnifyContinuous(delta: delta)
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

    func mouseMove(to point: CGPoint) {
        record("mouse_move_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func mouseDown(at point: CGPoint) {
        record("mouse_down_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func mouseDragged(to point: CGPoint) {
        record("mouse_dragged_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func mouseUp(at point: CGPoint) {
        record("mouse_up_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func mouseClick(at point: CGPoint) {
        mouseClick(at: point, clickCount: 1)
    }

    func mouseClick(at point: CGPoint, clickCount: Int) {
        if clickCount > 1 {
            record("mouse_double_click_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
        } else {
            record("mouse_click_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
        }
    }

    func rightMouseDown(at point: CGPoint) {
        record("right_mouse_down_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func rightMouseUp(at point: CGPoint) {
        record("right_mouse_up_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func rightClick(at point: CGPoint) {
        record("right_click_\(Int(point.x.rounded()))_\(Int(point.y.rounded()))")
    }

    func scrollWheel(deltaX: CGFloat, deltaY: CGFloat) {
        record(String(format: "scroll_wheel_dx_%.1f_dy_%.1f", deltaX, deltaY))
    }

    func magnifyContinuous(delta: CGFloat) {
        record(String(format: "magnify_continuous_%.4f", delta))
    }

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

