import SwiftUI

// MARK: - Credit Card View
struct CreditCardView: View {
    @EnvironmentObject var store: TransactionStore
    @ObservedObject private var billService = CCBillService.shared
    @State private var selectedMonth: Date = Date()
    @State private var showMarkPaidSheet = false
    @State private var markPaidRecord: CCBillRecord? = nil

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

    // Bill records: latest-period record per card, plus any records in selected billing month
    private var billRecordsForDisplay: [CCBillRecord] {
        // Show records whose billing month matches the selected month,
        // plus the latest record for any card not already represented.
        let monthRecords = billService.records(for: selectedMonth)
        var shown = Set(monthRecords.map { $0.matchKey })
        var result = monthRecords
        for r in billService.latestPerCard {
            if !shown.contains(r.matchKey) {
                result.append(r)
                shown.insert(r.matchKey)
            }
        }
        return result.sorted { ($0.bank + $0.cardName) < ($1.bank + $1.cardName) }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    monthPicker
                    summaryCards
                    if !billRecordsForDisplay.isEmpty {
                        billStatusSection
                    }
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
            .sheet(item: $markPaidRecord) { record in
                MarkPaidSheet(record: record)
            }
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
            // Large card for total CC spend
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

            // Secondary row
            HStack(spacing: 12) {
                SummaryCard(
                    title:  "Bill Paid",
                    amount: totalBillPaid,
                    icon:   "arrow.up.circle.fill",
                    color:  Color(hex: "#E67E22")
                )
                SummaryCard(
                    title:  "Outstanding",
                    amount: max(0, totalCCSpend - totalBillPaid),
                    icon:   "exclamationmark.circle.fill",
                    color:  totalCCSpend > totalBillPaid
                              ? Color(hex: "#E74C3C")
                              : Color(hex: "#3CB371")
                )
            }
        }
    }

    // MARK: - Bill Status Section
    // Shows one card per known CC — statement amount, due date, and paid/unpaid status.
    private var billStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bill Status")
                    .font(.headline)
                Spacer()
                Text("\(billRecordsForDisplay.count) card\(billRecordsForDisplay.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(billRecordsForDisplay) { record in
                BillStatusCard(record: record) {
                    markPaidRecord = record
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
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
                // Group by section: CC Purchases and Bill Payments
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

// MARK: - Bill Status Card
// Displays one CC bill record: statement period, total due, status chip, payments.
private struct BillStatusCard: View {
    let record:   CCBillRecord
    let onMarkPaid: () -> Void

    private let dateF: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()
    private let shortMonthF: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Header: card name + bank + status chip ──────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if record.cardName.isEmpty {
                        Text(record.bank)
                            .font(.subheadline).fontWeight(.semibold)
                    } else {
                        Text(record.cardName)
                            .font(.subheadline).fontWeight(.semibold)
                        Text(record.bank)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    // Billing period
                    if let start = record.periodStart, let end = record.periodEnd {
                        Text("\(dateF.string(from: start)) – \(dateF.string(from: end))")
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        Text(shortMonthF.string(from: record.billingMonth))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Status chip
                HStack(spacing: 4) {
                    Image(systemName: record.status.icon)
                    Text(record.status.label)
                        .font(.caption).fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(record.status.color.opacity(0.15))
                .foregroundColor(record.status.color)
                .cornerRadius(20)
            }

            Divider()

            // ── Amounts grid ────────────────────────────────
            HStack(spacing: 0) {
                amountCell(title: "Total Due",
                           value: record.totalDue > 0 ? "₹\(Int(record.totalDue).formatted())" : "—",
                           color: record.totalDue > 0 ? .primary : .secondary)
                Spacer()
                amountCell(title: "Min. Due",
                           value: record.minimumDue > 0 ? "₹\(Int(record.minimumDue).formatted())" : "—",
                           color: .secondary)
                Spacer()
                amountCell(title: "Paid",
                           value: record.totalPaid > 0 ? "₹\(Int(record.totalPaid).formatted())" : "—",
                           color: record.totalPaid > 0 ? Color(hex: "#2ECC71") : .secondary)
            }

            // ── Outstanding warning ─────────────────────────
            if record.status == .unpaid || record.status == .partiallyPaid {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(record.status.color)
                        .font(.caption)
                    Text(record.status == .unpaid
                         ? "Bill unpaid — ₹\(Int(record.totalDue).formatted()) due"
                         : "Partial payment — ₹\(Int(record.outstanding).formatted()) still outstanding")
                        .font(.caption)
                        .foregroundColor(record.status.color)
                    Spacer()
                }
            }

            // ── Due date ────────────────────────────────────
            if let due = record.dueDate {
                let isOverdue = due < Date() && record.status != .paid
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundColor(isOverdue ? .red : .secondary)
                    Text("Due: \(dateF.string(from: due))")
                        .font(.caption2)
                        .foregroundColor(isOverdue ? .red : .secondary)
                    if isOverdue { Text("OVERDUE").font(.caption2).fontWeight(.bold).foregroundColor(.red) }
                }
            }

            // ── Payment history ─────────────────────────────
            if !record.payments.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(record.payments, id: \.date) { p in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "#2ECC71"))
                                .font(.caption2)
                            Text("₹\(Int(p.amount).formatted()) received on \(dateF.string(from: p.date))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // ── Mark as Paid button (only when unpaid/partial) ─
            if record.status == .unpaid || record.status == .partiallyPaid {
                Button(action: onMarkPaid) {
                    Label("Mark as Paid", systemImage: "checkmark.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color(hex: "#2ECC71").opacity(0.12))
                        .foregroundColor(Color(hex: "#2ECC71"))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(record.status.color.opacity(0.3), lineWidth: 1)
        )
    }

    private func amountCell(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundColor(color)
        }
    }
}

// MARK: - Mark Paid Sheet
// Lets the user manually log a payment when no confirmation email was found.
private struct MarkPaidSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: CCBillRecord

    @State private var amountText = ""
    @State private var paymentDate = Date()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Card")) {
                    if !record.cardName.isEmpty {
                        Text("\(record.cardName) – \(record.bank)")
                    } else {
                        Text(record.bank)
                    }
                    Text("Bill: \(record.billingMonth.monthYearString)")
                        .foregroundColor(.secondary)
                    if record.totalDue > 0 {
                        Text("Total Due: ₹\(Int(record.totalDue).formatted())")
                            .foregroundColor(Color(hex: "#E74C3C"))
                    }
                }

                Section(header: Text("Payment Details")) {
                    HStack {
                        Text("₹").foregroundColor(.secondary)
                        TextField(record.totalDue > 0
                                  ? "\(Int(record.totalDue))"
                                  : "Amount paid",
                                  text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Payment Date", selection: $paymentDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Mark as Paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount = Double(amountText)
                            ?? record.totalDue
                        if amount > 0 {
                            CCBillService.shared.markPaid(
                                recordID: record.id,
                                amount: amount,
                                on: paymentDate
                            )
                        }
                        dismiss()
                    }
                    .disabled(amountText.isEmpty && record.totalDue == 0)
                }
            }
            .onAppear {
                if record.totalDue > 0 {
                    amountText = "\(Int(record.totalDue))"
                }
            }
        }
    }
}

