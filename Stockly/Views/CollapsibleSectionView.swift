import SwiftUI

// MARK: - Collapsible Section

struct CollapsibleSection: View {
    let group: GroupType
    let items: [HoldingLocal]
    @ObservedObject var vm: PortfolioViewModel
    let editMode: Bool
    @Binding var selectedSyms: Set<String>
    @Binding var activeSheet: SheetDestination?

    @State private var isExpanded = true

    var sectionPnl: Double {
        items.reduce(0) { total, h in
            let px = vm.prices[h.sym]?.price ?? h.cost
            return total + (px - h.cost) * h.shares
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tappable header
            Button(action: {
                isExpanded.toggle()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 12)

                    Text(group.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.textTertiary)
                        .textCase(.uppercase)
                        .kerning(0.8)

                    Spacer()

                    // Section P&L summary
                    if !isExpanded {
                        Text(sectionPnl >= 0 ? "+" : "")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(sectionPnl >= 0 ? .gain : .loss)
                        + Text(String(format: "%.0f", sectionPnl))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(sectionPnl >= 0 ? .gain : .loss)
                    }

                    Text("\(items.count)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.rawValue), \(items.count) holding\(items.count == 1 ? "" : "s"), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(items, id: \.sym) { item in
                        rowView(item)
                    }
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.border, lineWidth: 1))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    func rowView(_ item: HoldingLocal) -> some View {
        let priceData  = vm.prices[item.sym]
        let px         = priceData?.price ?? item.cost
        let dayChange  = priceData?.dayChangePercent ?? 0
        let pnl        = (px - item.cost) * item.shares
        let pnlPct     = ((px - item.cost) / item.cost) * 100
        let isUp       = dayChange >= 0
        let status     = vm.smartStatus(for: item)
        let isSelected = selectedSyms.contains(item.sym)

        return ContentView.makeRow(
            h: item, priceData: priceData, px: px, dayChange: dayChange,
            pnl: pnl, pnlPct: pnlPct, isUp: isUp, status: status,
            isSelected: isSelected, editMode: editMode,
            isEarnings: vm.isEarningsThisWeek(item.sym)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: { activeSheet = .addPosition(item) }) {
                Label("Add to Position", systemImage: "plus.circle")
            }
            Button(action: { activeSheet = .detail(item) }) {
                Label("View Analysis", systemImage: "chart.bar.xaxis")
            }
            Divider()
            Button(role: .destructive, action: { vm.removeHoldings(syms: [item.sym]) }) {
                Label("Remove", systemImage: "trash")
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if editMode {
                withAnimation(.spring(response: 0.2)) {
                    if selectedSyms.contains(item.sym) { selectedSyms.remove(item.sym) }
                    else { selectedSyms.insert(item.sym) }
                }
            } else {
                activeSheet = .detail(item)
            }
        })
    }
}

