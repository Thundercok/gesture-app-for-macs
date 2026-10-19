import XCTest
@testable import GestureFlow

final class GestureTuningTests: XCTestCase {
    func testDecodesLegacyJSONWithoutUseLearnedPosture() throws {
        let safeTuning = GestureTuning.safe
        let encoder = JSONEncoder()
        let data = try encoder.encode(safeTuning)
        
        var jsonDict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(jsonDict["useLearnedPosture"], "Encoded JSON should contain useLearnedPosture")
        jsonDict.removeValue(forKey: "useLearnedPosture")
        
        let strippedData = try JSONSerialization.data(withJSONObject: jsonDict)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(GestureTuning.self, from: strippedData)
        
        XCTAssertEqual(decoded.preset, .safe)
        XCTAssertEqual(decoded.swipeMinVelocity, 0.65)
        XCTAssertFalse(decoded.useLearnedPosture)
    }

    func testBalancedMatchesBaseline() {
        let b = GestureTuning.balanced
        XCTAssertEqual(b.preset, .balanced)
        XCTAssertEqual(b.swipeMinDisplacement, 0.065, accuracy: 1e-6)
        XCTAssertEqual(b.swipeMinVelocity, 0.50, accuracy: 1e-6)
        XCTAssertEqual(b.swipeAxisDominance, 1.30, accuracy: 1e-6)
        XCTAssertEqual(b.openPalmDwellSeconds, 0.05, accuracy: 1e-6)
        XCTAssertEqual(b.pinchCalmHandSpeed, 0.42, accuracy: 1e-6)
        XCTAssertEqual(b.postPinchSwipeGuardSeconds, 0.35, accuracy: 1e-6)
        XCTAssertEqual(b.swipeCooldownSeconds, 0.45, accuracy: 1e-6)
        XCTAssertEqual(b.scrollFlickMinVelocity, 0.42, accuracy: 1e-6)
        XCTAssertFalse(b.useLearnedPosture)
    }

    func testLerpEndpoints() {
        let a = GestureTuning.safe
        let b = GestureTuning.sensitive

        let atZero = GestureTuning.lerp(a, b, t: 0.0)
        XCTAssertEqual(atZero.swipeMinDisplacement, a.swipeMinDisplacement, accuracy: 1e-6)
        XCTAssertEqual(atZero.swipeMinVelocity, a.swipeMinVelocity, accuracy: 1e-6)
        XCTAssertEqual(atZero.swipeAxisDominance, a.swipeAxisDominance, accuracy: 1e-6)
        XCTAssertEqual(atZero.openPalmDwellSeconds, a.openPalmDwellSeconds, accuracy: 1e-6)
        XCTAssertEqual(atZero.pinchCalmHandSpeed, a.pinchCalmHandSpeed, accuracy: 1e-6)
        XCTAssertEqual(atZero.postPinchSwipeGuardSeconds, a.postPinchSwipeGuardSeconds, accuracy: 1e-6)
        XCTAssertEqual(atZero.swipeCooldownSeconds, a.swipeCooldownSeconds, accuracy: 1e-6)
        XCTAssertEqual(atZero.scrollFlickMinVelocity, a.scrollFlickMinVelocity, accuracy: 1e-6)

        let atOne = GestureTuning.lerp(a, b, t: 1.0)
        XCTAssertEqual(atOne.swipeMinDisplacement, b.swipeMinDisplacement, accuracy: 1e-6)
        XCTAssertEqual(atOne.swipeMinVelocity, b.swipeMinVelocity, accuracy: 1e-6)
        XCTAssertEqual(atOne.swipeAxisDominance, b.swipeAxisDominance, accuracy: 1e-6)
        XCTAssertEqual(atOne.openPalmDwellSeconds, b.openPalmDwellSeconds, accuracy: 1e-6)
        XCTAssertEqual(atOne.pinchCalmHandSpeed, b.pinchCalmHandSpeed, accuracy: 1e-6)
        XCTAssertEqual(atOne.postPinchSwipeGuardSeconds, b.postPinchSwipeGuardSeconds, accuracy: 1e-6)
        XCTAssertEqual(atOne.swipeCooldownSeconds, b.swipeCooldownSeconds, accuracy: 1e-6)
        XCTAssertEqual(atOne.scrollFlickMinVelocity, b.scrollFlickMinVelocity, accuracy: 1e-6)

        let belowZero = GestureTuning.lerp(a, b, t: -0.5)
        XCTAssertEqual(belowZero.swipeMinVelocity, a.swipeMinVelocity, accuracy: 1e-6)

        let aboveOne = GestureTuning.lerp(a, b, t: 1.5)
        XCTAssertEqual(aboveOne.swipeMinVelocity, b.swipeMinVelocity, accuracy: 1e-6)
    }

    func testRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for preset in TuningPreset.allCases {
            let original = GestureTuning.preset(for: preset)
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(GestureTuning.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }
}
