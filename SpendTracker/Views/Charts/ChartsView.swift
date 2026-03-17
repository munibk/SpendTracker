import SwiftUI
import Charts

// MARK: - Charts View
struct ChartsView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedMonth: Date = Date()
    @State private var selectedChart: ChartType = .category
    
    enum ChartType: String, CaseIterable {
        case category = "Category"
        case daily = "Daily"
        case trend = "Trend"
        case comparison = "Comparison"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Month Picker
                    monthPicker
                    
                    // Chart Type Selector
                    chartTypeSelector
                    
                    // Chart Content
                    switch selectedChart {
                    case .category:
                        CategoryChartSection(month: selectedMonth)
                    case .daily:
                        DailySpendChartSection(month: selectedMonth)
                    case .trend:
                        TrendChartSection()
                    case .comparison:
                        ComparisonChartSection(month: selectedMonth)
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
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthYearString(selectedMonth))
                .font(.headline)
            Spacer()
            Button(action: { moveMonth(1) }) {
                Image(systemName: "chevron.right")
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedChart == type ? Color(hex: "#6C63FF") : Color(.systemGray5))
                            .foregroundColor(selectedChart == type ? .white : .primary)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }
    
    private func moveMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Category Chart
struct CategoryChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date
    
    private var data: [(category: SpendCategory, amount: Double)] {
        store.spendByCategory(month: month)
            .sorted { $0.value > $1.value }
            .map { (category: $0.key, amount: $0.value) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Spending by Category")
                .font(.headline)
            
            if data.isEmpty {
                emptyState
            } else {
                // Donut Chart
                if #available(iOS 16.0, *) {
                    Chart(data, id: \.category) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.6),
                            angularInset: 2
                        )
                        .foregroundStyle(item.category.color)
                        .cornerRadius(5)
                        .annotation(position: .overlay) {
                            if item.amount / data.reduce(0, { $0 + $1.amount }) > 0.1 {
                                Text("\(Int(item.amount / data.reduce(0, { $0 + $1.amount }) * 100))%")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(height: 240)
                }
                
                // Table
                VStack(spacing: 0) {
                    ForEach(data, id: \.category) { item in
                        CategoryTableRow(
                            category: item.category,
                            amount: item.amount,
                            total: data.reduce(0) { $0 + $1.amount }
                        )
                        if item.category != data.last?.category {
                            Divider()
                        }
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
            Image(systemName: "chart.pie")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No data for this month")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

struct CategoryTableRow: View {
    let category: SpendCategory
    let amount: Double
    let total: Double
    
    var percentage: Double { amount / max(total, 1) }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                    .font(.system(size: 14))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.rawValue)
                        .font(.subheadline)
                    Spacer()
                    Text("₹\(amount.formatted(.number.precision(.fractionLength(0))))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(category.color)
                            .frame(width: geo.size.width * CGFloat(percentage), height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            Text("\(Int(percentage * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Daily Spend Chart
struct DailySpendChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date
    
    private var dailyData: [(day: Int, amount: Double)] {
        store.dailySpend(month: month)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Spending")
                .font(.headline)
            
            if dailyData.isEmpty {
                Text("No data").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else if #available(iOS 16.0, *) {
                Chart(dailyData, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#6C63FF"), Color(hex: "#4ECDC4")],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 5))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("₹\(Int(v/1000))k")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                
                // Stats
                HStack {
                    StatBadge(title: "Highest Day", value: "Day \(dailyData.max(by: { $0.amount < $1.amount })?.day ?? 0)")
                    StatBadge(title: "Peak Spend", value: "₹\(Int(dailyData.max(by: { $0.amount < $1.amount })?.amount ?? 0))")
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
    
    private var trendData: [(month: Date, spend: Double)] {
        store.monthlyTrend(months: 6)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("6-Month Trend")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart(Array(trendData.enumerated()), id: \.offset) { idx, item in
                    LineMark(
                        x: .value("Month", idx),
                        y: .value("Spend", item.spend)
                    )
                    .foregroundStyle(Color(hex: "#6C63FF"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    
                    AreaMark(
                        x: .value("Month", idx),
                        y: .value("Spend", item.spend)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#6C63FF").opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    PointMark(
                        x: .value("Month", idx),
                        y: .value("Spend", item.spend)
                    )
                    .foregroundStyle(Color(hex: "#6C63FF"))
                    .symbolSize(50)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let idx = value.as(Int.self), idx < trendData.count {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "MMM"
                                Text(formatter.string(from: trendData[idx].month))
                                    .font(.caption2)
                            }
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

// MARK: - Comparison Chart (Debit vs Credit)
struct ComparisonChartSection: View {
    @EnvironmentObject var store: TransactionStore
    let month: Date
    
    struct CompData: Identifiable {
        let id = UUID()
        let label: String
        let type: String
        let amount: Double
    }
    
    private var data: [CompData] {
        [
            CompData(label: "Spend", type: "Debit", amount: store.totalSpend(for: month)),
            CompData(label: "Income", type: "Credit", amount: store.totalCredit(for: month)),
            CompData(label: "Savings", type: "Savings", amount: max(store.totalCredit(for: month) - store.totalSpend(for: month), 0))
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income vs Spend")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart(data) { item in
                    BarMark(
                        x: .value("Type", item.label),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(
                        item.type == "Debit" ? Color(hex: "#FF6B6B") :
                        item.type == "Credit" ? Color(hex: "#2ECC71") :
                        Color(hex: "#3498DB")
                    )
                    .cornerRadius(8)
                }
                .frame(height: 200)
            }
            
            HStack {
                ForEach(data) { item in
                    VStack {
                        Text(item.label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("₹\(Int(item.amount))")
                            .font(.subheadline)
                            .fontWeight(.bold)
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
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// Calendar extension
extension Calendar {
    func isDateInThisMonth(_ date: Date) -> Bool {
        isDate(date, equalTo: Date(), toGranularity: .month)
    }
}
