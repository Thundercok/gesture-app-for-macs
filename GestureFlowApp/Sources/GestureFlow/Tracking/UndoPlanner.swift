import Foundation

enum InverseAction: Equatable {
    case switchSpace(ActionDispatcher.SpaceDirection)
    case pressEscape
    case toggleShowDesktop
}

enum UndoPlanner {
    static func inverse(for action: String) -> InverseAction? {
        switch action {
        case "swipe_left":
            return .switchSpace(.left)
        case "swipe_right":
            return .switchSpace(.right)
        case "swipe_up":
            return .pressEscape
        case "swipe_down":
            return .toggleShowDesktop
        default:
            return nil
        }
    }

    static func description(for inverseAction: InverseAction) -> String {
        switch inverseAction {
        case .switchSpace(.left):
            return "Đã hoàn tác: Space Trái ←"
        case .switchSpace(.right):
            return "Đã hoàn tác: Space Phải →"
        case .pressEscape:
            return "Đã hoàn tác: Thoát Mission Control"
        case .toggleShowDesktop:
            return "Đã hoàn tác: Hiện lại cửa sổ"
        }
    }
}
