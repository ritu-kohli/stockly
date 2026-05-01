import SwiftUI

struct StockDetailView: View {
    let holding: Holding
    @ObservedObject var vm: PortfolioViewModel
    @State private var analysis: StockAnalysis?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private var priceData: PriceData? { vm.prices[holding.sym] }
    private var px: Double { priceData?.price ?? holding.cost }
    private var pnl: Double { (px - holding.cost) * holding.shares }
    private var pnlPct: Double { ((px - holding.cost) / holding.cost) * 100 }
    private var smartStatus: SmartStatus { vm.smartStatus(for: holding) }

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerBar
                    priceCard
                    if isLoading {
                        loadingCard
                    } else if let analysis {
                        sentimentCard(analysis)
                        newsCard(analysis)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .task {
            analysis = await NewsService.shared.fetchAnalysis(for: holding.sym, companyName: holding.name)
            isLoading = false
        }
    }

    // MARK: - Header

    var headerBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")

            Spacer()

            VStack(spacing: 2) {
                Text(holding.sym)
                    .font(.headline.bold())
                    .foregroundColor(.textPrimary)
                Text(holding.name)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Spacer()

            // Balance the back button
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    // MARK: - Price Card

    var priceCard: some View {
        let isUp = (priceData?.dayChangePercent ?? 0) >= 0
        return VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(money(px))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                        .minimumScaleFactor(0.7)

                    if let p = priceData {
                        HStack(spacing: 4) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption.weight(.bold))
                            Text(String(format: "%+.2f%%", p.dayChangePercent))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(isUp ? .gain : .loss)
                    }
                }

                Spacer()

                // Smart status badge
                let (bg, fg) = statusColors(smartStatus.status)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(smartStatus.label)
                        .font(.caption.weight(.bold))
                        .foregroundColor(fg)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(bg)
                        .clipShape(Capsule())
                    Text("Score: \(smartStatus.score > 0 ? "+" : "")\(String(format: "%.0f", smartStatus.score))")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }
            }

            Divider().background(Color.border)

            // Position stats
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                statCell("P&L", value: "\(pnl >= 0 ? "+" : "")\(money(pnl))", color: pnl >= 0 ? .gain : .loss)
                statCell("Return", value: String(format: "%+.1f%%", pnlPct), color: pnlPct >= 0 ? .gain : .loss)
                statCell("Shares", value: String(format: "%.4g", holding.shares), color: .textSecondary)
                statCell("Avg Cost", value: money(holding.cost), color: .textSecondary)
                if let p = priceData {
                    statCell("52W High", value: money(p.fiftyTwoWeekHigh), color: .textSecondary)
                    statCell("52W Low",  value: money(p.fiftyTwoWeekLow),  color: .textSecondary)
                }
            }

            // Technical signals
            if !smartStatus.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Technical Signals")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textTertiary)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    FlowLayout(spacing: 6) {
                        ForEach(smartStatus.reasons, id: \.self) { reason in
                            Text(reason)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.surface2)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // After hours
            if let extPx = priceData?.extendedPrice, let extChg = priceData?.extendedChangePercent {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars").font(.caption).foregroundColor(.textTertiary)
                    Text("After hours").font(.caption).foregroundColor(.textTertiary)
                    Text(money(extPx)).font(.caption.weight(.semibold)).foregroundColor(.textSecondary)
                    Text(String(format: "%+.2f%%", extChg))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(extChg >= 0 ? .gain : .loss)
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.border, lineWidth: 1))
    }

    // MARK: - Loading

    var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.accent)
            Text("Analyzing news with \(Keychain.claudeKey != nil ? "Claude AI" : "on-device NLP")…")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Sentiment Card

    func sentimentCard(_ analysis: StockAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("News Analysis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if analysis.analyzedWithAI {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("Claude AI")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accent.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            // Overall sentiment
            HStack(spacing: 12) {
                sentimentMeter(analysis)
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.overallSentiment.rawValue)
                        .font(.title3.weight(.bold))
                        .foregroundColor(sentimentColor(analysis.overallSentiment))
                    Text(analysis.summary)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Catalyst tags
            if !analysis.topCatalysts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Key Catalysts")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textTertiary)
                        .textCase(.uppercase)
                        .kerning(0.6)
                    FlowLayout(spacing: 6) {
                        ForEach(analysis.topCatalysts, id: \.rawValue) { catalyst in
                            Text(catalyst.rawValue)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(catalystColor(catalyst))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(catalystColor(catalyst).opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Sentiment breakdown bar
            sentimentBar(analysis)
        }
        .padding(20)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.border, lineWidth: 1))
    }

    func sentimentMeter(_ analysis: StockAnalysis) -> some View {
        ZStack {
            Circle()
                .stroke(Color.surface2, lineWidth: 6)
                .frame(width: 64, height: 64)
            Circle()
                .trim(from: 0, to: CGFloat(analysis.bullishCount) / CGFloat(max(analysis.articles.count, 1)))
                .stroke(Color.gain, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-90))
            Text(analysis.overallSentiment.emoji)
                .font(.title2)
        }
    }

    func sentimentBar(_ analysis: StockAnalysis) -> some View {
        let total = max(analysis.articles.count, 1)
        let bullPct = CGFloat(analysis.bullishCount) / CGFloat(total)
        let bearPct = CGFloat(analysis.bearishCount) / CGFloat(total)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gain)
                        .frame(width: geo.size.width * bullPct)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.loss)
                        .frame(width: geo.size.width * bearPct)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.surface2)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack {
                Label("\(analysis.bullishCount) Bullish", systemImage: "arrow.up.right")
                    .font(.caption2).foregroundColor(.gain)
                Spacer()
                Label("\(analysis.neutralCount) Neutral", systemImage: "minus")
                    .font(.caption2).foregroundColor(.textTertiary)
                Spacer()
                Label("\(analysis.bearishCount) Bearish", systemImage: "arrow.down.right")
                    .font(.caption2).foregroundColor(.loss)
            }
        }
    }

    // MARK: - News Card

    func newsCard(_ analysis: StockAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent News")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            ForEach(analysis.articles) { article in
                newsRow(article)
                if article.id != analysis.articles.last?.id {
                    Divider().padding(.leading, 20).background(Color.border)
                }
            }
        }
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.border, lineWidth: 1))
    }

    func newsRow(_ article: NewsArticle) -> some View {
        Button(action: {
            if let url = URL(string: article.url) {
                UIApplication.shared.open(url)
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    // Sentiment indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(sentimentColor(article.sentiment))
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(article.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 8) {
                            Text(article.publisher)
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            Text("·")
                                .foregroundColor(.textTertiary)
                            Text(article.publishedAt.formatted(.relative(presentation: .named)))
                                .font(.caption2)
                                .foregroundColor(.textTertiary)
                            Spacer()
                            // Catalyst + impact
                            HStack(spacing: 4) {
                                if article.catalyst != .general {
                                    Text(article.catalyst.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(catalystColor(article.catalyst))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(catalystColor(article.catalyst).opacity(0.12))
                                        .clipShape(Capsule())
                                }
                                impactDots(article.impactScore)
                            }
                        }

                        // Claude's reasoning
                        if !article.reasoning.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                    .foregroundColor(.accent)
                                Text(article.reasoning)
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(article.title). \(article.publisher). \(article.sentiment.rawValue) sentiment. \(article.reasoning)")
    }

    func impactDots(_ score: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Double(i) < score * 3 ? Color.accent : Color.surface2)
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: - Helpers

    func statCell(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    func sentimentColor(_ s: Sentiment) -> Color {
        switch s {
        case .bullish: return .gain
        case .bearish: return .loss
        case .neutral: return .textSecondary
        }
    }

    func catalystColor(_ c: CatalystType) -> Color {
        switch c {
        case .earnings: return .accent
        case .analyst:  return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .macro:    return .orange
        case .product:  return Color(red: 0.4, green: 0.8, blue: 0.6)
        case .legal:    return .loss
        case .insider:  return Color(red: 0.9, green: 0.7, blue: 0.2)
        case .dividend: return .gain
        case .merger:   return Color(red: 0.8, green: 0.4, blue: 1.0)
        case .general:  return .textTertiary
        }
    }

    func statusColors(_ s: SmartStatusType) -> (Color, Color) {
        switch s {
        case .strongBuy: return (Color.gain.opacity(0.2),    .gain)
        case .buy:       return (Color.gain.opacity(0.15),   .gain)
        case .hold:      return (Color.white.opacity(0.08),  .textSecondary)
        case .watch:     return (Color.blue.opacity(0.15),   .blue)
        case .trim:      return (Color.orange.opacity(0.15), .orange)
        case .review:    return (Color.loss.opacity(0.15),   .loss)
        }
    }

    private let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    func money(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}

// MARK: - Flow Layout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for view in row {
                let size = view.sizeThatFits(.unspecified)
                view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var x: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity
        for view in subviews {
            let w = view.sizeThatFits(.unspecified).width
            if x + w > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(view)
            x += w + spacing
        }
        return rows
    }
}
