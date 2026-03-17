import Foundation
import Combine
import SwiftUI

// MARK: - Transaction Store (ObservableObject - single source of truth)
class TransactionStore: ObservableObject {
    
    @Published var transactions: [Transaction] = []
    @Published var monthlyReports: [MonthlyReport] = []
    @Published var budgets: [SpendCategory: Double] = [:]
    @Published var selectedMonth: Date = Date()
    
    private let transactionsKey = "transactions_v1"
    private let budgetsKey = "budgets_v1"
    private let reportsKey = "reports_v1"
    
    init() {
        loadFromDisk()
        generateDefaultBudgets()
    }
    
    // MARK: - CRUD
    func addTransaction(_ txn: Transaction) {
        guard !transactions.contains(where: { $0.id == txn.id }) else { return }
        transactions.insert(txn, at: 0)
        saveToDisk()
        regenerateCurrentMonthReport()
    }
    
    func addTransactions(_ txns: [Transaction]) {
        let newTxns = txns.filter { txn in
            !transactions.contains(where: { $0.id == txn.id })
        }
        guard !newTxns.isEmpty else { return }
        transactions.insert(contentsOf: newTxns, at: 0)
        transactions.sort { $0.date > $1.date }
        saveToDisk()
        regenerateCurrentMonthReport()
    }
    
    func updateTransaction(_ txn: Transaction) {
        if let idx = transactions.firstIndex(where: { $0.id == txn.id }) {
            transactions[idx] = txn
            saveToDisk()
            regenerateCurrentMonthReport()
        }
    }
    
    func deleteTransaction(id: UUID) {
        transactions.removeAll { $0.id == id }
        saveToDisk()
        regenerateCurrentMonthReport()
    }
    
    // MARK: - Queries
    func transactions(for month: Date) -> [Transaction] {
        let cal = Calendar.current
        return transactions.filter {
            cal.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }
    
    func transactions(for category: SpendCategory, month: Date? = nil) -> [Transaction] {
        var filtered = transactions.filter { $0.category == category && $0.type == .debit }
        if let month = month {
            let cal = Calendar.current
            filtered = filtered.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        }
        return filtered
    }
    
    func totalSpend(for month: Date) -> Double {
        transactions(for: month)
            .filter { $0.type == .debit }
            .reduce(0) { $0 + $1.amount }
    }
    
    func totalCredit(for month: Date) -> Double {
        transactions(for: month)
            .filter { $0.type == .credit }
            .reduce(0) { $0 + $1.amount }
    }
    
    func spendByCategory(month: Date) -> [SpendCategory: Double] {
        var breakdown: [SpendCategory: Double] = [:]
        for txn in transactions(for: month).filter({ $0.type == .debit }) {
            breakdown[txn.category, default: 0] += txn.amount
        }
        return breakdown
    }
    
    func dailySpend(month: Date) -> [(day: Int, amount: Double)] {
        let cal = Calendar.current
        var daily: [Int: Double] = [:]
        for txn in transactions(for: month).filter({ $0.type == .debit }) {
            let day = cal.component(.day, from: txn.date)
            daily[day, default: 0] += txn.amount
        }
        return daily.sorted { $0.key < $1.key }.map { (day: $0.key, amount: $0.value) }
    }
    
    func monthlyTrend(months: Int = 6) -> [(month: Date, spend: Double)] {
        let cal = Calendar.current
        var result: [(month: Date, spend: Double)] = []
        
        for i in 0..<months {
            if let date = cal.date(byAdding: .month, value: -i, to: Date()) {
                let spend = totalSpend(for: date)
                result.append((month: date, spend: spend))
            }
        }
        return result.reversed()
    }
    
    // MARK: - Budget
    func setBudget(_ amount: Double, for category: SpendCategory) {
        budgets[category] = amount
        saveToDisk()
    }
    
    func budgetUtilization(for category: SpendCategory, month: Date) -> Double? {
        guard let budget = budgets[category], budget > 0 else { return nil }
        let spent = transactions(for: category, month: month).reduce(0) { $0 + $1.amount }
        return spent / budget
    }
    
    func isOverBudget(for category: SpendCategory, month: Date) -> Bool {
        guard let util = budgetUtilization(for: category, month: month) else { return false }
        return util > 1.0
    }
    
    // MARK: - Reports
    func generateReport(for month: Date) -> MonthlyReport {
        let txns = transactions(for: month)
        let cal = Calendar.current
        let report = MonthlyReport(
            month: cal.component(.month, from: month),
            year: cal.component(.year, from: month),
            transactions: txns
        )
        
        // Save/update report
        if let idx = monthlyReports.firstIndex(where: {
            $0.month == report.month && $0.year == report.year
        }) {
            monthlyReports[idx] = report
        } else {
            monthlyReports.append(report)
        }
        
        saveToDisk()
        return report
    }
    
    private func regenerateCurrentMonthReport() {
        _ = generateReport(for: Date())
    }
    
    func report(for month: Date) -> MonthlyReport? {
        let cal = Calendar.current
        let m = cal.component(.month, from: month)
        let y = cal.component(.year, from: month)
        return monthlyReports.first { $0.month == m && $0.year == y }
    }
    
    // MARK: - Persistence
    private func saveToDisk() {
        if let data = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(data, forKey: transactionsKey)
        }
        if let data = try? JSONEncoder().encode(monthlyReports) {
            UserDefaults.standard.set(data, forKey: reportsKey)
        }
        let budgetDict = Dictionary(uniqueKeysWithValues: budgets.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(budgetDict) {
            UserDefaults.standard.set(data, forKey: budgetsKey)
        }
    }
    
    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: transactionsKey),
           let txns = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = txns
        }
        if let data = UserDefaults.standard.data(forKey: reportsKey),
           let reports = try? JSONDecoder().decode([MonthlyReport].self, from: data) {
            monthlyReports = reports
        }
        if let data = UserDefaults.standard.data(forKey: budgetsKey),
           let dict = try? JSONDecoder().decode([String: Double].self, from: data) {
            budgets = dict.compactMapKeys { SpendCategory(rawValue: $0) }
        }
    }
    
    private func generateDefaultBudgets() {
        guard budgets.isEmpty else { return }
        let defaults: [SpendCategory: Double] = [
            .food: 5000,
            .shopping: 3000,
            .fuel: 2000,
            .bills: 2000,
            .entertainment: 1000,
            .groceries: 4000,
        ]
        budgets = defaults
    }
    
    // MARK: - Export
    func exportCSV(month: Date) -> String {
        let txns = transactions(for: month)
        var csv = "Date,Amount,Type,Category,Merchant,Bank,UPI ID,Balance,Notes\n"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        
        for txn in txns {
            let row = [
                formatter.string(from: txn.date),
                String(format: "%.2f", txn.amount),
                txn.type.rawValue,
                txn.category.rawValue,
                txn.merchant,
                txn.bankName,
                txn.upiId ?? "",
                txn.balance.map { String(format: "%.2f", $0) } ?? "",
                txn.note ?? ""
            ].map { "\"\($0)\"" }.joined(separator: ",")
            csv += row + "\n"
        }
        return csv
    }
}

// Helper extension
extension Dictionary {
    func compactMapKeys<T: Hashable>(_ transform: (Key) -> T?) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let newKey = transform(key) {
                result[newKey] = value
            }
        }
        return result
    }
}
