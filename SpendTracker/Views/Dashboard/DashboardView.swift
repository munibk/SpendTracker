import SwiftUI
import Charts

// MARK: - Dashboard View
struct DashboardView: View {
    @EnvironmentObject var store: TransactionStore
    @EnvironmentObject var smsService: SMSReaderService
    @State private var showAddTransaction = false
    @State private var showManualImport = false
    
    private var currentMonth: Date { Date() }
    
    private var totalSpend: Double { store.totalSpend(for: currentMonth) }
    private var totalCredit: Double { store.totalCredit(for: currentMonth) }
    private var recentTransactions: [Transaction] {
        Array(store.transactions(for: currentMonth).prefix(5))
    }
    private var categoryData: [(category: SpendCategory, amount: Double)] {
        store.spendByCategory(month: currentMonth)
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (category: $0.key, amount: $0.value) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Summary Cards
                    summaryCards
                    
                    // Sync Status
                    syncStatusCard
                    
                    // Category Breakdown (Mini Pie)
                    if !categoryData.isEmpty {
                        categoryMiniChart
                    }
                    
                    // Budget Overview
                    budgetOverview
                    
                    // Recent Transactions
                    recentTransactionsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("SpendTracker")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showAddTransaction = true }) {
                            Label("Add Manually", systemImage: "plus.circle")
                        }
                        Button(action: { showManualImport = true }) {
                            Label("Import SMS", systemImage: "message.fill")
                        }
                        Button(action: { smsService.fetchNewMessages() }) {
                            Label("Sync Now", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTransactionView()
            }
            .sheet(isPresented: $showManualImport) {
                ManualSMSImportView()
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(monthYearString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("₹\(totalSpend.formatted(.number.precision(.fractionLength(0))))")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Total Spent This Month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Circle gauge
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(totalSpend / max(totalCredit, 1)), 1))
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "#6C63FF"), Color(hex: "#FF6B6B")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(min(totalSpend / max(totalCredit, 1), 1) * 100))%")
                            .font(.system(size: 14, weight: .bold))
                        Text("of income")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(hex: "#1A1A2E"), Color(hex: "#16213E")],
                    startPoint: .topLeading,
                    endPoint: .bottomRight
                ))
        )
        .colorScheme(.dark)
    }
    
    // MARK: - Summary Cards
    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Income",
                amount: totalCredit,
                icon: "arrow.down.circle.fill",
                color: Color(hex: "#2ECC71")
            )
            SummaryCard(
                title: "Savings",
                amount: max(totalCredit - totalSpend, 0),
                icon: "banknote.fill",
                color: Color(hex: "#3498DB")
            )
            SummaryCard(
                title: "Transactions",
                amount: Double(store.transactions(for: currentMonth).count),
                icon: "list.bullet",
                color: Color(hex: "#9B59B6"),
                isCount: true
            )
        }
    }
    
    // MARK: - Sync Status
    private var syncStatusCard: some View {
        HStack {
            Circle()
                .fill(smsService.isMonitoring ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(smsService.syncStatus)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let lastSync = smsService.lastSyncDate {
                Text("Last: \(lastSync.formatted(.relative(presentation: .numeric)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Category Mini Chart
    private var categoryMiniChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Categories")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                Chart(categoryData, id: \.category) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(item.category.color)
                    .cornerRadius(4)
                }
                .frame(height: 200)
            }
            
            // Legend
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(categoryData, id: \.category) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.category.color)
                            .frame(width: 8, height: 8)
                        Text(item.category.rawValue)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("₹\(Int(item.amount))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Budget Overview
    private var budgetOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Overview")
                .font(.headline)
            
            ForEach(store.budgets.sorted(by: { $0.value > $1.value }).prefix(4), id: \.key) { cat, budget in
                let spent = store.transactions(for: cat, month: currentMonth).reduce(0) { $0 + $1.amount }
                let utilization = spent / budget
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: cat.icon)
                            .foregroundColor(cat.color)
                            .frame(width: 16)
                        Text(cat.rawValue)
                            .font(.caption)
                        Spacer()
                        Text("₹\(Int(spent)) / ₹\(Int(budget))")
                            .font(.caption)
                            .foregroundColor(utilization > 1 ? .red : .secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(utilization > 1 ? Color.red : cat.color)
                                .frame(width: geo.size.width * min(CGFloat(utilization), 1), height: 6)
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
    
    // MARK: - Recent Transactions
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Transactions")
                    .font(.headline)
                Spacer()
                NavigationLink("See All") {
                    TransactionsListView()
                }
                .font(.caption)
            }
            
            if recentTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No transactions yet")
                        .foregroundColor(.secondary)
                    Text("Sync SMS or add manually")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(recentTransactions) { txn in
                    TransactionRow(transaction: txn)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }
}

// MARK: - Summary Card
struct SummaryCard: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    var isCount: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            Text(isCount ? "\(Int(amount))" : "₹\(amount.formatted(.number.precision(.fractionLength(0))))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Transaction Row
struct TransactionRow: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(transaction.category.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: transaction.category.icon)
                    .foregroundColor(transaction.category.color)
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant.isEmpty ? "Unknown" : transaction.merchant)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack {
                    Text(transaction.category.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    if let acct = transaction.accountLast4 {
                        Text("••\(acct)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.type == .debit ? "-₹\(Int(transaction.amount))" : "+₹\(Int(transaction.amount))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(transaction.type.color)
                Text(transaction.shortDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
