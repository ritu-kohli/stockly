import Foundation
import SwiftUI
import SwiftData

@MainActor
class PortfolioViewModel: ObservableObject {

    @Published var holdings: [Holding] = []
    @Published var prices: [String: PriceData] = [:]
    @Published var isLoading = false
    @Published var lastUpdated = "Loading prices..."
    @Published var earningsDates: [String: EarningsInfo] = [:]
    @Published var errorMessage: String?

    private var modelContext: ModelContext
    private var historicalCache: [String: (data: PriceData, fetchedAt: Date)] = [:]
    private static let historicalCacheTTL: TimeInterval = 3600 // 1 hour

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadHoldings()
    }

    // Placeholder init — real context injected via updateContext on onAppear
    convenience init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = (try? ModelContainer(for: Holding.self, configurations: config))
            ?? (try! ModelContainer(for: Holding.self))
        self.init(modelContext: container.mainContext)
    }

    // MARK: - Context

    func updateContext(_ context: ModelContext) {
        guard modelContext !== context else { return }
        self.modelContext = context
        loadHoldings()
    }

    // MARK: - Holdings

    func loadHoldings() {
        do {
            holdings = try modelContext.fetch(FetchDescriptor<Holding>())
        } catch {
            errorMessage = "Failed to load holdings: \(error.localizedDescription)"
        }
    }

    func addHolding(_ holding: Holding) {
        guard !holdings.contains(where: { $0.sym == holding.sym }) else {
            errorMessage = "\(holding.sym) is already in your portfolio"
            return
        }
        modelContext.insert(holding)
        save()
        loadHoldings()
        Task { await fetchPrices(for: [holding.sym]) }
    }

    func removeHoldings(ids: Set<PersistentIdentifier>) {
        ids.compactMap { modelContext.model(for: $0) as? Holding }
            .forEach { modelContext.delete($0) }
        save()
        loadHoldings()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed Totals

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
    // Each signal votes: positive = bullish, negative = bearish.
    // Maps to: Strong Buy / Buy / Hold / Watch / Trim / Review

    func smartStatus(for holding: Holding) -> SmartStatus {
        guard let p = prices[holding.sym] else {
            return SmartStatus(status: .hold, label: "Hold")
        }

        var score: Double = 0
        var reasons: [String] = []

        // 1. Cost basis P&L (-3 to +3)
        let plPct = ((p.price - holding.cost) / holding.cost) * 100
        switch plPct {
        case ..<(-20): score -= 3; reasons.append("down >20%")
        case ..<(-10): score -= 2; reasons.append("down >10%")
        case ..<(-5):  score -= 1; reasons.append("down >5%")
        case 20...:    score += 3; reasons.append("up >20%")
        case 10...:    score += 2; reasons.append("up >10%")
        case 5...:     score += 1; reasons.append("up >5%")
        default: break
        }

        // 2. RSI — overbought/oversold (-2 to +2)
        if let rsi = p.rsi14 {
            switch rsi {
            case ..<30: score += 2; reasons.append("RSI oversold")
            case ..<40: score += 1; reasons.append("RSI low")
            case 70...: score -= 2; reasons.append("RSI overbought")
            case 60...: score -= 1; reasons.append("RSI high")
            default: break
            }
        }

        // 3. Price vs SMA20 & SMA50 (-2 to +2)
        if let sma20 = p.sma20 {
            if p.price > sma20 * 1.02      { score += 1; reasons.append("above SMA20") }
            else if p.price < sma20 * 0.98 { score -= 1; reasons.append("below SMA20") }
        }
        if let sma50 = p.sma50 {
            if p.price > sma50 * 1.02      { score += 1; reasons.append("above SMA50") }
            else if p.price < sma50 * 0.98 { score -= 1; reasons.append("below SMA50") }
        }

        // 4. 52-week position (-1 to +1)
        let week52Range = p.fiftyTwoWeekHigh - p.fiftyTwoWeekLow
        if week52Range > 0 {
            let position = (p.price - p.fiftyTwoWeekLow) / week52Range
            if position >= 0.80      { score -= 1; reasons.append("near 52w high") }
            else if position <= 0.20 { score += 1; reasons.append("near 52w low") }
        }

        // 5. Volume surge (-1 to +1)
        if p.avgVolume20d > 0 {
            let volRatio = Double(p.volume) / Double(p.avgVolume20d)
            if volRatio >= 2.0 && p.dayChangePercent > 0 { score += 1; reasons.append("volume surge up") }
            if volRatio >= 2.0 && p.dayChangePercent < 0 { score -= 1; reasons.append("volume surge down") }
        }

        // 6. Day momentum (-1 to +1)
        switch p.dayChangePercent {
        case ..<(-3): score -= 1; reasons.append("big day drop")
        case 3...:    score += 1; reasons.append("big day gain")
        default: break
        }

        let status: SmartStatusType
        let label: String
        switch score {
        case 5...:         status = .strongBuy; label = "Strong Buy"
        case 2...:         status = .buy;       label = "Buy"
        case 0..<2:        status = .hold;      label = "Hold"
        case (-2)..<0:     status = .watch;     label = "Watch"
        case (-4)..<(-2):  status = .trim;      label = "Trim"
        default:           status = .review;    label = "Review"
        }

        return SmartStatus(status: status, label: label, score: score, reasons: reasons)
    }

    // MARK: - Earnings

    func isEarningsThisWeek(_ symbol: String) -> Bool {
        guard let info = earningsDates[symbol],
              let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return false }
        let today = Date()
        return info.date >= today && info.date <= weekFromNow
    }

    // MARK: - Prices

    func refreshPrices() {
        guard !holdings.isEmpty else { return }
        Task { await fetchPrices(for: holdings.map { $0.sym }) }
    }

    private func fetchPrices(for symbols: [String]) async {
        isLoading = true
        errorMessage = nil

        let result = await YahooFinanceService.shared.fetchPrices(
            for: symbols,
            cachedHistorical: historicalCache,
            cacheTTL: Self.historicalCacheTTL
        )

        switch result {
        case .success(let (newPrices, updatedCache)):
            for (sym, data) in newPrices { prices[sym] = data }
            for (sym, entry) in updatedCache { historicalCache[sym] = entry }
            lastUpdated = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
        case .failure(let error):
            for sym in symbols where prices[sym] == nil {
                prices[sym] = fallbackPrice(for: sym)
            }
            errorMessage = "Price fetch failed: \(error.localizedDescription)"
            lastUpdated = "Fallback \(Date().formatted(date: .omitted, time: .shortened))"
        }

        isLoading = false
    }

    private func fallbackPrice(for sym: String) -> PriceData {
        let cost = holdings.first(where: { $0.sym == sym })?.cost ?? 100
        return PriceData(
            price: cost * (1 + Double.random(in: -0.05...0.10)),
            dayChangePercent: Double.random(in: -2...2),
            extendedPrice: nil, extendedChangePercent: nil,
            fiftyTwoWeekHigh: cost * 1.3, fiftyTwoWeekLow: cost * 0.7,
            dayHigh: cost * 1.01, dayLow: cost * 0.99,
            volume: 0, avgVolume20d: 0,
            sma20: nil, sma50: nil, rsi14: nil
        )
    }
}

// MARK: - Yahoo Finance Service

actor YahooFinanceService {
    static let shared = YahooFinanceService()
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
    private init() {}

    typealias HistoricalCache = [String: (data: PriceData, fetchedAt: Date)]

    func fetchPrices(
        for symbols: [String],
        cachedHistorical: HistoricalCache,
        cacheTTL: TimeInterval
    ) async -> Result<([String: PriceData], HistoricalCache), Error> {
        var priceData: [String: PriceData] = [:]
        var updatedCache: HistoricalCache = [:]
        var fetchError: Error?

        await withTaskGroup(of: (String, Result<PriceData, Error>, (data: PriceData, fetchedAt: Date)?).self) { group in
            for symbol in symbols {
                let cached = cachedHistorical[symbol]
                group.addTask {
                    let (result, cacheEntry) = await self.fetchSinglePrice(for: symbol, cachedEntry: cached, cacheTTL: cacheTTL)
                    return (symbol, result, cacheEntry)
                }
            }
            for await (symbol, result, cacheEntry) in group {
                switch result {
                case .success(let data):
                    priceData[symbol] = data
                    if let entry = cacheEntry { updatedCache[symbol] = entry }
                case .failure(let error):
                    fetchError = error
                }
            }
        }

        if let error = fetchError, priceData.isEmpty { return .failure(error) }
        return .success((priceData, updatedCache))
    }

    private func fetchSinglePrice(
        for symbol: String,
        cachedEntry: (data: PriceData, fetchedAt: Date)?,
        cacheTTL: TimeInterval
    ) async -> (Result<PriceData, Error>, (data: PriceData, fetchedAt: Date)?) {
        do {
            // Always fetch intraday for live price
            let intraday = try await fetch(url: "\(baseURL)/\(symbol)?interval=1m&range=1d&includePrePost=true")

            guard let chart = intraday["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any],
                  let regularPrice = meta["regularMarketPrice"] as? Double,
                  let previousClose = meta["chartPreviousClose"] as? Double else {
                let msg = ((intraday["chart"] as? [String: Any])?["error"] as? [String: Any])?["description"] as? String ?? "Invalid response"
                return (.failure(NSError(domain: "YahooFinance", code: -2, userInfo: [NSLocalizedDescriptionKey: msg])), nil)
            }

            let dayChangePct  = ((regularPrice - previousClose) / previousClose) * 100
            let week52High    = meta["fiftyTwoWeekHigh"] as? Double ?? regularPrice
            let week52Low     = meta["fiftyTwoWeekLow"]  as? Double ?? regularPrice
            let dayHigh       = meta["regularMarketDayHigh"] as? Double ?? regularPrice
            let dayLow        = meta["regularMarketDayLow"]  as? Double ?? regularPrice
            let volume        = meta["regularMarketVolume"] as? Int ?? 0

            let closes1m = (first["indicators"] as? [String: Any])
                .flatMap { $0["quote"] as? [[String: Any]] }
                .flatMap { $0.first }
                .flatMap { $0["close"] as? [Double?] }
            let lastExtended = closes1m?.compactMap { $0 }.last
            let isExtended   = lastExtended.map { abs($0 - regularPrice) > 0.01 } ?? false

            // Use cached historical if still fresh, otherwise fetch
            let isCacheValid = cachedEntry.map { Date().timeIntervalSince($0.fetchedAt) < cacheTTL } ?? false
            var sma20: Double? = isCacheValid ? cachedEntry?.data.sma20 : nil
            var sma50: Double? = isCacheValid ? cachedEntry?.data.sma50 : nil
            var rsi14: Double? = isCacheValid ? cachedEntry?.data.rsi14 : nil
            var avgVol: Int    = isCacheValid ? (cachedEntry?.data.avgVolume20d ?? 0) : 0
            var newCacheEntry: (data: PriceData, fetchedAt: Date)? = isCacheValid ? cachedEntry : nil

            if !isCacheValid {
                if let historical = try? await fetch(url: "\(baseURL)/\(symbol)?interval=1d&range=3mo"),
                   let hChart = historical["chart"] as? [String: Any],
                   let hResults = hChart["result"] as? [[String: Any]],
                   let hFirst = hResults.first,
                   let quotes = (hFirst["indicators"] as? [String: Any])?["quote"] as? [[String: Any]],
                   let q = quotes.first {
                    let closes  = (q["close"]  as? [Double?])?.compactMap { $0 } ?? []
                    let volumes = (q["volume"] as? [Int?])?.compactMap { $0 } ?? []
                    sma20  = closes.count  >= 20 ? closes.suffix(20).reduce(0,+) / 20 : nil
                    sma50  = closes.count  >= 50 ? closes.suffix(50).reduce(0,+) / 50 : nil
                    avgVol = volumes.count >= 20 ? volumes.suffix(20).reduce(0,+) / 20 : 0
                    rsi14  = Self.computeWildersRSI(closes: closes, period: 14)
                    // Store a placeholder in cache with current values
                    let placeholder = PriceData(
                        price: regularPrice, dayChangePercent: dayChangePct,
                        extendedPrice: nil, extendedChangePercent: nil,
                        fiftyTwoWeekHigh: week52High, fiftyTwoWeekLow: week52Low,
                        dayHigh: dayHigh, dayLow: dayLow,
                        volume: volume, avgVolume20d: avgVol,
                        sma20: sma20, sma50: sma50, rsi14: rsi14
                    )
                    newCacheEntry = (data: placeholder, fetchedAt: Date())
                }
            }

            let priceData = PriceData(
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
            )
            return (.success(priceData), newCacheEntry)
        } catch {
            return (.failure(error), nil)
        }
    }

    nonisolated private func fetch(url: String) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard http.statusCode == 200 else {
            throw NSError(domain: "YahooFinance", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode)\(http.statusCode == 429 ? " — rate limited" : "")"
            ])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Parse error"])
        }
        return json
    }

    // Wilder's smoothed RSI — matches TradingView/Bloomberg output
    private static func computeWildersRSI(closes: [Double], period: Int) -> Double? {
        guard closes.count > period + 1 else { return nil }
        let changes = zip(closes.dropFirst(), closes).map { $0 - $1 }

        // Seed with simple average over first period
        let seed = Array(changes.prefix(period))
        var avgGain = seed.map { max($0, 0) }.reduce(0, +) / Double(period)
        var avgLoss = seed.map { max(-$0, 0) }.reduce(0, +) / Double(period)

        // Apply Wilder's smoothing for remaining periods
        for change in changes.dropFirst(period) {
            avgGain = (avgGain * Double(period - 1) + max(change, 0)) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + max(-change, 0)) / Double(period)
        }

        guard avgLoss > 0 else { return 100 }
        return 100 - (100 / (1 + avgGain / avgLoss))
    }
}
