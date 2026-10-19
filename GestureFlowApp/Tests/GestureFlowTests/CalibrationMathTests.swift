import XCTest
@testable import GestureFlow

final class CalibrationMathTests: XCTestCase {

    func testWindowedPeakVelocityOnStraightLine() {
        // 60 fps, 0.8 units/s straight line
        let fps = 60.0
        let dt = 1.0 / fps
        let knownSpeed = 0.8
        var samples: [(point: CGPoint, t: TimeInterval)] = []

        for i in 0..<30 {
            let t = Double(i) * dt
            let x = knownSpeed * t
            samples.append((point: CGPoint(x: x, y: 0.5), t: t))
        }

        let peakV = CalibrationMath.windowedPeakVelocity(samples: samples)
        XCTAssertEqual(peakV, knownSpeed, accuracy: 1e-6)
    }

    func testWindowedPeakDisplacementOnStraightLine() {
        let fps = 60.0
        let dt = 1.0 / fps
        let knownSpeed = 0.8
        var samples: [(point: CGPoint, t: TimeInterval)] = []

        for i in 0..<30 {
            let t = Double(i) * dt
            let x = knownSpeed * t
            samples.append((point: CGPoint(x: x, y: 0.5), t: t))
        }

        let peakDisp = CalibrationMath.windowedPeakDisplacement(samples: samples)
        // Max offset in window is 7 frames: dt = 7 / 60 s, displacement = 0.8 * (7/60) ≈ 0.093333
        let expectedMaxDisp = knownSpeed * (7.0 / 60.0)
        XCTAssertEqual(peakDisp, expectedMaxDisp, accuracy: 1e-6)
    }

    func testJitterRobustness() {
        // High-frequency sensor jitter: alternating noise on top of a 0.8 units/s motion
        // Windowed method filters out high-frequency noise because min offset is 3 (dt >= 0.035).
        // Old per-frame peak method amplifies noise between adjacent frames.
        var samples: [(point: CGPoint, t: TimeInterval)] = []
        let dt = 1.0 / 60.0
        for k in 0..<30 {
            let t = Double(k) * dt
            let noise = (k % 2 == 0 ? 0.0035 : -0.0035)
            let x = 0.8 * t + noise
            samples.append((point: CGPoint(x: x, y: 0.5), t: t))
        }

        let windowedPeak = CalibrationMath.windowedPeakVelocity(samples: samples)

        // Compute old per-frame peak velocity
        var oldPerFramePeak = 0.0
        for i in 1..<samples.count {
            let frameDt = max(0.001, samples[i].t - samples[i - 1].t)
            let dx = samples[i].point.x - samples[i - 1].point.x
            let dy = samples[i].point.y - samples[i - 1].point.y
            let s = Double(hypot(dx, dy)) / frameDt
            if s > oldPerFramePeak {
                oldPerFramePeak = s
            }
        }

        XCTAssertLessThan(windowedPeak, 1.2, "Windowed velocity must reject high-frequency jitter and stay < 1.2")
        XCTAssertGreaterThan(oldPerFramePeak, 1.2, "Old per-frame method would have falsely exceeded 1.2 due to adjacent-frame noise amplification")
    }

    func testDeriveClamps() {
        // Nominal case: 65% fraction
        let nominal = CalibrationMath.derive(medianVelocity: 1.0, medianDisplacement: 0.10, fraction: 0.65)
        XCTAssertEqual(nominal.velocity, 0.65, accuracy: 1e-6)
        XCTAssertEqual(nominal.displacement, 0.065, accuracy: 1e-6)

        // Low clamp: velocity >= 0.30, displacement >= 0.045
        let low = CalibrationMath.derive(medianVelocity: 0.10, medianDisplacement: 0.01, fraction: 0.65)
        XCTAssertEqual(low.velocity, 0.30, accuracy: 1e-6)
        XCTAssertEqual(low.displacement, 0.045, accuracy: 1e-6)

        // High clamp: velocity <= 0.85, displacement <= 0.110
        let high = CalibrationMath.derive(medianVelocity: 2.50, medianDisplacement: 0.50, fraction: 0.65)
        XCTAssertEqual(high.velocity, 0.85, accuracy: 1e-6)
        XCTAssertEqual(high.displacement, 0.110, accuracy: 1e-6)
    }

    func testMedian() {
        // Empty
        XCTAssertNil(CalibrationMath.median([]))

        // Single element
        XCTAssertEqual(CalibrationMath.median([42.0]), 42.0)

        // Odd length
        XCTAssertEqual(CalibrationMath.median([5.0, 1.0, 3.0]), 3.0)

        // Even length: average of middle two
        XCTAssertEqual(CalibrationMath.median([10.0, 20.0, 30.0, 40.0]), 25.0)
    }
}
