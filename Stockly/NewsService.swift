import Foundation

// MARK: - Models

struct NewsArticle: Identifiable, Sendable {
    let id: String
    let title: String
    let publisher: String
    let url: String
    let publishedAt: Date
    let sentiment: Sentiment
    let catalyst: CatalystType
    let impactScore: Double   // 0.0 - 1.0, how significant this news is
    let reasoning: String     // Claude's explanation
}

enum Sentiment: String, Sendable {
    case bullish = "Bullish"
    case bearish = "Bearish"
    case neutral = "Neutral"

    var emoji: String {
        switch self {
        case .bullish: return "↑"
        case .bearish: return "↓"
        case .neutral: return "–"
        }
    }
}

enum CatalystType: String, Sendable {
    case earnings = "Earnings"
    case analyst  = "Analyst"
    case macro    = "Macro"
    case product  = "Product"
    case legal    = "Legal"
    case insider  = "Insider"
    case dividend = "Dividend"
    case merger   = "M&A"
    case general  = "News"
}

struct StockAnalysis: Sendable {
    let symbol: String
    let articles: [NewsArticle]
    let overallSentiment: Sentiment
    let bullishCount: Int
    let bearishCount: Int
    let neutralCount: Int
    let topCatalysts: [CatalystType]
    let summary: String
    let analyzedWithAI: Bool
}

// MARK: - News Service

actor NewsService {
    static let shared = NewsService()
    private init() {}

    private var cache: [String: (analysis: StockAnalysis, fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 900 // 15 min

    func fetchAnalysis(for symbol: String, companyName: String) async -> StockAnalysis {
        if let cached = cache[symbol], Date().timeIntervalSince(cached.fetchedAt) < cacheTTL {
            return cached.analysis
        }
        let rawArticles = await fetchNews(for: symbol)
        // If no symbol-specific articles found, return empty rather than misclassifying
        guard !rawArticles.isEmpty else {
            return emptyAnalysis(symbol: symbol, withAI: Keychain.claudeKey != nil)
        }
        let analysis: StockAnalysis

        if let apiKey = Keychain.claudeKey, !apiKey.isEmpty {
            analysis = await analyzeWithClaude(symbol: symbol, companyName: companyName, rawArticles: rawArticles, apiKey: apiKey)
        } else {
            analysis = analyzeOnDevice(symbol: symbol, companyName: companyName, rawArticles: rawArticles)
        }

        cache[symbol] = (analysis: analysis, fetchedAt: Date())
        return analysis
    }

    // MARK: - Fetch raw news

    private func fetchNews(for symbol: String) async -> [(uuid: String, title: String, publisher: String, link: String, time: TimeInterval)] {
        let query = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(query)&quotesCount=0&newsCount=10&enableFuzzyQuery=false") else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let news = json["news"] as? [[String: Any]] else { return [] }

        return news.compactMap { item in
            guard let uuid  = item["uuid"]  as? String,
                  let title = item["title"] as? String,
                  let pub   = item["publisher"] as? String,
                  let link  = item["link"] as? String,
                  let time  = item["providerPublishTime"] as? TimeInterval else { return nil }
            // Filter out articles that don't mention the symbol — reduces noise from market-wide news
            let tickers = item["relatedTickers"] as? [String] ?? []
            let titleMentionsSymbol = title.localizedCaseInsensitiveContains(symbol)
            guard tickers.contains(symbol) || titleMentionsSymbol else { return nil }
            return (uuid, title, pub, link, time)
        }
    }

    // MARK: - Claude Analysis

    private func analyzeWithClaude(
        symbol: String,
        companyName: String,
        rawArticles: [(uuid: String, title: String, publisher: String, link: String, time: TimeInterval)],
        apiKey: String
    ) async -> StockAnalysis {
        guard !rawArticles.isEmpty else {
            return emptyAnalysis(symbol: symbol, withAI: true)
        }

        // Build headlines list for Claude
        let headlines = rawArticles.enumerated().map { i, a in
            "\(i + 1). \"\(a.title)\" — \(a.publisher)"
        }.joined(separator: "\n")

        let prompt = """
        You are a financial analyst. Analyze these recent news headlines for \(companyName) (\(symbol)).

        Headlines:
        \(headlines)

        For each headline, respond with a JSON array. Each object must have:
        - "index": number (1-based, matching the headline number)
        - "sentiment": "bullish", "bearish", or "neutral"
        - "catalyst": one of "Earnings", "Analyst", "Macro", "Product", "Legal", "Insider", "Dividend", "M&A", "News"
        - "impact": number 0.0-1.0 (how significant is this for the stock price)
        - "reasoning": one concise sentence explaining the impact on \(symbol) stock

        Consider:
        - Analyst upgrades/downgrades and price target changes
        - Earnings beats/misses and guidance changes
        - Macro factors like tariffs, rates, regulation
        - Product launches, partnerships, competitive threats
        - Management changes, legal issues, insider activity

        Respond with ONLY the JSON array, no other text.
        """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return analyzeOnDevice(symbol: symbol, companyName: companyName, rawArticles: rawArticles)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json",      forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,                  forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",            forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return analyzeOnDevice(symbol: symbol, companyName: companyName, rawArticles: rawArticles)
        }
        request.httpBody = bodyData

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              let text = content["text"] as? String else {
            return analyzeOnDevice(symbol: symbol, companyName: companyName, rawArticles: rawArticles)
        }

        // Parse Claude's JSON response
        guard let jsonData = text.data(using: .utf8),
              let results = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return analyzeOnDevice(symbol: symbol, companyName: companyName, rawArticles: rawArticles)
        }

        let articles: [NewsArticle] = rawArticles.enumerated().compactMap { i, raw in
            let result = results.first { ($0["index"] as? Int) == i + 1 }
            let sentimentStr = result?["sentiment"] as? String ?? "neutral"
            let catalystStr  = result?["catalyst"]  as? String ?? "News"
            let impact       = result?["impact"]     as? Double ?? 0.3
            let reasoning    = result?["reasoning"]  as? String ?? ""

            return NewsArticle(
                id: raw.uuid, title: raw.title, publisher: raw.publisher, url: raw.link,
                publishedAt: Date(timeIntervalSince1970: raw.time),
                sentiment: Sentiment(rawValue: sentimentStr.capitalized) ?? .neutral,
                catalyst: CatalystType(rawValue: catalystStr) ?? .general,
                impactScore: impact,
                reasoning: reasoning
            )
        }

        return buildAnalysis(symbol: symbol, articles: articles, withAI: true)
    }

    // MARK: - On-device fallback (NLTagger + domain boosters)

    private func analyzeOnDevice(
        symbol: String,
        companyName: String,
        rawArticles: [(uuid: String, title: String, publisher: String, link: String, time: TimeInterval)]
    ) -> StockAnalysis {
        let articles: [NewsArticle] = rawArticles.map { raw in
            NewsArticle(
                id: raw.uuid, title: raw.title, publisher: raw.publisher, url: raw.link,
                publishedAt: Date(timeIntervalSince1970: raw.time),
                sentiment: classifySentiment(raw.title),
                catalyst: classifyCatalyst(raw.title),
                impactScore: classifyImpact(raw.title),
                reasoning: ""
            )
        }
        return buildAnalysis(symbol: symbol, articles: articles, withAI: false)
    }

    // MARK: - Build final analysis

    private func buildAnalysis(symbol: String, articles: [NewsArticle], withAI: Bool) -> StockAnalysis {
        let bullish = articles.filter { $0.sentiment == .bullish }.count
        let bearish = articles.filter { $0.sentiment == .bearish }.count
        let neutral = articles.filter { $0.sentiment == .neutral }.count
        let total   = bullish + bearish + neutral

        // Use weighted average impact score for overall sentiment
        // Neutral articles count as 0, bullish as +impact, bearish as -impact
        let sentimentScore: Double
        if total == 0 {
            sentimentScore = 0
        } else {
            let bullishWeight = articles.filter { $0.sentiment == .bullish }.map { $0.impactScore }.reduce(0, +)
            let bearishWeight = articles.filter { $0.sentiment == .bearish }.map { $0.impactScore }.reduce(0, +)
            sentimentScore = bullishWeight - bearishWeight
        }

        let overall: Sentiment
        if sentimentScore > 0.3       { overall = .bullish }
        else if sentimentScore < -0.3 { overall = .bearish }
        else                          { overall = .neutral }

        let topCatalysts = Dictionary(grouping: articles, by: { $0.catalyst })
            .filter { $0.key != .general }
            .sorted { $0.value.count > $1.value.count }
            .prefix(3).map { $0.key }

        var summaryParts: [String] = []
        if total == 0 {
            summaryParts.append("No recent news found.")
        } else {
            switch overall {
            case .bullish: summaryParts.append("News sentiment is mostly positive (\(bullish)/\(total) bullish).")
            case .bearish: summaryParts.append("News sentiment is mostly negative (\(bearish)/\(total) bearish).")
            case .neutral: summaryParts.append("News sentiment is mixed (\(bullish) bullish, \(bearish) bearish).")
            }
            if !topCatalysts.isEmpty {
                summaryParts.append("Key drivers: \(topCatalysts.map { $0.rawValue }.joined(separator: ", ")).")
            }
        }
        if withAI { summaryParts.append("Analyzed by Claude AI.") }

        return StockAnalysis(
            symbol: symbol, articles: articles,
            overallSentiment: overall,
            bullishCount: bullish, bearishCount: bearish, neutralCount: neutral,
            topCatalysts: Array(topCatalysts),
            summary: summaryParts.joined(separator: " "),
            analyzedWithAI: withAI
        )
    }

    private func emptyAnalysis(symbol: String, withAI: Bool) -> StockAnalysis {
        StockAnalysis(symbol: symbol, articles: [], overallSentiment: .neutral,
                      bullishCount: 0, bearishCount: 0, neutralCount: 0,
                      topCatalysts: [], summary: "No recent news found for \(symbol).", analyzedWithAI: withAI)
    }

    // MARK: - NLTagger + domain boosters

    nonisolated private func classifySentiment(_ title: String) -> Sentiment {
        // NLTagger is trained on general English and scores financial headlines incorrectly
        // (e.g. "GOOGL surges" = -0.8, "Apple shares rise" = -0.6)
        // Use financial domain keyword scoring only
        let t = title.lowercased()
        var score: Double = 0

        let bullish: [(String, Double)] = [
            ("beat", 0.5), ("beats", 0.5), ("topped", 0.4), ("surpass", 0.4),
            ("record", 0.3), ("upgrade", 0.5), ("upgraded", 0.5),
            ("raises guidance", 0.6), ("raised guidance", 0.6), ("raises forecast", 0.6),
            ("outperform", 0.4), ("overweight", 0.4), ("buy rating", 0.5),
            ("price target raised", 0.6), ("target raised", 0.5),
            ("better than expected", 0.5), ("above expectations", 0.5),
            ("strong earnings", 0.6), ("strong results", 0.5), ("strong quarter", 0.5),
            ("all-time high", 0.5), ("52-week high", 0.4),
            ("buyback", 0.3), ("dividend increase", 0.4), ("revenue growth", 0.4),
            ("surges", 0.4), ("jumps", 0.4), ("climbs", 0.3), ("rises", 0.3),
            ("rallies", 0.4), ("soars", 0.5), ("breakout", 0.4),
            ("profit rises", 0.5), ("earnings beat", 0.6), ("eps beat", 0.6),
            ("accelerating growth", 0.5), ("strong demand", 0.4)
        ]
        let bearish: [(String, Double)] = [
            ("miss", 0.5), ("misses", 0.5), ("missed", 0.5),
            ("downgrade", 0.5), ("downgraded", 0.5),
            ("cuts guidance", 0.6), ("cut guidance", 0.6), ("lowers guidance", 0.6),
            ("below expectations", 0.5), ("below estimates", 0.5),
            ("price target cut", 0.6), ("target cut", 0.5), ("target lowered", 0.5),
            ("sell rating", 0.5), ("underperform", 0.4), ("underweight", 0.4),
            ("layoffs", 0.4), ("job cuts", 0.4), ("cuts jobs", 0.4),
            ("investigation", 0.4), ("lawsuit", 0.3), ("fine", 0.3), ("penalty", 0.3),
            ("tariff", 0.3), ("recall", 0.4), ("bankruptcy", 0.6),
            ("earnings miss", 0.6), ("eps miss", 0.6), ("revenue miss", 0.6),
            ("falls", 0.3), ("drops", 0.3), ("slides", 0.3), ("plunges", 0.5),
            ("tumbles", 0.4), ("sinks", 0.4), ("slumps", 0.4),
            ("profit warning", 0.6), ("revenue decline", 0.5), ("slowing growth", 0.4)
        ]

        for (term, weight) in bullish where t.contains(term) { score += weight }
        for (term, weight) in bearish where t.contains(term) { score -= weight }

        // Threshold: require meaningful signal, default to neutral
        if score > 0.3  { return .bullish }
        if score < -0.3 { return .bearish }
        return .neutral
    }

    nonisolated private func classifyImpact(_ title: String) -> Double {
        let t = title.lowercased()
        let highImpact = ["earnings", "guidance", "upgrade", "downgrade", "merger", "acquisition", "lawsuit", "bankruptcy", "beat", "miss"]
        let medImpact  = ["analyst", "price target", "product", "launch", "tariff", "layoff"]
        if highImpact.contains(where: { t.contains($0) }) { return 0.8 }
        if medImpact.contains(where: { t.contains($0) })  { return 0.5 }
        return 0.3
    }

    nonisolated private func classifyCatalyst(_ title: String) -> CatalystType {
        let t = title.lowercased()
        if t.contains("earn") || t.contains("eps") || t.contains("quarter") || t.contains("guidance") { return .earnings }
        if t.contains("analyst") || t.contains("upgrade") || t.contains("downgrade") || t.contains("price target") { return .analyst }
        if t.contains("fed") || t.contains("inflation") || t.contains("rate") || t.contains("tariff") || t.contains("macro") { return .macro }
        if t.contains("product") || t.contains("launch") || t.contains("release") || t.contains("announce") { return .product }
        if t.contains("lawsuit") || t.contains("legal") || t.contains("court") || t.contains("sec") || t.contains("fine") { return .legal }
        if t.contains("ceo") || t.contains("cfo") || t.contains("executive") || t.contains("appoint") || t.contains("resign") { return .insider }
        if t.contains("dividend") || t.contains("buyback") || t.contains("repurchase") { return .dividend }
        if t.contains("merger") || t.contains("acqui") || t.contains("takeover") || t.contains("buyout") { return .merger }
        return .general
    }
}
