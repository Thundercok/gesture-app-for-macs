import Foundation
import CoreGraphics

enum GestureIntent: String, Equatable, CaseIterable {
    case idle = "idle"
    case pinchDock = "pinch_dock"
    case swipe = "swipe"
    case airScroll = "air_scroll"
    case spatialZoom = "spatial_zoom"
    case cooldown = "cooldown"
}

/// Unified Intent Arbiter: Prevents cross-gesture interference and race conditions
/// Guarantees that at any instant, exactly one gesture domain owns interaction.
final class IntentArbiter {
    static let shared = IntentArbiter()

    private let lock = NSLock()
    private(set) var activeIntent: GestureIntent = .idle
    private var cooldownUntil: TimeInterval = 0.0
    private var lastActionTimestamp: TimeInterval = 0.0

    let defaultCooldownDuration: TimeInterval = 0.380

    private init() {}

    func canBegin(intent: GestureIntent, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {

        lock.lock()
        defer { lock.unlock() }

        if now < cooldownUntil {
            return false
        }
        if activeIntent == .cooldown {
            activeIntent = .idle
        }
        if activeIntent == .idle || activeIntent == intent {
            return true
        }
        return false
    }

    func claim(intent: GestureIntent) {
        lock.lock()
        defer { lock.unlock() }
        activeIntent = intent
    }

    func release(intent: GestureIntent) {
        lock.lock()
        defer { lock.unlock() }
        if activeIntent == intent {
            activeIntent = .idle
        }
    }

    func commitAction(gesture: GestureIntent, cooldown: TimeInterval? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        let duration = cooldown ?? defaultCooldownDuration
        cooldownUntil = now + duration
        lastActionTimestamp = now
        activeIntent = .cooldown
    }

    func forceReset() {
        lock.lock()
        defer { lock.unlock() }
        activeIntent = .idle
        cooldownUntil = 0.0
    }

    var isInCooldown: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime < cooldownUntil
    }

    var currentIntent: GestureIntent {
        lock.lock()
        defer { lock.unlock() }
        if ProcessInfo.processInfo.systemUptime >= cooldownUntil && activeIntent == .cooldown {
            activeIntent = .idle
        }

        return activeIntent
    }
}

