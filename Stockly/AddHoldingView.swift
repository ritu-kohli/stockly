import SwiftUI

struct TickerSuggestion {
    let symbol: String
    let name: String
    let group: GroupType
}

struct AddHoldingView: View {
    @ObservedObject var vm: PortfolioViewModel
    @Environment(\.dismiss) var dismiss

    @State private var query = ""
    @State private var suggestions: [TickerSuggestion] = []
    @State private var isSearching = false
    @State private var showSuggestions = false

    @State private var sym = ""
    @State private var name = ""
    @State private var group: GroupType = .other
    @State private var shares = ""
    @State private var cost = ""
    @State private var error: String?

    private let searchDebounce = Debouncer(delay: 0.3)

    var body: some View {
        NavigationView {
            Form {
                Section("Search") {
                    HStack {
                        TextField("Search company or ticker…", text: $query)
                            .autocorrectionDisabled()
                            .onChange(of: query) { _, val in
                                showSuggestions = true
                                searchDebounce.call { [self] in
                                    Task { await searchTickers(val) }
                                }
                            }
                        if isSearching {
                            ProgressView().scaleEffect(0.7)
                        }
                    }

                    if showSuggestions && !suggestions.isEmpty {
                        ForEach(suggestions, id: \.symbol) { s in
                            Button(action: { pick(s) }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.symbol).font(.headline)
                                        Text(s.name).font(.caption).foregroundColor(.gray)
                                    }
                                    Spacer()
                                    Text(s.group.rawValue)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(4)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }

                Section("Stock") {
                    TextField("Ticker", text: $sym)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("Company Name", text: $name)
                }

                Section("Position") {
                    TextField("Shares", text: $shares).keyboardType(.decimalPad)
                    TextField("Avg Cost ($)", text: $cost).keyboardType(.decimalPad)
                }

                Section("Classification") {
                    HStack {
                        Text("Group")
                        Spacer()
                        Text(sym.isEmpty ? "Auto-detected from ticker" : group.rawValue)
                            .foregroundColor(sym.isEmpty ? .secondary.opacity(0.5) : .secondary)
                            .font(sym.isEmpty ? .caption : .body)
                    }
                }

                if let error {
                    Section { Text(error).foregroundColor(.red).font(.caption) }
                }
            }
            .navigationTitle("Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { submit() } }
            }
        }
    }

    private func pick(_ s: TickerSuggestion) {
        sym = s.symbol
        name = s.name
        group = s.group
        query = "\(s.symbol) — \(s.name)"
        suggestions = []
        showSuggestions = false
    }

    @MainActor
    private func searchTickers(_ q: String) {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { suggestions = []; return }
        isSearching = true

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=6&newsCount=0") else { return }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quotes = json["quotes"] as? [[String: Any]] else {
                DispatchQueue.main.async { isSearching = false }
                return
            }

            let results: [TickerSuggestion] = quotes.compactMap { q in
                guard let sym = q["symbol"] as? String,
                      let name = q["shortname"] as? String,
                      let type = q["quoteType"] as? String, type == "EQUITY",
                      !sym.contains(".")
                else { return nil }
                let sector = q["sector"] as? String ?? ""
                let industry = q["industry"] as? String ?? ""
                return TickerSuggestion(symbol: sym, name: name, group: groupForSectorIndustry(sector, industry))
            }

            DispatchQueue.main.async {
                suggestions = results
                isSearching = false
            }
        }.resume()
    }

    private func submit() {
        guard !sym.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Ticker is required"; return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Company name is required"; return }
        guard let sharesVal = Double(shares), sharesVal > 0 else { error = "Enter valid shares"; return }
        guard let costVal = Double(cost), costVal > 0 else { error = "Enter valid avg cost"; return }
        vm.addHolding(Holding(sym: sym, name: name, shares: sharesVal, cost: costVal, group: group))
        dismiss()
    }
}

// MARK: - Group Detection

func groupForSectorIndustry(_ sector: String, _ industry: String) -> GroupType {
    let s = sector.lowercased()
    let i = industry.lowercased()
    if i.contains("semiconductor") || i.contains("electronic component") || i.contains("solar") { return .semi }
    if s.contains("technology") || s.contains("communication") || i.contains("internet") || i.contains("software") { return .tech }
    if i.contains("freight") || i.contains("logistics") || i.contains("trucking") || i.contains("shipping") || i.contains("air delivery") { return .logistics }
    if s.contains("financial") || s.contains("banking") || i.contains("bank") || i.contains("insurance") || i.contains("asset management") { return .logistics }
    if s.contains("healthcare") || s.contains("health care") || i.contains("biotech") || i.contains("pharmaceutical") || i.contains("medical") { return .healthcare }
    if s.contains("energy") || i.contains("oil") || i.contains("gas") || i.contains("mining") || i.contains("coal") { return .energy }
    if s.contains("consumer") || i.contains("retail") || i.contains("restaurant") || i.contains("apparel") || i.contains("food") { return .consumer }
    if s.contains("real estate") || i.contains("reit") { return .realestate }
    if s.contains("utilities") || i.contains("electric") || i.contains("water") { return .utilities }
    if i.contains("bitcoin") || i.contains("crypto") || i.contains("blockchain") || i.contains("capital markets") { return .speculative }
    return .other
}

// MARK: - Debouncer

final class Debouncer: @unchecked Sendable {
    private let delay: TimeInterval
    private var task: Task<Void, Never>?

    init(delay: TimeInterval) { self.delay = delay }

    func call(_ action: @escaping @Sendable () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { action() }
        }
    }
}
