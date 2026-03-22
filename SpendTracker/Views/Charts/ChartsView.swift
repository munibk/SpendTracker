import SwiftUI
import Charts

// MARK: - Charts View
struct ChartsView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()
    @State private var selectedChart: ChartType = .category

    enum ChartType: String, CaseIterable {
        case category   = "Category"
        case cards      = "Cards"
        case daily      = "Daily"
        case trend      = "Trend"
        case comparison = "Income vs Spend"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    monthPicker
                    chartTypeSelector
                    switch selectedChart {
                    case .category:   CategoryChartSection(month: selectedMonth)
                    case .cards:      CardAnalyticsSection(month: selectedMonth)
                    case .daily:      DailySpendChartSection(month: selectedMonth)
                    case .trend:      TrendChartSection()
                    case .comparison: ComparisonChartSection(month: selectedMonth)
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
        }
    }

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

    private var chartTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChartType.allCases, id: \.self) { type in
                    Button(action: { selectedChart = type }) {
                        Text(type.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedChart == type ? .semibold : .regular)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(selectedChart == type
                                        ? Color(hex: "#6C63FF")
                                        : Color(.systemGray5))
                            .foregroundColor(selectedChart == type ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }

    private func moveMonth(_ delta: Int) {
        if let d = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = d
        }
    }
}

// MARK: - Card Analytics Section
struct CardAnalyticsSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date

    // Credit card transactions
    private var creditCardTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .credit
        }
    }
    // Debit card transactions
    private var debitCardTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .debit
        }
    }
    // UPI transactions
    private var upiTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .none && $0.category == .upi
        }
    }
    // Other transactions
    private var otherTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .none && $0.category != .upi
        }
    }

    private var ccTotal:    Double { creditCardTxns.reduce(0) { $0 + $1.amount } }
    private var dcTotal:    Double { debitCardTxns.reduce(0) { $0 + $1.amount } }
    private var upiTotal:   Double { upiTxns.reduce(0) { $0 + $1.amount } }
    private var otherTotal: Double { otherTxns.reduce(0) { $0 + $1.amount } }
    private var grandTotal: Double { ccTotal + dcTotal + upiTotal + otherTotal }

    var body: some View {
        VStack(spacing: 16) {

            // ── Summary Cards ──────────────────────────────────
            HStack(spacing: 12) {
                CardSpendBox(
                    title:  "Credit Card",
                    amount: ccTotal,
                    count:  creditCardTxns.count,
                    color:  Color(hex: "#E74C3C"),
                    icon:   "creditcard.fill"
                )
                CardSpendBox(
                    title:  "Debit Card",
                    amount: dcTotal,
                    count:  debitCardTxns.count,
                    color:  Color(hex: "#E67E22"),
                    icon:   "creditcard"
                )
            }
            HStack(spacing: 12) {
                CardSpendBox(
                    title:  "UPI",
                    amount: upiTotal,
                    count:  upiTxns.count,
                    color:  Color(hex: "#45B7D1"),
                    icon:   "qrcode"
                )
                CardSpendBox(
                    title:  "Others",
                    amount: otherTotal,
                    count:  otherTxns.count,
                    color:  Color(hex: "#A9A9A9"),
                    icon:   "ellipsis.circle"
                )
            }

            // ── Payment Method Bar Chart ───────────────────────
            if grandTotal > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Payment Method Split")
                        .font(.headline)

                    // Visual bar
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            if ccTotal > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "#E74C3C"))
                                    .frame(width: geo.size.width * CGFloat(ccTotal / grandTotal))
                            }
                            if dcTotal > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "#E67E22"))
                                    .frame(width: geo.size.width * CGFloat(dcTotal / grandTotal))
                            }
                            if upiTotal > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "#45B7D1"))
                                    .frame(width: geo.size.width * CGFloat(upiTotal / grandTotal))
                            }
                            if otherTotal > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(hex: "#A9A9A9"))
                                    .frame(width: max(geo.size.width * CGFloat(otherTotal / grandTotal), 2))
                            }
                        }
                    }
                    .frame(height: 20)

                    // Legend
                    VStack(spacing: 6) {
                        ForEach([
                            ("Credit Card", ccTotal,    Color(hex: "#E74C3C")),
                            ("Debit Card",  dcTotal,    Color(hex: "#E67E22")),
                            ("UPI",         upiTotal,   Color(hex: "#45B7D1")),
                            ("Others",      otherTotal, Color(hex: "#A9A9A9")),
                        ], id: \.0) { item in
                            if item.1 > 0 {
                                HStack {
                                    Circle().fill(item.2).frame(width: 10, height: 10)
                                    Text(item.0).font(.subheadline)
                                    Spacer()
                                    Text("₹\(Int(item.1))")
                                        .font(.subheadline).fontWeight(.semibold)
                                    Text("\(Int(item.1 / grandTotal * 100))%")
                                        .font(.caption).foregroundColor(.secondary)
                                        .frame(width: 35, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.05), radius: 6)
            }

            // ── Credit Card Transactions ───────────────────────
            if !creditCardTxns.isEmpty {
                CardTransactionList(
                    title:        "Credit Card Transactions",
                    transactions: creditCardTxns,
                    color:        Color(hex: "#E74C3C"),
                    icon:         "creditcard.fill"
                )
            }

            // ── Debit Card Transactions ────────────────────────
            if !debitCardTxns.isEmpty {
                CardTransactionList(
                    title:        "Debit Card Transactions",
                    transactions: debitCardTxns,
                    color:        Color(hex: "#E67E22"),
                    icon:         "creditcard"
                )
            }

            // ── Category breakdown for Credit Card ────────────
            if !creditCardTxns.isEmpty {
                CardCategoryBreakdown(
                    title:        "Credit Card Spend by Category",
                    transactions: creditCardTxns,
                    color:        Color(hex: "#E74C3C")
                )
            }

            // ── Category breakdown for Debit Card ─────────────
            if !debitCardTxns.isEmpty {
                CardCategoryBreakdown(
                    title:        "Debit Card Spend by Category",
                    transactions: debitCardTxns,
                    color:        Color(hex: "#E67E22")
                )
            }

            if grandTotal == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("No card transactions this month")
                        .foregroundColor(.secondary)
                    Text("Import emails or add transactions manually")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
            }
        }
    }
}

// MARK: - Card Spend Box
struct CardSpendBox: View {
    let title:  String
    let amount: Double
    let count:  Int
    let color:  Color
    let icon:   String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
                Text("\(count) txns")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text("₹\(Int(amount))")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(amount > 0 ? .primary : .secondary)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(amount > 0 ? color.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Card Transaction List
struct CardTransactionList: View {
    let title:        String
    let transactions: [Transaction]
    let color:        Color
    let icon:         String

    @State private var isExpanded = true

    var total: Double { transactions.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.headline)
                    Spacer()
                    Text("₹\(Int(total))")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(color)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()

                ForEach(transactions.sorted { $0.date > $1.date }) { txn in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.merchant.isEmpty ? "Unknown" : txn.merchant)
                                .font(.subheadline).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(txn.category.rawValue)
                                    .font(.caption2).foregroundColor(.secondary)
                                if let acct = txn.accountLast4 {
                                    Text("••\(acct)")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("-₹\(Int(txn.amount))")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.red)
                            Text(txn.shortDate)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider().padding(.leading)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }
}

// MARK: - Card Category Breakdown
struct CardCategoryBreakdown: View {
    let title:        String
    let transactions: [Transaction]
    let color:        Color

    private var byCategory: [(cat: SpendCategory, amount: Double)] {
        var map: [SpendCategory: Double] = [:]
        for t in transactions { map[t.category, default: 0] += t.amount }
        return map.sorted { $0.value > $1.value }
                  .map { (cat: $0.key, amount: $0.value) }
    }

    private var total: Double { transactions.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).padding(.horizontal)

            ForEach(byCategory, id: \.cat) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.cat.icon)
                        .foregroundColor(item.cat.color)
                        .frame(width: 24)
                    Text(item.cat.rawValue).font(.subheadline)
                    Spacer()
                    Text("₹\(Int(item.amount))")
                        .font(.subheadline).fontWeight(.medium)
                    Text("\(Int(item.amount / max(total, 1) * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(item.amount / max(total, 1)))
                    }
                }
                .frame(height: 4)
                .padding(.horizontal)

                if item.cat != byCategory.last?.cat { Divider().padding(.leading, 44) }
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }
}

// MARK: - Category Chart (existing)
struct CategoryChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date

    private var data: [(category: SpendCategory, amount: Double)] {
        store.spendByCategory(month: month)
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, amount: $0.value) }
    }
    private var total: Double { data.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spending by Category").font(.headline)

            if data.isEmpty {
                emptyState
            } else {
                if #available(iOS 17.0, *) {
                    Chart(data, id: \.category) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(item.category.color)
                        .cornerRadius(5)
                    }
                    .frame(height: 240)
                } else {
                    Chart(data, id: \.category) { item in
                        BarMark(
                            x: .value("Amount", item.amount),
                            y: .value("Category", item.category.rawValue)
                        )
                        .foregroundStyle(item.category.color)
                        .cornerRadius(4)
                    }
                    .frame(height: CGFloat(data.count) * 36 + 20)
                }

                VStack(spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.element.category) { idx, item in
                        CategoryTableRow(category: item.category, amount: item.amount, total: total)
                        if idx < data.count - 1 { Divider() }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie").font(.system(size: 50)).foregroundColor(.secondary)
            Text("No data for this month").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

struct CategoryTableRow: View {
    let category: SpendCategory
    let amount:   Double
    let total:    Double
    var percentage: Double { amount / max(total, 1) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(category.color.opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: category.icon).foregroundColor(category.color).font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.rawValue).font(.subheadline)
                    Spacer()
                    Text("₹\(Int(amount))").font(.subheadline).fontWeight(.semibold)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(category.color)
                            .frame(width: geo.size.width * CGFloat(percentage), height: 4)
                    }
                }
                .frame(height: 4)
            }
            Text("\(Int(percentage * 100))%")
                .font(.caption).foregroundColor(.secondary).frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }
}

// MARK: - Daily Spend Chart
struct DailySpendChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date

    private var dailyData: [(day: Int, amount: Double)] { store.dailySpend(month: month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Spending").font(.headline)

            if dailyData.isEmpty {
                Text("No data").foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(dailyData, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#6C63FF"), Color(hex: "#4ECDC4")],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 5)) { _ in
                        AxisValueLabel()
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v >= 1000 ? "₹\(Int(v/1000))k" : "₹\(Int(v))")
                                    .font(.caption2)
                            }
                        }
                    }
                }

                HStack {
                    StatBadge(title: "Highest Day",
                              value: "Day \(dailyData.max(by: { $0.amount < $1.amount })?.day ?? 0)")
                    StatBadge(title: "Peak Spend",
                              value: "₹\(Int(dailyData.max(by: { $0.amount < $1.amount })?.amount ?? 0))")
                    StatBadge(title: "Active Days", value: "\(dailyData.count)")
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

// MARK: - Trend Chart
struct TrendChartSection: View {
    @EnvironmentObject var store: TransactionStore
    private var trendData: [(month: Date, spend: Double)] { store.monthlyTrend(months: 6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("6-Month Spend Trend").font(.headline)

            Chart(Array(trendData.enumerated()), id: \.offset) { idx, item in
                LineMark(x: .value("Month", idx), y: .value("Spend", item.spend))
                    .foregroundStyle(Color(hex: "#6C63FF"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                AreaMark(x: .value("Month", idx), y: .value("Spend", item.spend))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "#6C63FF").opacity(0.3), .clear],
                        startPoint: .top, endPoint: .bottom))
                PointMark(x: .value("Month", idx), y: .value("Spend", item.spend))
                    .foregroundStyle(Color(hex: "#6C63FF")).symbolSize(50)
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(values: Array(0..<trendData.count)) { value in
                    AxisValueLabel {
                        if let idx = value.as(Int.self), idx < trendData.count {
                            Text(trendData[idx].month.shortMonthYear).font(.caption2)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

// MARK: - Comparison Chart
struct ComparisonChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date

    struct BarItem: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let color: Color
    }

    private var items: [BarItem] {[
        BarItem(label: "Income",  amount: store.totalCredit(for: month), color: Color(hex: "#2ECC71")),
        BarItem(label: "Spend",   amount: store.totalSpend(for: month),  color: Color(hex: "#FF6B6B")),
        BarItem(label: "Savings",
                amount: max(store.totalCredit(for: month) - store.totalSpend(for: month), 0),
                color: Color(hex: "#3498DB")),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income vs Spend").font(.headline)

            Chart(items) { item in
                BarMark(x: .value("Type", item.label), y: .value("Amount", item.amount))
                    .foregroundStyle(item.color).cornerRadius(8)
            }
            .frame(height: 200)

            HStack {
                ForEach(items) { item in
                    VStack {
                        Text(item.label).font(.caption).foregroundColor(.secondary)
                        Text("₹\(Int(item.amount))").font(.subheadline).fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.subheadline).fontWeight(.bold)
            Text(title).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
