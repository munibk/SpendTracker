import SwiftUI

// MARK: - Transactions List View
struct TransactionsListView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var searchText = ""
    @State private var selectedCategory: SpendCategory? = nil
    @State private var selectedType: TransactionType? = nil
    @State private var selectedMonth: Date = Date()
    @State private var showFilters = false
    @State private var editingTransaction: Transaction? = nil
    
    private var filteredTransactions: [Transaction] {
        var txns = store.transactions(for: selectedMonth)
        
        if let category = selectedCategory {
            txns = txns.filter { $0.category == category }
        }
        if let type = selectedType {
            txns = txns.filter { $0.type == type }
        }
        if !searchText.isEmpty {
            txns = txns.filter {
                $0.merchant.localizedCaseInsensitiveContains(searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(searchText) ||
                $0.bankName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return txns
    }
    
    private var groupedTransactions: [(date: String, transactions: [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { txn -> String in
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMM yyyy"
            return formatter.string(from: txn.date)
        }
        return grouped
            .sorted { a, b in
                let formatter = DateFormatter()
                formatter.dateFormat = "dd MMM yyyy"
                let dateA = formatter.date(from: a.key) ?? Date.distantPast
                let dateB = formatter.date(from: b.key) ?? Date.distantPast
                return dateA > dateB
            }
            .map { (date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Month + Filter Bar
                filterBar
                
                // Summary strip
                summaryStrip
                
                // List
                if filteredTransactions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedTransactions, id: \.date) { group in
                            Section(header: sectionHeader(group.date, transactions: group.transactions)) {
                                ForEach(group.transactions) { txn in
                                    TransactionRow(transaction: txn)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editingTransaction = txn }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                store.deleteTransaction(id: txn.id)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                editingTransaction = txn
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search merchant, category...")
            .sheet(item: $editingTransaction) { txn in
                EditTransactionView(transaction: txn)
            }
        }
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Month nav
                HStack(spacing: 4) {
                    Button(action: { moveMonth(-1) }) {
                        Image(systemName: "chevron.left").font(.caption)
                    }
                    Text(shortMonthYear(selectedMonth))
                        .font(.caption)
                        .fontWeight(.medium)
                    Button(action: { moveMonth(1) }) {
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .disabled(Calendar.current.isDateInThisMonth(selectedMonth))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "#6C63FF").opacity(0.15))
                .cornerRadius(16)
                
                Divider().frame(height: 20)
                
                // Type filter
                ForEach(TransactionType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        isSelected: selectedType == type,
                        color: type.color
                    ) {
                        selectedType = selectedType == type ? nil : type
                    }
                }
                
                Divider().frame(height: 20)
                
                // Category filters
                ForEach(SpendCategory.allCases.prefix(8)) { cat in
                    FilterChip(
                        title: cat.rawValue,
                        isSelected: selectedCategory == cat,
                        color: cat.color
                    ) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGray6))
    }
    
    private var summaryStrip: some View {
        HStack {
            Label(
                "₹\(filteredTransactions.filter({ $0.type == .debit }).reduce(0, { $0 + $1.amount }).formatted(.number.precision(.fractionLength(0))))",
                systemImage: "arrow.up.right"
            )
            .foregroundColor(.red)
            .font(.caption)
            
            Spacer()
            
            Text("\(filteredTransactions.count) transactions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Label(
                "₹\(filteredTransactions.filter({ $0.type == .credit }).reduce(0, { $0 + $1.amount }).formatted(.number.precision(.fractionLength(0))))",
                systemImage: "arrow.down.left"
            )
            .foregroundColor(.green)
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private func sectionHeader(_ dateString: String, transactions: [Transaction]) -> some View {
        HStack {
            Text(dateString)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            let dayTotal = transactions.filter { $0.type == .debit }.reduce(0) { $0 + $1.amount }
            Text("-₹\(Int(dayTotal))")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No transactions found")
                .font(.headline)
            Text("Try changing the filters or sync SMS")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func moveMonth(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
            selectedMonth = newDate
        }
    }
    
    private func shortMonthYear(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM yy"; return f.string(from: date)
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color : color.opacity(0.12))
                .foregroundColor(isSelected ? .white : color)
                .cornerRadius(12)
        }
    }
}
