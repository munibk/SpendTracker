import SwiftUI

// MARK: - Reports View (Ultra Lightweight)
struct ReportsView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()
    @State private var showShare  = false
    @State private var shareURL: URL? = nil
    @State private var reportData: ReportData = ReportData()

    struct ReportData {
        var totalSpend:   Double = 0
        var totalCredit:  Double = 0
        var txnCount:     Int    = 0
        var categories:   [(name: String, amount: Double, icon: String)] = []
        var merchants:    [(name: String, amount: Double)] = []
        var monthName:    String = ""
    }

    var body: some View {
        NavigationView {
            List {
                // Month Picker
                Section {
                    HStack {
                        Button(action: { moveMonth(-1) }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                        Text(reportData.monthName)
                            .font(.headline)
                        Spacer()

                        Button(action: { moveMonth(1) }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(
                                    Calendar.current.isDateInThisMonth(selectedMonth)
                                    ? .gray : .blue
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(Calendar.current.isDateInThisMonth(selectedMonth))
                    }
                }

                // Summary Numbers
                Section(header: Text("Summary")) {
                    HStack {
                        Text("Total Spend")
                        Spacer()
                        Text("₹\(Int(reportData.totalSpend))")
                            .foregroundColor(.red)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Total Income")
                        Spacer()
                        Text("₹\(Int(reportData.totalCredit))")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Savings")
                        Spacer()
                        Text("₹\(Int(max(reportData.totalCredit - reportData.totalSpend, 0)))")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Transactions")
                        Spacer()
                        Text("\(reportData.txnCount)")
                            .foregroundColor(.secondary)
                    }
                }

                // Categories
                Section(header: Text("By Category")) {
                    if reportData.categories.isEmpty {
                        Text("No data this month")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(reportData.categories, id: \.name) { item in
                            HStack {
                                Image(systemName: item.icon)
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)
                                Text(item.name)
                                Spacer()
                                Text("₹\(Int(item.amount))")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }

                // Top Merchants
                Section(header: Text("Top Merchants")) {
                    if reportData.merchants.isEmpty {
                        Text("No data this month")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(
                            Array(reportData.merchants.enumerated()),
                            id: \.offset
                        ) { idx, item in
                            HStack {
                                Text("\(idx + 1).")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                Text(item.name)
                                Spacer()
                                Text("₹\(Int(item.amount))")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }

                // Export
                Section(header: Text("Export")) {
                    Button(action: exportCSV) {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Reports")
            .onAppear { loadData() }
            .onChange(of: selectedMonth) { _ in loadData() }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Load data in background to prevent freeze
    private func loadData() {
        let month = selectedMonth
        DispatchQueue.global(qos: .userInitiated).async {
            let txns    = store.transactions(for: month)
            let debits  = txns.filter { $0.type == .debit }
            let credits = txns.filter { $0.type == .credit }
            let spend   = debits.reduce(0)  { $0 + $1.amount }
            let credit  = credits.reduce(0) { $0 + $1.amount }

            // Categories
            var catMap: [String: (amount: Double, icon: String)] = [:]
            for t in debits {
                if catMap[t.category.rawValue] == nil {
                    catMap[t.category.rawValue] = (0, t.category.icon)
                }
                catMap[t.category.rawValue]!.amount += t.amount
            }
            let cats = catMap
                .sorted { $0.value.amount > $1.value.amount }
                .map { (name: $0.key, amount: $0.value.amount, icon: $0.value.icon) }

            // Merchants
            var merMap: [String: Double] = [:]
            for t in debits { merMap[t.merchant, default: 0] += t.amount }
            let mers = merMap
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { (name: $0.key, amount: $0.value) }

            // Month name
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            let name = f.string(from: month)

            DispatchQueue.main.async {
                self.reportData = ReportData(
                    totalSpend:  spend,
                    totalCredit: credit,
                    txnCount:    txns.count,
                    categories:  cats,
                    merchants:   Array(mers),
                    monthName:   name
                )
            }
        }
    }

    private func moveMonth(_ delta: Int) {
        if let d = Calendar.current.date(
            byAdding: .month, value: delta, to: selectedMonth
        ) {
            selectedMonth = d
        }
    }

    private func exportCSV() {
        let csv  = store.exportCSV(month: selectedMonth)
        let f    = DateFormatter(); f.dateFormat = "MMMM_yyyy"
        let name = f.string(from: selectedMonth)
        let url  = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_SpendTracker.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        shareURL  = url
        showShare = true
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
