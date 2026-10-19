import XCTest
@testable import GestureFlow

final class SmokeTests: XCTestCase {
    func testBalancedSwipeMinVelocity() {
        XCTAssertEqual(GestureTuning.balanced.swipeMinVelocity, 0.50)
    }
}
