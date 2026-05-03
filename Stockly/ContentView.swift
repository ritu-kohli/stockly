import SwiftUI
import Foundation
import SwiftData

// MARK: - Design Tokens

extension Color {
    static let bg            = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let surface       = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let surface2      = Color(red: 0.15, green: 0.15, blue: 0.18)
    static let border        = Color.white.opacity(0.07)
    static let textPrimary   = Color.white
    static let textSecondary = Color(white: 0.60)
    static let textTertiary  = Color(white: 0.80)  // raised from 0.35 for contrast
    static let accent        = Color(red: 0.55, green: 0.45, blue: 1.0) // brighter for WCAG AA
    static let gain          = Color(red: 0.18, green: 0.78, blue: 0.44)
    static let loss          = Color(red: 0.95, green: 0.32, blue: 0.32)
}

// MARK: - Main View

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = PortfolioViewModel()
    @State private var showAddHolding = false
    @State private var editMode = false
    @State private var selectedIDs = Set<PersistentIdentifier>()
    @State private var contextInjected = false
    @State private var showError = false
    @State private var showSettings = false
    @State private var selectedHolding: Holding?
    @State private var addPositionHolding: Holding?
    @State private var showDisclaimer = !UserDefaults.standard.bool(forKey: "disclaimer_shown")

    var body: some View {
        NavigationView {
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
                vm.updateContext(modelContext)
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
        .sheet(isPresented: $showAddHolding) {
            AddHoldingView(vm: vm)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(vm: vm)
        }
        .sheet(item: $selectedHolding) { holding in
            StockDetailView(holding: holding, vm: vm)
        }
        .sheet(item: $addPositionHolding) { holding in
            AddPositionView(holding: holding, vm: vm)
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView()
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
                    if editMode && !selectedIDs.isEmpty {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                vm.removeHoldings(ids: selectedIDs)
                                selectedIDs.removeAll()
                                editMode = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.caption.weight(.semibold))
                                Text("Delete (\(selectedIDs.count))")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.loss)
                            .clipShape(Capsule())
                        }
                        .accessibilityLabel("Delete \(selectedIDs.count) selected holdings")
                        .transition(.scale.combined(with: .opacity))
                    }

                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            editMode.toggle()
                            if !editMode { selectedIDs.removeAll() }
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

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")

                Button(action: { showAddHolding = true }) {
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

    func sectionView(group: GroupType, items: [Holding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.8)
                Spacer()
                Text("\(items.count)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(group.rawValue), \(items.count) holding\(items.count == 1 ? "" : "s")")

            VStack(spacing: 2) {
                ForEach(items) { item in
                    rowView(item)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(action: { addPositionHolding = item }) {
                                Label("Add to Position", systemImage: "plus.circle")
                            }
                            Button(action: { selectedHolding = item }) {
                                Label("View Analysis", systemImage: "chart.bar.xaxis")
                            }
                            Divider()
                            Button(role: .destructive, action: {
                                vm.removeHoldings(ids: [item.id])
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            if editMode {
                                withAnimation(.spring(response: 0.2)) {
                                    if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
                                    else { selectedIDs.insert(item.id) }
                                }
                            } else {
                                selectedHolding = item
                            }
                        })
                }
            }
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
        }
    }

    // MARK: - Row

    func rowView(_ h: Holding) -> some View {
        let priceData  = vm.prices[h.sym]
        let px         = priceData?.price ?? h.cost
        let dayChange  = priceData?.dayChangePercent ?? 0
        let pnl        = (px - h.cost) * h.shares
        let pnlPct     = ((px - h.cost) / h.cost) * 100
        let isUp       = dayChange >= 0
        let status     = vm.smartStatus(for: h)
        let isSelected = selectedIDs.contains(h.id)
        let pnlSign    = pnl >= 0 ? "gain" : "loss"
        let daySign    = isUp ? "up" : "down"

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if editMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(isSelected ? .loss : .textTertiary)
                        .animation(.spring(response: 0.2), value: isSelected)
                        .accessibilityHidden(true)
                }

                // Ticker avatar
//                ZStack {
//                    RoundedRectangle(cornerRadius: 10)
//                        .fill(Color.surface2)
//                        .frame(width: 42, height: 42)
//                    Text(h.sym)
//                        .font(.system(size: h.sym.count > 3 ? 9 : 11, weight: .bold, design: .rounded))
//                        .foregroundColor(.white) // white on surface2 guarantees contrast
//                        .minimumScaleFactor(0.5)
//                        .lineLimit(1)
//                        .padding(4)
//                }
//                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(h.sym)
                            .font(.body.weight(.bold))
                            .foregroundColor(.textPrimary)
                        statusPill(status)
                        if vm.isEarningsThisWeek(h.sym) {
                            Text("EARNINGS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(h.name)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(money(px))
                        .font(.body.weight(.bold))
                        .foregroundColor(.textPrimary)

                    if priceData != nil {
                        HStack(spacing: 2) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: "%.2f%%", abs(dayChange)))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(isUp ? .gain : .loss)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.loss.opacity(0.08) : Color.clear)
            .animation(.easeInOut(duration: 0.15), value: isSelected)

            if priceData != nil {
                HStack(spacing: 0) {
                    detailCell(label: "P&L",      value: "\(pnl >= 0 ? "+" : "")\(money(pnl))",          color: pnl >= 0 ? .gain : .loss)
                    detailCell(label: "Return",   value: String(format: "%+.1f%%", pnlPct),               color: pnlPct >= 0 ? .gain : .loss)
                    detailCell(label: "Shares",   value: String(format: "%.4g", h.shares),                color: .textSecondary)
                    detailCell(label: "Avg Cost", value: money(h.cost),                                   color: .textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if let extPx = priceData?.extendedPrice, let extChg = priceData?.extendedChangePercent {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.stars")
                            .font(.caption2)
                            .foregroundColor(.textTertiary)
                            .accessibilityHidden(true)
                        Text("After hours")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.textTertiary)
                        Text(money(extPx))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%+.2f%%", extChg))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(extChg >= 0 ? .gain : .loss)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("After hours price \(money(extPx)), \(extChg >= 0 ? "up" : "down") \(String(format: "%.2f", abs(extChg))) percent")
                }

//                if !status.reasons.isEmpty {
//                    ScrollView(.horizontal, showsIndicators: false) {
//                        HStack(spacing: 6) {
//                            ForEach(status.reasons, id: \.self) { reason in
////                                SignalPill(reason: reason)
//                            }
//                        }
//                        .padding(.horizontal, 16)
//                    }
//                    .padding(.bottom, 12)
//                    .accessibilityLabel("Signals: \(status.reasons.joined(separator: ", "))")
//                }
            }

            Rectangle()
                .fill(Color.border)
                .frame(height: 1)
                .padding(.leading, 70)
                .accessibilityHidden(true)
        }
        // Single VoiceOver element per row with full context
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(h, px: px, dayChange: dayChange, pnl: pnl, pnlPct: pnlPct, status: status, daySign: daySign, pnlSign: pnlSign, priceData: priceData))
        .accessibilityHint(editMode ? "Double tap to \(isSelected ? "deselect" : "select") for deletion" : "")
        .accessibilityAddTraits(editMode && isSelected ? .isSelected : [])
    }

    private func rowAccessibilityLabel(_ h: Holding, px: Double, dayChange: Double, pnl: Double, pnlPct: Double, status: SmartStatus, daySign: String, pnlSign: String, priceData: PriceData?) -> String {
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
            Button(action: { showAddHolding = true }) {
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
