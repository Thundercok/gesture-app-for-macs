import XCTest
@testable import GestureFlow

final class UndoPlannerTests: XCTestCase {

    func testInverseMappingTable() {
        // FINE_DIRECTIONAL_CLASSES: swipe_left, swipe_right, swipe_up, swipe_down, scroll_down, scroll_up
        XCTAssertEqual(UndoPlanner.inverse(for: "swipe_left"), .switchSpace(.left))
        XCTAssertEqual(UndoPlanner.inverse(for: "swipe_right"), .switchSpace(.right))
        XCTAssertEqual(UndoPlanner.inverse(for: "swipe_up"), .pressEscape)
        XCTAssertEqual(UndoPlanner.inverse(for: "swipe_down"), .toggleShowDesktop)
        XCTAssertNil(UndoPlanner.inverse(for: "scroll_down"))
        XCTAssertNil(UndoPlanner.inverse(for: "scroll_up"))

        // Additional non-directional / non-undoable actions
        XCTAssertNil(UndoPlanner.inverse(for: "pinch_dock"))
        XCTAssertNil(UndoPlanner.inverse(for: ""))
        XCTAssertNil(UndoPlanner.inverse(for: "unregistered_action"))
    }

    func testPerformUndoDispatchesThroughActionSink() {
        let clock = ReplayClock(initialTime: 0.0)
        let sink = RecordingActionSink(clock: clock)

        // 1. swipe_left -> switchSpace(.left)
        let descLeft = ActionDispatcher.performUndo(forAction: "swipe_left", sink: sink)
        XCTAssertEqual(descLeft, "Đã hoàn tác: Space Trái ←")
        XCTAssertEqual(sink.actions, ["switchSpace_left"])

        // 2. swipe_right -> switchSpace(.right)
        sink.clear()
        let descRight = ActionDispatcher.performUndo(forAction: "swipe_right", sink: sink)
        XCTAssertEqual(descRight, "Đã hoàn tác: Space Phải →")
        XCTAssertEqual(sink.actions, ["switchSpace_right"])

        // 3. swipe_up -> pressEscape
        sink.clear()
        let descUp = ActionDispatcher.performUndo(forAction: "swipe_up", sink: sink)
        XCTAssertEqual(descUp, "Đã hoàn tác: Thoát Mission Control")
        XCTAssertEqual(sink.actions, ["press_escape"])

        // 4. swipe_down -> showDesktop
        sink.clear()
        let descDown = ActionDispatcher.performUndo(forAction: "swipe_down", sink: sink)
        XCTAssertEqual(descDown, "Đã hoàn tác: Hiện lại cửa sổ")
        XCTAssertEqual(sink.actions, ["showDesktop"])

        // 5. Unmapped actions produce nil and dispatch nothing
        sink.clear()
        XCTAssertNil(ActionDispatcher.performUndo(forAction: "scroll_down", sink: sink))
        XCTAssertNil(ActionDispatcher.performUndo(forAction: "pinch_dock", sink: sink))
        XCTAssertNil(ActionDispatcher.performUndo(forAction: "", sink: sink))
        XCTAssertTrue(sink.actions.isEmpty)
    }

    func testIntentArbiterRecentCommittedActionBoundaries() {
        let clock = ReplayClock(initialTime: 100.0)
        let arbiter = IntentArbiter(clock: clock)

        // 1. No prior commit -> nil
        XCTAssertNil(arbiter.recentCommittedAction(within: 3.0))

        // 2. Commit at t=100.0
        arbiter.commitAction(gesture: .swipe, action: "swipe_left", cooldown: 0.45)
        XCTAssertEqual(arbiter.recentCommittedAction(within: 3.0), "swipe_left")

        // 3. At t=102.9 -> returns action
        clock.advance(to: 102.9)
        XCTAssertEqual(arbiter.recentCommittedAction(within: 3.0), "swipe_left")

        // 4. At t=103.0 -> boundary is inclusive (<= 3.0)
        clock.advance(to: 103.0)
        XCTAssertEqual(arbiter.recentCommittedAction(within: 3.0), "swipe_left")

        // 5. At t=103.1 -> past 3.0s window -> nil
        clock.advance(to: 103.1)
        XCTAssertNil(arbiter.recentCommittedAction(within: 3.0))
    }
}
