import Foundation

// MARK: - Models

struct Holding: Identifiable, Codable {
    let id: UUID
    let sym: String
    let name: String
    let shares: Double
    let cost: Double
    let status: StatusType
    let note: String
    let group: GroupType

    init(sym: String, name: String, shares: Double, cost: Double, status: StatusType, note: String, group: GroupType) {
        self.id = UUID()
        self.sym = sym.uppercased()
        self.name = name
        self.shares = shares
        self.cost = cost
        self.status = status
        self.note = note
        self.group = group
    }
}

enum StatusType: String, Codable, CaseIterable {
    case buy = "Buy"
    case hold = "Hold"
    case watch = "Watch"
}

enum GroupType: String, Codable, CaseIterable {
    case tech = "Tech & Social"
    case semi = "Semiconductors & Materials"
    case logistics = "Logistics & Finance"
    case speculative = "Speculative"
}

struct PriceData {
    let price: Double
    let dayChangePercent: Double
    let extendedPrice: Double?      // pre/post market price
    let extendedChangePercent: Double? // change vs regular close
}

struct EarningsInfo {
    let date: Date
    let label: String
}

struct SmartStatus {
    let status: SmartStatusType
    let label: String
}

enum SmartStatusType {
    case buy, hold, watch, review, trim
}
