import Foundation
import Combine

// MARK: - Transaction Store
class TransactionStore: ObservableObject {

    @Published var transactions:   [Transaction]   = []
    @Published var monthlyReports: [MonthlyReport] = []
    @Published var budgets:        [SpendCategory: Double] = [:]

    private let txKey      = "transactions_v1"
    private let budgetKey  = "budgets_v1"
    private let reportKey  = "reports_v1"

    init() {
        loadFromDisk()
        if budgets.isEmpty { setDefaultBudgets() }
    }

    // MARK: - CRUD
    func addTransaction(_ txn: Transaction) {
        guard !transactions.contains(where: { $0.id == txn.id }) else { return }
        transactions.insert(txn, at: 0)
        save()
        regenerateReport(for: txn.date)
    }

    func addTransactions(_ txns: [Transaction]) {
        let fresh = txns.filter { t in !transactions.contains(where: { $0.id == t.id }) }
        guard !fresh.isEmpty else { return }
        transactions.insert(contentsOf: fresh, at: 0)
        transactions.sort { $0.date > $1.date }
        save()
        if let d = fresh.first?.date { regenerateReport(for: d) }
    }

    func updateTransaction(_ txn: Transaction) {
        guard let idx = transactions.firstIndex(where: { $0.id == txn.id }) else { return }
        transactions[idx] = txn
        save()
        regenerateReport(for: txn.date)
    }

    func deleteTransaction(id: UUID) {
        guard let txn = transactions.first(where: { $0.id == id }) else { return }
        transactions.removeAll { $0.id == id }
        save()
        regenerateReport(for: txn.date)
    }

    // MARK: - Queries
    func transactions(for month: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func transactions(for category: SpendCategory, month: Date? = nil) -> [Transaction] {
        var result = transactions.filter { $0.category == category && $0.type == .debit }
        if let month {
            result = result.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
        }
        return result
    }

    func totalSpend(for month: Date) -> Double {
        transactions(for: month).filter { $0.type == .debit }.reduce(0) { $0 + $1.amount }
    }

    func totalCredit(for month: Date) -> Double {
        transactions(for: month).filter { $0.type == .credit }.reduce(0) { $0 + $1.amount }
    }

    func spendByCategory(month: Date) -> [SpendCategory: Double] {
        var result: [SpendCategory: Double] = [:]
        for t in transactions(for: month).filter({ $0.type == .debit }) {
            result[t.category, default: 0] += t.amount
        }
        return result
    }

    func dailySpend(month: Date) -> [(day: Int, amount: Double)] {
        var daily: [Int: Double] = [:]
        for t in transactions(for: month).filter({ $0.type == .debit }) {
            let d = Calendar.current.component(.day, from: t.date)
            daily[d, default: 0] += t.amount
        }
        return daily.sorted { $0.key < $1.key }.map { (day: $0.key, amount: $0.value) }
    }

    func monthlyTrend(months: Int = 6) -> [(month: Date, spend: Double)] {
        (0..<months).compactMap { i -> (month: Date, spend: Double)? in
            guard let d = Calendar.current.date(byAdding: .month, value: -i, to: Date()) else { return nil }
            return (month: d, spend: totalSpend(for: d))
        }.reversed()
    }

    // MARK: - Budget
    func setBudget(_ amount: Double, for category: SpendCategory) {
        budgets[category] = amount
        save()
    }

    func budgetUtilization(for category: SpendCategory, month: Date) -> Double? {
        guard let budget = budgets[category], budget > 0 else { return nil }
        let spent = transactions(for: category, month: month).reduce(0) { $0 + $1.amount }
        return spent / budget
    }

    func isOverBudget(for category: SpendCategory, month: Date) -> Bool {
        (budgetUtilization(for: category, month: month) ?? 0) > 1.0
    }

    // MARK: - Reports
    @discardableResult
    func generateReport(for month: Date) -> MonthlyReport {
        let cal = Calendar.current
        let report = MonthlyReport(
            month: cal.component(.month, from: month),
            year:  cal.component(.year,  from: month),
            transactions: transactions(for: month)
        )
        if let idx = monthlyReports.firstIndex(where: { $0.month == report.month && $0.year == report.year }) {
            monthlyReports[idx] = report
        } else {
            monthlyReports.append(report)
        }
        save()
        return report
    }

    func report(for month: Date) -> MonthlyReport? {
        let cal = Calendar.current
        let m = cal.component(.month, from: month)
        let y = cal.component(.year,  from: month)
        return monthlyReports.first { $0.month == m && $0.year == y }
    }

    private func regenerateReport(for date: Date) {
        generateReport(for: date)
    }

    func clearAllData() {
        transactions   = []
        monthlyReports = []
        UserDefaults.standard.removeObject(forKey: txKey)
        UserDefaults.standard.removeObject(forKey: reportKey)
    }

    // MARK: - CSV Export
    func exportCSV(month: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy HH:mm"
        var csv = "Date,Amount,Type,Category,Merchant,Bank,UPI ID,Balance,Note\n"
        for t in transactions(for: month) {
            let row = [
                f.string(from: t.date),
                String(format: "%.2f", t.amount),
                t.type.rawValue,
                t.category.rawValue,
                t.merchant,
                t.bankName,
                t.upiId ?? "",
                t.balance.map { String(format: "%.2f", $0) } ?? "",
                t.note ?? ""
            ].map { "\"\($0)\"" }.joined(separator: ",")
            csv += row + "\n"
        }
        return csv
    }

    // MARK: - Persistence
    private func save() {
        if let data = try? JSONEncoder().encode(transactions) {
            UserDefaults.standard.set(data, forKey: txKey)
        }
        if let data = try? JSONEncoder().encode(monthlyReports) {
            UserDefaults.standard.set(data, forKey: reportKey)
        }
        let budgetRaw = Dictionary(uniqueKeysWithValues: budgets.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(budgetRaw) {
            UserDefaults.standard.set(data, forKey: budgetKey)
        }
    }

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: txKey),
           let decoded = try? JSONDecoder().decode([Transaction].self, from: data) {
            transactions = decoded
        }
        if let data = UserDefaults.standard.data(forKey: reportKey),
           let decoded = try? JSONDecoder().decode([MonthlyReport].self, from: data) {
            monthlyReports = decoded
        }
        if let data = UserDefaults.standard.data(forKey: budgetKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            budgets = Dictionary(uniqueKeysWithValues:
                decoded.compactMap { k, v -> (SpendCategory, Double)? in
                    guard let cat = SpendCategory(rawValue: k) else { return nil }
                    return (cat, v)
                })
        }
    }

    private func setDefaultBudgets() {
        budgets = [
            .food: 5000, .shopping: 3000, .fuel: 2000,
            .bills: 2000, .entertainment: 1000, .groceries: 4000,
            .travel: 3000, .health: 2000,
        ]
    }
}
