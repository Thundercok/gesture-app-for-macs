import XCTest
import CoreGraphics
@testable import GestureFlow

final class ActionSinkTests: XCTestCase {
    func testRecordingActionSinkMouseEvents() {
        let clock = ReplayClock()
        let sink = RecordingActionSink(clock: clock)

        clock.advance(to: 10.0)
        sink.mouseMove(to: CGPoint(x: 100.2, y: 200.7))
        XCTAssertEqual(sink.actions.last, "mouse_move_100_201")
        XCTAssertEqual(sink.records.last?.timestamp, 10.0)

        clock.advance(to: 10.05)
        sink.mouseDown(at: CGPoint(x: 100, y: 200))
        XCTAssertEqual(sink.actions.last, "mouse_down_100_200")
        XCTAssertEqual(sink.records.last?.timestamp, 10.05)

        clock.advance(to: 10.10)
        sink.mouseDragged(to: CGPoint(x: 150, y: 250))
        XCTAssertEqual(sink.actions.last, "mouse_dragged_150_250")

        clock.advance(to: 10.15)
        sink.mouseUp(at: CGPoint(x: 150, y: 250))
        XCTAssertEqual(sink.actions.last, "mouse_up_150_250")

        clock.advance(to: 10.20)
        sink.mouseClick(at: CGPoint(x: 300, y: 400))
        XCTAssertEqual(sink.actions.last, "mouse_click_300_400")

        clock.advance(to: 10.22)
        sink.mouseClick(at: CGPoint(x: 300, y: 400), clickCount: 2)
        XCTAssertEqual(sink.actions.last, "mouse_double_click_300_400")

        clock.advance(to: 10.24)
        sink.rightMouseDown(at: CGPoint(x: 350, y: 450))
        XCTAssertEqual(sink.actions.last, "right_mouse_down_350_450")

        clock.advance(to: 10.25)
        sink.rightMouseUp(at: CGPoint(x: 350, y: 450))
        XCTAssertEqual(sink.actions.last, "right_mouse_up_350_450")

        clock.advance(to: 10.26)
        sink.rightClick(at: CGPoint(x: 350, y: 450))
        XCTAssertEqual(sink.actions.last, "right_click_350_450")

        clock.advance(to: 10.28)
        sink.scrollWheel(deltaX: 0.0, deltaY: -15.5)
        XCTAssertEqual(sink.actions.last, "scroll_wheel_dx_0.0_dy_-15.5")

        clock.advance(to: 10.30)
        sink.magnifyContinuous(delta: 0.05)
        XCTAssertEqual(sink.actions.last, "magnify_continuous_0.0500")

        XCTAssertEqual(sink.actions.count, 11)
        sink.clear()
        XCTAssertTrue(sink.actions.isEmpty)
        XCTAssertTrue(sink.records.isEmpty)
    }
}
