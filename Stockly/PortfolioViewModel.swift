// MARK: - ViewModel
import Foundation
import SwiftUI

// Models are defined in Models.swift

@MainActor
class PortfolioViewModel: ObservableObject {

    @Published var holdings: [Holding] = []
    @Published var prices: [String: PriceData] = [:]
    @Published var isLoading = false
    @Published var statusMessage = "Loading..."
    @Published var lastUpdated = "Loading prices..."
    @Published var earningsDates: [String: EarningsInfo] = [:]

    init() {
        loadHoldings()
        refreshPrices()
    }

    private let holdingsKey = "saved_holdings"

    func loadHoldings() {
        if let data = UserDefaults.standard.data(forKey: holdingsKey),
           let saved = try? JSONDecoder().decode([Holding].self, from: data), !saved.isEmpty {
            holdings = saved
        } else {
            holdings = [
                Holding(sym: "META", name: "Meta Platforms", shares: 16, cost: 669.51, status: .hold, note: "", group: .tech),
                Holding(sym: "MSFT", name: "Microsoft", shares: 14, cost: 422.51, status: .buy, note: "", group: .tech),
                Holding(sym: "GOOGL", name: "Alphabet", shares: 5, cost: 336.43, status: .buy, note: "", group: .tech),
                Holding(sym: "AAPL", name: "Apple", shares: 10, cost: 270.50, status: .buy, note: "", group: .tech),
                Holding(sym: "RDDT", name: "Reddit", shares: 50.5811, cost: 165.06, status: .buy, note: "", group: .tech),
                Holding(sym: "AMZN", name: "Amazon", shares: 15.6826, cost: 212.62, status: .buy, note: "", group: .tech),
                Holding(sym: "ONTO", name: "Onto Innovation", shares: 20, cost: 277.97, status: .buy, note: "", group: .semi),
                Holding(sym: "SOLS", name: "Solstice Adv Mat.", shares: 45, cost: 80.09, status: .buy, note: "", group: .semi),
                Holding(sym: "CHRW", name: "C.H. Robinson", shares: 15, cost: 168.13, status: .buy, note: "", group: .logistics),
                Holding(sym: "ODFL", name: "Old Dominion", shares: 10, cost: 208.34, status: .hold, note: "", group: .logistics),
                Holding(sym: "COF", name: "Capital One", shares: 20, cost: 194.38, status: .buy, note: "", group: .logistics),
                Holding(sym: "IREN", name: "Iris Energy", shares: 56, cost: 49.82, status: .watch, note: "", group: .speculative),
                Holding(sym: "PSKY", name: "Paramount Skydance", shares: 127, cost: 11.45, status: .watch, note: "", group: .speculative),
                Holding(sym: "BULL", name: "Webull Corp", shares: 14, cost: 11.55, status: .watch, note: "", group: .speculative)
            ]
            saveHoldings()
        }
    }

    func addHolding(_ holding: Holding) {
        holdings.append(holding)
        saveHoldings()
        refreshPrices()
    }

    func removeHoldings(ids: Set<UUID>) {
        holdings.removeAll { ids.contains($0.id) }
        saveHoldings()
    }

    private func saveHoldings() {
        if let data = try? JSONEncoder().encode(holdings) {
            UserDefaults.standard.set(data, forKey: holdingsKey)
        }
    }

    func refreshPrices() {
        isLoading = true
        statusMessage = "Fetching live prices..."

        // Fetch from Yahoo Finance API
        YahooFinanceService.shared.fetchPrices(for: holdings.map { $0.sym }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                switch result {
                case .success(let priceData):
                    self.prices = priceData
                    self.lastUpdated = "Updated \(Date().formatted(date: .omitted, time: .shortened))"
                    self.statusMessage = "Prices loaded"
                case .failure(let error):
                    // Fallback to simulated prices if API fails
                    self.prices = self.generateFallbackPrices()
                    self.statusMessage = "Using fallback prices: \(error.localizedDescription)"
                    self.lastUpdated = "Fallback \(Date().formatted(date: .omitted, time: .shortened))"
                }

                self.isLoading = false
            }
        }
    }

    // Generate fallback prices based on cost with small random changes
    private func generateFallbackPrices() -> [String: PriceData] {
        var prices: [String: PriceData] = [:]
        for holding in holdings {
            // Simulate a small random day change (-2% to +2%)
            let dayChangePercent = Double.random(in: -2...2)
            // Price varies -5% to +10% from cost
            let variation = Double.random(in: -0.05...0.10)
            let simulatedPrice = holding.cost * (1 + variation)
            prices[holding.sym] = PriceData(price: simulatedPrice, dayChangePercent: dayChangePercent, extendedPrice: nil, extendedChangePercent: nil)
        }
        return prices
    }

    var totalInvested: Double {
        holdings.reduce(0) { $0 + ($1.shares * $1.cost) }
    }

    var totalValue: Double {
        holdings.reduce(0) { total, h in
            let px = prices[h.sym]?.price ?? h.cost
            return total + (h.shares * px)
        }
    }

    var totalPL: Double {
        totalValue - totalInvested
    }

    var totalReturn: Double {
        (totalPL / totalInvested) * 100
    }

    // MARK: - Smart Status Logic

    func smartStatus(for holding: Holding) -> SmartStatus {
        guard let priceData = prices[holding.sym] else {
            return SmartStatus(status: .hold, label: "Hold")
        }

        let currentPrice = priceData.price
        let costBasis = holding.cost
        let percentChange = ((currentPrice - costBasis) / costBasis) * 100

        // Check if position is down more than 15% -> Flag as "Review"
        if percentChange < -15 {
            return SmartStatus(status: .review, label: "Review")
        }

        // Check if Watch stock is up 30%+ -> Flag as "Trim?"
        if holding.status == .watch && percentChange >= 30 {
            return SmartStatus(status: .trim, label: "Trim?")
        }

        // Otherwise return standard rating
        switch holding.status {
        case .buy:
            return SmartStatus(status: .buy, label: "Buy")
        case .hold:
            return SmartStatus(status: .hold, label: "Hold")
        case .watch:
            return SmartStatus(status: .watch, label: "Watch")
        }
    }

    func isReportingEarnings(_ symbol: String) -> EarningsInfo? {
        earningsDates[symbol]
    }

    func isEarningsThisWeek(_ symbol: String) -> Bool {
        guard let info = earningsDates[symbol] else { return false }
        let calendar = Calendar.current
        let today = Date()
        let weekFromNow = calendar.date(byAdding: .day, value: 7, to: today)!
        return info.date >= today && info.date <= weekFromNow
    }
}

// MARK: - Yahoo Finance Service

class YahooFinanceService {
    @MainActor static let shared = YahooFinanceService()

    // Yahoo Finance API endpoint (v8/finance)
    private let baseURL = "https://query1.finance.yahoo.com/v8/finance/chart"

    private init() {}

    func fetchPrices(for symbols: [String], completion: @escaping (Result<[String: PriceData], Error>) -> Void) {
        // Fetch prices for each symbol individually for better error handling
        let group = DispatchGroup()
        var priceData: [String: PriceData] = [:]
        var fetchError: Error?

        for symbol in symbols {
            group.enter()
            fetchSinglePrice(for: symbol) { result in
                switch result {
                case .success(let data):
                    priceData[symbol] = data
                case .failure(let error):
                    fetchError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let error = fetchError {
                completion(.failure(error))
            } else {
                completion(.success(priceData))
            }
        }
    }

    private func fetchSinglePrice(for symbol: String, completion: @escaping (Result<PriceData, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/\(symbol)?interval=1m&range=1d&includePrePost=true") else {
            completion(.failure(NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            let httpResponse = response as? HTTPURLResponse
            guard let httpResponse = httpResponse, httpResponse.statusCode == 200 else {
                completion(.failure(NSError(domain: "YahooFinance", code: httpResponse?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "YahooFinance", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let chart = json?["chart"] as? [String: Any],
                      let result = chart["result"] as? [[String: Any]],
                      let first = result.first,
                      let meta = first["meta"] as? [String: Any] else {
                    if let errorResult = json?["error"] as? [String: Any],
                       let message = errorResult["description"] as? String {
                        completion(.failure(NSError(domain: "YahooFinance", code: -2, userInfo: [NSLocalizedDescriptionKey: message])))
                    } else {
                        completion(.failure(NSError(domain: "YahooFinance", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                    return
                }

                guard let regularPrice = meta["regularMarketPrice"] as? Double,
                      let previousClose = meta["chartPreviousClose"] as? Double else {
                    completion(.failure(NSError(domain: "YahooFinance", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing price data"])))
                    return
                }

                let dayChangePercent = ((regularPrice - previousClose) / previousClose) * 100

                // Extract last price from timestamps (includes pre/post market)
                let closes = (first["indicators"] as? [String: Any])
                    .flatMap { $0["quote"] as? [[String: Any]] }
                    .flatMap { $0.first }
                    .flatMap { $0["close"] as? [Double?] }

                let lastExtended = closes?.compactMap { $0 }.last
                let extendedChange = lastExtended.map { (($0 - regularPrice) / regularPrice) * 100 }
                // Only report extended price if it differs from regular (i.e. market is closed)
                let isExtended = lastExtended.map { abs($0 - regularPrice) > 0.01 } ?? false

                completion(.success(PriceData(
                    price: regularPrice,
                    dayChangePercent: dayChangePercent,
                    extendedPrice: isExtended ? lastExtended : nil,
                    extendedChangePercent: isExtended ? extendedChange : nil
                )))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
}
