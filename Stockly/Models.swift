import Foundation
import SwiftData

// MARK: - Holding Model

@Model
class Holding {
    var sym: String
    var name: String
    var shares: Double
    var cost: Double
    var status: StatusType
    var group: GroupType

    init(sym: String, name: String, shares: Double, cost: Double, status: StatusType, group: GroupType) {
        self.sym = sym.uppercased()
        self.name = name
        self.shares = shares
        self.cost = cost
        self.status = status
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
    let extendedPrice: Double?
    let extendedChangePercent: Double?
    // Technical signals
    let fiftyTwoWeekHigh: Double
    let fiftyTwoWeekLow: Double
    let dayHigh: Double
    let dayLow: Double
    let volume: Int
    let avgVolume20d: Int
    let sma20: Double?
    let sma50: Double?
    let rsi14: Double?
}

struct EarningsInfo {
    let date: Date
    let label: String
}

struct SmartStatus {
    let status: SmartStatusType
    let label: String
    let score: Double
    let reasons: [String]

    init(status: SmartStatusType, label: String, score: Double = 0, reasons: [String] = []) {
        self.status = status
        self.label = label
        self.score = score
        self.reasons = reasons
    }
}

enum SmartStatusType {
    case buy, hold, watch, review, trim
}
