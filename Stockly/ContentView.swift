import SwiftUI
import Foundation
import SwiftData

// MARK: - Main View

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = PortfolioViewModel()
    @State private var showAddHolding = false
    @State private var editMode = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var contextInjected = false
    @State private var showError = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {

                    header

                    if editMode && !selectedIDs.isEmpty {
                        Button(action: {
                            withAnimation {
                                vm.removeHoldings(ids: selectedIDs)
                                selectedIDs.removeAll()
                                editMode = false
                            }
                        }) {
                            Label("Delete \(selectedIDs.count) selected", systemImage: "trash")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !vm.holdings.isEmpty { summaryGrid }

                    if vm.holdings.isEmpty {
                        emptyState
                    } else {
                        ForEach(GroupType.allCases, id: \.self) { group in
                            let items = vm.holdings.filter { $0.group == group }
                            if !items.isEmpty { section(group) }
                        }
                        alertBox
                    }
                }
                .padding()
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .onAppear {
                guard !contextInjected else { return }
                contextInjected = true
                vm.updateContext(modelContext)
                vm.refreshPrices()
                vm.startAutoRefresh()
            }
            .onDisappear {
                vm.stopAutoRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                vm.refreshPrices()
                vm.startAutoRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                vm.stopAutoRefresh()
            }
            .onChange(of: vm.errorMessage) { _, msg in showError = msg != nil }
            .alert("Error", isPresented: $showError) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
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
                withAnimation {
                    editMode.toggle()
                    if !editMode { selectedIDs.removeAll() }
                }
            }) {
                Text(editMode ? "Done" : "Edit")
                    .foregroundColor(.purple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
            }
            .opacity(vm.holdings.isEmpty ? 0 : 1)

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

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.4))
            Text("No stocks yet")
                .font(.headline)
                .foregroundColor(.gray)
            Text("Tap + to add your first holding")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    var statusBar: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.purple)
            Text(vm.lastUpdated)
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
                    HStack(spacing: 10) {
                        if editMode {
                            Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedIDs.contains(item.id) ? .red : .gray)
                                .onTapGesture {
                                    withAnimation {
                                        if selectedIDs.contains(item.id) {
                                            selectedIDs.remove(item.id)
                                        } else {
                                            selectedIDs.insert(item.id)
                                        }
                                    }
                                }
                        }
                        row(item)
                            .onTapGesture {
                                guard editMode else { return }
                                withAnimation {
                                    if selectedIDs.contains(item.id) {
                                        selectedIDs.remove(item.id)
                                    } else {
                                        selectedIDs.insert(item.id)
                                    }
                                }
                            }
                            .overlay {
                                if editMode && selectedIDs.contains(item.id) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red, lineWidth: 2)
                                }
                            }
                    }
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
                    VStack(alignment: .leading, spacing: 3) {
                        statusBadge(smartStatus)
                        if !smartStatus.reasons.isEmpty {
                            Text(smartStatus.reasons.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.7))
                        }
                    }

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
        case .strongBuy: return (Color.green.opacity(0.3), .green)
        case .buy:       return (Color.green.opacity(0.2), .green)
        case .hold:      return (Color.gray.opacity(0.2),  .gray)
        case .watch:     return (Color.blue.opacity(0.2),  .blue)
        case .review:    return (Color.red.opacity(0.2),   .red)
        case .trim:      return (Color.yellow.opacity(0.2), .yellow)
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

// MARK: - App Entry

#Preview {
    ContentView()
}
