import Foundation
import CoreGraphics

/// Pure mathematical routines for calibration measurement and threshold derivation (WP9.3, WP16).
/// Replicates GestureEngine.evaluateSwipe windowing constants to ensure calibration matches the engine exactly.
enum CalibrationMath {

    /// Replicates evaluateSwipe's windowed peak horizontal velocity:
    /// For each sample index `i`, considers offsets 3...min(7, i).
    /// For sample pairs with 0.035 <= dt <= 0.180, computes |dx| / dt.
    /// Returns the maximum observed velocity, or 0.0 if insufficient samples.
    static func windowedPeakVelocity(samples: [(point: CGPoint, t: TimeInterval)]) -> Double {
        guard samples.count >= 4 else { return 0.0 }
        var maxVx: Double = 0.0
        for i in 3..<samples.count {
            for offset in 3...min(7, i) {
                let oldSample = samples[i - offset]
                let dt = samples[i].t - oldSample.t
                guard dt >= 0.035 && dt <= 0.180 else { continue }
                let dx = samples[i].point.x - oldSample.point.x
                let vx = Double(abs(dx)) / dt
                if vx > maxVx {
                    maxVx = vx
                }
            }
        }
        return maxVx
    }

    /// Replicates evaluateSwipe's windowed peak horizontal displacement:
    /// For each sample index `i`, considers offsets 3...min(7, i).
    /// For sample pairs with 0.035 <= dt <= 0.180, computes |dx|.
    /// Returns the maximum observed displacement, or 0.0 if insufficient samples.
    static func windowedPeakDisplacement(samples: [(point: CGPoint, t: TimeInterval)]) -> Double {
        guard samples.count >= 4 else { return 0.0 }
        var maxDisp: Double = 0.0
        for i in 3..<samples.count {
            for offset in 3...min(7, i) {
                let oldSample = samples[i - offset]
                let dt = samples[i].t - oldSample.t
                guard dt >= 0.035 && dt <= 0.180 else { continue }
                let dx = samples[i].point.x - oldSample.point.x
                let disp = Double(abs(dx))
                if disp > maxDisp {
                    maxDisp = disp
                }
            }
        }
        return maxDisp
    }

    /// Derives swipeMinVelocity and swipeMinDisplacement as a fraction of median user motion.
    /// Velocity is clamped to [0.30, 0.85].
    /// Displacement is clamped to [0.045, 0.110].
    static func derive(
        medianVelocity: Double,
        medianDisplacement: Double,
        fraction: Double = 0.65
    ) -> (velocity: Double, displacement: Double) {
        let derivedVel = max(0.30, min(0.85, medianVelocity * fraction))
        let derivedDisp = max(0.045, min(0.110, medianDisplacement * fraction))
        return (velocity: derivedVel, displacement: derivedDisp)
    }

    /// Computes the median of an array of Doubles.
    /// For an even number of elements, returns the average of the middle two.
    /// Returns nil if the array is empty.
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            return sorted[mid]
        }
    }
}
