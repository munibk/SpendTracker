import SwiftUI

// MARK: - Credit Card View
struct CreditCardView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()

    // Transactions made *using* a credit card in the selected month
    private var ccPurchases: [Transaction] {
        store.transactions(for: selectedMonth)
            .filter { $0.cardType == .credit && $0.type == .debit }
    }

    // CC bill payments debited from savings/bank account in the selected month
    private var ccBillPayments: [Transaction] {
        store.transactions(for: selectedMonth)
            .filter { $0.category == .creditCard && $0.type == .debit }
    }

    // All CC-related transactions (purchases + bill payments) for the list
    private var allCCTransactions: [Transaction] {
        let combined = ccPurchases + ccBillPayments
        return combined.sorted { $0.date > $1.date }
    }

    private var totalCCSpend: Double {
        ccPurchases.reduce(0) { $0 + $1.amount }
    }

    private var totalBillPaid: Double {
        ccBillPayments.reduce(0) { $0 + $1.amount }
    }

    // Per-card spending breakdown grouped by bank + last4
    private var perCardBreakdown: [(label: String, amount: Double, count: Int)] {
        var map: [String: (amount: Double, count: Int)] = [:]
        for t in ccPurchases {
            let key = "\(t.bankName) \(t.accountLast4.map { "xx\($0)" } ?? "")"
                .trimmingCharacters(in: .whitespaces)
            map[key, default: (0, 0)].amount += t.amount
            map[key, default: (0, 0)].count  += 1
        }
        return map
            .map { (label: $0.key, amount: $0.value.amount, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
    }

    // Spending by category for CC purchases
    private var categoryBreakdown: [(category: SpendCategory, amount: Double)] {
        var map: [SpendCategory: Double] = [:]
        for t in ccPurchases { map[t.category, default: 0] += t.amount }
        return map.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    monthPicker
                    summaryCards
                    if perCardBreakdown.count > 1 {
                        perCardSection
                    }
                    if !categoryBreakdown.isEmpty {
                        categorySection
                    }
                    transactionsSection
                }
                .padding()
            }
            .navigationTitle("Credit Card")
        }
    }

    // MARK: - Month Picker
    private var monthPicker: some View {
        HStack {
            Button(action: { moveMonth(-1) }) {
                Image(systemName: "chevron.left").font(.title3)
            }
            Spacer()
            Text(selectedMonth.monthYearString).font(.headline)
            Spacer()
            Button(action: { moveMonth(1) }) {
                Image(systemName: "chevron.right").font(.title3)
            }
            .disabled(Calendar.current.isDateInThisMonth(selectedMonth))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Summary Cards
    private var summaryCards: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(Color(hex: "#E74C3C"))
                        .font(.title2)
                    Text("CC Purchases")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(ccPurchases.count) txns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("₹\(Int(totalCCSpend).formatted())")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#E74C3C"))
            }
            .padding()
            .background(Color(hex: "#E74C3C").opacity(0.08))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#E74C3C").opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 12) {
                SummaryCard(
                    title:  "Bill Paid",
                    amount: totalBillPaid,
                    icon:   "arrow.up.circle.fill",
                    color:  Color(hex: "#E67E22")
                )
                SummaryCard(
                    title:  "Est. Next Bill",
                    amount: totalCCSpend,
                    icon:   "exclamationmark.circle.fill",
                    color:  totalCCSpend > 0
                              ? Color(hex: "#E74C3C")
                              : Color(hex: "#3CB371")
                )
            }
        }
    }

    // MARK: - Per Card Breakdown
    private var perCardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spent by Card")
                .font(.headline)

            ForEach(perCardBreakdown, id: \.label) { item in
                let pct = totalCCSpend > 0 ? item.amount / totalCCSpend : 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "creditcard.fill")
                            .foregroundColor(Color(hex: "#E74C3C"))
                            .frame(width: 18)
                        Text(item.label.isEmpty ? "Unknown Card" : item.label)
                            .font(.subheadline)
                        Spacer()
                        Text("₹\(Int(item.amount).formatted())")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("\(item.count) txns")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: "#E74C3C"))
                                .frame(width: geo.size.width * CGFloat(pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Category Breakdown
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending by Category")
                .font(.headline)

            ForEach(categoryBreakdown.prefix(6), id: \.category) { item in
                let pct = totalCCSpend > 0 ? item.amount / totalCCSpend : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: item.category.icon)
                            .foregroundColor(item.category.color)
                            .frame(width: 18)
                        Text(item.category.rawValue)
                            .font(.subheadline)
                        Spacer()
                        Text("₹\(Int(item.amount).formatted())")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String(format: "%.0f%%", pct * 100))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.category.color)
                                .frame(width: geo.size.width * CGFloat(pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Transactions List
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transactions")
                    .font(.headline)
                Spacer()
                if !allCCTransactions.isEmpty {
                    Text("\(allCCTransactions.count) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if allCCTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No credit card transactions")
                        .foregroundColor(.secondary)
                    Text("Transactions made using a credit card\nwill appear here automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                if !ccPurchases.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("CC Purchases", systemImage: "cart.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#E74C3C"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#E74C3C").opacity(0.1))
                            .cornerRadius(6)

                        ForEach(ccPurchases) { txn in
                            TransactionRow(transaction: txn)
                        }
                    }
                }

                if !ccBillPayments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bill Payments", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "#E67E22"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: "#E67E22").opacity(0.1))
                            .cornerRadius(6)

                        ForEach(ccBillPayments) { txn in
                            TransactionRow(transaction: txn)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    // MARK: - Helpers
    private func moveMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = d
        }
    }
}
