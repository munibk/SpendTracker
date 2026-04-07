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

    @State private var selectedMethod: PayMethod = .all

    // ── Payment method enum ────────────────────────────────
    enum PayMethod: String, CaseIterable, Identifiable {
        case all    = "All Debits"
        case credit = "Credit Card"
        case debit  = "Debit Card"
        case upi    = "UPI"
        case others = "Others"
        var id: String { rawValue }
        var shortName: String {
            switch self {
            case .all: return "All"; case .credit: return "Credit"
            case .debit: return "Debit"; case .upi: return "UPI"; case .others: return "Others"
            }
        }
        var color: Color {
            switch self {
            case .all:    return Color(hex: "#6C63FF")
            case .credit: return Color(hex: "#E74C3C")
            case .debit:  return Color(hex: "#E67E22")
            case .upi:    return Color(hex: "#45B7D1")
            case .others: return Color(hex: "#A9A9A9")
            }
        }
        var icon: String {
            switch self {
            case .all:    return "rectangle.stack"
            case .credit: return "creditcard.fill"
            case .debit:  return "creditcard"
            case .upi:    return "qrcode"
            case .others: return "ellipsis.circle"
            }
        }
    }

    // ── Transaction buckets ────────────────────────────────
    private var creditCardTxns: [Transaction] {
        store.transactions(for: month).filter { $0.type == .debit && $0.cardType == .credit }
    }
    private var debitCardTxns: [Transaction] {
        store.transactions(for: month).filter { $0.type == .debit && $0.cardType == .debit }
    }
    private var upiTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .none &&
            ($0.upiId != nil || $0.category == .upi)
        }
    }
    private var otherTxns: [Transaction] {
        store.transactions(for: month).filter {
            $0.type == .debit && $0.cardType == .none &&
            $0.upiId == nil && $0.category != .upi
        }
    }
    private var allDebitTxns: [Transaction] {
        creditCardTxns + debitCardTxns + upiTxns + otherTxns
    }

    private func txns(for method: PayMethod) -> [Transaction] {
        switch method {
        case .all:    return allDebitTxns
        case .credit: return creditCardTxns
        case .debit:  return debitCardTxns
        case .upi:    return upiTxns
        case .others: return otherTxns
        }
    }
    private func total(for method: PayMethod) -> Double {
        txns(for: method).reduce(0) { $0 + $1.amount }
    }
    private var grandTotal: Double { total(for: .all) }

    var body: some View {
        VStack(spacing: 16) {
            if grandTotal == 0 {
                emptyState
            } else {
                // Horizontally scrollable tappable payment-method cards
                methodSelectorRow
                // Category breakdown + transaction list for selected method
                methodDetailView
            }
        }
    }

    // ── Tappable method selector ───────────────────────────
    private var methodSelectorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PayMethod.allCases) { method in
                    let t          = total(for: method)
                    let cnt        = txns(for: method).count
                    let isSelected = selectedMethod == method
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: method.icon)
                                .font(.caption)
                                .foregroundColor(isSelected ? .white : method.color)
                            Text(method.shortName)
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(isSelected ? .white : .primary)
                            Spacer(minLength: 0)
                        }
                        Text("₹\(Int(t))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .white : (t > 0 ? .primary : .secondary))
                        Text("\(cnt) txns")
                            .font(.caption2)
                            .foregroundColor(isSelected ? .white.opacity(0.75) : .secondary)
                    }
                    .padding(12)
                    .frame(width: 110)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? method.color : Color(.systemBackground))
                            .shadow(color: (isSelected ? method.color : Color.black).opacity(0.15),
                                    radius: 6, x: 0, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.clear : method.color.opacity(0.25), lineWidth: 1)
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) { selectedMethod = method }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }

    // ── Detail: donut chart + category rows + transaction list ──
    @ViewBuilder
    private var methodDetailView: some View {
        if txns(for: selectedMethod).isEmpty {
            Text("No transactions for this payment method")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(Color(.systemBackground))
                .cornerRadius(16)
        } else {
            CategoryBreakdownCard(
                transactions: txns(for: selectedMethod),
                color: selectedMethod.color,
                title: "\(selectedMethod.rawValue) — by Category"
            )
            CollapsibleTransactionList(
                title: "\(selectedMethod.rawValue) Transactions",
                transactions: txns(for: selectedMethod),
                color: selectedMethod.color,
                icon: selectedMethod.icon
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 50)).foregroundColor(.secondary)
            Text("No card transactions this month").foregroundColor(.secondary)
            Text("Import emails or add transactions manually")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Category Breakdown Card (donut chart + category rows)
struct CategoryBreakdownCard: View {
    let transactions: [Transaction]
    let color: Color
    let title: String

    private var byCategory: [(cat: SpendCategory, amount: Double)] {
        var map: [SpendCategory: Double] = [:]
        for t in transactions { map[t.category, default: 0] += t.amount }
        return map.sorted { $0.value > $1.value }.map { (cat: $0.key, amount: $0.value) }
    }
    private var total: Double { transactions.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("₹\(Int(total))").font(.subheadline).fontWeight(.bold).foregroundColor(color)
            }
            .padding([.horizontal, .top])

            // Donut chart (iOS 17+) / horizontal bar chart fallback
            if #available(iOS 17.0, *) {
                Chart(byCategory, id: \.cat) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(item.cat.color)
                    .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(height: 200)
                .padding()
            } else {
                Chart(byCategory, id: \.cat) { item in
                    BarMark(
                        x: .value("Amount", item.amount),
                        y: .value("Category", item.cat.rawValue)
                    )
                    .foregroundStyle(item.cat.color)
                    .cornerRadius(4)
                }
                .frame(height: CGFloat(min(byCategory.count, 8)) * 36 + 20)
                .padding()
            }

            Divider()

            // Category rows with inline progress bars
            ForEach(Array(byCategory.enumerated()), id: \.element.cat) { idx, item in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(item.cat.color.opacity(0.15)).frame(width: 32, height: 32)
                        Image(systemName: item.cat.icon)
                            .foregroundColor(item.cat.color).font(.system(size: 13))
                    }
                    Text(item.cat.rawValue).font(.subheadline)
                    Spacer()
                    Text("₹\(Int(item.amount))").font(.subheadline).fontWeight(.semibold)
                    Text("\(Int(item.amount / max(total, 1) * 100))%")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.horizontal).padding(.vertical, 8)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.cat.color)
                            .frame(width: geo.size.width * CGFloat(item.amount / max(total, 1)))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal)

                if idx < byCategory.count - 1 { Divider().padding(.leading, 52) }
            }

            Spacer(minLength: 12)
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6)
    }
}

// MARK: - Collapsible Transaction List
struct CollapsibleTransactionList: View {
    let title:        String
    let transactions: [Transaction]
    let color:        Color
    let icon:         String

    @State private var isExpanded = false

    private var total:  Double        { transactions.reduce(0) { $0 + $1.amount } }
    private var sorted: [Transaction] { transactions.sorted { $0.date > $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon).foregroundColor(color)
                    Text(title).font(.headline)
                    Spacer()
                    Text("₹\(Int(total))")
                        .font(.subheadline).fontWeight(.semibold).foregroundColor(color)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                ForEach(sorted) { txn in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(txn.category.color.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: txn.category.icon)
                                .foregroundColor(txn.category.color).font(.system(size: 13))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.merchant.isEmpty ? "Unknown" : txn.merchant)
                                .font(.subheadline).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(txn.category.rawValue)
                                    .font(.caption2).foregroundColor(.secondary)
                                if let acct = txn.accountLast4 {
                                    Text("••\(acct)").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("-₹\(Int(txn.amount))")
                                .font(.subheadline).fontWeight(.semibold).foregroundColor(.red)
                            Text(txn.shortDate).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    Divider().padding(.leading, 60)
                }
            }
        }
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
