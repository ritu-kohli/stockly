import Foundation
import SwiftData

// MARK: - Holding Model

@Model
class Holding {
    var sym: String
    var name: String
    var shares: Double
    var cost: Double
    var group: GroupType

    init(sym: String, name: String, shares: Double, cost: Double, group: GroupType) {
        self.sym = sym.uppercased()
        self.name = name
        self.shares = shares
        self.cost = cost
        self.group = group
    }
}

// MARK: - Enums

enum GroupType: String, Codable, CaseIterable, Sendable {
    case tech = "Tech & Social"
    case semi = "Semiconductors & Materials"
    case logistics = "Logistics & Finance"
    case healthcare = "Healthcare"
    case energy = "Energy"
    case consumer = "Consumer"
    case realestate = "Real Estate"
    case utilities = "Utilities"
    case speculative = "Speculative"
    case other = "Other"
}

enum SmartStatusType: Sendable {
    case strongBuy, buy, hold, watch, trim, review
}

// MARK: - Supporting Types

struct PriceData: Sendable {
    let price: Double
    let dayChangePercent: Double
    let extendedPrice: Double?
    let extendedChangePercent: Double?
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

struct EarningsInfo: Sendable {
    let date: Date
    let label: String
}

struct SmartStatus: Sendable {
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
