import Foundation

/// Reasons why a candidate gesture motion was rejected by the engines.
enum RejectReason: Equatable {
    case faceOverlap
    case edgeOnPalm
    case notStable
    case tooSlow
    case tooShort
    case axisAmbiguous
    case cooldown
    case arbiterBusy(String)
    case pinchGuard
    case lowConfidence

    var displayLabel: String {
        switch self {
        case .faceOverlap:
            return "Chạm vùng mặt"
        case .edgeOnPalm:
            return "Nghiêng bàn tay"
        case .notStable:
            return "Chưa xòe ổn định"
        case .tooSlow:
            return "Vuốt quá chậm"
        case .tooShort:
            return "Biên độ quá ngắn"
        case .axisAmbiguous:
            return "Chệch hướng vuốt"
        case .cooldown:
            return "Đang nghỉ giữa nhịp"
        case .arbiterBusy(let owner):
            return "Đang bận (\(owner))"
        case .pinchGuard:
            return "Vừa chụm ngón"
        case .lowConfidence:
            return "Tín hiệu mờ"
        }
    }
}
