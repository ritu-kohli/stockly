import Foundation
import SwiftUI
// import SwiftData  // DISABLED — Supabase is source of truth
import Network

@MainActor
class PortfolioViewModel: ObservableObject {

    @Published var holdings: [HoldingLocal] = []
    @Published var prices: [String: PriceData] = [:]
    @Published var isLoading = false
    @Published var isSyncing = false
    @Published var isOffline = false
    @Published var lastUpdated = "Loading prices..."
    @Published var earningsDates: [String: EarningsInfo] = [:]
    @Published var errorMessage: String?

    // private var modelContext: ModelContext  // DISABLED — SwiftData
    private var historicalCache: [String: (data: PriceData, fetchedAt: Date)] = [:]
    private var refreshTimer: Timer?
    private var networkMonitor: NWPathMonitor?
    private static let historicalCacheTTL: TimeInterval = 3600
    private static let refreshInterval: TimeInterval = 300

    init() {
        startNetworkMonitor()
    }

    // MARK: - Network Monitor

    private func startNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                if wasOffline && path.status == .satisfied {
                    self?.syncFromSupabase()
                    self?.refreshPrices()
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    // MARK: - Context (SwiftData disabled)
    // func updateContext(_ context: ModelContext) { ... }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isMarketHours(), !self.isOffline else { return }
                await self.fetchPrices(for: self.holdings.map { $0.sym })
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func isMarketHours() -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }
        let totalMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return totalMinutes >= 570 && totalMinutes <= 1020
    }

    // MARK: - Supabase Sync (sole source of truth)

    func syncFromSupabase() {
        guard !isSyncing else { return }
        Task {
            guard await SupabaseService.shared.isConfigured else { return }
            isSyncing = true
            defer { isSyncing = false }
            do {
                let remote = try await SupabaseService.shared.fetchHoldings()
                holdings = remote
                if !holdings.isEmpty {
                    await fetchPrices(for: holdings.map { $0.sym })
                }
            } catch {
                if isOffline {
                    lastUpdated = "Offline — data will sync when connected"
                } else {
                    errorMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func addHolding(_ holding: HoldingLocal) {
        guard !holdings.contains(where: { $0.sym == holding.sym }) else {
            errorMessage = "\(holding.sym) is already in your portfolio"
            return
        }
        holdings.append(holding)
        Task {
            if await SupabaseService.shared.isConfigured {
                do {
                    try await SupabaseService.shared.insert(holding)
                } catch {
                    // Rollback local if Supabase fails
                    holdings.removeAll { $0.sym == holding.sym }
                    errorMessage = "Failed to add \(holding.sym): \(error.localizedDescription)"
                    return
                }
            }
            await fetchPrices(for: [holding.sym])
        }
    }

    func updateHolding(_ holding: HoldingLocal, additionalShares: Double, pricePerShare: Double) {
        let totalShares = holding.shares + additionalShares
        let newAvgCost = ((holding.shares * holding.cost) + (additionalShares * pricePerShare)) / totalShares
        if let idx = holdings.firstIndex(where: { $0.sym == holding.sym }) {
            holdings[idx] = HoldingLocal(id: holding.id, sym: holding.sym, name: holding.name,
                                          shares: totalShares, cost: newAvgCost, group: holding.group)
        }
        Task {
            if await SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.upsertHolding(sym: holding.sym,
                                                                 shares: totalShares, cost: newAvgCost)
            }
        }
    }

    func removeHoldings(syms: Set<String>) {
        holdings.removeAll { syms.contains($0.sym) }
        Task {
            if await SupabaseService.shared.isConfigured {
                try? await SupabaseService.shared.delete(syms: Array(syms))
            }
        }
    }

    // MARK: - Computed Totals

    var totalInvested: Double { holdings.reduce(0) { $0 + ($1.shares * $1.cost) } }

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

    func smartStatus(for holding: HoldingLocal) -> SmartStatus {
        guard let p = prices[holding.sym] else {
            return SmartStatus(status: .hold, label: "Neutral")
        }

        var score: Double = 0
        var reasons: [String] = []

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

        if let rsi = p.rsi14 {
            switch rsi {
            case ..<30: score += 2; reasons.append("RSI oversold")
            case ..<40: score += 1; reasons.append("RSI low")
            case 70...: score -= 2; reasons.append("RSI overbought")
            case 60...: score -= 1; reasons.append("RSI high")
            default: break
            }
        }

        if let sma20 = p.sma20 {
            if p.price > sma20 * 1.02      { score += 1; reasons.append("above SMA20") }
            else if p.price < sma20 * 0.98 { score -= 1; reasons.append("below SMA20") }
        }
        if let sma50 = p.sma50 {
            if p.price > sma50 * 1.02      { score += 1; reasons.append("above SMA50") }
            else if p.price < sma50 * 0.98 { score -= 1; reasons.append("below SMA50") }
        }
        if let sma200 = p.sma200 {
            if p.price > sma200 * 1.02      { score += 1; reasons.append("above SMA200") }
            else if p.price < sma200 * 0.98 { score -= 1; reasons.append("below SMA200") }
        }

        let week52Range = p.fiftyTwoWeekHigh - p.fiftyTwoWeekLow
        if week52Range > 0 {
            let position = (p.price - p.fiftyTwoWeekLow) / week52Range
            if position >= 0.80      { score -= 1; reasons.append("near 52w high") }
            else if position <= 0.20 { score += 1; reasons.append("near 52w low") }
        }

        if p.avgVolume20d > 0 {
            let volRatio = Double(p.volume) / Double(p.avgVolume20d)
            if volRatio >= 2.0 && p.dayChangePercent > 0 { score += 1; reasons.append("volume surge up") }
            if volRatio >= 2.0 && p.dayChangePercent < 0 { score -= 1; reasons.append("volume surge down") }
        }

        switch p.dayChangePercent {
        case ..<(-3): score -= 1; reasons.append("big day drop")
        case 3...:    score += 1; reasons.append("big day gain")
        default: break
        }

        let status: SmartStatusType
        let label: String
        switch score {
        case 5...:        status = .strongBuy; label = "Trending Up"
        case 2...:        status = .buy;       label = "Bullish"
        case 0..<2:       status = .hold;      label = "Sideways"
        case (-2)..<0:    status = .watch;     label = "Bearish"
        case (-4)..<(-2): status = .trim;      label = "Deteriorating"
        default:          status = .review;    label = "Breaking Down"
        }

        return SmartStatus(status: status, label: label, score: score, reasons: reasons)
    }

    // MARK: - Earnings

    func isEarningsThisWeek(_ symbol: String) -> Bool {
        guard let info = earningsDates[symbol],
              let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) else { return false }
        return info.date >= Date() && info.date <= weekFromNow
    }

    // MARK: - Prices

    func refreshPrices() {
        guard !holdings.isEmpty, !isOffline else { return }
        Task { await fetchPrices(for: holdings.map { $0.sym }) }
    }

    private func fetchPrices(for symbols: [String]) async {
        isLoading = true
        let spyCloses = await YahooFinanceService.shared.fetchSPYCloses()
        let result = await YahooFinanceService.shared.fetchPrices(
            for: symbols,
            cachedHistorical: historicalCache,
            cacheTTL: Self.historicalCacheTTL,
            spyCloses: spyCloses
        )
        switch result {
        case .success(let (newPrices, updatedCache)):
            for (sym, data) in newPrices { prices[sym] = data }
            for (sym, entry) in updatedCache { historicalCache[sym] = entry }
            lastUpdated = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
        case .failure:
            for sym in symbols where prices[sym] == nil {
                prices[sym] = fallbackPrice(for: sym)
            }
            lastUpdated = isOffline ? "Offline" : "Using cached prices"
        }
        isLoading = false
    }

    private func fallbackPrice(for sym: String) -> PriceData {
        let cost = holdings.first(where: { $0.sym == sym })?.cost ?? 100
        return PriceData(
            price: cost, dayChangePercent: 0,
            extendedPrice: nil, extendedChangePercent: nil,
            fiftyTwoWeekHigh: cost * 1.3, fiftyTwoWeekLow: cost * 0.7,
            dayHigh: cost, dayLow: cost,
            volume: 0, avgVolume20d: 0,
            sma20: nil, sma50: nil, sma200: nil, rsi14: nil,
            beta: nil, sharpeRatio: nil,
            annualizedVolatility: nil, maxDrawdown: nil, return1y: nil
        )
    }
}

// MARK: - Yahoo Finance Service

actor YahooFinanceService {
    static let shared = YahooFinanceService()
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"
    private init() {}

    typealias HistoricalCache = [String: (data: PriceData, fetchedAt: Date)]

    func fetchSPYCloses() async -> [Double] {
        guard let spy = try? await fetch(url: "\(baseURL)/SPY?interval=1d&range=1y"),
              let chart = spy["chart"] as? [String: Any],
              let results = chart["result"] as? [[String: Any]],
              let first = results.first,
              let quotes = (first["indicators"] as? [String: Any])?["quote"] as? [[String: Any]],
              let q = quotes.first else { return [] }
        return (q["close"] as? [Double?])?.compactMap { $0 } ?? []
    }

    func fetchPrices(
        for symbols: [String],
        cachedHistorical: HistoricalCache,
        cacheTTL: TimeInterval,
        spyCloses: [Double]
    ) async -> Result<([String: PriceData], HistoricalCache), Error> {
        var priceData: [String: PriceData] = [:]
        var updatedCache: HistoricalCache = [:]
        var fetchError: Error?

        await withTaskGroup(of: (String, Result<PriceData, Error>, (data: PriceData, fetchedAt: Date)?).self) { group in
            for symbol in symbols {
                let cached = cachedHistorical[symbol]
                group.addTask {
                    let (result, entry) = await self.fetchSinglePrice(
                        for: symbol, cachedEntry: cached,
                        cacheTTL: cacheTTL, spyCloses: spyCloses
                    )
                    return (symbol, result, entry)
                }
            }
            for await (symbol, result, entry) in group {
                switch result {
                case .success(let data):
                    priceData[symbol] = data
                    if let e = entry { updatedCache[symbol] = e }
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
        cacheTTL: TimeInterval,
        spyCloses: [Double]
    ) async -> (Result<PriceData, Error>, (data: PriceData, fetchedAt: Date)?) {
        do {
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

            let dayChangePct = ((regularPrice - previousClose) / previousClose) * 100
            let week52High   = meta["fiftyTwoWeekHigh"] as? Double ?? regularPrice
            let week52Low    = meta["fiftyTwoWeekLow"]  as? Double ?? regularPrice
            let dayHigh      = meta["regularMarketDayHigh"] as? Double ?? regularPrice
            let dayLow       = meta["regularMarketDayLow"]  as? Double ?? regularPrice
            let volume       = meta["regularMarketVolume"] as? Int ?? 0

            let closes1m = (first["indicators"] as? [String: Any])
                .flatMap { $0["quote"] as? [[String: Any]] }
                .flatMap { $0.first }
                .flatMap { $0["close"] as? [Double?] }
            let lastExtended = closes1m?.compactMap { $0 }.last
            let isExtended   = lastExtended.map { abs($0 - regularPrice) > 0.01 } ?? false

            let isCacheValid = cachedEntry.map { Date().timeIntervalSince($0.fetchedAt) < cacheTTL } ?? false
            var sma20: Double?  = isCacheValid ? cachedEntry?.data.sma20 : nil
            var sma50: Double?  = isCacheValid ? cachedEntry?.data.sma50 : nil
            var sma200: Double? = isCacheValid ? cachedEntry?.data.sma200 : nil
            var rsi14: Double?  = isCacheValid ? cachedEntry?.data.rsi14 : nil
            var avgVol: Int     = isCacheValid ? (cachedEntry?.data.avgVolume20d ?? 0) : 0
            var beta: Double?   = isCacheValid ? cachedEntry?.data.beta : nil
            var sharpe: Double? = isCacheValid ? cachedEntry?.data.sharpeRatio : nil
            var annVol: Double? = isCacheValid ? cachedEntry?.data.annualizedVolatility : nil
            var maxDD: Double?  = isCacheValid ? cachedEntry?.data.maxDrawdown : nil
            var ret1y: Double?  = isCacheValid ? cachedEntry?.data.return1y : nil
            var newCacheEntry: (data: PriceData, fetchedAt: Date)? = isCacheValid ? cachedEntry : nil

            if !isCacheValid {
                if let h1y = try? await fetch(url: "\(baseURL)/\(symbol)?interval=1d&range=1y"),
                   let hChart = h1y["chart"] as? [String: Any],
                   let hResults = hChart["result"] as? [[String: Any]],
                   let hFirst = hResults.first,
                   let quotes = (hFirst["indicators"] as? [String: Any])?["quote"] as? [[String: Any]],
                   let q = quotes.first {

                    let closes  = (q["close"]  as? [Double?])?.compactMap { $0 } ?? []
                    let volumes = (q["volume"] as? [Int?])?.compactMap { $0 } ?? []

                    sma20  = closes.count >= 20  ? closes.suffix(20).reduce(0,+)  / 20  : nil
                    sma50  = closes.count >= 50  ? closes.suffix(50).reduce(0,+)  / 50  : nil
                    sma200 = closes.count >= 200 ? closes.suffix(200).reduce(0,+) / 200 : nil
                    avgVol = volumes.count >= 20 ? volumes.suffix(20).reduce(0,+) / 20 : 0
                    rsi14  = Self.computeWildersRSI(closes: closes, period: 14)

                    let metrics = Self.computeRiskMetrics(closes: closes)
                    annVol = metrics.volatility
                    sharpe = metrics.sharpe
                    maxDD  = metrics.maxDrawdown
                    ret1y  = metrics.return1y

                    if !spyCloses.isEmpty {
                        beta = Self.computeBeta(stock: closes, market: spyCloses)
                    }

                    let placeholder = PriceData(
                        price: regularPrice, dayChangePercent: dayChangePct,
                        extendedPrice: nil, extendedChangePercent: nil,
                        fiftyTwoWeekHigh: week52High, fiftyTwoWeekLow: week52Low,
                        dayHigh: dayHigh, dayLow: dayLow,
                        volume: volume, avgVolume20d: avgVol,
                        sma20: sma20, sma50: sma50, sma200: sma200, rsi14: rsi14,
                        beta: beta, sharpeRatio: sharpe,
                        annualizedVolatility: annVol, maxDrawdown: maxDD, return1y: ret1y
                    )
                    newCacheEntry = (data: placeholder, fetchedAt: Date())
                }
            }

            let priceData = PriceData(
                price: regularPrice, dayChangePercent: dayChangePct,
                extendedPrice: isExtended ? lastExtended : nil,
                extendedChangePercent: isExtended ? lastExtended.map { (($0 - regularPrice) / regularPrice) * 100 } : nil,
                fiftyTwoWeekHigh: week52High, fiftyTwoWeekLow: week52Low,
                dayHigh: dayHigh, dayLow: dayLow,
                volume: volume, avgVolume20d: avgVol,
                sma20: sma20, sma50: sma50, sma200: sma200, rsi14: rsi14,
                beta: beta, sharpeRatio: sharpe,
                annualizedVolatility: annVol, maxDrawdown: maxDD, return1y: ret1y
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

    private static func computeBeta(stock: [Double], market: [Double]) -> Double? {
        let n = min(stock.count, market.count)
        guard n > 30 else { return nil }
        let s = Array(stock.suffix(n))
        let m = Array(market.suffix(n))
        let sr = (1..<n).map { s[$0]/s[$0-1] - 1 }
        let mr = (1..<n).map { m[$0]/m[$0-1] - 1 }
        let meanS = sr.reduce(0,+) / Double(sr.count)
        let meanM = mr.reduce(0,+) / Double(mr.count)
        let cov  = zip(sr, mr).map { ($0 - meanS) * ($1 - meanM) }.reduce(0,+) / Double(sr.count)
        let varM = mr.map { ($0 - meanM) * ($0 - meanM) }.reduce(0,+) / Double(mr.count)
        guard varM > 1e-10 else { return nil }
        return cov / varM
    }

    private static func computeRiskMetrics(closes: [Double]) -> (volatility: Double?, sharpe: Double?, maxDrawdown: Double?, return1y: Double?) {
        guard closes.count > 2 else { return (nil, nil, nil, nil) }
        let returns = (1..<closes.count).map { closes[$0]/closes[$0-1] - 1 }
        let mean = returns.reduce(0,+) / Double(returns.count)
        let variance = returns.map { ($0 - mean) * ($0 - mean) }.reduce(0,+) / Double(returns.count)
        let stdDev = variance.squareRoot()
        guard stdDev > 1e-10 else { return (0, nil, 0, (closes.last! / closes.first! - 1) * 100) }
        let annVol = stdDev * sqrt(252) * 100
        let rfDaily = 0.045 / 252
        let sharpe = (mean - rfDaily) / stdDev * sqrt(252)
        var peak = closes[0], maxDD = 0.0
        for c in closes {
            if c > peak { peak = c }
            let dd = (peak - c) / peak
            if dd > maxDD { maxDD = dd }
        }
        return (annVol, sharpe, maxDD * 100, (closes.last! / closes.first! - 1) * 100)
    }

    private static func computeWildersRSI(closes: [Double], period: Int) -> Double? {
        guard closes.count > period + 1 else { return nil }
        let changes = zip(closes.dropFirst(), closes).map { $0 - $1 }
        let seed = Array(changes.prefix(period))
        var avgGain = seed.map { max($0, 0) }.reduce(0, +) / Double(period)
        var avgLoss = seed.map { max(-$0, 0) }.reduce(0, +) / Double(period)
        for change in changes.dropFirst(period) {
            avgGain = (avgGain * Double(period - 1) + max(change, 0)) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + max(-change, 0)) / Double(period)
        }
        guard avgLoss > 1e-10 else { return 100 }
        return 100 - (100 / (1 + avgGain / avgLoss))
    }
}
