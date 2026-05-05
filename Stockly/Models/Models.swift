import Foundation
// import SwiftData  // DISABLED — Supabase is source of truth

// MARK: - Holding Model (SwiftData @Model disabled, using HoldingLocal from SupabaseService)
// @Model
// class Holding { ... }
// Re-enable when SwiftData is needed again

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
    let sma200: Double?
    let rsi14: Double?
    let beta: Double?
    let sharpeRatio: Double?
    let annualizedVolatility: Double?
    let maxDrawdown: Double?
    let return1y: Double?
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
