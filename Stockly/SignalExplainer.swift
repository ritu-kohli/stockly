import SwiftUI

// MARK: - Signal Explanations

struct SignalInfo: Identifiable {
    let id = UUID()
    let title: String
    let plain: String       // one sentence, no jargon
    let what: String        // what it measures
    let implication: String // what it means for the stock
    let color: Color
}

enum SignalExplainer {
    static func info(for reason: String) -> SignalInfo {
        switch reason {

        // P&L signals
        case let r where r.contains("up >20%"):
            return SignalInfo(title: "Up >20% from your cost",
                plain: "You're up more than 20% on this position.",
                what: "Compares current price to what you paid. This is not a predictive signal — it tells you what happened, not what will happen next.",
                implication: "Strong gain. Consider whether your original thesis still holds. Up 20% doesn't mean it will keep going up.",
                color: .gain)
        case let r where r.contains("up >10%"):
            return SignalInfo(title: "Up >10% from your cost",
                plain: "You're up more than 10% on this position.",
                what: "Compares current price to what you paid. Not a predictive signal.",
                implication: "Healthy gain. Position is working in your favour.",
                color: .gain)
        case let r where r.contains("up >5%"):
            return SignalInfo(title: "Up >5% from your cost",
                plain: "You're up more than 5% on this position.",
                what: "Compares current price to what you paid. Not a predictive signal.",
                implication: "Modest gain. Position is profitable.",
                color: .gain)
        case let r where r.contains("down >20%"):
            return SignalInfo(title: "Down >20% from your cost",
                plain: "You're down more than 20% on this position.",
                what: "Compares current price to what you paid. Not a predictive signal — being down 20% does not mean it will recover.",
                implication: "Significant loss. Ask yourself: would you buy this stock today at this price? If not, that's worth reflecting on.",
                color: .loss)
        case let r where r.contains("down >10%"):
            return SignalInfo(title: "Down >10% from your cost",
                plain: "You're down more than 10% on this position.",
                what: "Compares current price to what you paid. Not a predictive signal.",
                implication: "Notable loss. Review whether your original investment thesis has changed.",
                color: .loss)
        case let r where r.contains("down >5%"):
            return SignalInfo(title: "Down >5% from your cost",
                plain: "You're down more than 5% on this position.",
                what: "Compares current price to what you paid. Not a predictive signal.",
                implication: "Small loss. Normal market fluctuation. Not alarming on its own.",
                color: .loss)

        // RSI signals
        case "RSI oversold":
            return SignalInfo(title: "RSI Oversold",
                plain: "The stock has fallen sharply and may be due for a bounce.",
                what: "RSI below 30 means the stock has dropped very quickly in recent weeks. Historically ~55-60% of oversold readings lead to a short-term bounce.",
                implication: "Possible recovery signal but unreliable in strong downtrends. NVDA stayed oversold for weeks in 2022 before falling further.",
                color: .gain)
        case "RSI low":
            return SignalInfo(title: "RSI Low (30-40)",
                plain: "The stock has been falling and showing weakness.",
                what: "RSI between 30-40 means recent selling pressure is elevated but not extreme.",
                implication: "Mild bearish momentum. ~55% of the time the stock continues lower before recovering.",
                color: .gain)
        case "RSI overbought":
            return SignalInfo(title: "RSI Overbought",
                plain: "The stock has risen sharply. It may pause or pull back.",
                what: "RSI above 70 means the stock has moved up very quickly. ~55-60% of overbought readings lead to a short-term pullback.",
                implication: "Stocks in strong uptrends can stay overbought for months. NVDA was overbought for most of 2023 while tripling in price.",
                color: .loss)
        case "RSI high":
            return SignalInfo(title: "RSI High (60-70)",
                plain: "The stock has been rising and showing strength.",
                what: "RSI between 60-70 means recent buying pressure is elevated.",
                implication: "Bullish momentum. ~60% of the time the stock continues higher from here.",
                color: .loss)

        // SMA signals
        case "above SMA20":
            return SignalInfo(title: "Above 20-Day Average",
                plain: "The stock is trading above its average price over the last 4 weeks.",
                what: "SMA20 is the average closing price over the last 20 trading days. ~60% of stocks above their SMA20 continue higher over the next 2 weeks.",
                implication: "Short-term trend is up. This signal lags — the move has already happened by the time you see it.",
                color: .gain)
        case "below SMA20":
            return SignalInfo(title: "Below 20-Day Average",
                plain: "The stock is trading below its average price over the last 4 weeks.",
                what: "SMA20 is the average closing price over the last 20 trading days. ~60% of stocks below their SMA20 continue lower over the next 2 weeks.",
                implication: "Short-term trend is down. Can generate false signals in volatile markets.",
                color: .loss)
        case "above SMA50":
            return SignalInfo(title: "Above 50-Day Average",
                plain: "The stock is trading above its average price over the last 2.5 months.",
                what: "SMA50 is widely watched by professional traders. ~62-65% of stocks above their SMA50 continue higher over the next month.",
                implication: "Medium-term trend is up. More reliable than SMA20 but still a lagging indicator — it confirms a trend, it doesn't predict one.",
                color: .gain)
        case "below SMA50":
            return SignalInfo(title: "Below 50-Day Average",
                plain: "The stock is trading below its average price over the last 2.5 months.",
                what: "SMA50 is a widely watched level. ~62-65% of stocks below their SMA50 continue lower over the next month.",
                implication: "Medium-term trend is down. Many institutional investors use this as a risk-off signal.",
                color: .loss)

        case "above SMA200":
            return SignalInfo(title: "Above 200-Day Average",
                plain: "The stock is trading above its average price over the last 10 months.",
                what: "SMA200 is the most widely watched long-term trend indicator. ~65% of stocks above their SMA200 continue higher over the next 3 months. Fund managers use it to define bull vs bear market for individual stocks.",
                implication: "Long-term trend is up. This is the most reliable of the three moving average signals. When price is above SMA200, the stock is considered in a long-term uptrend.",
                color: .gain)
        case "below SMA200":
            return SignalInfo(title: "Below 200-Day Average",
                plain: "The stock is trading below its average price over the last 10 months.",
                what: "SMA200 below means the stock is in a long-term downtrend. ~65% of stocks below their SMA200 continue lower over the next 3 months.",
                implication: "Long-term trend is down. Many institutional investors will not buy a stock below its SMA200. This is the most significant of the three moving average signals.",
                color: .loss)

        // 52-week signals
        case "near 52w high":
            return SignalInfo(title: "Near 52-Week High",
                plain: "The stock is close to its highest price in the past year.",
                what: "Stocks breaking to new 52-week highs actually continue higher ~63% of the time — momentum tends to persist.",
                implication: "Counterintuitively, this is often bullish. The caution score reflects potential resistance, but strong stocks make new highs regularly.",
                color: .loss)
        case "near 52w low":
            return SignalInfo(title: "Near 52-Week Low",
                plain: "The stock is close to its lowest price in the past year.",
                what: "Stocks near 52-week lows continue lower ~55% of the time. They are often there for a reason.",
                implication: "Could be a value opportunity or a value trap. Research why it has fallen before acting.",
                color: .gain)

        // Volume signals
        case "volume surge up":
            return SignalInfo(title: "High Volume on Up Day",
                plain: "Far more shares traded today than usual, and the price went up.",
                what: "2x+ average volume on an up day suggests institutional buying. ~62% of the time the stock is higher 1 week later.",
                implication: "Strongest confirmation signal in this app. Large players are buying. By the time you see it, some of the move has already happened.",
                color: .gain)
        case "volume surge down":
            return SignalInfo(title: "High Volume on Down Day",
                plain: "Far more shares traded today than usual, and the price went down.",
                what: "2x+ average volume on a down day suggests institutional selling. ~62% of the time the stock is lower 1 week later.",
                implication: "Strongest bearish confirmation signal in this app. Large players are selling.",
                color: .loss)

        // Day momentum
        case "big day gain":
            return SignalInfo(title: "Strong Day (+3%+)",
                plain: "The stock is up more than 3% today.",
                what: "Single-day momentum of 3%+ continues the next day only ~52% of the time — barely better than a coin flip.",
                implication: "Weak predictive signal on its own. More meaningful when combined with high volume or an earnings beat.",
                color: .gain)
        case "big day drop":
            return SignalInfo(title: "Sharp Drop (-3%+)",
                plain: "The stock is down more than 3% today.",
                what: "Single-day drops of 3%+ reverse the next day ~48% of the time. The stock continues lower ~52% of the time.",
                implication: "Check for news. Earnings misses and guidance cuts often lead to multi-day declines.",
                color: .loss)

        default:
            return SignalInfo(title: reason,
                plain: "Technical indicator signal.",
                what: "This signal is based on price and volume data.",
                implication: "Consider alongside other signals before acting.",
                color: .textSecondary)
        }
    }
}

// MARK: - Tappable Signal Pill with Tooltip

struct SignalPill: View {
    let reason: String
    var onTap: ((SignalInfo) -> Void)? = nil
    @State private var showTooltip = false

    var body: some View {
        let info = SignalExplainer.info(for: reason)
        Button(action: {
            if let onTap { onTap(info) }
            else { showTooltip = true }
        }) {
            Text(reason)
                .font(.caption2.weight(.medium))
                .foregroundColor(info.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(info.color.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showTooltip) {
            SignalTooltipView(info: info)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Tooltip Sheet

struct SignalTooltipView: View {
    let info: SignalInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Title + color indicator
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(info.color)
                            .frame(width: 4, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.title)
                                .font(.title3.bold())
                            Text(info.plain)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    infoBlock(icon: "chart.xyaxis.line", title: "What it measures", body: info.what)
                    infoBlock(icon: "lightbulb", title: "What it means", body: info.implication)

                    Text("⚠️ This is a technical indicator only, not financial advice.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding(24)
            }
        }
    }

    private func infoBlock(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
