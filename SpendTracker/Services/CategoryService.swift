import Foundation

// MARK: - Category Service
class CategoryService {

    static let shared = CategoryService()
    private init() {}

    private var userOverrides: [String: SpendCategory] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "categoryOverrides"),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return dict.compactMapValues { SpendCategory(rawValue: $0) }
        }
        set {
            let dict = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key, $0.value.rawValue) })
            if let data = try? JSONEncoder().encode(dict) {
                UserDefaults.standard.set(data, forKey: "categoryOverrides")
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Main Categorize
    // ─────────────────────────────────────────────────────────
    func categorize(
        merchant: String,
        body:     String,
        type:     TransactionType,
        upiId:    String? = nil
    ) -> SpendCategory {

        if type == .credit { return categorizeCredit(body: body) }

        let ml = merchant.lowercased()
        let bl = body.lowercased()

        // 1. User override (highest priority)
        if let override = userOverrides[ml] { return override }

        // 2. UPI check FIRST — before ATM
        // If body mentions UPI/IMPS/NEFT with a reference number
        // it is a UPI transfer NOT ATM withdrawal
        let isUPI = bl.contains("upi/") ||
                    bl.contains("upi-") ||
                    bl.contains("upi ref") ||
                    bl.contains("upi id") ||
                    (bl.contains("upi") && (bl.contains("p2a") || bl.contains("p2m") || bl.contains("p2p"))) ||
                    upiId != nil

        if isUPI {
            // Even if UPI, try to find a better category from merchant/body
            let scored = scoreCategories(merchant: ml, body: bl, upiId: upiId)
            if let best = scored.first, best.score >= 3 {
                return best.category
            }
            return .upi
        }

        // 3. ATM check — only if clearly ATM (not just contains "atm")
        let isATM = bl.contains("atm wtdl") ||
                    bl.contains("atm withdrawal") ||
                    bl.contains("cash wtdl") ||
                    bl.contains("cash withdrawal") ||
                    (bl.contains("atm") && bl.contains("cash"))
        if isATM { return .atm }

        // 4. Credit/Debit card transaction check
        let isCardTxn = bl.contains("credit card") ||
                        bl.contains("debit card") ||
                        bl.contains("card no") ||
                        bl.contains("card ending") ||
                        bl.contains("pos purchase") ||
                        bl.contains("online purchase")

        // 5. Score categories
        let scored = scoreCategories(merchant: ml, body: bl, upiId: upiId)
        if let best = scored.first, best.score > 0 { return best.category }

        // 6. Card transaction with no category match → shopping
        if isCardTxn { return .shopping }

        // 7. NEFT/IMPS without UPI → still UPI transfer bucket
        if bl.contains("imps") || bl.contains("neft") || bl.contains("rtgs") {
            return .upi
        }

        return .others
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Score Categories
    // ─────────────────────────────────────────────────────────
    private struct CategoryScore {
        let category: SpendCategory
        let score:    Int
    }

    private func scoreCategories(
        merchant: String,
        body:     String,
        upiId:    String?
    ) -> [CategoryScore] {
        var scores: [SpendCategory: Int] = [:]

        for cat in SpendCategory.allCases
        where cat != .others && cat != .salary && cat != .upi && cat != .atm {
            var score = 0
            for kw in cat.keywords {
                if merchant.contains(kw) { score += 3 }
                if body.contains(kw)     { score += 1 }
            }
            if score > 0 { scores[cat] = score }
        }

        // Boost from UPI VPA
        if let vpa = upiId?.lowercased() {
            let boosts: [(String, SpendCategory)] = [
                ("swiggy", .food),    ("zomato", .food),    ("dominos", .food),
                ("uber", .travel),    ("ola", .travel),     ("rapido", .travel),
                ("irctc", .travel),   ("amazon", .shopping),("flipkart", .shopping),
                ("myntra", .shopping),("netflix", .entertainment),
                ("bigbasket", .groceries), ("blinkit", .groceries),
                ("zepto", .groceries),("phonepe", .upi),    ("paytm", .upi),
            ]
            for (kw, cat) in boosts {
                if vpa.contains(kw) { scores[cat, default: 0] += 5 }
            }
        }

        return scores
            .sorted { $0.value > $1.value }
            .map { CategoryScore(category: $0.key, score: $0.value) }
    }

    private func categorizeCredit(body: String) -> SpendCategory {
        let bl = body.lowercased()
        if bl.contains("salary") || bl.contains("payroll") { return .salary }
        if bl.contains("refund") || bl.contains("cashback") || bl.contains("reversal") { return .others }
        if bl.contains("mutual fund") || bl.contains("dividend") || bl.contains("fd maturity") { return .investment }
        return .others
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Override Management
    // ─────────────────────────────────────────────────────────
    func setOverride(merchant: String, category: SpendCategory) {
        var overrides = userOverrides
        overrides[merchant.lowercased()] = category
        userOverrides = overrides
    }

    func removeOverride(merchant: String) {
        var overrides = userOverrides
        overrides.removeValue(forKey: merchant.lowercased())
        userOverrides = overrides
    }
}
