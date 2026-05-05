import Foundation
// MARK: - Sheet Destination

enum SheetDestination: Identifiable, Hashable {
    case addHolding
    case settings
    case detail(HoldingLocal)
    case addPosition(HoldingLocal)
    case disclaimer

    var id: String {
        switch self {
        case .addHolding:        return "addHolding"
        case .settings:          return "settings"
        case .detail(let h):     return "detail_\(h.sym)"
        case .addPosition(let h):return "addPosition_\(h.sym)"
        case .disclaimer:        return "disclaimer"
        }
    }
}
