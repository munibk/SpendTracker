import Foundation

// MARK: - Monthly Report
struct MonthlyReport: Identifiable, Codable {
    var id:          UUID = UUID()
    var month:       Int
    var year:        Int
    var generatedAt: Date = Date()
    var totalSpend:  Double
    var totalCredit: Double
    var transactions: [Transaction]

    // Non-Codable computed storage — rebuilt on init
    var categoryBreakdown: [SpendCategory: Double] = [:]
    var dailySpend:        [Int: Double]           = [:]
    var topMerchants:      [(name: String, amount: Double)] = []

    var netBalance: Double { totalCredit - totalSpend }

    var monthName: String {
        var c = DateComponents()
        c.month = month; c.year = year; c.day = 1
        let d = Calendar.current.date(from: c) ?? Date()
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }
    var topCategory: SpendCategory? {
        categoryBreakdown.max(by: { $0.value < $1.value })?.key
    }
    var averageDailySpend: Double {
        dailySpend.isEmpty ? 0 : totalSpend / Double(dailySpend.count)
    }

    init(month: Int, year: Int, transactions: [Transaction]) {
        self.month        = month
        self.year         = year
        self.transactions = transactions

        let debits  = transactions.filter { $0.type == .debit }
        let credits = transactions.filter { $0.type == .credit }
        totalSpend  = debits.reduce(0)  { $0 + $1.amount }
        totalCredit = credits.reduce(0) { $0 + $1.amount }

        var breakdown: [SpendCategory: Double] = [:]
        for t in debits { breakdown[t.category, default: 0] += t.amount }
        categoryBreakdown = breakdown

        var daily: [Int: Double] = [:]
        for t in debits {
            let day = Calendar.current.component(.day, from: t.date)
            daily[day, default: 0] += t.amount
        }
        dailySpend = daily

        var merchants: [String: Double] = [:]
        for t in debits { merchants[t.merchant.isEmpty ? "Unknown" : t.merchant, default: 0] += t.amount }
        topMerchants = merchants.sorted { $0.value > $1.value }.prefix(5).map { (name: $0.key, amount: $0.value) }
    }

    // MARK: Codable
    enum CodingKeys: String, CodingKey {
        case id, month, year, generatedAt, totalSpend, totalCredit, transactions
        case categoryBreakdownRaw, dailySpendRaw, topMerchantsRaw
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,          forKey: .id)
        month        = try c.decode(Int.self,           forKey: .month)
        year         = try c.decode(Int.self,           forKey: .year)
        generatedAt  = try c.decode(Date.self,          forKey: .generatedAt)
        totalSpend   = try c.decode(Double.self,        forKey: .totalSpend)
        totalCredit  = try c.decode(Double.self,        forKey: .totalCredit)
        transactions = try c.decode([Transaction].self, forKey: .transactions)

        let rawBreakdown = try c.decode([String: Double].self, forKey: .categoryBreakdownRaw)
        categoryBreakdown = Dictionary(uniqueKeysWithValues:
            rawBreakdown.compactMap { k, v -> (SpendCategory, Double)? in
                guard let cat = SpendCategory(rawValue: k) else { return nil }
                return (cat, v)
            })

        let rawDaily = try c.decode([String: Double].self, forKey: .dailySpendRaw)
        dailySpend = Dictionary(uniqueKeysWithValues:
            rawDaily.compactMap { k, v -> (Int, Double)? in
                guard let day = Int(k) else { return nil }
                return (day, v)
            })

        let rawMerchants = try c.decode([[String: Double]].self, forKey: .topMerchantsRaw)
        topMerchants = rawMerchants.compactMap { dict -> (name: String, amount: Double)? in
            guard let name = dict.keys.first, let amount = dict[name] else { return nil }
            return (name: name, amount: amount)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,           forKey: .id)
        try c.encode(month,        forKey: .month)
        try c.encode(year,         forKey: .year)
        try c.encode(generatedAt,  forKey: .generatedAt)
        try c.encode(totalSpend,   forKey: .totalSpend)
        try c.encode(totalCredit,  forKey: .totalCredit)
        try c.encode(transactions, forKey: .transactions)

        let rawBreakdown = Dictionary(uniqueKeysWithValues: categoryBreakdown.map { ($0.key.rawValue, $0.value) })
        try c.encode(rawBreakdown, forKey: .categoryBreakdownRaw)

        let rawDaily = Dictionary(uniqueKeysWithValues: dailySpend.map { (String($0.key), $0.value) })
        try c.encode(rawDaily, forKey: .dailySpendRaw)

        let rawMerchants = topMerchants.map { ["\($0.name)": $0.amount] }
        try c.encode(rawMerchants, forKey: .topMerchantsRaw)
    }
}
