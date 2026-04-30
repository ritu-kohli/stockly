import SwiftUI
import Foundation

// MARK: - Main View

struct ContentView: View {

    @StateObject var vm = PortfolioViewModel()
    @State private var showAddHolding = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {

                    header

                    summaryGrid

//                    statusBar

                    ForEach(GroupType.allCases, id: \.self) { group in
                        section(group)
                    }

                    alertBox
                }
                .padding()
            }
            .background(Color.black)
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAddHolding) {
            AddHoldingView(vm: vm)
        }
    }

    var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Prosper's Portfolio")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text(vm.lastUpdated)
                    .foregroundColor(.gray)
                    .font(.caption)
            }

            Spacer()

            Button(action: { showAddHolding = true }) {
                Image(systemName: "plus")
                    .foregroundColor(.purple)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }

            Button(action: {
                vm.refreshPrices()
            }) {
                Image(systemName: vm.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .rotationEffect(.degrees(vm.isLoading ? 180 : 0))
                    .animation(vm.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isLoading)
                    .foregroundColor(.purple)
                    .padding()
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
    }

    var summaryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {

            summaryCard("Invested", value: money(vm.totalInvested))
            summaryCard("Current", value: money(vm.totalValue))
            summaryCard("P&L", value: money(vm.totalPL), color: vm.totalPL >= 0 ? .green : .red)
            summaryCard("Return", value: "\(String(format: "%.2f", vm.totalReturn))%", color: vm.totalReturn >= 0 ? .green : .red)
        }
    }

    func summaryCard(_ title: String, value: String, color: Color = .white) -> some View {
        VStack(alignment: .leading) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundColor(.gray)

            Text(value)
                .font(.headline.bold())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    var statusBar: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.purple)
            Text(vm.statusMessage)
                .foregroundColor(.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.purple.opacity(0.15))
        .cornerRadius(12)
    }

    func section(_ group: GroupType) -> some View {
        let items = vm.holdings.filter { $0.group == group }

        return VStack(alignment: .leading, spacing: 10) {
            Text(group.rawValue.uppercased())
                .font(.caption)
                .foregroundColor(.gray)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    row(item)
                }
                .onDelete { offsets in
                    vm.removeHolding(at: offsets, in: group)
                }
            }
            .padding()
            .background(Color.white.opacity(0.04))
            .cornerRadius(16)
        }
    }

    func row(_ h: Holding) -> some View {
        let priceData = vm.prices[h.sym]
        let px = priceData?.price ?? h.cost
        let dayChange = priceData?.dayChangePercent ?? 0
        let pnl = (px - h.cost) * h.shares
        let pnlPercent = ((px - h.cost) / h.cost) * 100
        let isUp = dayChange >= 0
        let smartStatus = vm.smartStatus(for: h)
        let isEarningsWeek = vm.isEarningsThisWeek(h.sym)
        let accentColor: Color = isUp ? .green : .red

        return VStack(spacing: 0) {
            // Colored top bar indicating up/down
            Rectangle()
                .fill(priceData != nil ? accentColor : Color.clear)
                .frame(height: 3)
                .cornerRadius(3)

            VStack(spacing: 8) {
                HStack(alignment: .top) {
                    // Left: ticker + name + badges
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(h.sym)
                                .font(.headline.bold())
                                .foregroundColor(.white)
                            if isEarningsWeek {
                                Text("📈").font(.caption)
                            }
                        }
                        Text(h.name)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(String(format: "%.4g", h.shares)) shares @ \(money(h.cost))")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    // Right: current price (big) + day change
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(money(px))
                            .font(.title3.bold())
                            .foregroundColor(.white)

                        if priceData != nil {
                            HStack(spacing: 3) {
                                Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2.bold())
                                Text(String(format: "%.2f%%", abs(dayChange)))
                                    .font(.caption.bold())
                            }
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accentColor.opacity(0.15))
                            .cornerRadius(4)
                        }

                        // After-hours price
                        if let extPx = priceData?.extendedPrice,
                           let extChg = priceData?.extendedChangePercent {
                            HStack(spacing: 3) {
                                Text(money(extPx))
                                    .font(.caption.bold())
                                Text(String(format: "%+.2f%%", extChg))
                                    .font(.caption2)
                            }
                            .foregroundColor(extChg >= 0 ? .green : .red)
                            .opacity(0.85)

                            Text("after hours")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Bottom: status badge + P&L + earnings
                HStack {
                    statusBadge(smartStatus)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(pnl >= 0 ? "+" : "")\(money(pnl))")
                            .font(.caption.bold())
                            .foregroundColor(pnl >= 0 ? .green : .red)
                        Text("\(pnlPercent >= 0 ? "+" : "")\(String(format: "%.1f", pnlPercent))% overall")
                            .font(.caption2)
                            .foregroundColor(pnl >= 0 ? .green.opacity(0.8) : .red.opacity(0.8))
                    }

                    if isEarningsWeek, let info = vm.earningsDates[h.sym] {
                        Text("Earnings: \(info.label)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.leading, 8)
                    }
                }
            }
            .padding()
        }
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(priceData != nil ? accentColor.opacity(0.2) : Color.clear, lineWidth: 1))
    }

    @ViewBuilder
    func statusBadge(_ status: SmartStatus) -> some View {
        let (bgColor, textColor) = badgeColors(for: status.status)

        Text(status.label)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bgColor)
            .foregroundColor(textColor)
            .cornerRadius(6)
    }

    func badgeColors(for status: SmartStatusType) -> (bg: Color, text: Color) {
        switch status {
        case .buy:
            return (Color.green.opacity(0.2), .green)
        case .hold:
            return (Color.gray.opacity(0.2), .gray)
        case .watch:
            return (Color.blue.opacity(0.2), .blue)
        case .review:
            return (Color.red.opacity(0.2), .red)
        case .trim:
            return (Color.yellow.opacity(0.2), .yellow)
        }
    }

    var alertBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔔 Trading Alerts")
                .font(.headline)
                .foregroundColor(.white)

            Text("Use TradingView to set alerts like META below $600.")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    func money(_ value: Double) -> String {
        "$" + String(format: "%.2f", value)
    }
}

// MARK: - App Entry
