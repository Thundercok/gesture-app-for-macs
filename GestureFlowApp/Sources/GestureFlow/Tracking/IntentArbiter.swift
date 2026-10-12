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
    private var commitSequenceStorage: Int = 0
    private var lastCommittedStorage: GestureIntent = .idle
    private var lastCommittedActionStorage: String = ""

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

    func commitAction(gesture: GestureIntent, action: String = "", cooldown: TimeInterval? = nil, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        let duration = cooldown ?? defaultCooldownDuration
        cooldownUntil = now + duration
        lastActionTimestamp = now
        activeIntent = .cooldown
        commitSequenceStorage += 1
        lastCommittedStorage = gesture
        lastCommittedActionStorage = action.isEmpty ? gesture.rawValue : action
    }

    /// Monotonic counter incremented on every committed (fired) action.
    /// The dataset recorder diffs this per frame to log discrete fired events.
    var commitSequence: Int {
        lock.lock()
        defer { lock.unlock() }
        return commitSequenceStorage
    }

    /// The gesture domain of the most recently committed action.
    var lastCommitted: GestureIntent {
        lock.lock()
        defer { lock.unlock() }
        return lastCommittedStorage
    }

    /// The concrete action name of the most recently committed action (e.g. "swipe_left", "scroll_down").
    var lastCommittedActionName: String {
        lock.lock()
        defer { lock.unlock() }
        return lastCommittedActionStorage
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

