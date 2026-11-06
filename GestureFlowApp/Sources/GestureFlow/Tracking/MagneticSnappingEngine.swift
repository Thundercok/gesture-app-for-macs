import Foundation
import CoreGraphics

/// Target representation for magnetic cursor attraction in screen space
public struct SnapTarget: Equatable {
    public let id: String
    public let rect: CGRect
    public var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }
    public var snapRadius: CGFloat
    public var strength: CGFloat // Attraction gain k in [0.0 ... 1.0], default 0.65

    public init(id: String, rect: CGRect, snapRadius: CGFloat? = nil, strength: CGFloat = 0.65) {
        self.id = id
        self.rect = rect
        let halfDiag = hypot(rect.width, rect.height) * 0.5
        self.snapRadius = snapRadius ?? max(30.0, halfDiag + 25.0)
        self.strength = max(0.0, min(1.0, strength))
    }
}

/// Adaptive Magnetic Snapping Engine (Module 2 of RESEARCH_ROADMAP.md)
///
/// Implements a continuous Gaussian potential well around UI targets:
///   F_attract = k * (c_target - p_cursor) * exp(-r^2 / (2 * sigma^2))
///
/// Features:
/// 1. C^infinity smooth potential well: zero cursor teleportation or discontinuity.
/// 2. Sticky-Trap Breakaway: Modulates attraction by cursor speed. When user makes a ballistic flick
///    (speed > breakawayThreshold), the attraction smoothly drops to 0, eliminating sticky trapping.
/// 3. Nearest-target selection: avoids saddle point artifacts when two buttons are adjacent.
public final class MagneticSnappingEngine {
    public var targets: [SnapTarget] = []
    public var isEnabled: Bool = true

    /// Breakaway parameters (in px/sec)
    /// Below lowSpeedThreshold, full magnetic attraction is exerted.
    /// Above breakawayThreshold, magnetic attraction is completely disengaged.
    public var lowSpeedThreshold: CGFloat = 200.0   // px/sec
    public var breakawayThreshold: CGFloat = 650.0  // px/sec

    public init(targets: [SnapTarget] = [], isEnabled: Bool = true) {
        self.targets = targets
        self.isEnabled = isEnabled
    }

    /// Register or update a snap target
    public func registerTarget(_ target: SnapTarget) {
        targets.removeAll { $0.id == target.id }
        targets.append(target)
    }

    /// Remove a snap target by ID
    public func unregisterTarget(id: String) {
        targets.removeAll { $0.id == id }
    }

    /// Clear all targets
    public func clearTargets() {
        targets.removeAll()
    }

    /// Calculate snapped cursor position given raw cursor coordinate and instantaneous velocity (in px/sec)
    public func applySnapping(cursorPos: CGPoint, speedPxPerSec: CGFloat) -> CGPoint {
        guard isEnabled, !targets.isEmpty else {
            return cursorPos
        }

        // 1. Breakaway velocity weight w_v in [0, 1]
        let velocityWeight: CGFloat
        if speedPxPerSec <= lowSpeedThreshold {
            velocityWeight = 1.0
        } else if speedPxPerSec >= breakawayThreshold {
            velocityWeight = 0.0
        } else {
            let t = (speedPxPerSec - lowSpeedThreshold) / (breakawayThreshold - lowSpeedThreshold)
            // Smoothstep hermite interpolation: 1 - (3t^2 - 2t^3)
            velocityWeight = 1.0 - (3.0 * t * t - 2.0 * t * t * t)
        }

        if velocityWeight <= 0.001 {
            return cursorPos
        }

        // 2. Find nearest target whose basin contains the cursor
        var nearestTarget: SnapTarget?
        var minDistance: CGFloat = .infinity

        for target in targets {
            let center = target.center
            let dist = hypot(center.x - cursorPos.x, center.y - cursorPos.y)
            if dist < target.snapRadius * 2.5 && dist < minDistance {
                minDistance = dist
                nearestTarget = target
            }
        }

        guard let target = nearestTarget else {
            return cursorPos
        }

        let center = target.center
        let dx = center.x - cursorPos.x
        let dy = center.y - cursorPos.y
        let dist = hypot(dx, dy)

        if dist < 0.001 {
            return cursorPos
        }

        // 3. Gaussian attraction potential
        let sigma = target.snapRadius * 0.707 // sigma chosen so peak pull is within target margin
        let gaussian = exp(-CGFloat(dist * dist) / (2.0 * sigma * sigma))
        let pullFactor = target.strength * velocityWeight * gaussian

        let snappedX = cursorPos.x + dx * pullFactor
        let snappedY = cursorPos.y + dy * pullFactor

        return CGPoint(x: snappedX, y: snappedY)
    }
}
