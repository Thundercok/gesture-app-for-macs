import Foundation

/// High-level research intent classes for Experiment 001:
/// Context-Conditioned Human Intent Inference for Hands-Free Desktop Interaction.
public enum ResearchIntent: String, Codable, CaseIterable {
    case idle = "IDLE"
    case scroll = "SCROLL"
    case windowManipulate = "WINDOW_MANIPULATE"
    case workspaceNavigate = "WORKSPACE_NAVIGATE"
    case select = "SELECT"
    case other = "OTHER"

    /// Maps legacy low-level gesture labels to research intent baseline classes.
    /// Returns nil if ambiguous or unknown.
    public static func baselineMapping(forGestureLabel label: String) -> ResearchIntent? {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch clean {
        case "idle", "0", "none":
            return .idle
        case "pinch_dock", "pinch", "1":
            return .select
        case "swipe_left", "swipe_right", "2", "3":
            return .workspaceNavigate
        case "swipe_up", "swipe_down", "4", "5":
            return .windowManipulate
        case "scroll_down", "scroll_up", "6", "7":
            return .scroll
        case "zoom", "8":
            return .windowManipulate
        default:
            return nil
        }
    }
}
