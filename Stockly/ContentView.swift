import SwiftUI
import Foundation
// import SwiftData  // DISABLED — Supabase is source of truth



// MARK: - Main View

struct ContentView: View {

    // @Environment(\.modelContext) private var modelContext  // DISABLED — SwiftData
    @StateObject private var vm = PortfolioViewModel()
    @State private var route: SheetDestination?
    @State private var editMode = false
    @State private var selectedSyms = Set<String>()
    @State private var contextInjected = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        header
                        if vm.isOffline {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                    .font(.caption)
                                Text("Offline — showing cached data")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if vm.holdings.isEmpty {
                            emptyState
                        } else {
                            heroCard
                            holdingsList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                guard !contextInjected else { return }
                contextInjected = true
//                if !UserDefaults.standard.bool(forKey: "disclaimer_shown") {
//                    activeSheet = .disclaimer
//                }
                // vm.updateContext(modelContext)  // DISABLED — SwiftData
                vm.syncFromSupabase()
                vm.refreshPrices()
                vm.startAutoRefresh()
            }
            .onDisappear { vm.stopAutoRefresh() }
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
        .sheet(item: $route) { destination in
            switch destination {
            case .addHolding:
                AddHoldingView(vm: vm)
            case .settings:
                SettingsView(vm: vm)
            case .detail(let h):
                StockDetailView(holding: h, vm: vm)
            case .addPosition(let h):
                AddPositionView(holding: h, vm: vm)
            case .disclaimer:
                DisclaimerView()
            }
        }
    }

    // MARK: - Header

    var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio")
                    .font(.largeTitle.bold())
                    .foregroundColor(.textPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(vm.isLoading ? Color.orange : Color.gain)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(vm.isLoading ? "Updating…" : vm.lastUpdated)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Portfolio, \(vm.isLoading ? "updating prices" : vm.lastUpdated)")

            Spacer()

            HStack(spacing: 10) {
                if !vm.holdings.isEmpty {
                    if editMode && !selectedSyms.isEmpty {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                vm.removeHoldings(syms: selectedSyms)
                                selectedSyms.removeAll()
                                editMode = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.semibold))
                                Text("Delete (\(selectedSyms.count))")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.loss)
                            .clipShape(Capsule())
                        }
                        .accessibilityLabel("Delete \(selectedSyms.count) selected holdings")
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            editMode.toggle()
//                            if !editMode { selectedIDs.removeAll() }
                        }
                    }) {
                        Image(systemName: editMode ? "checkmark" : "trash")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(editMode ? .white : .textSecondary)
                            .frame(width: 44, height: 44)
                            .background(editMode ? Color.accent : Color.surface)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(editMode ? "Done editing" : "Edit holdings")
                    .accessibilityHint(editMode ? "Exits edit mode" : "Select holdings to delete")
                }

                Button(action: { vm.refreshPrices() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(vm.isLoading ? .accent : .textSecondary)
                        .rotationEffect(.degrees(vm.isLoading ? 360 : 0))
                        .animation(vm.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.isLoading)
                        .frame(width: 44, height: 44)
                        .background(Color.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Refresh prices")
                .accessibilityHint("Fetches the latest stock prices")

                Button(action: { route = .settings }) {
                    Image(systemName: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")

                Button(action: { route = .addHolding }) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accent)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Add holding")
                .accessibilityHint("Opens form to add a new stock")
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Hero Card

    var heroCard: some View {
        let isPositive = vm.totalPL >= 0
        let plSign = isPositive ? "up" : "down"
        return ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(
                    colors: isPositive
                        ? [Color(red: 0.1, green: 0.28, blue: 0.2), Color(red: 0.08, green: 0.16, blue: 0.12)]
                        : [Color(red: 0.28, green: 0.1, blue: 0.1), Color(red: 0.16, green: 0.08, blue: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: 24)
                .stroke(isPositive ? Color.gain.opacity(0.2) : Color.loss.opacity(0.2), lineWidth: 1)

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Total Value")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(money(vm.totalValue))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .foregroundColor(.white)
                    HStack(spacing: 6) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.bold))
                        Text("\(isPositive ? "+" : "")\(money(vm.totalPL)) (\(String(format: "%+.2f", vm.totalReturn))%)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(isPositive ? .gain : .loss)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background((isPositive ? Color.gain : Color.loss).opacity(0.15))
                    .clipShape(Capsule())
                }
                .padding(.top, 28)
                .padding(.bottom, 24)

                Divider().background(Color.white.opacity(0.1))

                HStack {
                    heroStat("Invested", value: money(vm.totalInvested))
                    Divider().frame(height: 30).background(Color.white.opacity(0.1))
                    heroStat("Holdings", value: "\(vm.holdings.count)")
                    Divider().frame(height: 30).background(Color.white.opacity(0.1))
                    heroStat("Groups", value: "\(Set(vm.holdings.map { $0.group }).count)")
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Portfolio summary. Total value \(money(vm.totalValue)), \(plSign) \(money(abs(vm.totalPL))), \(String(format: "%+.2f", vm.totalReturn)) percent overall. Amount invested \(money(vm.totalInvested)). \(vm.holdings.count) holdings."
        )
    }

    func heroStat(_ title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(.white)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Holdings List

    var holdingsList: some View {
        VStack(spacing: 28) {
            ForEach(GroupType.allCases, id: \.self) { group in
                let items = vm.holdings.filter { $0.group == group }
                if !items.isEmpty {
                    sectionView(group: group, items: items)
                }
            }
        }
    }

    func sectionView(group: GroupType, items: [HoldingLocal]) -> some View {
        CollapsibleSection(group: group, items: items, vm: vm,
                           editMode: editMode, selectedSyms: $selectedSyms,
                           activeSheet: $route)
    }

    static func makeRow(h: HoldingLocal, priceData: PriceData?, px: Double, dayChange: Double,
                         pnl: Double, pnlPct: Double, isUp: Bool, status: SmartStatus,
                         isSelected: Bool, editMode: Bool, isEarnings: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if editMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .loss : .textTertiary)
                        .animation(.spring(response: 0.2), value: isSelected)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(h.sym).font(.body.weight(.bold)).foregroundColor(.textPrimary)
                        statusPillStatic(status)
                        if isEarnings {
                            Text("EARNINGS")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15)).clipShape(Capsule())
                        }
                    }
                    Text(h.name).font(.caption).foregroundColor(.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(moneyStatic(px)).font(.body.weight(.bold)).foregroundColor(.textPrimary)
                    if priceData != nil {
                        HStack(spacing: 2) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%.2f%%", abs(dayChange))).font(.caption.weight(.semibold))
                        }
                        .foregroundColor(isUp ? .gain : .loss)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(isSelected ? Color.loss.opacity(0.08) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            if priceData != nil {
                HStack(spacing: 0) {
                    detailCellStatic(label: "P&L",      value: "\(pnl >= 0 ? "+" : "")\(moneyStatic(pnl))",   color: pnl >= 0 ? .gain : .loss)
                    detailCellStatic(label: "Return",   value: String(format: "%+.1f%%", pnlPct),              color: pnlPct >= 0 ? .gain : .loss)
                    detailCellStatic(label: "Shares",   value: String(format: "%.4g", h.shares),               color: .textSecondary)
                    detailCellStatic(label: "Avg Cost", value: moneyStatic(h.cost),                            color: .textSecondary)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

                if let extPx = priceData?.extendedPrice, let extChg = priceData?.extendedChangePercent {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars").font(.caption2).foregroundColor(.textTertiary).accessibilityHidden(true)
                        Text("After hours").font(.caption.weight(.medium)).foregroundColor(.textTertiary)
                        Text(moneyStatic(extPx)).font(.caption.weight(.semibold)).foregroundColor(.textSecondary)
                        Text(String(format: "%+.2f%%", extChg)).font(.caption.weight(.semibold))
                            .foregroundColor(extChg >= 0 ? .gain : .loss)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)
                }

                if !status.reasons.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(status.reasons, id: \.self) { SignalPill(reason: $0) }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 12)
                }
            }

            Rectangle().fill(Color.border).frame(height: 1).padding(.leading, 16).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(h.name), \(h.sym), \(moneyStatic(px))")
        .accessibilityHint("Double tap to view analysis")
    }

    static func statusPillStatic(_ status: SmartStatus) -> some View {
        let colors: (Color, Color) = {
            switch status.status {
            case .strongBuy: return (Color.gain.opacity(0.2),    .gain)
            case .buy:       return (Color.gain.opacity(0.15),   .gain)
            case .hold:      return (Color.white.opacity(0.08),  .textSecondary)
            case .watch:     return (Color.blue.opacity(0.15),   .blue)
            case .trim:      return (Color.orange.opacity(0.15), .orange)
            case .review:    return (Color.loss.opacity(0.15),   .loss)
            }
        }()
        return Text(status.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(colors.1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(colors.0).clipShape(Capsule())
            .accessibilityHidden(true)
    }

    static func detailCellStatic(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.semibold)).foregroundColor(color)
            Text(label).font(.caption2.weight(.medium)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    static func moneyStatic(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }

    // MARK: - Row (delegates to static helper)

    func rowView(_ h: HoldingLocal) -> some View {
        let priceData  = vm.prices[h.sym]
        let px         = priceData?.price ?? h.cost
        let dayChange  = priceData?.dayChangePercent ?? 0
        let pnl        = (px - h.cost) * h.shares
        let pnlPct     = ((px - h.cost) / h.cost) * 100
        let isUp       = dayChange >= 0
        let status     = vm.smartStatus(for: h)
        let isSelected = selectedSyms.contains(h.sym)
        let pnlSign    = pnl >= 0 ? "gain" : "loss"
        let daySign    = isUp ? "up" : "down"

        return ContentView.makeRow(
            h: h, priceData: priceData, px: px, dayChange: dayChange,
            pnl: pnl, pnlPct: pnlPct, isUp: isUp, status: status,
            isSelected: isSelected, editMode: editMode,
            isEarnings: vm.isEarningsThisWeek(h.sym)
        )
    }

    private func rowAccessibilityLabel(_ h: HoldingLocal, px: Double, dayChange: Double, pnl: Double, pnlPct: Double, status: SmartStatus, daySign: String, pnlSign: String, priceData: PriceData?) -> String {
        var label = "\(h.name), \(h.sym). Current price \(money(px))."
        if priceData != nil {
            label += " \(daySign) \(String(format: "%.2f", abs(dayChange))) percent today."
            label += " P&L \(pnlSign) \(money(abs(pnl))), \(String(format: "%.1f", abs(pnlPct))) percent overall."
        }
        label += " Signal: \(status.label)."
        if vm.isEarningsThisWeek(h.sym) { label += " Earnings this week." }
        return label
    }

    func detailCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Pill

    func statusPill(_ status: SmartStatus) -> some View {
        let (bg, fg) = statusColors(status.status)
        return Text(status.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
            .accessibilityHidden(true) // spoken as part of row label
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

    // MARK: - Empty State

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            ZStack {
                Circle()
                    .fill(Color.surface)
                    .frame(width: 80, height: 80)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.accent)
            }
            .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("No holdings yet")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.textPrimary)
                Text("Add your first stock to start\ntracking your portfolio")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: { route = .addHolding }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.subheadline.weight(.bold))
                    Text("Add Holding").font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Color.accent)
                .clipShape(Capsule())
            }
            .accessibilityLabel("Add your first holding")
            .accessibilityHint("Opens form to search and add a stock")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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

#Preview {
    ContentView()
}
