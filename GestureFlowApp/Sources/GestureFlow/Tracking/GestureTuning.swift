import Foundation
import CoreGraphics

enum TuningPreset: String, CaseIterable, Codable {
    case safe = "safe"
    case balanced = "balanced"
    case sensitive = "sensitive"
    case custom = "custom"
}

/// Central Gesture Tuning parameters.
/// Controls motion thresholds, dwelling times, and refractory cooldowns across engines.
struct GestureTuning: Codable, Equatable {
    var preset: TuningPreset = .balanced

    // Swipes
    var swipeMinDisplacement: CGFloat      // Baseline: 0.065
    var swipeMinVelocity: Double           // Baseline: 0.50
    var swipeAxisDominance: CGFloat        // Baseline: 1.30
    var openPalmDwellSeconds: Double       // Baseline: 0.05 (~3 frames at 60fps)
    var pinchCalmHandSpeed: Double         // Baseline: 0.42
    var postPinchSwipeGuardSeconds: Double // Baseline: 0.35
    var swipeCooldownSeconds: Double       // Baseline: 0.45

    // Scroll flicks
    var scrollFlickMinVelocity: Double     // Baseline: 0.42 (from ScrollEngine.swift)

    // Learned Posture Shadow Mode (WP7)
    var useLearnedPosture: Bool = false    // Default false, cannot be flipped without gate passing and user approval

    enum CodingKeys: String, CodingKey {
        case preset
        case swipeMinDisplacement
        case swipeMinVelocity
        case swipeAxisDominance
        case openPalmDwellSeconds
        case pinchCalmHandSpeed
        case postPinchSwipeGuardSeconds
        case swipeCooldownSeconds
        case scrollFlickMinVelocity
        case useLearnedPosture
    }

    init(
        preset: TuningPreset = .balanced,
        swipeMinDisplacement: CGFloat,
        swipeMinVelocity: Double,
        swipeAxisDominance: CGFloat,
        openPalmDwellSeconds: Double,
        pinchCalmHandSpeed: Double,
        postPinchSwipeGuardSeconds: Double,
        swipeCooldownSeconds: Double,
        scrollFlickMinVelocity: Double,
        useLearnedPosture: Bool = false
    ) {
        self.preset = preset
        self.swipeMinDisplacement = swipeMinDisplacement
        self.swipeMinVelocity = swipeMinVelocity
        self.swipeAxisDominance = swipeAxisDominance
        self.openPalmDwellSeconds = openPalmDwellSeconds
        self.pinchCalmHandSpeed = pinchCalmHandSpeed
        self.postPinchSwipeGuardSeconds = postPinchSwipeGuardSeconds
        self.swipeCooldownSeconds = swipeCooldownSeconds
        self.scrollFlickMinVelocity = scrollFlickMinVelocity
        self.useLearnedPosture = useLearnedPosture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedPreset = try? container.decode(TuningPreset.self, forKey: .preset) {
            self.preset = decodedPreset
        } else {
            self.preset = .balanced
        }
        self.swipeMinDisplacement = try container.decode(CGFloat.self, forKey: .swipeMinDisplacement)
        self.swipeMinVelocity = try container.decode(Double.self, forKey: .swipeMinVelocity)
        self.swipeAxisDominance = try container.decode(CGFloat.self, forKey: .swipeAxisDominance)
        self.openPalmDwellSeconds = try container.decode(Double.self, forKey: .openPalmDwellSeconds)
        self.pinchCalmHandSpeed = try container.decode(Double.self, forKey: .pinchCalmHandSpeed)
        self.postPinchSwipeGuardSeconds = try container.decode(Double.self, forKey: .postPinchSwipeGuardSeconds)
        self.swipeCooldownSeconds = try container.decode(Double.self, forKey: .swipeCooldownSeconds)
        self.scrollFlickMinVelocity = try container.decode(Double.self, forKey: .scrollFlickMinVelocity)
        self.useLearnedPosture = try container.decodeIfPresent(Bool.self, forKey: .useLearnedPosture) ?? false
    }

    // MARK: - Presets

    /// Balanced: EXACTLY the baseline behaviour (regression-safe parity)
    static let balanced = GestureTuning(
        preset: .balanced,
        swipeMinDisplacement: 0.065,
        swipeMinVelocity: 0.50,
        swipeAxisDominance: 1.30,
        openPalmDwellSeconds: 0.05,
        pinchCalmHandSpeed: 0.42,
        postPinchSwipeGuardSeconds: 0.35,
        swipeCooldownSeconds: 0.45,
        scrollFlickMinVelocity: 0.42,
        useLearnedPosture: false
    )

    /// Safe: stricter thresholds to minimize false triggers during typing / talking / resting
    static let safe = GestureTuning(
        preset: .safe,
        swipeMinDisplacement: 0.085,
        swipeMinVelocity: 0.65,
        swipeAxisDominance: 1.50,
        openPalmDwellSeconds: 0.15,
        pinchCalmHandSpeed: 0.32,
        postPinchSwipeGuardSeconds: 0.50,
        swipeCooldownSeconds: 0.55,
        scrollFlickMinVelocity: 0.55,
        useLearnedPosture: false
    )

    /// Sensitive: lower thresholds for quick, effortless spatial triggers
    static let sensitive = GestureTuning(
        preset: .sensitive,
        swipeMinDisplacement: 0.055,
        swipeMinVelocity: 0.40,
        swipeAxisDominance: 1.20,
        openPalmDwellSeconds: 0.03,
        pinchCalmHandSpeed: 0.50,
        postPinchSwipeGuardSeconds: 0.25,
        swipeCooldownSeconds: 0.38,
        scrollFlickMinVelocity: 0.35,
        useLearnedPosture: false
    )

    static func preset(for preset: TuningPreset) -> GestureTuning {
        switch preset {
        case .safe: return .safe
        case .balanced: return .balanced
        case .sensitive: return .sensitive
        case .custom:
            var c = GestureTuning.balanced
            c.preset = .custom
            return c
        }
    }

    static func lerp(_ a: GestureTuning, _ b: GestureTuning, t: Double) -> GestureTuning {
        let clamped = max(0.0, min(1.0, t))
        let cgT = CGFloat(clamped)
        return GestureTuning(
            preset: .balanced,
            swipeMinDisplacement: a.swipeMinDisplacement + (b.swipeMinDisplacement - a.swipeMinDisplacement) * cgT,
            swipeMinVelocity: a.swipeMinVelocity + (b.swipeMinVelocity - a.swipeMinVelocity) * clamped,
            swipeAxisDominance: a.swipeAxisDominance + (b.swipeAxisDominance - a.swipeAxisDominance) * cgT,
            openPalmDwellSeconds: a.openPalmDwellSeconds + (b.openPalmDwellSeconds - a.openPalmDwellSeconds) * clamped,
            pinchCalmHandSpeed: a.pinchCalmHandSpeed + (b.pinchCalmHandSpeed - a.pinchCalmHandSpeed) * clamped,
            postPinchSwipeGuardSeconds: a.postPinchSwipeGuardSeconds + (b.postPinchSwipeGuardSeconds - a.postPinchSwipeGuardSeconds) * clamped,
            swipeCooldownSeconds: a.swipeCooldownSeconds + (b.swipeCooldownSeconds - a.swipeCooldownSeconds) * clamped,
            scrollFlickMinVelocity: a.scrollFlickMinVelocity + (b.scrollFlickMinVelocity - a.scrollFlickMinVelocity) * clamped,
            useLearnedPosture: false
        )
    }

    // MARK: - Thread-safe Global Storage & Persistence

    private static let lock = NSLock()
    private static let userDefaultsKey = "gf.tuning.v1"

    private static var _current: GestureTuning = {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode(GestureTuning.self, from: data) {
            return decoded
        }
        return .balanced
    }()

    static var current: GestureTuning {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _current
        }
        set {
            lock.lock()
            _current = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
            lock.unlock()
        }
    }
}
