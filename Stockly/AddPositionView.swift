import SwiftUI

struct AddPositionView: View {
    let holding: Holding
    @ObservedObject var vm: PortfolioViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var shares = ""
    @State private var price = ""
    @State private var error: String?

    private var newShares: Double? { Double(shares) }
    private var newPrice: Double? { Double(price) }

    private var previewAvgCost: Double? {
        guard let s = newShares, s > 0, let p = newPrice, p > 0 else { return nil }
        return ((holding.shares * holding.cost) + (s * p)) / (holding.shares + s)
    }

    private var previewTotalShares: Double? {
        guard let s = newShares, s > 0 else { return nil }
        return holding.shares + s
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(holding.sym).font(.headline.bold())
                            Text(holding.name).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(String(format: "%.4g", holding.shares)) shares")
                                .font(.caption).foregroundColor(.secondary)
                            Text("Avg \(money(holding.cost))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Current Position")
                }

                Section {
                    TextField("Shares to add", text: $shares)
                        .keyboardType(.decimalPad)
                    TextField("Price per share ($)", text: $price)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("New Purchase")
                }

                if let avgCost = previewAvgCost, let totalShares = previewTotalShares {
                    Section {
                        HStack {
                            Text("New avg cost")
                            Spacer()
                            Text(money(avgCost))
                                .foregroundColor(avgCost < holding.cost ? .green : .red)
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Total shares")
                            Spacer()
                            Text(String(format: "%.4g", totalShares))
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("Avg cost change")
                            Spacer()
                            let diff = avgCost - holding.cost
                            Text("\(diff >= 0 ? "+" : "")\(money(diff))")
                                .foregroundColor(diff <= 0 ? .green : .red)
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Preview")
                    }
                }

                if let error {
                    Section { Text(error).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Add to Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                        .fontWeight(.semibold)
                        .disabled(previewAvgCost == nil)
                }
            }
        }
    }

    private func submit() {
        guard let s = newShares, s > 0 else { error = "Enter valid shares"; return }
        guard let p = newPrice, p > 0 else { error = "Enter valid price"; return }
        vm.updateHolding(holding, additionalShares: s, pricePerShare: p)
        dismiss()
    }

    private let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        return f
    }()

    private func money(_ v: Double) -> String {
        fmt.string(from: NSNumber(value: v)) ?? "$\(String(format: "%.2f", v))"
    }
}
