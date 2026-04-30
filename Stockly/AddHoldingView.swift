import SwiftUI

struct AddHoldingView: View {
    @ObservedObject var vm: PortfolioViewModel
    @Environment(\.dismiss) var dismiss

    @State private var sym = ""
    @State private var name = ""
    @State private var shares = ""
    @State private var cost = ""
    @State private var status: StatusType = .buy
    @State private var group: GroupType = .tech
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Stock") {
                    TextField("Ticker (e.g. NVDA)", text: $sym)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    TextField("Company Name", text: $name)
                }

                Section("Position") {
                    TextField("Shares", text: $shares)
                        .keyboardType(.decimalPad)
                    TextField("Avg Cost ($)", text: $cost)
                        .keyboardType(.decimalPad)
                }

                Section("Classification") {
                    Picker("Group", selection: $group) {
                        ForEach(GroupType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(StatusType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                if let error {
                    Text(error).foregroundColor(.red).font(.caption)
                }
            }
            .navigationTitle("Add Holding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submit() }
                }
            }
        }
    }

    private func submit() {
        guard !sym.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Ticker is required"; return }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Company name is required"; return }
        guard let sharesVal = Double(shares), sharesVal > 0 else { error = "Enter a valid number of shares"; return }
        guard let costVal = Double(cost), costVal > 0 else { error = "Enter a valid avg cost"; return }

        vm.addHolding(Holding(sym: sym, name: name, shares: sharesVal, cost: costVal, status: status, note: "", group: group))
        dismiss()
    }
}
