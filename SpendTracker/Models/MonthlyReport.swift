import Foundation
import SwiftUI

// MARK: - Monthly Report
struct MonthlyReport: Identifiable, Codable {
    var id: UUID = UUID()
    var month: Int          // 1-12
    var year: Int
    var generatedAt: Date = Date()
    
    var totalSpend: Double
    var totalCredit: Double
    var netBalance: Double { totalCredit - totalSpend }
    
    var categoryBreakdown: [SpendCategory: Double]  // category -> total spend
    var dailySpend: [Int: Double]                   // day of month -> spend
    var topMerchants: [(name: String, amount: Double)]
    var transactions: [Transaction]
    
    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.month = month
        components.year = year
        components.day = 1
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
    
    var topCategory: SpendCategory? {
        categoryBreakdown.max(by: { $0.value < $1.value })?.key
    }
    
    var averageDailySpend: Double {
        guard !dailySpend.isEmpty else { return 0 }
        return totalSpend / Double(dailySpend.count)
    }
    
    // Encoded category breakdown for Codable compliance
    private enum CodingKeys: String, CodingKey {
        case id, month, year, generatedAt, totalSpend, totalCredit
        case categoryBreakdownEncoded, dailySpend, topMerchantsEncoded, transactions
    }
    
    init(
        month: Int,
        year: Int,
        transactions: [Transaction]
    ) {
        self.month = month
        self.year = year
        self.transactions = transactions
        
        let debits = transactions.filter { $0.type == .debit }
        let credits = transactions.filter { $0.type == .credit }
        
        self.totalSpend = debits.reduce(0) { $0 + $1.amount }
        self.totalCredit = credits.reduce(0) { $0 + $1.amount }
        
        // Category breakdown
        var breakdown: [SpendCategory: Double] = [:]
        for txn in debits {
            breakdown[txn.category, default: 0] += txn.amount
        }
        self.categoryBreakdown = breakdown
        
        // Daily spend
        var daily: [Int: Double] = [:]
        for txn in debits {
            let day = Calendar.current.component(.day, from: txn.date)
            daily[day, default: 0] += txn.amount
        }
        self.dailySpend = daily
        
        // Top merchants
        var merchantMap: [String: Double] = [:]
        for txn in debits {
            let merchant = txn.merchant.isEmpty ? "Unknown" : txn.merchant
            merchantMap[merchant, default: 0] += txn.amount
        }
        self.topMerchants = merchantMap
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { (name: $0.key, amount: $0.value) }
    }
    
    // MARK: - Codable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        month = try container.decode(Int.self, forKey: .month)
        year = try container.decode(Int.self, forKey: .year)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        totalSpend = try container.decode(Double.self, forKey: .totalSpend)
        totalCredit = try container.decode(Double.self, forKey: .totalCredit)
        transactions = try container.decode([Transaction].self, forKey: .transactions)
        
        let encodedBreakdown = try container.decode([String: Double].self, forKey: .categoryBreakdownEncoded)
        var breakdown: [SpendCategory: Double] = [:]
        for (key, value) in encodedBreakdown {
            if let cat = SpendCategory(rawValue: key) {
                breakdown[cat] = value
            }
        }
        self.categoryBreakdown = breakdown
        
        let encodedMerchants = try container.decode([[String: Double]].self, forKey: .topMerchantsEncoded)
        self.topMerchants = encodedMerchants.compactMap { dict in
            guard let name = dict.keys.first, let amount = dict[name] else { return nil }
            return (name: name, amount: amount)
        }
        
        dailySpend = try container.decode([Int: Double].self, forKey: .dailySpend)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(month, forKey: .month)
        try container.encode(year, forKey: .year)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(totalSpend, forKey: .totalSpend)
        try container.encode(totalCredit, forKey: .totalCredit)
        try container.encode(transactions, forKey: .transactions)
        
        let encodedBreakdown = Dictionary(uniqueKeysWithValues: categoryBreakdown.map { ($0.key.rawValue, $0.value) })
        try container.encode(encodedBreakdown, forKey: .categoryBreakdownEncoded)
        
        let encodedMerchants = topMerchants.map { ["\($0.name)": $0.amount] }
        try container.encode(encodedMerchants, forKey: .topMerchantsEncoded)
        
        try container.encode(dailySpend, forKey: .dailySpend)
    }
}
