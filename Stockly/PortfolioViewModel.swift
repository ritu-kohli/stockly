// MARK: - ViewModel
import Foundation
import SwiftUI
import SwiftData

@MainActor
class PortfolioViewModel: ObservableObject {

    @Published var prices: [String: PriceData] = [:]
    @Published var isLoading = false
    @Published var statusMessage = "Loading..."
    @Published var lastUpdated = "Loading prices..."
    @Published var earningsDates: [String: EarningsInfo] = [:]

    private var modelContext: ModelContext

    var holdings: [Holding] {
        (try? modelContext.fetch(FetchDescriptor<Holding>())) ?? []
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        seedIfEmpty()
        refreshPrices()
    }

    // MARK: - Seed default holdings on first launch

    private func seedIfEmpty() {}

    func updateContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - CRUD

    func addHolding(_ holding: Holding) {
        modelContext.insert(holding)
        try? modelContext.save()
        refreshPrices()
    }

    func removeHoldings(ids: Set<PersistentIdentifier>) {
        ids.compactMap { modelContext.model(for: $0) as? Holding }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - Computed totals

    var totalInvested: Double {
        holdings.reduce(0) { $0 + ($1.shares * $1.cost) }
    }

    var totalValue: Double {
        holdings.reduce(0) { total, h in
            total + (h.shares * (prices[h.sym]?.price ?? h.cost))
        }
    }

    var totalPL: Double { totalValue - totalInvested }

    var totalReturn: Double {
        guard totalInvested > 0 else { return 0 }
        return (totalPL / totalInvested) * 100
    }

    // MARK: - Smart Status
    // Weighted signal scoring across 6 independent signals.
    // Each signal votes with a score: positive = bullish, negative = bearish.
    // Final score maps to: Strong Buy / Buy / Hold / Watch / Trim / Review
    func smartStatus(for holding: Holding) -> SmartStatus {
        guard let p = prices[holding.sym] else {
            return SmartStatus(status: .hold, label: "Hold")
        }

        var score: Double = 0
        var reasons: [String] = []

        // 1. Cost basis P&L (-3 to +3)
        let plPct = ((p.price - holding.cost) / holding.cost) * 100
        switch plPct {
        case ..<(-20):  score -= 3; reasons.append("down >20%")
        case ..<(-10):  score -= 2; reasons.append("down >10%")
        case ..<(-5):   score -= 1; reasons.append("down >5%")
        case 20...:     score += 3; reasons.append("up >20%")
        case 10...:     score += 2; reasons.append("up >10%")
        case 5...:      score += 1; reasons.append("up >5%")
        default: break
        }

        // 2. RSI — overbought/oversold (-2 to +2)
        if let rsi = p.rsi14 {
            switch rsi {
            case ..<30:  score += 2; reasons.append("RSI oversold")
            case ..<40:  score += 1; reasons.append("RSI low")
            case 70...:  score -= 2; reasons.append("RSI overbought")
            case 60...:  score -= 1; reasons.append("RSI high")
            default: break
            }
        }

        // 3. Price vs SMA20 & SMA50 (-2 to +2)
        if let sma20 = p.sma20 {
            if p.price > sma20 * 1.02  { score += 1; reasons.append("above SMA20") }
            else if p.price < sma20 * 0.98 { score -= 1; reasons.append("below SMA20") }
        }
        if let sma50 = p.sma50 {
            if p.price > sma50 * 1.02  { score += 1; reasons.append("above SMA50") }
            else if p.price < sma50 * 0.98 { score -= 1; reasons.append("below SMA50") }
        }

        // 4. 52-week position (-1 to +1)
        let week52Range = p.fiftyTwoWeekHigh - p.fiftyTwoWeekLow
        if week52Range > 0 {
            let position = (p.price - p.fiftyTwoWeekLow) / week52Range
            if position >= 0.80      { score -= 1; reasons.append("near 52w high") }
            else if position <= 0.20 { score += 1; reasons.append("near 52w low") }
        }

        // 5. Volume surge — unusual activity signals momentum (-1 to +1)
        if p.avgVolume20d > 0 {
            let volRatio = Double(p.volume) / Double(p.avgVolume20d)
            if volRatio >= 2.0 && p.dayChangePercent > 0 { score += 1; reasons.append("volume surge up") }
            if volRatio >= 2.0 && p.dayChangePercent < 0 { score -= 1; reasons.append("volume surge down") }
        }

        // 6. Day change momentum (-1 to +1)
        switch p.dayChangePercent {
        case ..<(-3): score -= 1; reasons.append("big day drop")
        case 3...:    score += 1; reasons.append("big day gain")
        default: break
        }

        // Map score to status (max possible: +9, min: -8)
        let status: SmartStatusType
        let label: String
        switch score {
        case 5...:        status = .strongBuy; label = "Strong Buy"
        case 2...:        status = .buy;       label = "Buy"
        case 0..<2:       status = .hold;      label = "Hold"
        case (-2)..<0:    status = .watch;     label = "Watch"
        case (-4)..<(-2): status = .trim;      label = "Trim"
        default:          status = .review;    label = "Review"
        }

        return SmartStatus(status: status, label: label, score: score, reasons: reasons)
    }

    // MARK: - Earnings

    func isEarningsThisWeek(_ symbol: String) -> Bool {
        guard let info = earningsDates[symbol] else { return false }
        let today = Date()
        let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        return info.date >= today && info.date <= weekFromNow
    }

    // MARK: - Prices

    func refreshPrices() {
        let syms = holdings.map { $0.sym }
        guard !syms.isEmpty else { return }
        isLoading = true
        statusMessage = "Fetching live prices..."

        Task {
            let result = await YahooFinanceService.shared.fetchPricesAsync(for: syms)
            switch result {
            case .success(let data):
                self.prices = data
                self.lastUpdated = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
                self.statusMessage = "Prices loaded"
            case .failure(let error):
                self.prices = self.generateFallbackPrices()
                self.statusMessage = "Using fallback prices: \(error.localizedDescription)"
                self.lastUpdated = "Fallback \(Date().formatted(date: .omitted, time: .shortened))"
            }
            self.isLoading = false
        }
    }

    private func generateFallbackPrices() -> [String: PriceData] {
        var result: [String: PriceData] = [:]
        for h in holdings {
            result[h.sym] = PriceData(
                price: h.cost * (1 + Double.random(in: -0.05...0.10)),
                dayChangePercent: Double.random(in: -2...2),
                extendedPrice: nil, extendedChangePercent: nil,
                fiftyTwoWeekHigh: h.cost * 1.3, fiftyTwoWeekLow: h.cost * 0.7,
                dayHigh: h.cost * 1.01, dayLow: h.cost * 0.99,
                volume: 0, avgVolume20d: 0,
                sma20: nil, sma50: nil, rsi14: nil
            )
        }
        return result
    }
}

// MARK: - Yahoo Finance Service

actor YahooFinanceService {
    static let shared = YahooFinanceService()
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
    private init() {}

    func fetchPricesAsync(for symbols: [String]) async -> Result<[String: PriceData], Error> {
        var priceData: [String: PriceData] = [:]
        var fetchError: Error?
        await withTaskGroup(of: (String, Result<PriceData, Error>).self) { group in
            for symbol in symbols {
                group.addTask { await (symbol, self.fetchSinglePrice(for: symbol)) }
            }
            for await (symbol, result) in group {
                switch result {
                case .success(let data): priceData[symbol] = data
                case .failure(let error): fetchError = error
                }
            }
        }
        if let error = fetchError { return .failure(error) }
        return .success(priceData)
    }

    nonisolated private func fetchSinglePrice(for symbol: String) async -> Result<PriceData, Error> {
        do {
            async let intradayJson = fetch(url: "\(baseURL)/\(symbol)?interval=1m&range=1d&includePrePost=true")
            async let historicalJson = fetch(url: "\(baseURL)/\(symbol)?interval=1d&range=3mo")
            let (intraday, historical) = try await (intradayJson, historicalJson)

            guard let chart = intraday["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let regularPrice = meta["regularMarketPrice"] as? Double,
                  let previousClose = meta["chartPreviousClose"] as? Double else {
                let msg = ((intraday["chart"] as? [String: Any])?["error"] as? [String: Any])?["description"] as? String ?? "Invalid response"
                return .failure(NSError(domain: "YahooFinance", code: -2, userInfo: [NSLocalizedDescriptionKey: msg]))
            }

            let dayChangePct = ((regularPrice - previousClose) / previousClose) * 100
            let week52High = meta["fiftyTwoWeekHigh"] as? Double ?? regularPrice
            let week52Low  = meta["fiftyTwoWeekLow"]  as? Double ?? regularPrice
            let dayHigh    = meta["regularMarketDayHigh"] as? Double ?? regularPrice
            let dayLow     = meta["regularMarketDayLow"]  as? Double ?? regularPrice
            let volume     = meta["regularMarketVolume"] as? Int ?? 0

            let closes1m = (first["indicators"] as? [String: Any])
                .flatMap { $0["quote"] as? [[String: Any]] }
                .flatMap { $0.first }
                .flatMap { $0["close"] as? [Double?] }
            let lastExtended = closes1m?.compactMap { $0 }.last
            let isExtended = lastExtended.map { abs($0 - regularPrice) > 0.01 } ?? false

            var historicalCloses: [Double] = []
            var historicalVolumes: [Int] = []
            if let hChart = historical["chart"] as? [String: Any],
               let hResults = hChart["result"] as? [[String: Any]],
               let hFirst = hResults.first,
               let quotes = (hFirst["indicators"] as? [String: Any])?["quote"] as? [[String: Any]],
               let q = quotes.first {
                historicalCloses = (q["close"] as? [Double?])?.compactMap { $0 } ?? []
                historicalVolumes = (q["volume"] as? [Int?])?.compactMap { $0 } ?? []
            }

            let sma20   = historicalCloses.count >= 20 ? historicalCloses.suffix(20).reduce(0,+) / 20 : nil
            let sma50   = historicalCloses.count >= 50 ? historicalCloses.suffix(50).reduce(0,+) / 50 : nil
            let avgVol  = historicalVolumes.count >= 20 ? historicalVolumes.suffix(20).reduce(0,+) / 20 : 0
            let rsi14   = Self.computeRSI(closes: historicalCloses, period: 14)

            return .success(PriceData(
                price: regularPrice,
                dayChangePercent: dayChangePct,
                extendedPrice: isExtended ? lastExtended : nil,
                extendedChangePercent: isExtended ? lastExtended.map { (($0 - regularPrice) / regularPrice) * 100 } : nil,
                fiftyTwoWeekHigh: week52High,
                fiftyTwoWeekLow: week52Low,
                dayHigh: dayHigh,
                dayLow: dayLow,
                volume: volume,
                avgVolume20d: avgVol,
                sma20: sma20,
                sma50: sma50,
                rsi14: rsi14
            ))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private func fetch(url: String) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Parse error"])
        }
        return json
    }

    private static func computeRSI(closes: [Double], period: Int) -> Double? {
        guard closes.count > period else { return nil }
        let changes = zip(closes.dropFirst(), closes).map { $0 - $1 }
        let recent = Array(changes.suffix(period))
        let gains = recent.map { max($0, 0) }
        let losses = recent.map { max(-$0, 0) }
        let avgGain = gains.reduce(0, +) / Double(period)
        let avgLoss = losses.reduce(0, +) / Double(period)
        guard avgLoss > 0 else { return 100 }
        return 100 - (100 / (1 + avgGain / avgLoss))
    }
}
