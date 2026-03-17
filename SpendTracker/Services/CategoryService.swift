import Foundation

// MARK: - Category Service
class CategoryService {

    static let shared = CategoryService()
    private init() {}

    // User-defined merchant → category overrides stored in UserDefaults
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

    // ─────────────────────────────────────────────────────────────
    // MARK: Main categorize
    // ─────────────────────────────────────────────────────────────
    func categorize(merchant: String,
                    body: String,
                    type: TransactionType,
                    upiId: String? = nil) -> SpendCategory {

        // Credits have their own logic
        if type == .credit { return categorizeCredit(body: body) }

        let ml = merchant.lowercased()
        let bl = body.lowercased()

        // 1. User override
        if let override = userOverrides[ml] { return override }

        // 2. ATM / cash withdrawal — highest priority
        if bl.contains("atm") || bl.contains("cash wtdl") || bl.contains("cash withdrawal")
            || bl.contains("atm wtdl") { return .atm }

        // 3. Score every category
        var scores: [SpendCategory: Int] = [:]
        for cat in SpendCategory.allCases where cat != .others && cat != .salary {
            var score = 0
            for kw in cat.keywords {
                if ml.contains(kw) { score += 3 }  // merchant match weighs more
                if bl.contains(kw) { score += 1 }
            }
            if score > 0 { scores[cat] = score }
        }

        // 4. Boost from UPI VPA
        if let vpa = upiId?.lowercased() {
            let vpaBoosts: [(String, SpendCategory)] = [
                ("swiggy", .food), ("zomato", .food), ("dominos", .food),
                ("uber", .travel), ("ola", .travel), ("rapido", .travel), ("irctc", .travel),
                ("amazon", .shopping), ("flipkart", .shopping), ("myntra", .shopping),
                ("netflix", .entertainment), ("spotify", .entertainment),
                ("bigbasket", .groceries), ("blinkit", .groceries), ("zepto", .groceries),
                ("phonepe", .upi), ("paytm", .upi), ("gpay", .upi),
            ]
            for (kw, cat) in vpaBoosts {
                if vpa.contains(kw) { scores[cat, default: 0] += 5 }
            }
        }

        // 5. Return best match
        if let best = scores.max(by: { $0.value < $1.value }) { return best.key }

        // 6. Generic UPI / NEFT / IMPS → UPI Transfer bucket
        if bl.contains("upi") || bl.contains("imps") || bl.contains("neft")
            || bl.contains("rtgs") { return .upi }

        return .others
    }

    private func categorizeCredit(body: String) -> SpendCategory {
        let bl = body.lowercased()
        if bl.contains("salary") || bl.contains("payroll") || bl.contains("wages") { return .salary }
        if bl.contains("refund") || bl.contains("cashback") || bl.contains("reversal")
            || bl.contains("reversed") { return .others }
        if bl.contains("mutual fund") || bl.contains("dividend") || bl.contains("interest credited")
            || bl.contains("fd maturity") { return .investment }
        return .others
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Override Management
    // ─────────────────────────────────────────────────────────────
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
